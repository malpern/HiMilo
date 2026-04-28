# Project Discovery

Techniques for understanding Apple platform project structure before building.

**Important**: Use `swift build` only for standalone `Package.swift` (no .xcodeproj). For Xcode projects—including those with SPM dependencies—use `xcodebuild`. Only use `-workspace` for CocoaPods or multi-project setups.

## Finding Project Files

```bash
ls Package.swift 2>/dev/null && echo "SPM Package found"
ls -d *.xcworkspace 2>/dev/null && echo "Workspace found"
ls -d *.xcodeproj 2>/dev/null && echo "Xcode project found"
```

## Listing Schemes and Targets

```bash
# Auto-detects when only one project/workspace exists
xcodebuild -list

# Explicit (only needed when multiple exist)
xcodebuild -project <Name>.xcodeproj -list
xcodebuild -workspace <Name>.xcworkspace -list
```

### Sample Output

```
Information about project "MyApp":
    Targets:
        MyApp
        MyAppTests
        MyAppUITests

    Build Configurations:
        Debug
        Release

    Schemes:
        MyApp
        MyAppTests
```

**Note**: Targets are buildable units; Schemes are named configurations specifying which targets to build.

## Swift Packages

### Describe Package

```bash
swift package describe
```

### JSON Output

```bash
swift package describe --type json
```

## Platform Support

```bash
xcodebuild -showdestinations -scheme <SchemeName>
```

## Mixed Projects

When a repository contains both `.xcodeproj` and local `Package.swift` folders:

- Use `xcodebuild` for the main app (Xcode resolves SPM dependencies automatically)
- Local packages referenced by the project are built through `xcodebuild`, not `swift build`
- Use `swift build` only for standalone packages not referenced by any .xcodeproj

## Local Package Schemes

Xcode generates a scheme for each **target** in a local Swift package. Scheme names match the target name, not the package name.

```
MyUtilities/Package.swift
├── Target: NetworkKit
├── Target: StorageKit
└── Target: AnalyticsKit
```

Running `xcodebuild -list` shows schemes named after each target: `NetworkKit`, `StorageKit`, `AnalyticsKit`.

```bash
# Build the NetworkKit target
xcodebuild build -scheme NetworkKit -destination 'generic/platform=iOS'

# Run tests for StorageKit
xcodebuild test -scheme StorageKitTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

Building individual targets is faster than building the full app scheme.

## Quick Reference

| Goal | Command |
|------|---------|
| Find project files | `ls Package.swift *.xcworkspace *.xcodeproj 2>/dev/null` |
| List schemes | `xcodebuild -list` |
| Describe Swift package | `swift package describe` |
| Show destinations | `xcodebuild -showdestinations -scheme <Name>` |
| Build package target | `xcodebuild build -scheme <TargetName> -destination '<spec>'` |

## Complete Example

### Minimal

```bash
xcodebuild -list
```

### Full Discovery Script

```bash
echo "=== Project Discovery ==="

if [ -f "Package.swift" ]; then
    echo "Swift Package found"
    swift package describe 2>/dev/null || echo "  (run 'swift package resolve' first)"
fi

for ws in *.xcworkspace; do
    [ -e "$ws" ] || continue
    echo "Workspace: $ws"
    xcodebuild -workspace "$ws" -list 2>/dev/null | head -30
done

for proj in *.xcodeproj; do
    [ -e "$proj" ] || continue
    echo "Project: $proj"
    xcodebuild -project "$proj" -list 2>/dev/null | head -30
done
```

## Troubleshooting

### "The project does not contain a scheme"

**Cause**: Schemes may not be shared (stored in user-specific xcuserdata).

**Solution**:
1. In Xcode: Product → Scheme → Manage Schemes → check "Shared"
2. Shared schemes are stored in `<project>.xcodeproj/xcshareddata/xcschemes/`

### "Unable to find a workspace named..."

**Cause**: Incorrect path or filename (case-sensitive).

**Solution**:
```bash
find . -name "*.xcworkspace" -type d
```

### "xcodebuild: error: The project '...' does not contain a target named '...'"

**Cause**: Target name doesn't match or doesn't exist.

**Solution**:
```bash
xcodebuild -list
```
