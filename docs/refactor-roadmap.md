# Refactor Roadmap

Open items from the Apr 2026 audit, in roughly the order I'd take them on next.
Each entry: what to do, where, why, and the dependency it has on other items.

---

## R1 — Split `AppCoordinator` into focused coordinators

**Where:** `Sources/VoxClawCore/VoxClawApp.swift` (the `AppCoordinator` class).

**Why:** `AppCoordinator` currently owns five+ unrelated concerns: networking
lifecycle, the speech queue + drain, polite-wait blocker monitoring, voice
resolution, session lifecycle, and CLI launch dispatch. This entanglement is
the reason the queue logic is currently untestable in isolation (R3 below).

**Sketch:**
- `SpeechQueueCoordinator` — owns `speechQueue`, `isDrainingQueue`,
  `enqueueSpeech`, `drainQueue`, `waitForBlockersIfNeeded`,
  `monitorBlockersDuringSpeech`, and the active `ReadingSession`. Knows
  nothing about networking.
- `NetworkCoordinator` — owns `networkListener`, `startListening`,
  `stopListening`, the `StatusInfo` snapshot construction. Hands incoming
  `ReadRequest`s off to `SpeechQueueCoordinator`.
- Keep `AppCoordinator` as a thin facade that holds both and exposes the
  same public API (`readText`, `togglePause`, `stop`, `setSpeed`,
  `handleCLILaunch`).

**Effort:** medium-large. ~300 LOC moves; affects `VoxClawApp.swift` heavily.
No behavior change.

**Blocks:** R3 (queue tests).

---

## R2 — Audit-driven big-file extractions

Mechanical, no behavior change. Do them when you're already in the file for
something else.

### `Views/OnboardingView.swift` (930 LOC)
- Per-step views to their own files.
- Extract the agent-handoff prompt template (currently duplicated near lines
  ~183 and ~575 in OnboardingView, plus ~503 and ~553 in `SettingsView`)
  into `Sources/VoxClawCore/Views/AgentHandoffPrompt.swift`. **All four
  call sites currently maintain the same string by hand.**

### `Settings/SettingsManager.swift` (~600 LOC after agent-speech delete)
- Extract iCloud KVS observation (`observeICloudKVSChanges` and the
  per-property `didSet` → KVS push) into `SettingsKVSSync`.
- Consider a property-wrapper or table-driven approach so adding a new
  setting is one line, not three (`KVSKey` constant + `didSet` + observer
  branch). Property-wrapper preferred — keeps types intact.

### `Views/SettingsView.swift` (~600 LOC)
- Extract per-engine credential rows.
- Extract the network-listener section.
- Share the agent-handoff prompt builder with `OnboardingView` (see above).

**Effort:** small per chunk, ~3-5 chunks per file.

---

## R3 — Queue/drain tests

**Where:** new `Tests/VoxClawCoreTests/SpeechQueueTests.swift`.

**Why:** the queue logic is the most regression-prone new code from the Apr
2026 work. Bugs we already shipped and fixed there: ghost panel from non-strong
dismiss capture, duplicate panel from non-idempotent `show()`, mid-speech
pause/resume not draining cleanly. Untested branches still include cap
eviction, the inter-item gap, the silent-fallback swap, `stop()` clearing
pending items, and the polite-wait timeout-then-stop path.

**Approach:** pre-requires R1 (split AppCoordinator) so `SpeechQueueCoordinator`
can be exercised without booting the network listener. After R1, tests can
inject a fake `ReadingSession` factory + a fake clock + a fake blocker source.

**Cheaper interim:** without R1, factor just `currentBlockers()` and the
polite-wait loop into a free function that takes a `CoreAudioProbe` and a
`@Sendable () -> ContinuousClock.Instant` clock. Test those in isolation. The
session-driving parts of `drainQueue` remain untested but the most subtle
logic (the wait loop) gets coverage.

**Effort:** small (interim) or medium (full, after R1).

---

## R4 — `PanelController` AppKit-flavored tests

**Where:** new tests in `Tests/VoxClawCoreTests/PanelControllerTests.swift`.

**Why:** real bugs hit this file recently — duplicate panels from
`pauseForBlocker → resumeFromBlocker`'s second `didChangeState(.playing)`
firing, ghost panels from `[weak self]` capture in dismiss completion. The
existing `FloatingPanelTests.swift` is 11 lines.

**Approach:** these need real `NSScreen`/`NSWindow`; will be slower and more
brittle than the unit suites. Recommend marking the suite `.serialized` and
bracketing each test with explicit show → dismiss pairs.

**What to cover:**
- Idempotent `show()`: calling twice yields one panel, not two
  (`PanelController.swift:23-30`).
- `dismiss()` strong-capture: panel reliably closes even after the
  controller's owner releases its reference (the regression that produced
  the ghost panel).
- Silent-mode skip-makeKey: panel ordered front, panel is not the key
  window of the app afterward.

**Effort:** medium. Worth the brittleness because the bugs here are
user-visible immediately.

---

## R5 — Magic-number consolidation

Repeated values that should live in one named place:

- Rate clamp `[0.5, 3.0]` — appears in `MenuBarView`, `SettingsView`,
  `PanelController.adjustSpeed`. Promote to `SpeedConfig.allowedRange`.
- `politeWaitMax = 150s`, `interItemDelay = 2s`, `politePollInterval = 1s`
  — currently `private static` on `AppCoordinator`. Move to
  `SpeechQueueConfig` once R1 splits the file.
- Panel animation constants (`scaleFactor: 0.75`, `duration: 0.15`, etc.)
  in `PanelController.dismiss()` — move to `PanelAnimationConfig`.

**Effort:** small. Pure renaming.

---

## R6 — `isDrainingQueue` → serial `AsyncStream<SpeechItem>` consumer

**Where:** `VoxClawApp.swift:521-531` (current `enqueueSpeech` +
`drainQueue` pair).

**Why:** the current re-entrancy guard (a `Bool` flag mutated from a
fire-and-forget `Task`) is racy in spirit even though MainActor isolation
keeps it correct in practice. An `AsyncStream` consumer is idiomatic and
removes the flag entirely.

**Effort:** small once R1 is done; awkward before because of the
networking entanglement.

**Priority:** low. The current code works; this is hygiene.

---

## Skipped / declined

- **Restore agent-speech UI.** Decided: delete it (done in commit
  `786227c`). If we ever miss the off/summary/live toggle, it's recoverable
  from git history.
- **Share `agent_notify_url` with peer setup.** Endpoint is gone; no longer
  applicable.

---

## What got us here

Recent commits worth knowing about for context:

- `ec52ff0` — tests for `AudioActivityMonitor` (with new `CoreAudioProbe`
  protocol), `SilentSpeechEngine`, `VoicePool`. **+28 tests, 210 total.**
- `a54a9fc` — extracted `makeEngine` helper, replaced 9-tuple
  `statusProvider` with `StatusInfo` struct, deleted vestigial
  `previouslyFrontmost` capture/restore.
- `786227c` — deleted agent-speech subsystem
  (`AgentSpeechMode`/`Verbosity`, `/agent-notify`, mode/verbosity gating).
  Bundles browser-control plumbing because `VoxClawApp.swift` and
  `SettingsView.swift` reference its types.
- `b4a7d0c` — skipped `panel.makeKey()`, idempotent `show()`, strong-capture
  in dismiss completion handler, removed global Space/Esc menu shortcuts.
