# VoxClaw Implementation Plan

## Context

Build a macOS menu bar app + CLI tool that reads text aloud using OpenAI TTS (`onyx` voice) while displaying a teleprompter-style floating overlay with synchronized word highlighting. The app launches from the terminal via `voxclaw` and accepts text from arguments, stdin, files, clipboard, or network. The overlay appears at the top center of the screen (Dynamic Island style) with dark background, white Helvetica text, and yellow word highlighting that tracks the spoken audio.

## Architecture

**Single SPM executable**, dual-mode: CLI tool or menu bar app depending on invocation.

```
Input (args/stdin/file/clipboard/network)
  -> InputResolver resolves to String
  -> ReadingSession orchestrator
  -> TTSService streams PCM from OpenAI API
  -> AudioPlayer schedules AVAudioEngine buffers
  -> WordTimingEstimator maps playback position to word index
  -> FloatingPanelView highlights current word
  -> Panel collapses when done
```

**Key decisions:**
- `@Observable` AppState as single source of truth
- NSPanel subclass (not SwiftUI Window) for borderless floating overlay
- AVAudioEngine + AVAudioPlayerNode for streaming PCM with precise time tracking
- Proportional word timing estimation (MVP) — no Whisper alignment yet
- `swift-argument-parser` as only external dependency (Network.framework is system)
- Swift 6 strict concurrency: `@MainActor` on UI/state, `actor` on TTSService
- Network.framework (NWListener) for zero-dependency LAN listener

## File Structure

```
VoxClaw/
  Package.swift                           # macOS 15+, swift-argument-parser dep
  README.md                               # Project documentation
  PLAN.md                                 # This file
  Sources/VoxClaw/
    main.swift                            # @main dual-mode: CLI vs MenuBarExtra
    AppState.swift                        # @Observable shared state
    Views/
      FloatingPanelView.swift             # Dark panel, flowing text, yellow highlight
      MenuBarView.swift                   # Paste & Read, Read from File, Quit
      FlowLayout.swift                    # Custom Layout for word wrapping
      FeedbackBadge.swift                 # Transient keyboard feedback indicator
    Panel/
      FloatingPanel.swift                 # NSPanel: borderless, floating, transparent
      PanelController.swift               # Show/hide/position/animate
    Audio/
      TTSService.swift                    # OpenAI TTS: POST, stream PCM bytes
      AudioPlayer.swift                   # AVAudioEngine: schedule buffers, track time
    Reading/
      ReadingSession.swift                # Orchestrator tying TTS+audio+highlighting
      WordTimingEstimator.swift           # Proportional timing from total duration
    Input/
      CLIParser.swift                     # ArgumentParser command
      InputResolver.swift                 # Resolve text from args/stdin/file/clipboard
      ModeDetector.swift                  # CLI vs menu bar detection
    Network/
      NetworkListener.swift               # NWListener: accept LAN connections on TCP port
      NetworkSession.swift                # Handle incoming connection, extract text, trigger read
    Utilities/
      KeychainHelper.swift                # Read API key from macOS Keychain
      KeyboardMonitor.swift               # NSEvent monitor: space/esc/arrows
  Scripts/
    package_app.sh                        # Build .app bundle
    install-cli.sh                        # Symlink voxclaw -> /usr/local/bin
```

## Implementation Phases

### Phase 1: Foundation ✅ (in progress)
- Create `Package.swift` (macOS 15+, swift-argument-parser, Swift 6 language mode)
- `VoxClawApp.swift` — dual-mode `@main` using two-struct pattern (VoxClawLauncher + VoxClawApp)
- `AppState.swift` — `@Observable @MainActor` with session state, word array, current index, pause flag
- `KeychainHelper.swift` — read API key via Security framework (`SecItemCopyMatching`)
- `ModeDetector.swift` — check `ProcessInfo.arguments` and `isatty(STDIN_FILENO)`
- Create GitHub repo `malpern/VoxClaw`, init git, initial commit
- **Verify:** `swift build` succeeds, `swift run VoxClaw` shows menu bar icon, keychain read works

### Phase 2: Audio Pipeline
- `TTSService.swift` — `actor`, POST to `/v1/audio/speech` with `gpt-4o-mini-tts`/`onyx`/`pcm`, stream via `URLSession.bytes(for:)`, yield 4800-byte chunks (100ms each)
- `AudioPlayer.swift` — `@MainActor`, AVAudioEngine + AVAudioPlayerNode at 24kHz mono Float32, `scheduleChunk()` converts Int16→Float32, `currentTime` via `playerTime(forNodeTime:)`, `totalDuration` from byte count
- Wire up a basic test: `voxclaw "Hello world"` plays audio
- **Verify:** Audio plays within ~500ms of invocation, `currentTime` advances correctly

### Phase 3: Floating Panel
- `FloatingPanel.swift` — NSPanel subclass: `.borderless`, `.nonactivatingPanel`, `.floating` level, `hidesOnDeactivate = false`, `ignoresMouseEvents = true`, clear background
- `PanelController.swift` — calculate position (top center, 1/3 screen width, 162pt tall), slide-down + fade-in animation (0.35s ease-out), slide-up + fade-out dismiss (0.3s ease-in)
- `FlowLayout.swift` — SwiftUI `Layout` protocol for word wrapping
- `FloatingPanelView.swift` — dark `RoundedRectangle(cornerRadius: 20)` background, `ScrollViewReader` for auto-scroll, per-word `Text` with `.custom("Helvetica Neue", size: 28).weight(.medium)`, yellow highlight background on current word
- **Verify:** Panel appears with hardcoded words and timer-driven highlight

