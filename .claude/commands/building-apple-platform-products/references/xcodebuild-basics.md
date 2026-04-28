# xcodebuild Basics

Core concepts and command patterns for xcodebuild.

**Important**: The `-scheme` flag is required for most operations. Use `-workspace` only for CocoaPods or multi-project setups. Standard projects with SPM dependencies just use `.xcodeproj`.

## Command Structure

```bash
xcodebuild [action] [options] [build settings]
```

## Actions

| Action | Purpose |
|--------|---------|
| `build` | Build the target (default if no action specified) |
| `test` | Build and run tests |
| `build-for-testing` | Build for testing without running |
| `test-without-building` | Run tests without rebuilding |
| `archive` | Create an archive |
| `clean` | Remove build products |

## Info Options

These options display information without performing a build:

| Option | Purpose |
|--------|---------|
| `-list` | List schemes and targets |
| `-showdestinations` | Show available destinations for a scheme |
| `-showBuildSettings` | Display resolved build settings |

## Project Specification

xcodebuild auto-detects when only one project exists. Explicit flags are only needed when multiple projects/workspaces exist.

### Standard Project

```bash
# Auto-detects .xcodeproj
xcodebuild -scheme MyScheme build

# Explicit (when multiple projects exist)
xcodebuild -project MyApp.xcodeproj -scheme MyScheme build
```

### Workspace (CocoaPods or multi-project)

```bash
xcodebuild -workspace MyApp.xcworkspace -scheme MyScheme build
```

## Scheme Selection

Schemes define what to build and how:

```bash
# List available schemes
xcodebuild -list

# Build specific scheme
xcodebuild -scheme "MyApp" build
```

**Note**: Scheme names are case-sensitive.

## Build Configurations

```bash
# Debug build
xcodebuild -scheme "MyApp" -configuration Debug build

# Release build
xcodebuild -scheme "MyApp" -configuration Release build
```

If not specified, the scheme's default configuration is used.

## Derived Data Location

Build products go to derived data:

```bash
# Use custom derived data path
xcodebuild -derivedDataPath ./build build

# Default location: ~/Library/Developer/Xcode/DerivedData
```

## Build Settings Overrides

Override settings on the command line:

```bash
xcodebuild build \
  -scheme "MyApp" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER="com.example.app"
```

### Common Build Settings

| Setting | Purpose | Example |
|---------|---------|---------|
| `ONLY_ACTIVE_ARCH` | Build for all architectures | `NO` |
| `CODE_SIGNING_ALLOWED` | Disable code signing | `NO` |
| `CODE_SIGN_IDENTITY` | Signing identity | `""` (empty) |
| `CONFIGURATION_BUILD_DIR` | Build output directory | `./build` |
| `SYMROOT` | Build products path | `./build` |

## Output Control

```bash
# Quiet output (warnings and errors only)
xcodebuild -quiet build

# Show build settings for scheme
xcodebuild -showBuildSettings -scheme "MyApp"
```

## Multi-Action Commands

Combine actions in one command:

```bash
# Clean then build
xcodebuild clean build -scheme "MyApp"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 65 | Build or data error (generic failure) |
| 66 | Tests failed |
| 70 | Command failed |

## Dependency Resolution

For projects with Swift Package Manager dependencies:

```bash
# Resolve package dependencies
xcodebuild -resolvePackageDependencies
```

## SDK Selection

```bash
# Build for iOS Simulator SDK
xcodebuild -sdk iphonesimulator build

# Build for iOS Device SDK
xcodebuild -sdk iphoneos build

# List available SDKs
xcodebuild -showsdks
```

## Xcode Version Management

```bash
# Check current Xcode
xcode-select -p

# Switch Xcode version
sudo xcode-select -s /Applications/Xcode.app

# Run with specific Xcode (without switching)
DEVELOPER_DIR=/Applications/Xcode-15.4.app xcodebuild build
```

## Quick Reference

| Goal | Command |
|------|---------|
| List schemes | `xcodebuild -list` |
| Build | `xcodebuild build -scheme <name>` |
| Clean | `xcodebuild clean -scheme <name>` |
| Clean and build | `xcodebuild clean build -scheme <name>` |
| Show build settings | `xcodebuild -showBuildSettings -scheme <name>` |
| Show destinations | `xcodebuild -showdestinations -scheme <name>` |
| Resolve package dependencies | `xcodebuild -resolvePackageDependencies` |

## Example

```bash
xcodebuild build -scheme "MyApp"
```

## Troubleshooting

### "No such module 'ModuleName'"

**Cause**: Dependencies not resolved or missing framework.

**Solution**:
```bash
xcodebuild -resolvePackageDependencies
xcodebuild clean build -scheme "MyApp"
```

### "Code Sign error: No signing certificate..."

**Cause**: Code signing required but no certificate available.

**Solution**:
```bash
xcodebuild build -scheme "MyApp" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=""
```

### "The target '...' has an architecture 'arm64' that is incompatible..."

**Cause**: Architecture mismatch.

**Solution**:
```bash
xcodebuild build -scheme "MyApp" \
  ONLY_ACTIVE_ARCH=NO \
  EXCLUDED_ARCHS=""
```

### "Build input file cannot be found"

**Cause**: Missing source file or stale project references.

**Solution**:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean build -scheme "MyApp"
```

### "xcrun: error: unable to find utility..."

**Cause**: Xcode command line tools not properly configured.

**Solution**:
```bash
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
```
