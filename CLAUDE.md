# HiMilo - Claude Code Project Notes

## Architecture

- **Menu bar app** (SwiftPM, no Xcode project) with optional CLI companion (`milo`)
- **SpeechEngine protocol** abstracts Apple TTS (default) and OpenAI TTS (optional BYOK)
- **Dual distribution:** App Store (sandboxed) + CLI (full features, separate install)
- Packaging via `Scripts/package_app.sh` (use `APP_STORE=1` for sandboxed build)

## App Store Submission Checklist

- [ ] **App Privacy nutrition labels** in App Store Connect: declare that text data is shared with OpenAI when the user opts into OpenAI voices. Category: "Data Used to Provide the App's Primary Purpose", shared with third party (OpenAI), data type: "Other Data" (reading text). Only collected when user explicitly enables OpenAI and enters their own API key.
- [ ] **Privacy policy** must mention OpenAI data sharing and link to OpenAI's privacy policy
- [ ] Verify sandbox entitlements are correct (`HiMilo-AppStore.entitlements`)
- [ ] Test with `APP_STORE=1 Scripts/package_app.sh` before submission
- [ ] Provide App Review notes explaining the app works without an API key (Apple reviewer won't have one)

## Build & Test

```bash
swift build          # Debug build
swift test           # 75 tests
APP_STORE=1 Scripts/package_app.sh release  # App Store build
Scripts/package_app.sh                       # Dev build (ad-hoc signed)
```

## Key Conventions

- Tests use Swift Testing framework (`@Test`, `#expect`)
- Network integration tests are `@Suite(.serialized)` to avoid port conflicts
- Logging via `os.Logger` categories in `Log.swift`
- Keychain: `SandboxedKeychainHelper` (App Store), `KeychainHelper` (CLI, supports env vars)
