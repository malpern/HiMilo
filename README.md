# VoxClaw

<p align="center">
  <a href="https://malpern.github.io/VoxClaw/">
    <img src="docs/voxclaw-hero.png" alt="VoxClaw app icon — a crab claw holding a speaker" width="320">
  </a>
</p>

<p align="center">
  <a href="https://malpern.github.io/VoxClaw/">
    <img src="https://img.shields.io/badge/Visit-Website-1f6feb?style=for-the-badge&logo=google-chrome&logoColor=white" alt="Visit Website">
  </a>
  <br/>
  <a href="https://github.com/malpern/VoxClaw/releases/latest/download/VoxClaw.zip">
    <img src="https://img.shields.io/badge/Download-Mac%20App-238636?style=for-the-badge&logo=apple&logoColor=white" alt="Download Mac App">
  </a>
</p>

**Give OpenClaw a voice.**

[OpenClaw](https://github.com/openclaw/openclaw) is the open-source personal AI assistant that runs on your devices — your files, your shell, your messaging apps (WhatsApp, Telegram, Slack, Discord, and more). It lives where you work. **VoxClaw gives it a voice.**

Run VoxClaw on your Mac and hear OpenClaw speak to you. When OpenClaw runs on another computer — a server, a headless box, or a different machine — send text to your Mac over the network and VoxClaw speaks it aloud with high-quality text-to-speech. Apple's built-in voices work out of the box; add your own OpenAI API key for neural voices when you want that extra polish. Paste text, pipe from the CLI, or stream from any device on your LAN — and listen.

---

A macOS menu bar app + CLI tool that reads text aloud using OpenAI TTS while displaying a teleprompter-style floating overlay with synchronized word highlighting.

## Features

- **Onboarding Wizard** — First-run setup walks you through voice selection, API key, agent location, and launch at login
- **Teleprompter Overlay** — Dynamic Island-style floating panel at the top of your screen with word-by-word highlighting synced to audio
- **Two Voice Engines** — OpenAI neural voices (bring your own API key) or Apple's built-in TTS with zero setup
- **Multiple Input Methods** — Text from arguments, stdin pipe, file, clipboard, or network
- **Menu Bar App** — Lives in your menu bar, paste and read anytime
- **CLI Tool** — Launch from terminal via `voxclaw`
- **Network Mode** — Accept text from other devices on your local network via HTTP
- **URL Scheme** — Trigger from any app with `voxclaw://read?text=...`
- **Keyboard Controls** — Space (pause/resume), Escape (stop), Arrow keys (skip ±3s)

## Installation

### Prerequisites

- macOS 26+
- OpenAI API key (optional — Apple's built-in voices work without one)

The onboarding wizard walks you through setup on first launch. To store an API key manually:

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
voxclaw --voice nova "Hello"           # OpenAI voice override
voxclaw --rate 1.5 "Hello"            # 1.5x speech speed
voxclaw --output hello.mp3 "Hello"    # save audio to file (OpenAI)
voxclaw --listen                       # network mode: listen for text from LAN
voxclaw --send "Hello from CLI"        # send text to a running listener
voxclaw --status                       # check if listener is running
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
# JSON body
curl -X POST http://your-mac.local:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello from my phone"}'

# With voice and rate overrides
curl -X POST http://your-mac.local:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello", "voice": "nova", "rate": 1.3}'

# Plain text body
curl -X POST http://your-mac.local:4140/read -d 'Hello from my phone'

# Health check (returns reading state, session state, word count)
curl http://your-mac.local:4140/status
```

### URL Scheme & Integration

```bash
# URL scheme — trigger from any app or script
open "voxclaw://read?text=Hello%20world"

# Services menu — select text in any app, right-click > Services > Read with VoxClaw

# Shortcuts / Siri
shortcuts run "Read with VoxClaw"
```

### Menu Bar

When launched without arguments, VoxClaw runs as a menu bar app with:

- **Paste & Read** (⌘⇧V) — Read text from clipboard
- **Read from File...** — Open a text file to read
- **Network Listener** — Toggle listening for text from LAN devices
- **Audio Only Mode** — Toggle overlay on/off
- **Pause/Resume** — When actively reading
- **Stop** — Cancel current reading
- **Settings** — Voice engine, API key, launch at login
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
- OpenAI TTS API (`gpt-4o-mini-tts`, `onyx` voice, raw PCM streaming) + Apple AVSpeechSynthesizer fallback
- Swift Argument Parser for CLI
- NWListener (Network.framework) for LAN text input
- Keychain Services for secure API key storage

## For Agents

If you're an AI agent and want to speak text aloud on the user's Mac, read [`SKILL.md`](SKILL.md). It has the full HTTP API, error codes, and examples. Quick version:

```bash
curl -X POST http://<mac-ip>:4140/read -H 'Content-Type: application/json' \
  -d '{"text": "Hello from your agent", "voice": "nova", "rate": 1.0}'
```

## License

MIT
