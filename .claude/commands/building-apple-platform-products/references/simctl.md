# Simulator Management with simctl

Comprehensive CLI for creating, managing, and interacting with iOS, tvOS, watchOS, and visionOS simulators.

**Important**: Simulator names change with each Xcode release. Always verify available simulators with `xcrun simctl list devices available`. The special device specifier `"booted"` targets whichever simulator is currently running. Use `--set <path>` to operate on an alternate device set directory (e.g., `xcrun simctl --set /path/to/custom/set list devices`).

## Device Lifecycle

### Listing Devices and Runtimes

```bash
# List everything (devices, runtimes, device types)
xcrun simctl list
xcrun simctl list devices available
xcrun simctl list runtimes --json
xcrun simctl list devicetypes
```

### Creating Simulators

```bash
# Create a new simulator (returns UDID on stdout)
UDID=$(xcrun simctl create "CI-iPhone" "iPhone 15 Pro" "iOS 17.0")
```

### Booting and Shutting Down

```bash
# Boot the simulator (headless, no GUI)
xcrun simctl boot "$UDID"

# Wait for boot completion
xcrun simctl bootstatus "$UDID"

# Show the Simulator.app GUI (optional)
open -a Simulator

# Shutdown
xcrun simctl shutdown "$UDID"
```

**Headless operation**: `xcrun simctl boot` runs the simulator without the Simulator.app GUI. For CI, `xcodebuild test -destination` handles booting internally when needed.

### Erasing, Cloning, and Deleting

```bash
# Erase (must shutdown first)
xcrun simctl shutdown "$UDID"
xcrun simctl erase "$UDID"

# Clone an existing simulator (preserves all data and settings)
xcrun simctl clone booted "My-Clone"

# Delete a specific simulator
xcrun simctl delete "$UDID"

# Clean up orphaned simulators
xcrun simctl delete unavailable
```

### Renaming, Upgrading, and Pairing

```bash
# Rename
xcrun simctl rename booted "NewName"

# Upgrade runtime
xcrun simctl upgrade "$UDID" com.apple.CoreSimulator.SimRuntime.iOS-18-0

# Pair Watch + Phone
xcrun simctl pair <watch_UDID> <phone_UDID>
```

## App Lifecycle

### Installing and Uninstalling

```bash
# Install a .app bundle (built for iphonesimulator SDK)
xcrun simctl install booted ./Build/Products/Debug-iphonesimulator/MyApp.app

# Uninstall by bundle ID
xcrun simctl uninstall booted com.example.myapp
```

### Launching

```bash
# Basic launch
xcrun simctl launch booted com.example.myapp

# Pass arguments to the app
xcrun simctl launch booted com.example.myapp --reset-data -v

# Stream stdout/stderr to terminal
xcrun simctl launch --console booted com.example.myapp

# Stream via PTY (for interactive output)
xcrun simctl launch --console-pty booted com.example.myapp

# Wait for debugger attachment
xcrun simctl launch -w booted com.example.myapp

# Kill and relaunch
xcrun simctl launch --terminate-running-process booted com.example.myapp

# Redirect output to files
xcrun simctl launch --stdout=/tmp/out.log --stderr=/tmp/err.log booted com.example.myapp
```

### Terminating

```bash
xcrun simctl terminate booted com.example.myapp
```

### Spawning Processes

Run arbitrary processes inside the simulator:

```bash
# Write app defaults
xcrun simctl spawn booted defaults write com.example.myapp apiBaseURL -string "https://staging.api.com"

# Stream system logs
xcrun simctl spawn booted log stream --level=debug
```

### App Container Paths

```bash
# .app bundle location
xcrun simctl get_app_container booted com.example.myapp

# Data container
xcrun simctl get_app_container booted com.example.myapp data

# App groups container
xcrun simctl get_app_container booted com.example.myapp groups
```

### Environment Variables

Environment variables are passed to launched apps using the `SIMCTL_CHILD_` prefix. The prefix is stripped before delivery:

