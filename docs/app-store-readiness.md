# App Store Readiness

Current state of submitting VoxClaw to the Mac App Store and iOS App Store,
with an honest assessment of what works, what needs compromise, and what
blocks submission entirely.

---

## iOS App Store

### Just works

- **Network listener (NWListener + Bonjour)** — allowed in the App Store.
  Needs the `com.apple.developer.networking.networkextension` entitlement
  or just the local-network privacy prompt. No sandbox restriction on iOS
  for local network servers.
- **iCloud KVS settings sync** — native App Store feature, already wired.
- **OpenAI / ElevenLabs API calls** — standard outbound HTTPS, no issue.
- **Apple TTS (AVSpeechSynthesizer)** — first-party framework, no review
  concern.
- **SwiftUI views / teleprompter overlay** — standard UI, nothing exotic.

### Requires work

- **Background audio** — the app has `BackgroundAudioKeepAlive.swift` with
  a 30-minute timeout. Apple requires the `audio` background mode in
  Info.plist and reviewers verify the app genuinely plays audio (not just
  silence to stay alive). VoxClaw does play real speech, so this should
  pass, but the keep-alive mechanism needs scrutiny — Apple rejects apps
  that play silent audio to prevent suspension.
- **Local network privacy prompt** — iOS 14+ shows a permission dialog
  when the app listens on the local network. Users need to accept this.
  Not a blocker, but the first-launch UX needs to explain why.
- **Missing entitlements** — the iOS entitlements file currently only has
  iCloud KVS. Needs `com.apple.security.network.server` and the audio
  background mode added.
- **Stale codebase** — the iOS app imports `VoxClawCore` which was heavily
  modified in the Apr 2026 session (deleted AgentSpeech, changed
  NetworkListener/NetworkSession APIs, added new types). The iOS app
  almost certainly does not compile against the current library. Fixing
  the build is straightforward but not zero effort.

### No blockers

iOS does not have macOS-style app sandboxing restrictions on CoreAudio
process enumeration. The polite-wait feature (AudioActivityMonitor) is
macOS-only (`#if os(macOS)`), so it does not affect the iOS build. The iOS
version can ship to the App Store without feature compromises.

---

## Mac App Store

### Just works

- **SMAppService (Launch at Login)** — designed for App Store apps.
- **NWListener / Bonjour discovery** — allowed with `network.server`
  entitlement inside the sandbox.
- **iCloud KVS** — native.
- **OpenAI / ElevenLabs TTS** — outbound HTTPS, fine.
- **Apple TTS** — first-party.
- **NSPanel floating overlay** — standard AppKit, allowed.
- **SwiftPM build** — can generate an Xcode project for archive +
  submission, or use `xcodebuild` directly with the package.

### Requires compromise

- **CoreAudio process enumeration (polite-wait)** — `AudioActivityMonitor`
  uses `kAudioHardwarePropertyProcessObjectList` and per-process properties
  (`BundleID`, `PID`, `IsRunningOutput`, `IsRunningInput`) to detect when
  Zoom, Teams, FaceTime, or a transcription tool is active. **Sandboxed
  apps cannot enumerate other processes' audio state.** This is a privacy
  boundary Apple enforces at the sandbox level. The feature would need to
  be compiled out for the App Store build (`#if !APPSTORE`). Users of the
  App Store version would not get:
  - Automatic pause when a video call is active
  - Automatic pause when a transcription tool is using the mic
  - The silent-display fallback after the polite-wait timeout
- **`NSRunningApplication.runningApplications(withBundleIdentifier:)`** —
  used in `VoxClawApp.swift` to detect and close duplicate instances on
  launch. Restricted inside the sandbox. Would need a different approach
  (e.g., a file lock or `NSDistributedNotificationCenter`).
- **Apple Events entitlement** — `com.apple.security.automation.apple-events`
  is used by `ExternalPlaybackController` to pause Spotify / Music via
  media keys. Apple allows this in the App Store but reviews it carefully.
  A clear `NSAppleEventsUsageDescription` string is required. Reviewers
  may push back if the justification is weak.
- **Incoming network connections** — the HTTP listener on port 4140 is the
  app's core integration surface. Apple allows `network.server` in the
  sandbox, but reviewers may question why a TTS app runs an HTTP server.
  Clear review notes explaining the agent-integration use case should
  suffice, but it is a review risk.

