# Full Client Implementation Plan

Making every VoxClaw device a full client with identical queue, badge,
and transition behavior. Any device can control which speakers are active.

---

## Architecture

```
Claude Code hook → POST /read → localhost:4140 (Mac)
                                     ↓
                          SpeechQueueCoordinator
                          (queue, drain, badges, transitions)
                                     ↓
                          Speaks locally if active
                          Relays to active peers:
                                     ↓
                          iPhone SpeechQueueCoordinator
                          (same code, same queue, same animations)
                                     ↓
                          Speaks locally if active
```

Each device runs identical queue logic. The Mac is the entry point
(where hooks fire), but every device is a full client with its own
queue, project badges, transitions, and controls.

---

## Shared state: iCloud KVS "active speakers"

One global setting synced via iCloud KVS:

```
activeSpeakers: ["macbook-air-m4", "iphone"]
```

- Editable from any device's Settings UI
- iCloud KVS propagates changes within seconds
- The source device (where /read arrives) checks activeSpeakers
  before relaying
- Each device checks if its own ID is in activeSpeakers before
  playing locally

Replaces the current per-device `activeSpeakers` and `__mute_local__`
sentinel. Simpler model: one list of active speakers, not a per-device
relay graph.

---

## Implementation phases

### Phase A: Extract SpeechQueueCoordinator

**Goal:** pull queue/drain/badge logic out of `AppCoordinator` into a
platform-independent coordinator that both macOS and iOS use.

**Files to create:**
- `Sources/VoxClawCore/Coordination/SpeechQueueCoordinator.swift`

**What moves out of AppCoordinator (~300 LOC):**
- `SpeechItem` struct
- `speechQueue: [SpeechItem]`
- `isDrainingQueue` flag
- `activeSession: ReadingSession?`
- `projectActivity: ProjectActivityTracker`
- `currentDrainingProjectId: String?`
- `isCurrentItemAcked: Bool`
- `enqueueSpeech(_:appState:settings:)`
- `drainQueue(appState:settings:)` — the main loop
- `waitForBlockersIfNeeded(item:)` — gate with `#if os(macOS)`
- `monitorBlockersDuringSpeech(session:)` — gate with `#if os(macOS)`
- `currentBlockers()` — gate with `#if os(macOS)`
- `rebuildProjectIndicators(appState:)`
- `makeEngine(for:settings:)` (or inject as a closure)
- Queue constants (`maxQueueSize`, `interItemDelay`, `politeWaitMax`, etc.)

**What stays on AppCoordinator (macOS-specific):**
- `networkListener` lifecycle
- `peerBrowser`
- `relayToPeers` / `relayControl`
- `handleReadRequest` (resolves voice, delegates to queue coordinator)
- `handleAck`
- `handleControl`
- `startListening` / `stopListening`
- `settingsRef`

**What iOSCoordinator gains:**
- Owns a `SpeechQueueCoordinator` instead of managing sessions directly
- Delegates incoming `/read` to the queue coordinator
- Gets queue, badges, transitions, fade-out for free

**Platform injection points:**
The queue coordinator needs a few platform-specific behaviors injected
at init (protocol or closures):

```swift
struct QueueConfiguration {
    let maxQueueSize: Int
    let interItemDelay: Duration
    let politeWaitMax: Duration
    let politePollInterval: Duration
}

protocol SpeechQueueDelegate: AnyObject {
    /// Build the speech engine for this request.
    func makeEngine(for request: ReadRequest, settings: SettingsManager) async -> (any SpeechEngine)?

    /// Called when a session starts playing (macOS: show panel).
    func sessionDidStartPlaying(_ session: ReadingSession)

    /// Called when all items are drained (macOS: dismiss panel).
    func queueDidEmpty()

    /// Check for audio blockers (macOS only; iOS returns empty).
    func currentBlockers() -> [String]

    /// Relay a read request to peers (if applicable).
    func relayToPeers(request: ReadRequest, settings: SettingsManager)
}
```

**Effort:** medium. ~300 LOC moves, ~50 LOC new (protocol, init).
No behavior change. Heavy on refactoring, light on new logic.

**Tests:** existing queue-adjacent tests should still pass. New tests
for `SpeechQueueCoordinator` in isolation become possible (roadmap R3).

---

### Phase B: Wire iOS to SpeechQueueCoordinator

**Goal:** replace `iOSCoordinator`'s manual session management with
the shared queue coordinator.

