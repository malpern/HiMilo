# VoxClaw - Claude Code Project Notes

## What it is

macOS menu bar app + CLI tool (SwiftPM, no Xcode) that reads text aloud using Apple TTS (default) or OpenAI TTS (optional BYOK). Shows a teleprompter-style floating overlay with synchronized word highlighting.

**Bundle ID:** `com.malpern.voxclaw`
**URL scheme:** `voxclaw://read?text=...`
**CLI command:** `voxclaw`

## Architecture

- **Single binary**, dual-mode: CLI or menu bar app depending on how it's launched (`ModeDetector`)
- **SpeechEngine protocol** abstracts Apple TTS (`AppleSpeechEngine`) and OpenAI TTS (`OpenAISpeechEngine`)
- **Distribution:** GitHub Releases (ad-hoc signed, or Developer ID for no-Gatekeeper-warning)
- **Packaging:** `Scripts/package_app.sh` (ad-hoc signed by default)

## Build & Test

```bash
swift build                    # Debug build
swift test                     # 75 tests
Scripts/compile_and_run.sh     # Build, package, and launch (dev loop)
Scripts/package_app.sh release # Release build (ad-hoc signed)
APP_IDENTITY="Developer ID Application: ..." Scripts/package_app.sh release  # Signed
```

## Integration Methods

```bash
# URL scheme
open "voxclaw://read?text=Hello%20world"

# Services menu
# Select text > right-click > Services > Read with VoxClaw

# Shortcuts CLI
shortcuts run "Read with VoxClaw" --input-string "Hello world"

# Network listener (toggle in Settings or --listen flag)
curl -X POST http://localhost:4140/read -d '{"text":"Hello"}'
curl -X POST http://localhost:4140/read -H 'Content-Type: application/json' -d '{"text":"Hello"}'
curl http://localhost:4140/status
```

## CLI Usage

```bash
voxclaw "Hello, world!"              # Read text aloud
voxclaw -a "Hello"                   # Audio only (no overlay)
voxclaw --clipboard                  # Read from clipboard
voxclaw --file article.txt           # Read from file
echo "Hello" | voxclaw              # Read from stdin
voxclaw --voice nova "Hello"         # OpenAI voice override
voxclaw --rate 1.5 "Hello"          # 1.5x speech speed
voxclaw --instructions "Read warmly" "Hello"  # OpenAI prosody control
voxclaw --output hello.mp3 "Hello"  # Save audio to file (OpenAI)
voxclaw --listen                     # Start HTTP listener on port 4140
voxclaw --listen --port 8080         # Custom port
voxclaw --send "Hello"              # Send text to running listener
voxclaw --status                     # Check if listener is running
```

## Key Conventions

- Tests use Swift Testing framework (`@Test`, `#expect`)
- Network integration tests are `@Suite(.serialized)` to avoid port conflicts
- Logging via `os.Logger` categories in `Log.swift`
- Keychain: `KeychainHelper` — checks `OPENAI_API_KEY` env var first, then system keychain
  - Set key: `security add-generic-password -a "openai" -s "openai-voice-api-key" -w "sk-..."`
- `@Observable` on `AppState` and `SettingsManager` — use stored properties with `didSet`, not computed, because `@Observable` can't track computed properties

## Logging

```bash
log stream --predicate 'subsystem == "com.malpern.voxclaw"' --level debug
```

## Release Workflow

Push a tag (e.g. `v1.0.0`) → `.github/workflows/release.yml` builds, packages, uploads `VoxClaw.zip` to GitHub Releases.

## Project Structure

```
Sources/
  VoxClawCore/    Library target (all logic)
  VoxClaw/        Thin executable (main.swift → VoxClawLauncher.main())
Tests/
  VoxClawCoreTests/   75+ tests
Scripts/
  compile_and_run.sh  Kill → build → package → launch (dev loop)
  package_app.sh      Build .app bundle
  install-cli.sh      Symlink voxclaw binary to /usr/local/bin
docs/
  privacy.html        https://malpern.github.io/VoxClaw/privacy.html
  index.html
```
