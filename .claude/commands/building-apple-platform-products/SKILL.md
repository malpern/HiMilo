---
name: building-apple-platform-products
description: Builds, tests, archives, and deploys Swift packages and Xcode projects for Apple platforms. Use when running xcodebuild, swift build, swift test, xcrun simctl, xcrun devicectl, or any xcrun developer tool. Covers project discovery, simulator management, physical device deployment, code signing, profiling, distribution, and binary inspection.
---

# Building Apple Platform Products

Build, test, archive, deploy, and automate Swift packages and Xcode projects for Apple platforms.

## When to Use This Skill

Use this skill when you need to:
- Build an iOS, macOS, tvOS, watchOS, or visionOS app
- Build a Swift package
- Run unit tests or UI tests
- Create an archive for distribution
- Discover project structure (schemes, targets, configurations)
- Manage simulators (create, boot, configure, install apps)
- Deploy to physical devices
- Automate simulator testing (permissions, push notifications, screenshots, location)
- Sign, notarize, or distribute apps
- Inspect binaries or debug symbols
- Profile app performance
- Resolve xcrun tool paths or switch Xcode versions

## xcrun Tool Resolution

`xcrun` resolves and executes Xcode developer tools without hardcoded paths. All tools in this skill are accessed through xcrun (e.g., `xcrun simctl`, `xcrun devicectl`, `xcrun xctrace`).

| Goal | Command |
|------|---------|
| Find tool path | `xcrun --find <tool>` |
| Show SDK path | `xcrun --sdk iphoneos --show-sdk-path` |
| Switch Xcode (per-command) | `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer xcrun <tool>` |
| Switch Xcode (system) | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Clear cache after upgrade | `xcrun --kill-cache` |

For tool resolution priority, toolchain selection, or debugging, see [xcrun-basics.md](references/xcrun-basics.md).

## Tool Selection

| Project Type | Primary Tool | When to Use |
|--------------|--------------|-------------|
| Standalone `Package.swift` | `swift build` | Libraries, CLI tools, cross-platform Swift (no .xcodeproj) |
| `.xcworkspace` | `xcodebuild -workspace` | CocoaPods or multi-project setups |
| `.xcodeproj` | `xcodebuild` | Standard Xcode projects (including those with SPM dependencies) |

**Important**: The `swift build` / `swift test` commands only work for **standalone Swift packages**. If a Swift package is embedded as a submodule within an Xcode project, you must use `xcodebuild` with the appropriate scheme—the Swift CLI cannot orchestrate builds in that context.

## Project Discovery

Before building, discover the project structure:

```bash
# Find what project files exist
ls Package.swift *.xcworkspace *.xcodeproj 2>/dev/null

# List schemes and targets (auto-detects project)
xcodebuild -list

# Describe package (standalone SPM only)
swift package describe
```

**Note**: When an Xcode project references a local Swift package, each package **target** gets its own scheme (named after the target, not the package). Use these schemes to build individual targets without building the entire app.

For mixed projects, shared schemes, or detailed output parsing, see [project-discovery.md](references/project-discovery.md).

## Swift Package Manager Commands

**Important**: These commands only work for standalone Swift packages, not Swift Package Manager submodules in Xcode projects.

| Goal | Command |
|------|---------|
| Build (debug) | `swift build` |
| Build (release) | `swift build -c release` |
| Run executable | `swift run [<target>]` |
| Run tests | `swift test` |
| Run specific test | `swift test --filter <TestClass.testMethod>` |
| Show binary path | `swift build --show-bin-path` |
| Clean | `swift package clean` |
| Initialize | `swift package init [--type library\|executable]` |

For cross-compilation, Package.swift syntax, or dependency management, see [swift-package-manager.md](references/swift-package-manager.md).

## xcodebuild Commands

**Command structure**: `xcodebuild [action] -scheme <name> [-workspace|-project] [options] [BUILD_SETTING=value]`

| Goal | Command |
|------|---------|
| List schemes | `xcodebuild -list` |
| Build | `xcodebuild build -scheme <name>` |
| Test | `xcodebuild test -scheme <name> -destination '<spec>'` |
| Build for testing | `xcodebuild build-for-testing -scheme <name> -destination '<spec>'` |
| Test without build | `xcodebuild test-without-building -scheme <name> -destination '<spec>'` |
| Archive | `xcodebuild archive -scheme <name> -archivePath <path>.xcarchive` |
| Clean | `xcodebuild clean -scheme <name>` |

**Required**: `-scheme` is always required. Add `-workspace` or `-project` when multiple exist.
**For tests**: `-destination` is required for iOS/tvOS/watchOS/visionOS targets.

For build settings, SDK selection, or CI configuration, see [xcodebuild-basics.md](references/xcodebuild-basics.md).

## Common Destinations

| Platform | Destination Specifier |
|----------|----------------------|
| macOS | `'platform=macOS'` |
| iOS Simulator | `'platform=iOS Simulator,name=iPhone 17'` |
| iOS Device | `'platform=iOS,id=<UDID>'` |
| tvOS Simulator | `'platform=tvOS Simulator,name=Apple TV'` |
| watchOS Simulator | `'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'` |
| visionOS Simulator | `'platform=visionOS Simulator,name=Apple Vision Pro'` |
| Generic (build only) | `'generic/platform=iOS'` |

**Note**: Simulator names change with each Xcode release. Always verify available simulators:
```bash
xcrun simctl list devices available
```

For all platforms, multiple destinations, or troubleshooting destination errors, see [destinations.md](references/destinations.md).

## Simulator Management (simctl)

