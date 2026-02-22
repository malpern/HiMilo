#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="VoxClaw"
BUNDLE_ID="com.malpern.voxclaw"
MACOS_MIN_VERSION="26.0"
MENU_BAR_APP=1
SIGNING_MODE=${SIGNING_MODE:-}
APP_IDENTITY=${APP_IDENTITY:-}

CONF="release"
DEPLOY_LOCAL=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONF="$arg" ;;
    --deploy-local) DEPLOY_LOCAL=1 ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [debug|release] [--deploy-local]
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

source "$ROOT/version.env"

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH"
done

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>MacOSX</string></array>
    <key>NSHumanReadableCopyright</key><string>Copyright 2026 Michael Alpern. All rights reserved.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>VoxClaw uses on-device speech recognition to synchronize word highlighting with audio playback.</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>voxclaw</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Read with VoxClaw</string>
            </dict>
            <key>NSMessage</key>
            <string>readText</string>
            <key>NSPortName</key>
            <string>${APP_NAME}</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
            </array>
            <key>NSRequiredContext</key>
            <dict/>
        </dict>
    </array>
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Copy app icon.
ICON_SOURCE="$ROOT/Sources/VoxClawCore/Resources/AppIcon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP/Contents/Resources/AppIcon.icns"
fi

# Copy any SwiftPM resource bundles.
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_NAME" "${ARCH_LIST[0]}")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
  done
fi

# Clean extended attributes.
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Entitlements — start from the checked-in base file.
BASE_ENTITLEMENTS="${ROOT}/Sources/VoxClawCore/Resources/VoxClaw.entitlements"
if [[ ! -f "$BASE_ENTITLEMENTS" ]]; then
  echo "ERROR: Entitlements file not found: $BASE_ENTITLEMENTS" >&2
  exit 1
fi

# Embed provisioning profile for Developer ID builds (needed for iCloud KVS).
PROVISION_PROFILE="${ROOT}/Sources/VoxClawCore/Resources/embedded.provisionprofile"
if [[ -f "$PROVISION_PROFILE" && ("$SIGNING_MODE" != "adhoc" && -n "$APP_IDENTITY") ]]; then
  cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

# Code sign.
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$BASE_ENTITLEMENTS}"
if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  # Ad-hoc signing: strip team-specific entitlements that require Developer ID.
  ADHOC_ENTITLEMENTS=$(mktemp)
  trap "rm -f '$ADHOC_ENTITLEMENTS'" EXIT
  /usr/libexec/PlistBuddy -c "Print" "$APP_ENTITLEMENTS" >/dev/null 2>&1
  cp "$APP_ENTITLEMENTS" "$ADHOC_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$ADHOC_ENTITLEMENTS" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$ADHOC_ENTITLEMENTS" 2>/dev/null || true
  CODESIGN_ARGS=(--force --sign "-")
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$ADHOC_ENTITLEMENTS" \
    "$APP"
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$APP_ENTITLEMENTS" \
    "$APP"
fi

echo "Created $APP (${MARKETING_VERSION} build ${BUILD_NUMBER}, ${GIT_COMMIT})"

if [[ "${DEPLOY_LOCAL}" == "1" ]]; then
  "${ROOT}/Scripts/deploy_local_app.sh"
fi
