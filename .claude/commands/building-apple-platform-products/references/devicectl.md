# Physical Device Management with devicectl

Apple's first-party CLI for physical device deployment, introduced in Xcode 15 alongside the CoreDevice framework. Replaces third-party tools like `ios-deploy` and `ideviceinstaller`.

**Important**: `devicectl` only works with devices running **iOS 17 and later**. Devices must have **Developer Mode enabled** (Settings → Privacy & Security → Developer Mode, mandatory on iOS 16+). Apps must be code-signed with a valid Apple Development certificate and matching provisioning profile. **JSON output is the only stable scripting interface** — human-readable stdout format may change between Xcode versions.

## Discovering Devices

```bash
# List all known/connected devices
xcrun devicectl list devices

# JSON output for scripting (the ONLY stable interface per Apple)
xcrun devicectl list devices --json-output /tmp/devices.json

# JSON to stdout
xcrun devicectl list devices -q --json-output -
```

Devices are specified via the `--device` (or `-d`) flag, accepting **CoreDevice UUID, ECID, serial number, UDID, device name, or DNS name**. The JSON output includes `connectionProperties.transportType` showing `"wired"` (USB) or `"localNetwork"` (WiFi).

## Device Information

```bash
# Detailed device information
xcrun devicectl device info details --device <ID>

# Display information
xcrun devicectl device info displays --device <ID>

# Lock state
xcrun devicectl device info lockState --device <ID>

# List installed apps
xcrun devicectl device info apps --device <ID>

# List running processes
xcrun devicectl device info processes --device <ID>
```

## Installing and Launching Apps

### Installation

```bash
# Install .app bundle or .ipa file
xcrun devicectl device install app --device <DEVICE_ID> /path/to/MyApp.app
xcrun devicectl device install app --device <DEVICE_ID> MyApp.ipa

# Uninstall by bundle ID
xcrun devicectl device uninstall app --device <DEVICE_ID> com.example.myapp
```

### Launching

```bash
# Launch an app (use --timeout defensively to prevent hangs)
xcrun devicectl device process launch --timeout 60 --device <DEVICE_ID> com.example.myapp

# Launch with console output (Xcode 16+ only)
xcrun devicectl device process launch --console --device <DEVICE_ID> com.example.myapp

# Kill and relaunch
xcrun devicectl device process launch --terminate-existing --device <DEVICE_ID> com.example.myapp

# Launch in stopped state for debugger attachment (use --json-output to get PID for lldb)
xcrun devicectl device process launch --start-stopped --device <DEVICE_ID> com.example.myapp --json-output launch.json
```

### Process Management

```bash
# Send signal to a process
xcrun devicectl device process signal --pid 1234 --signal SIGKILL --device <DEVICE_ID>
```

### Environment Variables

Environment variables use the `DEVICECTL_CHILD_` prefix, which is stripped before delivery to the app:

```bash
export DEVICECTL_CHILD_API_KEY="abc123"
xcrun devicectl device process launch --device <DEVICE_ID> com.example.myapp
# Inside the app: API_KEY="abc123"
```

## File Transfer

Only individual files can be transferred — directory-level copy is not supported.

```bash
# Copy file from device
xcrun devicectl device copy from --device <ID> \
  --domain-type appDataContainer --domain-identifier "com.example.myapp" \
  --source "Documents/data.db" --destination ./data.db

# Copy file to device
xcrun devicectl device copy to --device <ID> \
  --domain-type appDataContainer --domain-identifier "com.example.myapp" \
  --source "./test.db" --destination "Documents/test.db"

# List files in app container
xcrun devicectl device info files --device <ID> \
  --domain-type appDataContainer --domain-identifier "com.example.myapp"
```

Domain types: `appDataContainer`, `appGroupDataContainer`, `temporary`, `systemCrashLogs`.

## Device Management

```bash
# Reboot device
xcrun devicectl device reboot --device <ID>

# Pair/unpair
xcrun devicectl manage pair --device <ID>
xcrun devicectl manage unpair --device <ID>

# Collect CoreDevice diagnostic logs
xcrun devicectl diagnose --devices <ID>

# Observe Darwin notifications
xcrun devicectl device notification observe --device <ID> \
  --name com.example.MyNotification --timeout 300
```

## Limitations

- **iOS 17+ only** — older devices are invisible to devicectl
- `--console` flag was broken in Xcode 15 ("operation not implemented"); **fixed in Xcode 16**
- No screenshot or video recording capability (unlike `simctl io`)
- No equivalent to `simctl openurl` for opening deep links
- No built-in log streaming command
- `device info processes` and `device process launch` can occasionally hang; set `--timeout` defensively
- Xcode 15.0 had a `CoreDeviceService` memory exhaustion bug under heavy test loads, fixed in 15.1
- Devices must be unlocked for most operations

## Quick Reference

| Goal | Command |
|------|---------|
| List devices | `xcrun devicectl list devices` |
| List devices (JSON) | `xcrun devicectl list devices --json-output /tmp/devices.json` |
| Device details | `xcrun devicectl device info details --device <ID>` |
| Install app | `xcrun devicectl device install app --device <ID> <path>` |
| Uninstall app | `xcrun devicectl device uninstall app --device <ID> <bundle-id>` |
| Launch app | `xcrun devicectl device process launch --device <ID> <bundle-id>` |
| Launch with console | `xcrun devicectl device process launch --console --device <ID> <bundle-id>` |
| Kill and relaunch | `xcrun devicectl device process launch --terminate-existing --device <ID> <bundle-id>` |
| Copy file from device | `xcrun devicectl device copy from --device <ID> --domain-type appDataContainer --domain-identifier <bundle-id> --source <src> --destination <dst>` |
| Copy file to device | `xcrun devicectl device copy to --device <ID> --domain-type appDataContainer --domain-identifier <bundle-id> --source <src> --destination <dst>` |
| List installed apps | `xcrun devicectl device info apps --device <ID>` |
| Reboot device | `xcrun devicectl device reboot --device <ID>` |
| Pair device | `xcrun devicectl manage pair --device <ID>` |
| Unpair device | `xcrun devicectl manage unpair --device <ID>` |
| Diagnose | `xcrun devicectl diagnose --devices <ID>` |

## Troubleshooting

### "The specified device was not found" (error 1000)

**Cause**: Device isn't connected, isn't paired, has Developer Mode disabled, or is running iOS < 17.

**Solution**: Ensure the device is unlocked and has trusted the Mac. Verify Developer Mode is enabled in Settings → Privacy & Security → Developer Mode.

### "Failed to install the app" / "not a valid bundle"

**Cause**: Wrong architecture (simulator build on device), improperly signed, or malformed bundle.

**Solution**:
```bash
codesign --verify --verbose=4 MyApp.app
# Verify app was built with -sdk iphoneos for device use
```

### "--console" returns "operation not implemented"

**Cause**: Known bug in Xcode 15.

**Solution**: Upgrade to Xcode 16 or later.

### Operations hang indefinitely

**Cause**: `device info processes` and `device process launch` can occasionally hang.

**Solution**: Use `--timeout` flag defensively:
```bash
xcrun devicectl device process launch --timeout 60 --device <ID> com.example.myapp
```