```bash
export SIMCTL_CHILD_API_KEY="abc123"
export SIMCTL_CHILD_DEBUG_MODE="true"
xcrun simctl launch booted com.example.myapp
# Inside the app: API_KEY="abc123", DEBUG_MODE="true"
```

## Push Notifications, Privacy, and UI Controls

### Push Notifications (Xcode 11.4+)

```bash
# From a file
xcrun simctl push booted com.example.myapp notification.apns

# From stdin
echo '{"aps":{"alert":"Hello"}}' | xcrun simctl push booted com.example.myapp -
```

### Privacy Permissions

Grant or revoke permissions without system prompts:

```bash
# Grant specific permissions
xcrun simctl privacy booted grant location-always com.example.myapp
xcrun simctl privacy booted grant photos com.example.myapp
xcrun simctl privacy booted grant all com.example.myapp

# Revoke
xcrun simctl privacy booted revoke camera com.example.myapp

# Reset all permissions
xcrun simctl privacy booted reset all com.example.myapp
```

Available services: `all`, `calendar`, `contacts`, `location`, `location-always`, `photos`, `photos-add`, `media-library`, `microphone`, `camera`, `reminders`, `siri`, `health`, `homekit`, `speech-recognition`, `focus-status`.

### Status Bar Override

Override the status bar for consistent screenshots:

```bash
xcrun simctl status_bar booted override \
  --time "9:41" --batteryLevel 100 --batteryState charged \
  --dataNetwork wifi --wifiBars 3 --cellularBars 4

# Clear override
xcrun simctl status_bar booted clear
```

### Appearance and Accessibility

```bash
# Dark/light mode
xcrun simctl ui booted appearance dark
xcrun simctl ui booted appearance light

# Dynamic Type size
xcrun simctl ui booted content_size extra-large

# Increase contrast
xcrun simctl ui booted increase_contrast enabled
```

### URLs and Deep Links

```bash
xcrun simctl openurl booted "myapp://deep/link/path"
xcrun simctl openurl booted "https://example.com"
```

### Keychain

```bash
# Add a root certificate
xcrun simctl keychain booted add-root-cert myCA.cer

# Reset keychain
xcrun simctl keychain booted reset
```

## Screenshots, Video, and Media

### Screenshots

```bash
# PNG screenshot
xcrun simctl io booted screenshot screen.png

# JPEG with display selection
xcrun simctl io booted screenshot --type=jpeg --display=internal screen.jpg
```

### Video Recording

```bash
# Record video (stop with Ctrl+C or SIGINT)
xcrun simctl io booted recordVideo --codec=h264 recording.mov

# Pipe to ffmpeg
xcrun simctl io booted recordVideo --type=fmp4 - | ffmpeg -i - output.mp4
```

### Adding Media

```bash
# Add photos, videos, or contacts to the simulator library
xcrun simctl addmedia booted photo.jpg video.mp4 contact.vcf
```

### I/O Enumeration

```bash
xcrun simctl io booted enumerate
```

## Location Simulation (Xcode 14+)

```bash
# Set a fixed location
xcrun simctl location booted set 37.7749,-122.4194

# Simulate movement between waypoints
xcrun simctl location booted start --speed=20 37.7749,-122.4194 34.0522,-118.2437

# Clear simulated location
xcrun simctl location booted clear
```

## Logging and Diagnostics

### Log Streaming

```bash
# Stream logs with predicate filtering
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.example.myapp"'

# JSON format with debug level
xcrun simctl spawn booted log stream --style=json --level=debug
```

### Diagnostics

```bash
# Enable verbose logging for debugging simulator issues
xcrun simctl logverbose booted enable

# Generate comprehensive diagnostic report
xcrun simctl diagnose -b --all-logs --output=~/Desktop/sim-diag
```

### Pasteboard

