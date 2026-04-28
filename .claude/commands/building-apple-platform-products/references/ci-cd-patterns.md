# CI/CD Patterns

Complete workflow examples for automating Apple platform builds and tests in CI environments.

**Important**: Always prefer JSON output (`--json-output`, `--json`) when parsing tool output in scripts. Human-readable formats may change between Xcode versions.

## Full Simulator CI Pipeline

End-to-end script: create simulator, configure, test, capture results, clean up.

```bash
#!/bin/bash
set -euo pipefail

SCHEME="MyApp"
BUNDLE_ID="com.example.myapp"

# Create dedicated simulator
UDID=$(xcrun simctl create "CI-Test" "iPhone 15 Pro" \
  "$(xcrun simctl list runtimes | grep iOS | tail -1 | awk '{print $NF}')")

# Boot and wait
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" || sleep 30

# Pre-grant permissions to avoid system dialogs
xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID"

# Override status bar for consistent screenshots
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 --batteryState charged

# Set location
xcrun simctl location "$UDID" set 37.7749,-122.4194

# Build and test
xcodebuild test -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -resultBundlePath ./TestResults.xcresult \
  -parallel-testing-enabled YES \
  CODE_SIGNING_ALLOWED=NO

# Capture screenshot
xcrun simctl io "$UDID" screenshot final-state.png

# Extract test summary
xcrun xcresulttool get test-results summary --path TestResults.xcresult

# Cleanup
xcrun simctl shutdown "$UDID"
xcrun simctl delete "$UDID"
```

## Full Physical Device CI Pipeline

```bash
#!/bin/bash
set -euo pipefail

DEVICE_ID="00008120-001134592E88C01E"
SCHEME="MyApp"

# Verify device is available
xcrun devicectl list devices --json-output /tmp/devices.json

# Build for device
xcodebuild build -workspace MyApp.xcworkspace -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath ./DerivedData \
  -allowProvisioningUpdates

# Install
APP_PATH=$(find ./DerivedData -name "*.app" -path "*/Debug-iphoneos/*" | head -1)
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

# Launch with console output (Xcode 16+)
xcrun devicectl device process launch --console --terminate-existing \
  --device "$DEVICE_ID" com.example.myapp

# Run tests
xcodebuild test -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -resultBundlePath ./DeviceTestResults.xcresult
```

## Capturing Logs During Test Runs

```bash
# Stream simulator logs in background
xcrun simctl spawn booted log stream \
  --predicate 'subsystem == "com.example.myapp"' > test.log 2>&1 &
LOG_PID=$!

# Run tests
xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16'

# Stop log capture
kill $LOG_PID

# Record video evidence of test run
xcrun simctl io booted recordVideo test-run.mp4 &
VIDEO_PID=$!
# ... run UI tests ...
kill -INT $VIDEO_PID
```

## GitHub Actions

```yaml
name: iOS CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app
      - name: Build and Test
        run: |
          xcodebuild test \
            -scheme MyApp \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' \
            -resultBundlePath TestResults.xcresult
      - name: Cleanup
        if: always()
        run: xcrun simctl shutdown all && xcrun simctl delete unavailable
```

## Xcode Version Selection in CI

```bash
# System-wide switch (requires sudo, typical in CI)
sudo xcode-select -s /Applications/Xcode-16.app/Contents/Developer

# Per-command override (no sudo needed)
DEVELOPER_DIR=/Applications/Xcode-16.app/Contents/Developer xcrun swift --version

# Reset to default
sudo xcode-select -r
```

## Fastlane Equivalents

Fastlane wraps the same underlying tools:

| Fastlane Action | Underlying Tool |
|-----------------|-----------------|
| `gym` | `xcodebuild archive` + `-exportArchive` |
| `scan` | `xcodebuild test` + `.xcresult` parsing |
| `snapshot` | `simctl` for simulator management |

## Quick Reference

| Goal | Command |
|------|---------|
| Create CI simulator | `xcrun simctl create "CI-Test" "<type>" "<runtime>"` |
| Pre-grant permissions | `xcrun simctl privacy "$UDID" grant all "$BUNDLE_ID"` |
| Disable signing | `CODE_SIGNING_ALLOWED=NO` |
| Save test results | `-resultBundlePath ./Results.xcresult` |
| Extract test summary | `xcrun xcresulttool get test-results summary --path <xcresult>` |
| Clean up simulators | `xcrun simctl delete unavailable` |
| Select Xcode version | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