### Phase 4: Word Timing + Sync
- `WordTimingEstimator.swift` — split text into words, assign proportional durations by character count, add punctuation pauses (+300ms for `.!?`, +150ms for `,`, +500ms for paragraph breaks), normalize to total audio duration, binary search `wordIndex(at:in:)`
- `ReadingSession.swift` — orchestrator: create TTS stream, pipe chunks to AudioPlayer, calculate timings when all bytes received, run 30fps Timer to update `currentWordIndex` from `audioPlayer.currentTime`
- Handle the "timing not ready yet" gap: use heuristic 150ms/char until real duration known, then recalculate
- **Verify:** `voxclaw "The quick brown fox..."` highlights words in sync with audio

### Phase 5: CLI Input
- `CLIParser.swift` — `ParsableCommand` with `--audio-only/-a`, `--clipboard/-c`, `--file/-f`, `--voice`, `--listen/-l`, `--port`, positional `text` args
- `InputResolver.swift` — resolve from piped stdin, clipboard (NSPasteboard), file path, or positional args
- Wire into dual-mode launcher
- **Verify:** All input methods work: `voxclaw "text"`, `echo text | voxclaw`, `voxclaw -f file.txt`, `voxclaw -c`

### Phase 6: Menu Bar, Keyboard, Polish
- `MenuBarView.swift` — "Paste & Read" (Cmd+Shift+V), "Read from File...", "Network Listener" toggle, "Audio Only Mode" toggle, "Pause/Resume" (when active), "Stop", "Quit"
- `KeyboardMonitor.swift` — `NSEvent.addLocalMonitorForEvents`: Space=pause/resume, Escape=cancel, Left=skip back 3s, Right=skip forward 3s
- `FeedbackBadge.swift` — subtle transient indicator for keyboard actions (opacity + scale transition)
- Auto-dismiss: 0.5s delay after audio ends, then collapse animation
- **Verify:** All keyboard controls work, menu bar actions work end-to-end

### Phase 7: Network Listener
- `NetworkListener.swift` — uses Network.framework `NWListener` on configurable TCP port (default 4140)
  - Bonjour advertisement as `_voxclaw._tcp` for easy discovery
  - Accepts incoming TCP connections
  - Supports two protocols:
    1. **HTTP POST** — `POST /read` with JSON body `{"text": "..."}` or plain text body
    2. **Raw TCP** — plain text terminated by connection close
  - Returns 200 OK with `{"status": "reading"}` for HTTP, or silent ack for raw TCP
- `NetworkSession.swift` — handles individual connection lifecycle
  - Reads data from NWConnection
  - Detects HTTP vs raw TCP by checking first bytes for "POST"
  - Parses text from request body
  - Dispatches to `ReadingSession` on main actor
  - Sends response and closes connection
- Wire into `AppState`: `isListening` flag, shown in menu bar
- Wire into `CLIParser`: `--listen` flag starts menu bar app + listener, `--port` sets port
- **Verify:** `curl -X POST http://localhost:4140/read -d '{"text":"Hello from network"}'` triggers reading

### Phase 8: Build Scripts + Install
- `Scripts/package_app.sh` — build release, create `.app` bundle with Info.plist
- `Scripts/install-cli.sh` — symlink binary to `/usr/local/bin/voxclaw`
- **Verify:** `.app` launches as menu bar only, `voxclaw` works from any terminal

## CLI Usage

```bash
voxclaw "Hello, this is a test."       # direct text
echo "Read this" | voxclaw             # piped stdin
voxclaw --file ~/speech.txt            # from file
voxclaw --clipboard                    # from clipboard
voxclaw --audio-only "No overlay"      # audio only
voxclaw --listen                       # start network listener on port 4140
voxclaw --listen --port 8080           # custom port
voxclaw                                # launch menu bar app (no args)
```

## Network Protocol

### HTTP Mode
```
POST /read HTTP/1.1
Content-Type: application/json

{"text": "Hello from the network"}
```

Response:
```
HTTP/1.1 200 OK
Content-Type: application/json

{"status": "reading"}
```

### Raw TCP Mode
Connect to the port, send plain text, close connection. VoxClaw reads whatever was received.

### Discovery
VoxClaw advertises via Bonjour as `_voxclaw._tcp` so other devices on the LAN can discover it:
```bash
dns-sd -B _voxclaw._tcp
```

## Technical Notes

- **OpenAI TTS**: `gpt-4o-mini-tts` model, `onyx` voice, `pcm` format (24kHz 16-bit signed LE mono)
- **API key**: Keychain — `security find-generic-password -a "openai" -s "openai-voice-api-key" -w`
- **Panel sizing**: 1/3 screen width, 162pt tall (~2.25"), 20pt corner radius, 8pt below menu bar
- **Text**: Helvetica Neue Medium 28pt, white on black(0.85), yellow(0.35) highlight with 4pt corner radius
- **Network**: TCP via Network.framework NWListener, default port 4140, Bonjour `_voxclaw._tcp`
- **No Whisper alignment in MVP** — proportional estimation with punctuation weighting

## Verification

1. `swift build` compiles with no errors
2. `swift run VoxClaw` shows menu bar icon, no Dock icon
3. `swift run VoxClaw "Test sentence"` shows floating panel + plays audio with synchronized highlighting
4. Spacebar pauses/resumes, Escape closes, arrows skip
5. `voxclaw -c` reads clipboard, `echo text | voxclaw` reads stdin
6. Panel slides down from top, collapses when done
7. `voxclaw --listen` starts network listener, `curl` triggers reading
8. `./Scripts/package_app.sh && ./Scripts/install-cli.sh` produces working CLI
