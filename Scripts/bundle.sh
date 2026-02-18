#!/bin/bash
set -euo pipefail

PRODUCT_NAME="HiMilo"
APP_NAME="${PRODUCT_NAME}.app"
BUILD_DIR=".build/release"
BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}"

echo "Building ${PRODUCT_NAME} (release)..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${PRODUCT_NAME}" "${BUNDLE_DIR}/Contents/MacOS/${PRODUCT_NAME}"

# Create Info.plist
cat > "${BUNDLE_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HiMilo</string>
    <key>CFBundleIdentifier</key>
    <string>com.malpern.himilo</string>
    <key>CFBundleName</key>
    <string>HiMilo</string>
    <key>CFBundleDisplayName</key>
    <string>HiMilo</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>HiMilo needs audio access for text-to-speech playback.</string>
</dict>
</plist>
PLIST

# Copy icon
cp "Sources/HiMilo/Resources/AppIcon.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"

echo "App bundle created at: ${BUNDLE_DIR}"
echo "To run: open ${BUNDLE_DIR}"
