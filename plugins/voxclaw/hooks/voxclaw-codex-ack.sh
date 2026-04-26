#!/usr/bin/env bash
# Codex UserPromptSubmit hook. When the user sends a new message, notify
# VoxClaw that the previous response has been acknowledged.

set -euo pipefail

VOXCLAW_PORT="${VOXCLAW_PORT:-4140}"

payload="$(cat)"

printf '%s' "$payload" | python3 -c '
import json
import os
import sys
import urllib.request

port = sys.argv[1] if len(sys.argv) > 1 else "4140"

try:
    data = json.loads(sys.stdin.read() or "{}")
except json.JSONDecodeError:
    sys.exit(0)

project_id = os.environ.get("CODEX_PROJECT_DIR") or os.getcwd()
if not project_id:
    sys.exit(0)

ack_url = f"http://localhost:{port}/ack"
body = json.dumps({"project_id": project_id}).encode()

req = urllib.request.Request(
    ack_url,
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=1.0).read()
except Exception:
    pass
' "$VOXCLAW_PORT" || true

exit 0