`xcrun simctl` manages the full simulator lifecycle and enables test automation without launching Xcode.

| Goal | Command |
|------|---------|
| List available simulators | `xcrun simctl list devices available` |
| Create simulator | `xcrun simctl create "<name>" "<type>" "<runtime>"` |
| Boot / shutdown | `xcrun simctl boot <UDID>` / `xcrun simctl shutdown <UDID>` |
| Install app | `xcrun simctl install booted <path.app>` |
| Launch app | `xcrun simctl launch booted <bundle-id>` |
| Grant permissions | `xcrun simctl privacy booted grant all <bundle-id>` |
| Push notification | `xcrun simctl push booted <bundle-id> <file.apns>` |
| Set appearance | `xcrun simctl ui booted appearance dark` |
| Override status bar | `xcrun simctl status_bar booted override --time "9:41"` |
| Open URL / deep link | `xcrun simctl openurl booted "<url>"` |
| Take screenshot | `xcrun simctl io booted screenshot <file.png>` |
| Record video | `xcrun simctl io booted recordVideo <file.mov>` |
| Set location | `xcrun simctl location booted set <lat>,<lon>` |
| Stream logs | `xcrun simctl spawn booted log stream --predicate '...'` |
| Download runtime | `xcodebuild -downloadPlatform iOS` |

For app lifecycle, environment variables, privacy services, media, diagnostics, and runtime management, see [simctl.md](references/simctl.md).

## Physical Device Deployment (devicectl)

`xcrun devicectl` manages physical devices running iOS 17+. Introduced in Xcode 15.

| Goal | Command |
|------|---------|
| List devices | `xcrun devicectl list devices` |
| List devices (JSON) | `xcrun devicectl list devices --json-output /tmp/devices.json` |
| Install app | `xcrun devicectl device install app --device <ID> <path>` |
| Launch app | `xcrun devicectl device process launch --device <ID> <bundle-id>` |
| Copy file from device | `xcrun devicectl device copy from --device <ID> ...` |
| List installed apps | `xcrun devicectl device info apps --device <ID>` |

**Important**: Requires iOS 17+, Developer Mode enabled, and valid code signing. JSON output is the only stable scripting interface.

For file transfer, process management, device pairing, limitations, and troubleshooting, see [devicectl.md](references/devicectl.md).

## Code Signing

| Goal | Command |
|------|---------|
| List signing identities | `security find-identity -v -p codesigning` |
| Disable signing (build) | `CODE_SIGNING_ALLOWED=NO` |
| Auto provisioning | `-allowProvisioningUpdates` |
| Verify signature | `codesign --verify --verbose=4 MyApp.app` |

For CI keychain setup, manual vs automatic signing, and build settings, see [code-signing.md](references/code-signing.md).

## Reference Files

| Topic | File | When to Read |
|-------|------|--------------|
| xcrun Basics | [xcrun-basics.md](references/xcrun-basics.md) | Tool resolution, Xcode switching, SDK paths |
| Project Discovery | [project-discovery.md](references/project-discovery.md) | Mixed projects, shared schemes |
| Swift Package Manager | [swift-package-manager.md](references/swift-package-manager.md) | Cross-compilation, Package.swift syntax |
| xcodebuild Basics | [xcodebuild-basics.md](references/xcodebuild-basics.md) | Build settings, SDK selection |
| Destinations | [destinations.md](references/destinations.md) | All platforms, multiple destinations |
| Testing | [testing.md](references/testing.md) | Test filtering, parallel execution, coverage |
| Archiving | [archiving.md](references/archiving.md) | Archive creation |
| Simulator Management | [simctl.md](references/simctl.md) | Device lifecycle, app management, automation |
| Physical Devices | [devicectl.md](references/devicectl.md) | iOS 17+ device deployment |
| Code Signing | [code-signing.md](references/code-signing.md) | Certificates, provisioning, CI keychain |
| Profiling & Results | [profiling-and-results.md](references/profiling-and-results.md) | xctrace, xcresulttool, coverage |
| Distribution | [distribution.md](references/distribution.md) | IPA export, notarization, App Store upload |
| Binary Tools | [binary-tools.md](references/binary-tools.md) | lipo, otool, dsymutil, atos, plutil, docc |
| CI/CD Patterns | [ci-cd-patterns.md](references/ci-cd-patterns.md) | Complete pipelines, GitHub Actions, log capture |
| Troubleshooting | [troubleshooting.md](references/troubleshooting.md) | Error index across all topics |

## Common Pitfalls

1. **swift build with Xcode submodules**: Only works for standalone packages. Use `xcodebuild` with the package's scheme instead.
2. **Missing destination for iOS**: Use `-destination 'generic/platform=iOS'` for builds, or specify a simulator for tests.
3. **Unnecessary workspace flag**: Only use `-workspace` for CocoaPods or multi-project setups. Standard projects with SPM dependencies just use `.xcodeproj`.
4. **Case-sensitive scheme names**: Run `xcodebuild -list` to see exact scheme names.
5. **Outdated simulator names**: Names change with Xcode versions. Run `xcrun simctl list devices available`.
6. **Code signing errors**: Add `CODE_SIGNING_ALLOWED=NO` for builds that don't require signing.
7. **Stale xcrun cache**: After Xcode upgrades, run `xcrun --kill-cache`.
8. **devicectl only works with iOS 17+**: Older devices are invisible to devicectl.
9. **xctrace outputs to stderr**: Redirect with `2>&1` when parsing `xcrun xctrace list devices`.
10. **JSON output for scripting**: Both `simctl` and `devicectl` provide JSON output flags — always prefer structured output over parsing human-readable text.
