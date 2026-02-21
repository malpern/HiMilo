#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${1:-release}"

exec "${ROOT_DIR}/Scripts/package_app.sh" "${CONF}" --deploy-local
