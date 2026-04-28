# Distribution and Notarization

Exporting IPAs, notarizing macOS apps, and uploading to App Store Connect.

**Important**: The `xcodebuild archive` → `xcodebuild -exportArchive` workflow replaces the legacy `PackageApplication` tool (removed in Xcode 8.3). See [archiving.md](archiving.md) for creating archives.

## Exporting IPA from Archive

```bash
# Step 1: Archive (see archiving.md for details)
xcodebuild archive -workspace MyApp.xcworkspace -scheme MyApp \
  -archivePath ./build/MyApp.xcarchive \
  -destination 'generic/platform=iOS'

# Step 2: Export IPA (requires ExportOptions.plist)
xcodebuild -exportArchive \
  -archivePath ./build/MyApp.xcarchive \
  -exportPath ./build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

### ExportOptions.plist

The export options plist specifies distribution method, signing, and other export parameters. Generate a template by exporting from Xcode Organizer, or create manually:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>ABCDE12345</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

Common `method` values: `app-store-connect`, `ad-hoc`, `enterprise`, `development`.

## macOS Notarization (Xcode 13+)

### Store Credentials

```bash
xcrun notarytool store-credentials "NotaryProfile" \
  --apple-id "dev@company.com" --team-id TEAMID --password "app-specific-pw"
```

### Submit for Notarization

```bash
# Submit and wait for completion
xcrun notarytool submit MyApp.dmg --keychain-profile "NotaryProfile" --wait

# Staple the notarization ticket
xcrun stapler staple MyApp.dmg
```

## App Store Upload

```bash
xcrun altool --upload-package MyApp.ipa --type ios \
  --apple-id 42XXXX --bundle-id com.company.app --bundle-version '5' \
  --bundle-short-version-string '1.0' -u "dev@company.com" -p @keychain:SECRET
```

## Quick Reference

| Goal | Command |
|------|---------|
| Export IPA | `xcodebuild -exportArchive -archivePath <archive> -exportPath <dir> -exportOptionsPlist <plist>` |
| Store notary credentials | `xcrun notarytool store-credentials "<profile>" --apple-id "<email>" --team-id <id> --password "<pw>"` |
| Notarize | `xcrun notarytool submit <file> --keychain-profile "<profile>" --wait` |
| Staple ticket | `xcrun stapler staple <file>` |
| Upload to App Store | `xcrun altool --upload-package <ipa> --type ios ...` |

## Legacy Tools (Obsolete)

### PackageApplication (removed in Xcode 8.3)

This Perl script created `.ipa` files via `xcrun -sdk iphoneos PackageApplication`. Replaced by the `xcodebuild archive` → `-exportArchive` workflow.

### ios-deploy (broken on iOS 17+)

Third-party npm/Homebrew tool for device deployment. Stopped working with iOS 17 due to Apple's CoreDevice framework replacing the MobileDevice stack. Use `xcrun devicectl` instead.

### ideviceinstaller / libimobiledevice

Open-source tools that reverse-engineered Apple's device protocols. Face compatibility challenges with iOS 17+'s secure pairing protocols. Not accessible via xcrun.

### instruments (removed in Xcode 13)

Replaced by `xcrun xctrace`. See [profiling-and-results.md](profiling-and-results.md).

## Troubleshooting

### "No applicable devices found" during export

**Cause**: Export options specify a distribution method that doesn't match the signing configuration.

**Solution**: Verify the `method` in ExportOptions.plist matches your certificates and profiles.

### Notarization fails with "invalid signature"

**Cause**: App not properly code-signed before submission.

**Solution**:
```bash
codesign --verify --verbose=4 MyApp.app
# Re-sign if needed, then resubmit
```
