# Destination Specifications

Complete reference for the `-destination` parameter across Apple platforms.

**Important**: Simulator names change with each Xcode release. Always verify available destinations with `xcrun simctl list devices available` before hardcoding names.

## Destination Format

```
-destination 'key=value,key=value,...'
```

Quote the destination specifier (single or double quotes both work).

## Discovering Available Destinations

### For a Specific Scheme

```bash
xcodebuild -showdestinations -scheme "MyScheme"
```

### List Available Simulators

```bash
xcrun simctl list devices available
```

### List Physical Devices

```bash
xcrun xctrace list devices
```

## macOS

### Current Mac

```bash
-destination 'platform=macOS'
```

### Specific Architecture

```bash
# ARM Mac (Apple Silicon)
-destination 'platform=macOS,arch=arm64'

# Intel Mac
-destination 'platform=macOS,arch=x86_64'
```

### Mac Catalyst

```bash
-destination 'platform=macOS,variant=Mac Catalyst'
```

## iOS Simulator

### By Device Name

```bash
-destination 'platform=iOS Simulator,name=iPhone 17'
-destination 'platform=iOS Simulator,name=iPhone 17 Pro'
-destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
-destination 'platform=iOS Simulator,name=iPhone 16e'
-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
-destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)'
```

### By Device Name and OS Version

```bash
-destination 'platform=iOS Simulator,name=iPhone 17,OS=26'
-destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

### By Device ID

```bash
-destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>'
```

Get simulator UDIDs with: `xcrun simctl list devices`

## iOS Device

Physical devices require device ID:

```bash
-destination 'platform=iOS,id=<DEVICE-UDID>'
```

Get device UDIDs with: `xcrun xctrace list devices`

## tvOS

### Simulator

```bash
-destination 'platform=tvOS Simulator,name=Apple TV'
-destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
-destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation) (at 1080p)'
```

### Device

```bash
-destination 'platform=tvOS,id=<DEVICE-UDID>'
```

## watchOS

### Simulator

```bash
-destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
-destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)'
-destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (44mm)'
```

### Device

```bash
-destination 'platform=watchOS,id=<DEVICE-UDID>'
```

## visionOS

### Simulator

```bash
-destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

### Device

```bash
-destination 'platform=visionOS,id=<DEVICE-UDID>'
```

## Generic Destinations

Use generic destinations for build-only operations (no need to run on simulator):

```bash
# iOS
-destination 'generic/platform=iOS'

# iOS Simulator
-destination 'generic/platform=iOS Simulator'

# macOS
-destination 'generic/platform=macOS'

# tvOS
-destination 'generic/platform=tvOS'

# watchOS
-destination 'generic/platform=watchOS'

# visionOS
-destination 'generic/platform=visionOS'
```

Generic destinations are useful for:
- Archive builds
- Builds where you don't need to run the app
- Framework builds

## Multiple Destinations

Test on multiple destinations in sequence:

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## Common Simulator Names

**Note**: Simulator names change with each Xcode release. The names below are examples from Xcode 26. Always verify available simulators with `xcrun simctl list devices available`.

| Device | Simulator Name |
|--------|----------------|
| iPhone 17 | `iPhone 17` |
| iPhone 17 Pro | `iPhone 17 Pro` |
| iPhone 17 Pro Max | `iPhone 17 Pro Max` |
| iPhone Air | `iPhone Air` |
| iPhone 16 | `iPhone 16` |
| iPhone 16e | `iPhone 16e` |
| iPad Pro 13" | `iPad Pro 13-inch (M5)` |
| iPad Pro 11" | `iPad Pro 11-inch (M5)` |
| iPad Air 13" | `iPad Air 13-inch (M3)` |
| iPad Air 11" | `iPad Air 11-inch (M3)` |
| iPad mini | `iPad mini (A17 Pro)` |
| Apple Watch Series 11 | `Apple Watch Series 11 (46mm)` |
| Apple Watch Ultra 3 | `Apple Watch Ultra 3 (49mm)` |
| Apple TV 4K | `Apple TV 4K (3rd generation)` |
| Apple Vision Pro | `Apple Vision Pro` |

**Note**: Simulator names must match exactly (case-sensitive, including parentheses).

## Quick Reference

| Goal | Command |
|------|---------|
| List simulators | `xcrun simctl list devices available` |
| List physical devices | `xcrun xctrace list devices` |
| Show scheme destinations | `xcodebuild -showdestinations -scheme <name>` |
| Boot simulator | `xcrun simctl boot "<name>"` |
| Erase simulator | `xcrun simctl erase "<name>"` |
| Erase all simulators | `xcrun simctl erase all` |

## Example

```bash
xcodebuild test -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Troubleshooting

### "Unable to find a destination matching the provided destination specifier"

**Cause**: Simulator name doesn't exist or is misspelled (case-sensitive).

**Solution**:
```bash
xcrun simctl list devices available
```

### "Unable to boot device in current state: Booted"

**Cause**: Simulator is already running.

**Solution**: This is usually fine. If stuck:
```bash
xcrun simctl shutdown "<name>"
xcrun simctl boot "<name>"
```

### "The requested device could not be found because no available devices matched the request"

**Cause**: Simulator runtime not installed for requested OS version.

**Solution**:
```bash
# List available runtimes
xcrun simctl list runtimes

# Create simulator with available runtime
xcrun simctl create "iPhone 17" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-17" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
```

### Simulator is stuck or corrupt

**Cause**: Simulator state corruption.

**Solution**:
```bash
xcrun simctl erase "<name>"
# Or erase all
xcrun simctl erase all
```
