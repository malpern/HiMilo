# Testing Reference

Comprehensive testing strategies for Apple platforms.

**Important**: The `-destination` flag is required for iOS/tvOS/watchOS/visionOS targets. Only macOS tests can omit it.

## Test Command Variants

### Build and Test (Standard)

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Build for Testing (Separate Steps)

Useful when you want to build once and run tests multiple times.

**Step 1: Build**

```bash
xcodebuild build-for-testing \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ./build
```

Creates an `.xctestrun` file in derived data.

**Step 2: Test**

```bash
xcodebuild test-without-building \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ./build
```

### Test Using .xctestrun File

```bash
xcodebuild test-without-building \
  -xctestrun ./build/Build/Products/MyApp_iphonesimulator26.0-arm64.xctestrun \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Test Filtering

### By Test Target

```bash
xcodebuild test \
  -scheme "MyApp" \
  -only-testing:MyAppTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### By Test Class

```bash
xcodebuild test \
  -scheme "MyApp" \
  -only-testing:MyAppTests/LoginTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### By Test Method

```bash
xcodebuild test \
  -scheme "MyApp" \
  -only-testing:MyAppTests/LoginTests/testValidLogin \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Skip Specific Tests

```bash
xcodebuild test \
  -scheme "MyApp" \
  -skip-testing:MyAppTests/SlowTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Multiple Filters

```bash
xcodebuild test \
  -scheme "MyApp" \
  -only-testing:MyAppTests/FastTests \
  -only-testing:MyAppTests/CriticalTests \
  -skip-testing:MyAppTests/FastTests/testFlaky \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Parallel Testing

### Enable Parallel Execution

```bash
xcodebuild test \
  -scheme "MyApp" \
  -parallel-testing-enabled YES \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Control Worker Count

```bash
xcodebuild test \
  -scheme "MyApp" \
  -parallel-testing-worker-count 4 \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Multiple Destinations (Parallel)

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## Test Results

### Result Bundle

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath ./TestResults.xcresult
```

### Code Coverage

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -resultBundlePath ./TestResults.xcresult
```

### Extract Coverage Report

```bash
# Summary
xcrun xccov view --report TestResults.xcresult

# JSON format
xcrun xccov view --report --json TestResults.xcresult

# File-level detail
xcrun xccov view --file-list TestResults.xcresult
```

## Test Timeouts

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60
```

## UI Testing

```bash
xcodebuild test \
  -scheme "MyAppUITests" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### UI Test Requirements

- Target Application must be set in scheme
- Accessibility enabled on simulator
- Screen recording may be captured in result bundle

## Swift Package Manager Testing

### Run All Tests

```bash
swift test
```

### Filter Tests

```bash
# By test class
swift test --filter LoginTests

# By test method
swift test --filter LoginTests/testValidLogin

# Pattern matching
swift test --filter "Integration"
```

### Parallel Testing

```bash
swift test --parallel
```

### Code Coverage

```bash
swift test --enable-code-coverage

# Coverage data in .build/debug/codecov/
```

### Verbose Output

```bash
swift test -v
```

## macOS Testing

```bash
xcodebuild test \
  -scheme "MyMacApp" \
  -destination 'platform=macOS'
```

## Test Without Code Signing

```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

## Quick Reference

| Goal | Command |
|------|---------|
| Run tests | `xcodebuild test -scheme <name> -destination '<spec>'` |
| Run specific test | `-only-testing:<Target>/<Class>/<Method>` |
| Skip tests | `-skip-testing:<Target>/<Class>` |
| Build for testing | `xcodebuild build-for-testing -scheme <name> -destination '<spec>'` |
| Test without build | `xcodebuild test-without-building -scheme <name> -destination '<spec>'` |
| Enable coverage | `-enableCodeCoverage YES` |
| Parallel testing | `-parallel-testing-enabled YES` |
| Save results | `-resultBundlePath ./Results.xcresult` |

## Example

```bash
xcodebuild test -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Troubleshooting

### "Test runner exited before starting test execution"

**Cause**: Simulator hung, app crashed on launch, or missing entitlements.

**Solution**:
```bash
xcrun simctl erase "iPhone 17"
# Or reset all
xcrun simctl erase all
```

### "UI Testing Failure - No target application"

**Cause**: Test target doesn't have a Target Application configured.

**Solution**: In Xcode, edit the scheme and set "Target Application" under Test → Info.

### "Timed out waiting for test results"

**Cause**: Tests taking too long or hanging.

**Solution**:
```bash
xcodebuild test -scheme "MyApp" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300
```

### "Tests failed" (exit code 66)

**Cause**: One or more test assertions failed.

**Solution**: Check test results:
```bash
xcrun xcresulttool get --path ./TestResults.xcresult --format json
```
