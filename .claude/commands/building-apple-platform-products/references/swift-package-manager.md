# Swift Package Manager Reference

Complete reference for `swift build` and related commands.

**Important**: These commands only work for **standalone Swift packages**. If a Swift package is embedded as a submodule within an Xcode project or workspace, you must use `xcodebuild` with the appropriate scheme instead.

## When to Use Swift Package Manager

**Use `swift build` when**:
- Project is a standalone `Package.swift` (not embedded in an Xcode project)
- Building libraries or command-line tools
- Cross-platform Swift code
- No need for Xcode-specific features

**Use `xcodebuild` instead when**:
- Swift package is a submodule within an Xcode project
- Building iOS/tvOS/watchOS/visionOS apps (simulators required)
- UI testing needed
- Creating archives for distribution
- Project uses Xcode-specific resources (Storyboards, asset catalogs, etc.)

## Build Commands

### Debug Build (default)

```bash
swift build
```

### Release Build

```bash
swift build -c release
# or
swift build --configuration release
```

### Build Specific Target

```bash
swift build --target <TargetName>
```

### Build Specific Product

```bash
swift build --product <ProductName>
```

### Show Binary Output Path

```bash
swift build --show-bin-path

# Example output:
# /path/to/project/.build/arm64-apple-macosx/debug
```

### Verbose Output

```bash
swift build -v
# or
swift build --verbose
```

## Run Commands

### Run Default Executable

```bash
swift run
```

### Run Specific Target

```bash
swift run <TargetName>
```

### Run with Arguments

```bash
swift run <TargetName> -- --arg1 value1 --arg2 value2
```

### Run Release Build

```bash
swift run -c release <TargetName>
```

## Test Commands

### Run All Tests

```bash
swift test
```

### Filter Tests

```bash
# Run specific test class
swift test --filter MyTests

# Run specific test method
swift test --filter MyTests.testSpecificMethod

# Pattern matching (regex)
swift test --filter "Integration"
```

### Parallel Testing

```bash
# Enable parallel testing (default in Swift 5.5+)
swift test --parallel

# Disable parallel testing
swift test --no-parallel
```

### Code Coverage

```bash
swift test --enable-code-coverage

# Coverage data location:
# .build/debug/codecov/
```

## Package Management

### Initialize New Package

```bash
# Library (default)
swift package init

# Executable
swift package init --type executable

# Empty package
swift package init --type empty
```

### Dependency Resolution

```bash
# Resolve dependencies
swift package resolve

# Update dependencies to latest allowed versions
swift package update

# Show dependency graph
swift package show-dependencies
```

### Clean Build

```bash
# Clean build artifacts
swift package clean

# Full reset (removes .build directory)
swift package reset
```

## Cross-Compilation

### Build for Specific Architecture

```bash
# Build for Intel Mac
swift build --triple x86_64-apple-macosx

# Build for ARM Mac
swift build --triple arm64-apple-macosx
```

### Using Different Toolchain

```bash
swift build --toolchain /Library/Developer/Toolchains/swift-latest.xctoolchain
```

Or set environment variable:

```bash
export TOOLCHAINS=org.swift.latest
swift build
```

## Build Settings

### Custom Build Path

```bash
swift build --build-path /custom/path
```

### Optimization Flags

```bash
# Cross-module optimization (release builds)
swift build -c release -Xswiftc -cross-module-optimization
```

## Package.swift Reference

### Minimum Swift Tools Version

```swift
// swift-tools-version:5.9
```

### Platform Requirements

```swift
platforms: [
    .iOS(.v26),
    .macOS(.v26),
    .tvOS(.v26),
    .watchOS(.v26),
    .visionOS(.v26)
]
```

### Dependencies

```swift
dependencies: [
    .package(url: "https://github.com/example/repo.git", from: "1.0.0"),
    .package(path: "../LocalPackage")
]
```

### Targets

```swift
targets: [
    .target(
        name: "MyLibrary",
        dependencies: ["OtherLibrary"]
    ),
    .testTarget(
        name: "MyLibraryTests",
        dependencies: ["MyLibrary"]
    )
]
```

## Quick Reference

| Goal | Command |
|------|---------|
| Build (debug) | `swift build` |
| Build (release) | `swift build -c release` |
| Run executable | `swift run [<target>]` |
| Run tests | `swift test` |
| Filter tests | `swift test --filter <pattern>` |
| Show binary path | `swift build --show-bin-path` |
| Resolve dependencies | `swift package resolve` |
| Update dependencies | `swift package update` |
| Clean build | `swift package clean` |
| Full reset | `swift package reset` |

## Example

```bash
swift build
swift test
```

## Troubleshooting

### "error: root manifest not found"

**Cause**: No `Package.swift` in current directory.

**Solution**:
```bash
ls Package.swift
# If missing, initialize: swift package init
```

### "error: the package manifest at '...' cannot be accessed"

**Cause**: Syntax error in Package.swift or wrong Swift tools version.

**Solution**:
```bash
# Check Package.swift syntax
swift package dump-package
```

### "error: dependency '...' is not used by any target"

**Cause**: Package declared in dependencies but not used in any target.

**Solution**: Add the dependency to a target's `dependencies` array in Package.swift.

### "error: package '...' is using Swift tools version X but the installed toolchain requires Y"

**Cause**: Swift tools version mismatch.

**Solution**:
```bash
# Check your Swift version
swift --version

# Update swift-tools-version in Package.swift
```

### "error: could not find module '...' for target '...'"

**Cause**: Missing dependency or incorrect target name.

**Solution**:
```bash
swift package resolve
swift package update
```

### Build is slow or stale

**Cause**: Cached build artifacts.

**Solution**:
```bash
swift package clean
# or full reset
swift package reset
```
