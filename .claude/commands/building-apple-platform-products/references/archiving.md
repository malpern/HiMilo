# Archiving Reference

Creating archives for distribution.

**Important**: Archives require a scheme with a valid archive configuration. The scheme's archive action must be properly configured in Xcode, typically using the Release configuration.

## Archive Command

### Basic Archive

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive
```

### With Workspace

```bash
xcodebuild archive \
  -workspace MyApp.xcworkspace \
  -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive
```

### With Project

```bash
xcodebuild archive \
  -project MyApp.xcodeproj \
  -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive
```

## Destination for Archives

Archives typically use generic destinations:

### iOS

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/MyApp.xcarchive
```

### macOS

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -destination 'generic/platform=macOS' \
  -archivePath ./build/MyApp.xcarchive
```

### tvOS

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -destination 'generic/platform=tvOS' \
  -archivePath ./build/MyApp.xcarchive
```

### watchOS

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -destination 'generic/platform=watchOS' \
  -archivePath ./build/MyApp.xcarchive
```

### visionOS

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -destination 'generic/platform=visionOS' \
  -archivePath ./build/MyApp.xcarchive
```

## Archive Without Code Signing

For builds where signing is not needed:

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES
```

## Configuration Selection

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -configuration Release \
  -archivePath ./build/MyApp.xcarchive
```

**Note**: Archives use the scheme's archive configuration by default, which is typically Release.

## Derived Data Path

```bash
xcodebuild archive \
  -scheme "MyApp" \
  -derivedDataPath ./build/DerivedData \
  -archivePath ./build/MyApp.xcarchive
```

## Archive Contents

```
MyApp.xcarchive/
├── Info.plist                    # Archive metadata
├── Products/
│   └── Applications/
│       └── MyApp.app            # Built application
├── dSYMs/
│   └── MyApp.app.dSYM           # Debug symbols
├── SCMBlueprint/                 # Source control info
└── SwiftSupport/                 # Swift runtime (if applicable)
```

## Verifying Archive

### Check Contents

```bash
ls -la ./build/MyApp.xcarchive/Products/Applications/
```

### Check Info.plist

```bash
plutil -p ./build/MyApp.xcarchive/Info.plist
```

### Check App Info

```bash
plutil -p ./build/MyApp.xcarchive/Products/Applications/MyApp.app/Info.plist
```

## Archive Multiple Platforms

For universal apps or frameworks:

```bash
# iOS
xcodebuild archive -scheme "MyFramework" \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/MyFramework-iOS.xcarchive

# iOS Simulator
xcodebuild archive -scheme "MyFramework" \
  -destination 'generic/platform=iOS Simulator' \
  -archivePath ./build/MyFramework-iOSSimulator.xcarchive
```

## Quick Reference

| Goal | Command |
|------|---------|
| Create archive | `xcodebuild archive -scheme <name> -archivePath <path>.xcarchive` |
| iOS archive | `-destination 'generic/platform=iOS'` |
| macOS archive | `-destination 'generic/platform=macOS'` |
| No signing | `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` |
| Clean archive | `xcodebuild clean archive -scheme <name> -archivePath <path>` |
| Check archive | `plutil -p <path>.xcarchive/Info.plist` |

## Example

```bash
xcodebuild archive -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive
```

## Troubleshooting

### "Archive action requires specifying a scheme"

**Cause**: No `-scheme` flag provided.

**Solution**:
```bash
xcodebuild archive -scheme "MyApp" -archivePath ./build/MyApp.xcarchive
```

### "No signing certificate found"

**Cause**: Code signing required but no certificate available.

**Solution**:
```bash
xcodebuild archive -scheme "MyApp" \
  -archivePath ./build/MyApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=""
```

### "Archive not created"

**Cause**: Scheme's archive configuration is invalid or Release configuration fails.

**Solution**:
1. Verify scheme has archive action configured in Xcode
2. Test Release build: `xcodebuild build -scheme "MyApp" -configuration Release`

### "The archive is invalid"

**Cause**: Missing frameworks, dependencies, or Info.plist keys.

**Solution**:
```bash
# Check archive contents
ls -la ./build/MyApp.xcarchive/Products/Applications/
plutil -p ./build/MyApp.xcarchive/Info.plist
```