```bash
# Host → simulator
xcrun simctl pbcopy booted

# Simulator → host
xcrun simctl pbpaste booted

# Bidirectional sync
xcrun simctl pbsync booted
```

### Other Utilities

```bash
# Trigger iCloud sync
xcrun simctl icloud_sync booted

# List all installed apps
xcrun simctl listapps booted

# Get environment variable from running simulator
xcrun simctl getenv booted SIMULATOR_UDID
```

## Runtime Management (Xcode 14+)

Starting with Xcode 14, simulator runtimes ship as disk images and are managed separately. Xcode 15 no longer bundles the iOS runtime — it must be downloaded.

```bash
# List installed runtimes
xcrun simctl runtime list

# Install a runtime from a downloaded DMG
xcrun simctl runtime add ~/Downloads/iOS_17_Simulator_Runtime.dmg

# Delete a runtime
xcrun simctl runtime delete <identifier>

# Download platform runtimes via xcodebuild
xcodebuild -downloadAllPlatforms
xcodebuild -downloadPlatform iOS
```

Runtimes are stored in `/Library/Developer/CoreSimulator/Images/` and mounted via APFS cloning at `/Library/Developer/CoreSimulator/Volumes/`, consuming no additional disk space after installation.

## Quick Reference

| Goal | Command |
|------|---------|
| List available devices | `xcrun simctl list devices available` |
| List runtimes (JSON) | `xcrun simctl list runtimes --json` |
| Create simulator | `xcrun simctl create "<name>" "<type>" "<runtime>"` |
| Boot simulator | `xcrun simctl boot <UDID>` |
| Wait for boot | `xcrun simctl bootstatus <UDID>` |
| Shutdown simulator | `xcrun simctl shutdown <UDID>` |
| Erase simulator | `xcrun simctl erase <UDID>` |
| Delete unavailable | `xcrun simctl delete unavailable` |
| Install app | `xcrun simctl install booted <path.app>` |
| Launch app | `xcrun simctl launch booted <bundle-id>` |
| Launch with console | `xcrun simctl launch --console booted <bundle-id>` |
| Terminate app | `xcrun simctl terminate booted <bundle-id>` |
| Grant all permissions | `xcrun simctl privacy booted grant all <bundle-id>` |
| Push notification | `xcrun simctl push booted <bundle-id> <file.apns>` |
| Override status bar | `xcrun simctl status_bar booted override --time "9:41"` |
| Set appearance | `xcrun simctl ui booted appearance dark` |
| Open URL | `xcrun simctl openurl booted "<url>"` |
| Take screenshot | `xcrun simctl io booted screenshot <file.png>` |
| Record video | `xcrun simctl io booted recordVideo <file.mov>` |
| Set location | `xcrun simctl location booted set <lat>,<lon>` |
| Stream logs | `xcrun simctl spawn booted log stream --predicate '...'` |
| Add media | `xcrun simctl addmedia booted <file>` |
| Get app container | `xcrun simctl get_app_container booted <bundle-id> data` |
| Download runtime | `xcodebuild -downloadPlatform iOS` |

## Troubleshooting

### "Unable to boot device in current state: Booted"

**Cause**: The simulator is already running.

**Solution**: Check state before booting or ignore the error in scripts.

### "Unable to boot device because we cannot determine the runtime bundle"

**Cause**: The simulator runtime isn't installed.

**Solution**:
```bash
xcodebuild -downloadPlatform iOS
# Or install via Xcode → Settings → Platforms
```

### "Failed to install the app" / "not a valid bundle"

**Cause**: The `.app` is malformed, wrong architecture (simulator build on device or vice versa), or improperly signed.

**Solution**:
```bash
codesign --verify --verbose=4 MyApp.app
# Verify app was built with -sdk iphonesimulator for simulator use
```

### Simulator is stuck or corrupt

**Cause**: Simulator state corruption.

**Solution**:
```bash
xcrun simctl erase "<name>"
# Or erase all
xcrun simctl erase all
```
