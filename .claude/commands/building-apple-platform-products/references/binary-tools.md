# Binary and Asset Tools

Xcode developer tools for inspecting binaries, managing debug symbols, manipulating plists, and compiling assets.

**Important**: All tools listed here are accessed via `xcrun`. For example, `xcrun lipo`, `xcrun dsymutil`, etc.

## Binary Inspection

### lipo — Universal Binary Management

```bash
# Show architectures in a binary
xcrun lipo -info MyApp

# Create universal binary from slices
xcrun lipo -create MyApp-arm64 MyApp-x86_64 -output MyApp

# Extract a single architecture
xcrun lipo MyApp -thin arm64 -output MyApp-arm64
```

### otool — Mach-O Inspector

```bash
# List linked libraries
xcrun otool -L MyApp

# Show Mach-O header
xcrun otool -hv MyApp
```

## Debug Symbols

### dsymutil — Generate dSYMs

```bash
xcrun dsymutil MyApp -o MyApp.dSYM
```

### dwarfdump — Inspect Debug Symbols

```bash
# Show UUID (for matching with crash logs)
xcrun dwarfdump --uuid MyApp.dSYM
```

### atos — Address to Symbol

Symbolicate addresses from crash logs:

```bash
xcrun atos -arch arm64 -o MyApp.dSYM/Contents/Resources/DWARF/MyApp \
  -l 0x100000000 0x100001234
```

## Plist Manipulation

### plutil

```bash
# Extract a specific key
plutil -extract CFBundleIdentifier raw Info.plist

# Convert format
plutil -convert xml1 Info.plist
plutil -convert json Info.plist

# Validate
plutil -lint Info.plist
```

## Asset Compilation

### actool — Asset Catalog Compiler

```bash
xcrun actool Assets.xcassets --compile build/ --platform iphoneos
```

### ibtool — Storyboard/XIB Compiler

```bash
xcrun ibtool --compile Main.storyboardc Main.storyboard
```

## Swift Utilities

### swift-demangle

```bash
# Demangle Swift symbols
xcrun swift-demangle '_$s4main...'
```

### docc — Documentation Compiler

```bash
xcrun docc convert MyFramework.docc --output-path ./docs
```

## Quick Reference

| Tool | Purpose | Example |
|------|---------|---------|
| `lipo` | Manage universal binaries | `xcrun lipo -info MyApp` |
| `otool` | Inspect Mach-O binaries | `xcrun otool -L MyApp` |
| `dsymutil` | Generate dSYMs | `xcrun dsymutil MyApp -o MyApp.dSYM` |
| `dwarfdump` | Inspect debug symbols | `xcrun dwarfdump --uuid MyApp.dSYM` |
| `atos` | Symbolicate crash addresses | `xcrun atos -arch arm64 -o MyApp.dSYM/... -l 0x100000000 0x100001234` |
| `plutil` | Manipulate plists | `plutil -extract CFBundleIdentifier raw Info.plist` |
| `actool` | Compile asset catalogs | `xcrun actool Assets.xcassets --compile build/ --platform iphoneos` |
| `ibtool` | Compile storyboards/XIBs | `xcrun ibtool --compile Main.storyboardc Main.storyboard` |
| `swift-demangle` | Demangle Swift symbols | `xcrun swift-demangle '_$s4main...'` |
| `docc` | Compile documentation | `xcrun docc convert MyFramework.docc --output-path ./docs` |
