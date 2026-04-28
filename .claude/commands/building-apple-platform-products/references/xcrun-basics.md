# xcrun Tool Resolution

How xcrun finds and executes Xcode developer tools without hardcoded paths.

**Important**: After upgrading Xcode, run `xcrun --kill-cache` to clear stale tool resolution cache. The `TOOLCHAINS` environment variable silently falls back to the default toolchain if the specified identifier doesn't exist — a known source of subtle bugs.

## How xcrun Works

`xcrun` resolves the correct binary for any Xcode developer tool, then executes it with all supplied arguments. Instead of referencing paths like `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang`, you run `xcrun clang`.

When `xcrun` invokes a tool (not just `--find`), it automatically sets `SDKROOT`, `PATH`, `TARGET_TRIPLE`, and deployment target variables in the child process. It also adds `/usr/local/include` to `CPATH` and `/usr/local/lib` to `LIBRARY_PATH` when no explicit SDK is specified, ensuring Homebrew-installed libraries are found.

## Developer Directory Resolution

Resolution follows a strict priority order:

1. `DEVELOPER_DIR` environment variable (if set) — overrides everything
2. Symlink at `/var/db/xcode_select_link` (created by `xcode-select -s`)
3. `/Applications/Xcode.app/Contents/Developer`
4. `/Library/Developer/CommandLineTools`

Within the chosen developer directory, tool lookup searches SDK-specific paths, then the active toolchain (`Toolchains/XcodeDefault.xctoolchain/usr/bin/`), then the developer directory's own `usr/bin/`.

## Finding Tools and SDK Paths

```bash
# Find where a tool lives
xcrun --find simctl
xcrun --find clang
xcrun --sdk iphoneos --find clang

# Show SDK paths and versions
xcrun --sdk iphoneos --show-sdk-path
xcrun --show-sdk-version

# Run a tool from a specific SDK
xcrun --sdk iphonesimulator swiftc main.swift -target arm64-apple-ios18.0-simulator

# Use a specific toolchain
xcrun --toolchain org.swift.59202403031a --find swiftc

# Debug tool resolution
xcrun --verbose --find xcodebuild

# Clear stale cache after Xcode upgrades
xcrun --kill-cache
```

## Switching Xcode Versions

### System-Wide (requires sudo)

```bash
# Switch to a specific Xcode
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer

# Reset to default
sudo xcode-select -r

# Check current
xcode-select -p
```

### Per-Command Override (no sudo, ideal for CI)

```bash
DEVELOPER_DIR=/Applications/Xcode-16.app/Contents/Developer xcrun swift --version
```

## Quick Reference

| Goal | Command |
|------|---------|
| Find tool path | `xcrun --find <tool>` |
| Find tool in SDK | `xcrun --sdk iphoneos --find <tool>` |
| Show SDK path | `xcrun --sdk iphoneos --show-sdk-path` |
| Show SDK version | `xcrun --show-sdk-version` |
| Use specific toolchain | `xcrun --toolchain <id> <tool>` |
| Debug resolution | `xcrun --verbose --find <tool>` |
| Clear cache | `xcrun --kill-cache` |
| Switch Xcode (system) | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Switch Xcode (per-command) | `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer xcrun <tool>` |
| Reset Xcode selection | `sudo xcode-select -r` |
| Check active Xcode | `xcode-select -p` |

## Troubleshooting

### "xcrun: error: unable to find utility..."

**Cause**: Xcode command line tools not configured, or stale cache after upgrade.

**Solution**:
```bash
xcrun --kill-cache
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### Tool resolves to wrong version after Xcode upgrade

**Cause**: Cached tool paths from previous Xcode installation.

**Solution**:
```bash
xcrun --kill-cache
xcrun --verbose --find <tool>  # verify resolution
```

### TOOLCHAINS silently using wrong toolchain

**Cause**: `TOOLCHAINS` environment variable specifies an identifier that doesn't exist; xcrun falls back to the default toolchain without warning.

**Solution**:
```bash
# Verify the toolchain exists
ls /Library/Developer/Toolchains/
# Use --toolchain flag for explicit errors
xcrun --toolchain org.swift.59202403031a --find swiftc
```
