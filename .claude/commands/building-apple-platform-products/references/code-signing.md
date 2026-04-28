# Code Signing Reference

Command-line code signing for Apple platforms.

**Important**: Simulator builds require no signing. Device builds need valid certificates and provisioning profiles. For builds that don't require signing, add `CODE_SIGNING_ALLOWED=NO` to xcodebuild commands.

## Signing Identities

```bash
# List available signing identities
security find-identity -v -p codesigning
```

## Signing an App

```bash
# Sign with a specific identity
codesign -f -s "Apple Distribution: My Company (TEAMID)" --entitlements app.entitlements MyApp.app

# Verify signature
codesign --verify --verbose=4 MyApp.app

# Display entitlements
codesign -d --entitlements - MyApp.app
```

## Build Settings for Signing

Configure via xcodebuild command-line overrides:

| Setting | Purpose | Example |
|---------|---------|---------|
| `CODE_SIGN_IDENTITY` | Signing certificate | `"Apple Development"` |
| `DEVELOPMENT_TEAM` | Team ID | `"ABCDE12345"` |
| `PROVISIONING_PROFILE_SPECIFIER` | Profile name | `"MyApp Dev Profile"` |
| `CODE_SIGN_STYLE` | Signing mode | `Automatic` or `Manual` |
| `CODE_SIGNING_ALLOWED` | Enable/disable signing | `NO` for unsigned builds |

```bash
# Automatic signing
xcodebuild build -scheme "MyApp" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=ABCDE12345

# Manual signing
xcodebuild build -scheme "MyApp" \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution: My Company (TEAMID)" \
  PROVISIONING_PROFILE_SPECIFIER="MyApp Distribution"
```

## CI Keychain Setup

For CI environments where certificates need to be imported:

```bash
# Create a temporary keychain
security create-keychain -p "temp_pw" build.keychain

# Unlock it
security unlock-keychain -p "temp_pw" build.keychain

# Import the certificate
security import cert.p12 -k build.keychain -P "$CERT_PASSWORD" -T /usr/bin/codesign

# Add to search list
security list-keychains -d user -s build.keychain login.keychain
```

## Quick Reference

| Goal | Command |
|------|---------|
| List identities | `security find-identity -v -p codesigning` |
| Sign app | `codesign -f -s "<identity>" MyApp.app` |
| Verify signature | `codesign --verify --verbose=4 MyApp.app` |
| Show entitlements | `codesign -d --entitlements - MyApp.app` |
| Disable signing | `CODE_SIGNING_ALLOWED=NO` |
| Auto provisioning | `-allowProvisioningUpdates` |

## Troubleshooting

### "Code Sign error: No signing certificate..."

**Cause**: No valid signing identity found in keychain.

**Solution**:
```bash
# Check available identities
security find-identity -v -p codesigning

# For builds that don't need signing
xcodebuild build -scheme "MyApp" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

### "Provisioning profile doesn't match bundle identifier"

**Cause**: The provisioning profile's bundle ID doesn't match the app's `PRODUCT_BUNDLE_IDENTIFIER`.

**Solution**: Ensure the profile matches the bundle ID, or use automatic signing with `-allowProvisioningUpdates`.

### Code signing fails in CI

**Cause**: Keychain not configured or locked.

**Solution**: Set up the build keychain as shown in the CI Keychain Setup section above. Ensure `security unlock-keychain` runs before `xcodebuild`.
