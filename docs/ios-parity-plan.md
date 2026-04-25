# iOS Feature Parity Plan

Making the iPhone a first-class VoxClaw device, on par with the Mac.

---

## Current state

The iOS app has basic speech playback, pause/stop, overlay presets, and
voice engine selection. It is missing nearly every feature added to the
macOS app in the Apr 2026 work. Each new `/read` request stomps the
current one — no queue, no transitions, no project awareness.

## Feature gap inventory

| # | Feature | macOS | iOS | Effort |
|---|---------|:-----:|:---:|--------|
| 1 | Speech queue (FIFO, 1s gap, cap 20) | ✅ | ❌ | Medium |
| 2 | Per-project voice assignment | ✅ | ❌ | Small (relay sends resolved voice; iOS just uses it) |
| 3 | Project badges / indicators | ✅ | ❌ | Medium |
| 4 | Shared panel across queue items | ✅ | ❌ | Medium (ties to queue) |
| 5 | Polite-wait (defer-list + mic) | ✅ | ❌ | See discussion below |
| 6 | Mid-speech blocker pause/resume | ✅ | ❌ | See discussion below |
| 7 | Silent mode (SilentSpeechEngine) | ✅ | ❌ | See discussion below |
| 8 | Manual pause persistence | ✅ | ❌ | Small (once blockers exist) |
| 9 | User-ack (/ack, Submarine, dequeue) | ✅ | ❌ | Small |
| 10 | Paragraph breaks in teleprompter | ✅ | ❌ | Small |
| 11 | Inline code color | ✅ | ❌ | Small |
| 12 | Session timeout (5 min) | ✅ | ❌ | Small |
| 13 | Peer relay (forward to others) | ✅ | ❌ | Medium |
| 14 | Project name in overlay | ✅ | ❌ | Small (ties to badges) |
| 15 | Content fade-out between items | ✅ | ❌ | Small (ties to queue) |
| 16 | Cross-device pause sync | ❌ | ❌ | New feature — see below |

---

## New requirement: cross-device pause sync

When the user pauses on one device (or the system pauses for any
reason — blocker, mic, ack), all devices should pause together. And
vice versa.

### Design options

**Option A — Hub broadcasts state changes**

The Mac (hub) already relays `/read` to peers. Extend the relay to
also relay pause/resume/stop events. New endpoint: `POST /control`
with `{"action": "pause" | "resume" | "stop"}`.

When the Mac pauses (manual, blocker, ack), it POSTs `/control` to
all relay peers. When a peer pauses, it POSTs `/control` back to the
hub. The hub decides whether to propagate (e.g., user-pause propagates;
blocker-pause on the Mac propagates because the Mac controls the queue,
but a blocker-pause on the iPhone might not make sense to propagate
back since the Mac isn't affected by the iPhone's mic state).

*Pro:* centralized control, clear source of truth.
*Con:* must handle echo loops (Mac pauses → tells iPhone → iPhone
acks → tells Mac...). Need an "origin" field or a suppress-echo flag.

**Option B — Shared state via iCloud KVS**

Push pause/resume state to iCloud KVS. All devices observe changes.

*Pro:* no HTTP needed, works even without local network.
*Con:* iCloud KVS has ~1-2 second propagation delay. Too slow for
responsive pause sync. Also doesn't support the queue's per-item state.

**Option C — Multipeer Connectivity / Bonjour + persistent connection**

Maintain a persistent connection between VoxClaw peers (WebSocket or
Bonjour stream). State changes propagate instantly.

*Pro:* low latency, bidirectional.
*Con:* significantly more infrastructure than one-shot HTTP POSTs.
Overkill if the Mac is always the hub.

**Recommendation:** Option A (hub broadcasts). The Mac is already the
hub. Adding `POST /control` is one endpoint + one relay call. Use an
`origin` field to prevent echo loops:

```json
POST /control
{"action": "pause", "origin": "mac-hub-id"}
```

Peers that receive a control with their own ID as origin ignore it.

### What pauses should propagate?

