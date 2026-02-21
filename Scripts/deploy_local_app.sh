#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoxClaw"
SOURCE_APP="${ROOT_DIR}/${APP_NAME}.app"
PRIMARY_TARGET="/Applications/${APP_NAME}.app"
FALLBACK_DIR="${HOME}/Applications"
FALLBACK_TARGET="${FALLBACK_DIR}/${APP_NAME}.app"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ ! -d "${SOURCE_APP}" ]]; then
  fail "Missing ${SOURCE_APP}. Build first (e.g. ./Scripts/package_app.sh release)."
fi

if [[ -w "/Applications" ]]; then
  TARGET_APP="${PRIMARY_TARGET}"
else
  mkdir -p "${FALLBACK_DIR}"
  TARGET_APP="${FALLBACK_TARGET}"
fi

log "==> Stopping running ${APP_NAME} instances"
pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true

log "==> Deploying ${SOURCE_APP} -> ${TARGET_APP}"
rm -rf "${TARGET_APP}"
ditto "${SOURCE_APP}" "${TARGET_APP}"
xattr -cr "${TARGET_APP}" || true

log "==> Launching ${TARGET_APP}"
open -a "${TARGET_APP}"

for _ in {1..12}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "OK: ${APP_NAME} deployed and running from ${TARGET_APP}"
    exit 0
  fi
  sleep 0.5
done

fail "${APP_NAME} did not stay running after deployment. Check Console.app crash reports."
