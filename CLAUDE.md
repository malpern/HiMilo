# HiMilo - Claude Code Project Notes

## Architecture

- **Menu bar app** (SwiftPM, no Xcode project) with optional CLI companion (`milo`)
- **SpeechEngine protocol** abstracts Apple TTS (default) and OpenAI TTS (optional BYOK)
- **Dual distribution:** App Store (sandboxed) + CLI (full features, separate install)
- Packaging via `Scripts/package_app.sh` (use `APP_STORE=1` for sandboxed build)

## Integration Methods

Other apps can send text to HiMilo via:
- **URL Scheme:** `open "himilo://read?text=Hello%20world"`
- **Services Menu:** select text > right-click > Services > Read with HiMilo
- **App Intents / Shortcuts:** "Read Text Aloud" intent

## App Store Submission Checklist

### Code/Build (can be done now)
- [x] App Sandbox entitlements (`HiMilo-AppStore.entitlements`)
- [x] Privacy disclosure in Settings UI for OpenAI data sharing
- [x] Icon path fixed in `package_app.sh`
- [x] Info.plist: CFBundleInfoDictionaryVersion, CFBundleSupportedPlatforms, NSHumanReadableCopyright
- [x] Provisioning profile embedding support in `package_app.sh`
- [ ] Test full flow: `APP_STORE=1 Scripts/package_app.sh release`

### Apple Developer Program (requires enrollment, $99/year)
- [ ] Enroll in Apple Developer Program
- [ ] Create "Mac App Distribution" certificate
- [ ] Create "Mac Installer Distribution" certificate
- [ ] Create Mac App Store provisioning profile for `com.malpern.himilo`

### App Store Connect Metadata
- [x] **Privacy policy URL** — https://malpern.github.io/HiMilo/privacy.html (in `docs/privacy.html`)
- [x] **Support URL** — https://github.com/malpern/HiMilo/issues
- [ ] **App Privacy nutrition labels** — declare "Other Data" (reading text) shared with OpenAI when user opts in. Purpose: "App Functionality". Not linked to identity. Not tracking.
- [ ] **Screenshots** — at least 1 at 1280x800, 1440x900, 2560x1600, or 2880x1800
- [ ] **Description, keywords, subtitle** (subtitle max 30 chars)
- [ ] **Category** — Primary: Utilities, Secondary: Productivity
- [ ] **Age rating questionnaire** — answer No to all (qualifies for 4+)
- [ ] **App Review notes**: "HiMilo works out of the box with Apple's built-in voices — no account or API key required. The optional OpenAI voice feature uses BYOK (Bring Your Own Key). To test core functionality, use the default Apple voice. The app runs as a menu bar agent (LSUIElement) and does not appear in the Dock."

### Submission
- [ ] Build: `APP_STORE=1 APP_IDENTITY="3rd Party Mac Developer Application: ..." PROVISIONING_PROFILE=path/to/profile.provisionprofile Scripts/package_app.sh release`
- [ ] Package: `productbuild --sign "3rd Party Mac Developer Installer: ..." --component HiMilo.app /Applications HiMilo.pkg`
- [ ] Upload via Transporter app or `xcrun altool`

## Build & Test

```bash
swift build                    # Debug build
swift test                     # 75 tests
Scripts/compile_and_run.sh     # Build, package, and launch (dev)
APP_STORE=1 Scripts/package_app.sh release  # App Store build
Scripts/package_app.sh                       # Dev build (ad-hoc signed)
```

## Key Conventions

- Tests use Swift Testing framework (`@Test`, `#expect`)
- Network integration tests are `@Suite(.serialized)` to avoid port conflicts
- Logging via `os.Logger` categories in `Log.swift`
- Keychain: `SandboxedKeychainHelper` (App Store), `KeychainHelper` (CLI, supports env vars)