**Changes to iOSCoordinator:**
- Create `SpeechQueueCoordinator` at init
- Implement `SpeechQueueDelegate` (iOS version):
  - `makeEngine`: same as current `handleReadRequest` logic
  - `sessionDidStartPlaying`: no-op (no panel to show; the view
    observes `appState` reactively)
  - `queueDidEmpty`: no-op
  - `currentBlockers`: return `[]` (no blocker detection on iOS)
  - `relayToPeers`: no-op (iPhone doesn't relay)
- Remove `stopForReplacement` calls
- Remove manual `ReadingSession` creation
- Keep audio session configuration, background keep-alive,
  interruption observer

**Changes to TeleprompterView:**
- Add project indicator strip (same as macOS FloatingPanelView)
- Add `contentFadedOut` opacity binding
- Add top padding when indicators are present

**Effort:** small-medium. iOSCoordinator becomes much simpler.
TeleprompterView gains ~30 lines for badges.

---

### Phase C: Active speakers via iCloud KVS

**Goal:** replace per-device `activeSpeakers` with a shared
`activeSpeakers` set synced via iCloud.

**SettingsManager changes:**
- New property: `activeSpeakers: Set<String>` (KVS-synced)
- Remove `activeSpeakers` (or migrate: if activeSpeakers exist, convert
  to activeSpeakers on first launch, then delete)
- Each device generates a stable device ID (persisted in UserDefaults):
  `UIDevice.current.name` on iOS, `Host.current().localizedName` on
  macOS, or a UUID generated once and stored
- KVS key: `activeSpeakers`
- KVS observer updates `activeSpeakers` when remote changes arrive

**Settings UI changes (both platforms):**
- Show all Bonjour-discovered peers
- Each peer gets a speaker toggle
- Toggling writes to iCloud KVS
- This device shows "This device" label when alone; switch when
  multiple peers exist (same logic as current macOS UI)
- Toast on toggle ("Speaking on iPhone" / "Muted on iPhone")

**AppCoordinator/Relay changes:**
- `relayToPeers` checks `activeSpeakers` instead of `activeSpeakers`
- Local playback checks if own device ID is in `activeSpeakers`
- Remove `__mute_local__` sentinel

**iOSCoordinator changes:**
- Same Settings UI (shared SwiftUI view, platform-gated for any
  AppKit vs UIKit differences)
- Observes `activeSpeakers` for local mute decisions

**Effort:** medium. Mostly settings plumbing + KVS sync. The UI
is already built on macOS; needs porting to iOS Settings.

---

### Phase D: Control sync between devices

**Goal:** pause/resume/stop on one device propagates to all active
speakers.

**Already built:**
- `POST /control` endpoint (action + origin + echo suppression)
- macOS relays control on pause/resume/stop/blocker/ack
- iOS handles incoming `/control`

**Remaining work:**
- iOS should also relay control when user pauses on iPhone
  (currently only Mac relays)
- Both devices should relay to all `activeSpeakers` peers, not just
  the old `activeSpeakers`
- Control relay uses the same `activeSpeakers` set

**Edge cases to handle:**
- Both devices paused independently → one resumes → relay resume →
  other also resumes. Correct.
- Mac blocker-pauses → relays pause to iPhone → user resumes on
  iPhone → relay resume to Mac → Mac resumes even though blocker
  is still active. Fix: Mac's `handleControl` should check if local
  blockers are still active before honoring a remote resume.
- Ack on Mac → relay stop to iPhone → iPhone stops. Correct.

**Effort:** small. Most of the wiring exists. Just need to update
relay to use `activeSpeakers` and add iPhone → peer relay for
control events.

---

### Phase E: Shared Settings UI

**Goal:** one SwiftUI Settings view that works on both platforms.

**Current state:**
- macOS: `SettingsView.swift` (600+ LOC, macOS-only, uses AppKit)
- iOS: `iOSSettingsView.swift` (separate, smaller)

**Approach:**
- Extract the peer list + speaker toggles into a shared
  `PeerSpeakerList` view (SwiftUI, cross-platform)
- macOS `SettingsView` embeds it
- iOS `iOSSettingsView` embeds it
- Platform-specific sections (Launch at Login, browser control,
  overlay position) stay gated with `#if os(macOS)`

**Effort:** small. The speaker-toggle UI is ~40 lines of SwiftUI.

---

## Execution order

| Phase | What | Depends on | Effort |
|-------|------|------------|--------|
| A | Extract SpeechQueueCoordinator | Nothing | Medium |
| B | Wire iOS to queue coordinator | A | Small-medium |
| C | Active speakers via iCloud KVS | B | Medium |
| D | Control sync both directions | C | Small |
| E | Shared Settings UI | C | Small |

**A and B are the core.** C, D, E are incremental improvements on
top of a working foundation. A can be tested on macOS alone (no iOS
changes needed until B).

---

## What the user experiences after each phase

**After A:** Mac behaves identically (refactor, no behavior change).

**After B:** iPhone has full queue — multiple agents queue up, project
badges animate, content fades between items, transitions are smooth.
Relay from Mac → iPhone still works. iPhone is a real client.

**After C:** Settings show all devices with speaker toggles. Toggle
on iPhone → syncs to Mac via iCloud → Mac starts/stops relaying.
Any device can control which speakers are active.

**After D:** Pause on iPhone → Mac pauses. Resume on Mac → iPhone
resumes. Stop on either → both stop. True multi-device sync.

**After E:** Same Settings UI on both platforms. Polish.

---

## Risks and mitigations

**Risk: iCloud KVS propagation delay (1-5 seconds)**
If user toggles a speaker on iPhone, the Mac won't relay to it for
a few seconds. Mitigation: on toggle, also send a direct `POST /control`
to the peer with a "you're now active" message. Belt-and-suspenders.

**Risk: Device ID stability**
If the device ID changes (e.g., user renames their Mac), they lose
their activeSpeakers membership. Mitigation: use a UUID generated
once and stored in UserDefaults, not the device name. Display name
is separate from ID.

**Risk: Bonjour discovery lag**
A device might be in activeSpeakers but not yet discovered via
Bonjour. Relay fails silently. Mitigation: acceptable — the device
will be discovered within seconds. Relay on next queue item works.

**Risk: Queue divergence between devices**
If Mac and iPhone queue independently, their playback positions
could drift. Mitigation: the Mac is still the source of truth. It
relays items one at a time, timed by its own queue. The iPhone
queues what it receives — since items arrive sequentially, the
queues stay in sync naturally.
