#!/usr/bin/env bash
# Install VoxClaw hooks for OpenAI Codex CLI.
#
# This script:
# 1. Copies hook scripts to ~/.codex/hooks/
# 2. Merges hook entries into ~/.codex/config.toml
#
# Safe to run multiple times — skips hooks that are already installed.

set -euo pipefail

HOOKS_DIR="$HOME/.codex/hooks"
CONFIG="$HOME/.codex/config.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOKS="$SCRIPT_DIR/hooks"

echo "VoxClaw Codex Setup"
echo "==================="
echo ""

# Ensure directories exist
mkdir -p "$HOOKS_DIR"
if [[ ! -f "$CONFIG" ]]; then
  touch "$CONFIG"
fi

# Copy hook scripts
for hook in voxclaw-codex-stop-speak.sh voxclaw-codex-ack.sh; do
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

# Merge hook entries into config.toml
python3 -c '
import os
import sys

config_path = sys.argv[1]
hooks_dir = sys.argv[2]

with open(config_path, "r") as f:
    content = f.read()

stop_script = os.path.join(hooks_dir, "voxclaw-codex-stop-speak.sh")
ack_script = os.path.join(hooks_dir, "voxclaw-codex-ack.sh")

changes = False

if "voxclaw-codex-stop-speak.sh" not in content:
    content += f"""
[[hooks.Stop]]
hooks = [
  {{ type = "command", command = "{stop_script}", timeout = 5000 }}
]
"""
    print("  Added Stop hook for voxclaw-codex-stop-speak.sh")
    changes = True
else:
    print("  Stop hook already installed, skipping")

if "voxclaw-codex-ack.sh" not in content:
    content += f"""
[[hooks.UserPromptSubmit]]
hooks = [
  {{ type = "command", command = "{ack_script}", timeout = 2000 }}
]
"""
    print("  Added UserPromptSubmit hook for voxclaw-codex-ack.sh")
    changes = True
else:
    print("  UserPromptSubmit hook already installed, skipping")

if changes:
    with open(config_path, "w") as f:
        f.write(content)

' "$CONFIG" "$HOOKS_DIR"

echo ""
echo "Done. VoxClaw hooks are installed for Codex."
echo "New Codex sessions will pick them up automatically."
echo "Running sessions may need a restart to load the new hooks."
