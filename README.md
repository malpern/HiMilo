# VoxClaw

A macOS menu bar app + CLI tool that reads text aloud using OpenAI TTS while displaying a teleprompter-style floating overlay with synchronized word highlighting.

## Features

- **Teleprompter Overlay** — Dynamic Island-style floating panel at the top of your screen with word-by-word highlighting synced to audio
- **Multiple Input Methods** — Text from arguments, stdin pipe, file, clipboard, or network
- **Menu Bar App** — Lives in your menu bar, paste and read anytime
- **CLI Tool** — Launch from terminal via `voxclaw`
- **Network Mode** — Accept text from other devices on your local network
- **Keyboard Controls** — Space (pause/resume), Escape (stop), Arrow keys (skip ±3s)

## Installation

### Prerequisites

- macOS 26+
- OpenAI API key stored in Keychain or environment variable

### Store your API key

```bash
security add-generic-password -a "openai" -s "openai-voice-api-key" -w "sk-..."
```

Or set the environment variable:

```bash
export OPENAI_API_KEY="sk-..."
```

### Build & Install

```bash
swift build -c release
./Scripts/package_app.sh
./Scripts/install-cli.sh
```

## Usage

### CLI

```bash
voxclaw "Hello, this is a test."       # direct text
echo "Read this aloud" | voxclaw       # piped stdin
voxclaw --file ~/speech.txt            # from file
voxclaw --clipboard                    # from clipboard
voxclaw --audio-only "No overlay"      # audio only, no panel
voxclaw --listen                       # network mode: listen for text from LAN
voxclaw                                # launch menu bar app (no args)
```

### Network Mode

Start VoxClaw in network listener mode on your Mac:

```bash
voxclaw --listen                       # listens on port 4140
voxclaw --listen --port 8080           # custom port
```

Send text from another device on your local network:

```bash
# From any machine on the same network
curl -X POST http://voxclaw-mac.local:4140/read -d '{"text": "Hello from my phone"}'

# Or with netcat
echo "Read this text" | nc voxclaw-mac.local 4140
```

### Menu Bar

When launched without arguments, VoxClaw runs as a menu bar app with:

- **Paste & Read** (⌘⇧V) — Read text from clipboard
- **Read from File...** — Open a text file to read
- **Network Listener** — Toggle listening for text from LAN devices
- **Audio Only Mode** — Toggle overlay on/off
- **Pause/Resume** — When actively reading
- **Stop** — Cancel current reading
- **Quit** (⌘Q)

### Keyboard Controls (while reading)

| Key | Action |
|-----|--------|
| Space | Pause / Resume |
| Escape | Stop |
| ← | Skip back 3 seconds |
| → | Skip forward 3 seconds |

## Development

### Project Structure

```
Sources/
  VoxClawCore/       Library target (all logic)
  VoxClaw/           Thin executable (entry point only)
Tests/
  VoxClawCoreTests/  Unit + integration tests
```

### Running Tests

```bash
swift test
```

59 tests across 8 suites covering word timing math, app state, HTTP parsing, mode detection, input resolution, and network listener integration.

### CI

GitHub Actions runs on every push to `main` and on pull requests. See `.github/workflows/ci.yml`.

## Architecture

Swift Package Manager with a library target (`VoxClawCore`) and thin executable (`VoxClaw`):

```
Input (args/stdin/file/clipboard/network)
  → InputResolver resolves to String
  → ReadingSession orchestrator
  → TTSService streams PCM from OpenAI API
  → AudioPlayer schedules AVAudioEngine buffers
  → WordTimingEstimator maps playback position → word index
  → FloatingPanelView highlights current word
  → Panel collapses when done
```

**Tech Stack:**
- Swift 6.2 with strict concurrency
- SwiftUI + NSPanel for floating overlay
- AVAudioEngine for low-latency audio playback
- OpenAI TTS API (`gpt-4o-mini-tts`, `onyx` voice, raw PCM streaming)
- Swift Argument Parser for CLI
- NWListener (Network.framework) for LAN text input

## License

MIT
