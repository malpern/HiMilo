#!/usr/bin/env bash
# Install VoxClaw hooks for Claude Code.
#
# This script:
# 1. Copies hook scripts to ~/.claude/hooks/
# 2. Merges hook entries into ~/.claude/settings.json
#
# Safe to run multiple times — skips hooks that are already installed.

set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOKS="$SCRIPT_DIR/hooks"

echo "VoxClaw Claude Code Setup"
echo "========================="
echo ""

# Ensure directories exist
mkdir -p "$HOOKS_DIR"
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

# Copy hook scripts
for hook in voxclaw-stop-speak.sh voxclaw-ack.sh; do
  src="$SOURCE_HOOKS/$hook"
  dst="$HOOKS_DIR/$hook"
  if [[ -f "$src" ]]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  Installed $dst"
  else
    echo "  Warning: $src not found, skipping" >&2
  fi
done

# Merge hook entries into settings.json
python3 -c '
import json
import sys
import os

settings_path = sys.argv[1]
hooks_dir = sys.argv[2]

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Stop hook: speak assistant responses
stop_hooks = hooks.setdefault("Stop", [])
stop_cmd = os.path.join(hooks_dir, "voxclaw-stop-speak.sh")
already_has_stop = any(
    any(h.get("command", "").endswith("voxclaw-stop-speak.sh") for h in entry.get("hooks", []))
    for entry in stop_hooks
)
if not already_has_stop:
    stop_hooks.append({
        "hooks": [{
            "type": "command",
            "command": stop_cmd,
            "timeout": 5000
        }]
    })
    print("  Added Stop hook for voxclaw-stop-speak.sh")
else:
    print("  Stop hook already installed, skipping")

# UserPromptSubmit hook: ack (user responded, skip reading)
ups_hooks = hooks.setdefault("UserPromptSubmit", [])
ack_cmd = os.path.join(hooks_dir, "voxclaw-ack.sh")
already_has_ack = any(
    any(h.get("command", "").endswith("voxclaw-ack.sh") for h in entry.get("hooks", []))
    for entry in ups_hooks
)
if not already_has_ack:
    ups_hooks.append({
        "hooks": [{
            "type": "command",
            "command": ack_cmd,
            "timeout": 2000
        }]
    })
    print("  Added UserPromptSubmit hook for voxclaw-ack.sh")
else:
    print("  UserPromptSubmit hook already installed, skipping")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
' "$SETTINGS" "$HOOKS_DIR"

echo ""
echo "Done. VoxClaw hooks are installed for Claude Code."
echo "New Claude Code sessions will pick them up automatically."
echo "Running sessions may need a restart to load the new hooks."