### Showstopper

- **No sandbox entitlement** — the macOS entitlements file currently does
  not include `com.apple.security.app-sandbox`. The Mac App Store requires
  sandboxing. Adding it is a one-line change, but the app must then work
  correctly inside the sandbox, which surfaces all the restrictions above.

---

## Dual-distribution strategy

Many Mac apps ship two versions: a full-featured direct build and a
sandbox-constrained App Store build. VoxClaw is a natural fit for this.

### Direct build (full features)

Distributed via the VoxClaw website, GitHub Releases, or Homebrew Cask.
Signed with Developer ID (or ad-hoc for development). No sandbox.

Includes everything:
- Polite-wait (pause for video calls and transcription tools)
- Mic-hot detection
- Silent-display fallback
- Duplicate-instance detection via `NSRunningApplication`
- Apple Events automation for media-key pause

This is the version power users and developers want. It is the version
that works with Claude Code hooks, Codex plugins, and multi-agent setups.

Update mechanism: Sparkle framework (standard for direct-distributed Mac
apps) or manual download from GitHub Releases. The existing
`.github/workflows/release.yml` already builds and uploads to Releases.

### App Store build (sandbox-safe subset)

Distributed via the Mac App Store. Sandboxed. Reviewed by Apple.

Feature differences:
- No polite-wait (compiled out via `#if !APPSTORE`)
- No mic-hot detection
- No duplicate-instance auto-close
- Media-key pause may require Apple Events review approval
- Otherwise identical: same TTS engines, same overlay, same queue, same
  voice bindings, same network listener

The App Store build is best for:
- Users who prefer App Store discovery and updates
- Enterprise environments that require App Store distribution
- Users who do not need the multi-agent polite-wait features
- iOS users (no compromise needed on iOS)

### Implementation

To support both builds:

1. Add a Swift compiler flag: `-DAPPSTORE` in the Xcode build settings
   for the App Store scheme.
2. Guard sandbox-incompatible code:
   ```swift
   #if !APPSTORE
   // CoreAudio process enumeration, NSRunningApplication, etc.
   #endif
   ```
3. The queue's `waitForBlockersIfNeeded` and `monitorBlockersDuringSpeech`
   already have `#if os(macOS)` guards. Adding `&& !APPSTORE` inside
   those blocks is a small change.
4. Add `com.apple.security.app-sandbox` to a separate entitlements file
   used only by the App Store scheme.
5. The rest of the codebase (TTS engines, network listener, overlay,
   queue, voice bindings) works identically in both builds.

### iOS

No dual-distribution needed. The iOS App Store is the only distribution
path (outside TestFlight and enterprise). The iOS version has no
sandbox-incompatible features, so it ships with full functionality.

---

## Summary table

| Feature | iOS App Store | Mac App Store | Mac Direct |
|---|---|---|---|
| TTS (Apple / OpenAI / ElevenLabs) | Yes | Yes | Yes |
| Network listener + Bonjour | Yes | Yes | Yes |
| Speech queue + transitions | Yes | Yes | Yes |
| Per-project voice binding | Yes | Yes | Yes |
| Project badges + indicators | Yes | Yes | Yes |
| iCloud settings sync | Yes | Yes | Yes |
| Polite-wait (video calls) | N/A | **No** | Yes |
| Mic-hot detection | N/A | **No** | Yes |
| Silent-display fallback | N/A | **No** | Yes |
| Duplicate-instance close | N/A | **No** | Yes |
| Media-key pause | N/A | Review risk | Yes |
| User-ack (Submarine sound) | Yes | Yes | Yes |

---

## Next steps

1. Fix the iOS build against current `VoxClawCore` (API changes from the
   Apr 2026 session).
2. Add `com.apple.security.app-sandbox` to a Mac App Store entitlements
   file and test the sandbox.
3. Add `#if !APPSTORE` guards around `AudioActivityMonitor` usage and
   `NSRunningApplication` calls.
4. Write `NSAppleEventsUsageDescription` for the Apple Events entitlement.
5. Add `NSLocalNetworkUsageDescription` for the iOS network privacy prompt.
6. Set up a second Xcode scheme (or SwiftPM configuration) for the App
   Store build.
7. Integrate Sparkle for auto-updates on the direct build.