| Trigger | Mac → iPhone | iPhone → Mac |
|---------|:---:|:---:|
| Manual pause (user tap) | Yes | Yes |
| Manual stop | Yes | Yes |
| Blocker pause (Zoom, mic) | Yes (Mac controls queue) | No (iPhone's local mic state is irrelevant to Mac) |
| Blocker resume | Yes | N/A |
| Ack (user responded) | Yes | No (ack is per-agent, Mac handles queue) |
| System interruption (phone call on iPhone) | N/A | No (iPhone pauses locally, Mac continues) |

---

## Architecture: shared vs duplicated queue logic

### Current macOS architecture

All queue/badge/polite-wait/ack logic lives in `AppCoordinator`
(~300 lines). This is macOS-only. `iOSCoordinator` is a separate,
minimal coordinator (~130 lines).

### Options for iOS parity

**Option A — Port AppCoordinator features to iOSCoordinator**

Copy the queue, badge, and ack logic into iOSCoordinator. Gate
macOS-specific features (AudioActivityMonitor, PanelController)
with `#if os(macOS)`.

*Pro:* quick, direct.
*Con:* duplicated logic, diverges over time, two places to fix bugs.

**Option B — Extract shared SpeechQueueCoordinator**

Extract the queue/drain/badge/ack logic into a platform-independent
`SpeechQueueCoordinator`. Both `AppCoordinator` (macOS) and
`iOSCoordinator` use it. Platform-specific behavior (panel, blockers)
is injected via protocol or closure.

*Pro:* one implementation, no divergence, testable.
*Con:* moderate refactor. Aligns with roadmap item R1 (split
AppCoordinator).

**Option C — iPhone is relay-only, Mac controls everything**

The Mac is always the hub. The iPhone never needs its own queue —
the Mac relays one item at a time (already working) and sends
`/control` for pause/stop. But the iPhone's PRESENTATION must be
first-class: same teleprompter quality, same badges, same transitions.

*Pro:* minimal iOS queue code. Mac is the single source of truth.
*Con:* iPhone can't work without a Mac. Acceptable — the user
confirmed a Mac will always be present.

**Recommendation:** Option B for long-term, Option C as a fast
interim. Option C can ship today (add `/control` endpoint to iOS,
have Mac relay control events). Option B is the right architecture
but requires the AppCoordinator split (roadmap R1).

---

## Teleprompter parity

The iOS `TeleprompterView` is simpler than the macOS `FloatingPanelView`.
Missing features that need porting:

1. **Paragraph breaks** — add paragraph sentinel check + extra spacing
   in the word loop. Small.
2. **Inline code color** — add zero-width space detection + `codeWordColor`
   rendering. Small.
3. **Project badges** — add the indicator strip at top. Ties to queue
   (needs project data from the coordinator). Medium.
4. **Content fade-out** — add `contentFadedOut` opacity binding. Small
   once queue exists.
5. **Stop button** — already exists on iOS. ✅

### Visual bugs in current iOS teleprompter

Comparing macOS `WordView` to iOS `TeleprompterWordView`:

**1. Highlight causes layout jump (the spacing issue)**
iOS applies word padding only when highlighted:
```swift
.padding(.horizontal, isHighlighted ? 4 : 0)
.padding(.vertical, isHighlighted ? 2 : 0)
```
macOS always applies padding (4h, 2v) regardless of highlight state.
When a word becomes highlighted on iOS, it gains padding and pushes
neighboring words — the entire line shifts. On macOS, padding is
constant so words never move.

**Fix:** always apply `.padding(.horizontal, 4).padding(.vertical, 2)`
on iOS, matching macOS.

**2. Highlight background missing glow**
macOS `WordView` has a shadow glow (`glowRadius`) that breathes when
paused. iOS has a flat rectangle, no shadow, no animation. Makes the
highlight feel flat.

**Fix:** port the `glowRadius` shadow + breathing animation.

**3. ScrollView horizontal drift**
iOS uses `.scrollTo(newIndex, anchor: .center)` which can shift the
view horizontally when a word is near the edge of a line (same bug
we fixed on macOS). Should use `UnitPoint(x: 0, y: 0.5)`.

**4. No `.clipped()` on ScrollView**
Long words can overflow the edges (same issue we fixed on macOS).

**5. Missing teleprompter features**
- No paragraph break sentinel check (no extra spacing between
  paragraphs)
- No inline code color (no zero-width space detection)
- No project badges / indicator strip
- No content fade-out between queue items
- No `contentFadedOut` opacity binding

### Layout differences

The iOS teleprompter fills the screen (not a floating panel). Some
macOS-specific concerns don't apply:
- No `makeKey()` / focus-stealing (iOS doesn't have this concept)
- No `NSPanel` lifecycle (iOS uses a SwiftUI view)
- `FlowLayout` with `ParagraphBreakKey` should work cross-platform
  (it's in VoxClawCore, not macOS-gated)

---

## Prioritized implementation plan

### Phase 1: relay-only iPhone (fast, ships today's architecture)

1. Add `POST /control` endpoint to VoxClaw (both platforms).
2. Mac relays pause/resume/stop to peers alongside `/read` relay.
3. iPhone responds to `/control` by pausing/resuming/stopping its
   current playback.
4. Voice consistency via relayed voice field (already done).

**Result:** iPhone speaks in sync, pauses in sync, same voice. No
queue on iPhone — Mac handles sequencing.

### Phase 2: teleprompter parity (visual quality)

5. Port paragraph breaks + inline code color to iOS teleprompter.
6. Port `FlowLayout` with `ParagraphBreakKey` to iOS (if not already
   shared via VoxClawCore).

**Result:** iPhone display matches Mac quality.

### Phase 3: standalone iPhone (full parity)

7. Extract `SpeechQueueCoordinator` from `AppCoordinator` (roadmap R1).
8. Use it in both `AppCoordinator` and `iOSCoordinator`.
9. Port project badges / indicators to iOS teleprompter.
10. Add ack handling to iOS.
11. Add session timeout to iOS.
12. Add peer relay from iPhone (so iPhone can be a hub too).

**Result:** iPhone works standalone with full feature set. Either
device can be the hub.

### Phase 4: cross-device sync (new capability)

13. Implement `POST /control` with propagation rules.
14. Add origin-based echo suppression.
15. Handle edge cases (both devices paused, one resumes, etc.).

**Result:** pause on Mac = pause on iPhone, and vice versa. True
multi-device experience.

---

## Settings UI rules (implemented)

The peer list in macOS Settings adapts based on how many devices are
visible:

- **One device (this Mac only):** "This Mac" label, no switch. The Mac
  always speaks locally when it's the only device.
- **Multiple devices:** ALL devices get a switch, including "This Mac."
  The user can mute local playback and have speech play only on the
  iPhone (or vice versa, or both). Uses a `__mute_local__` sentinel
  in `relayPeerIDs` to track local mute.

---

## Open questions

1. **~~Should the iPhone auto-discover the Mac and offer to be a
   relay target?~~** No. The Mac is always the hub. The iPhone is
   always a relay target. Discovery and relay config live on the Mac.

2. **What happens when the Mac relays to the iPhone but the iPhone
   is locked?** iOS suspends apps when locked. The background audio
   keep-alive helps, but will the network listener survive? Needs
   testing.

3. **Should we relay /ack to peers?** If the user responds on Mac
   to project A, should the iPhone also stop speaking project A?
   Probably yes — add ack relay in Phase 1.
