#!/usr/bin/env bash
# Codex Stop hook. Extract the last assistant message and post it to VoxClaw's
# /read endpoint. Adapts the Claude Code hook for Codex's payload format.
# All failure paths are silent — this hook must never block the session.

set -euo pipefail

VOXCLAW_PORT="${VOXCLAW_PORT:-4140}"

payload="$(cat)"

printf '%s' "$payload" | python3 -c '
import json
import os
import re
import sys
import urllib.request

port = sys.argv[1] if len(sys.argv) > 1 else "4140"

try:
    data = json.loads(sys.stdin.read() or "{}")
except json.JSONDecodeError:
    sys.exit(0)

# Codex provides last_assistant_message directly in the Stop payload
last_text = data.get("last_assistant_message") or ""

# Also try transcript_path fallback (same as Claude Code)
if not last_text:
    transcript_path = data.get("transcript_path") or ""
    if not transcript_path:
        sys.exit(0)

    import time
    time.sleep(0.5)

    try:
        with open(transcript_path, "r") as f:
            lines = f.readlines()
    except OSError:
        sys.exit(0)

    collected = []
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        entry_type = entry.get("type")
        message = entry.get("message") or {}
        content = message.get("content")

        if entry_type == "user":
            is_tool_result = False
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        is_tool_result = True
                        break
            if is_tool_result:
                continue
            break

        if entry_type != "assistant":
            continue

        chunks = []
        if isinstance(content, str):
            chunks.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    t = block.get("text")
                    if isinstance(t, str):
                        chunks.append(t)
        if chunks:
            collected.insert(0, "\n".join(chunks))

    last_text = "\n\n".join(collected).strip()

if not last_text:
    sys.exit(0)

read_url = f"http://localhost:{port}/read"

text = last_text
text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
text = re.sub(r"`([^`]*)`", lambda m: " ".join("​" + w for w in m.group(1).split()), text)
text = re.sub(r"^\s{0,3}#{1,6}\s*", "", text, flags=re.MULTILINE)
text = re.sub(r"^\s*[-*+]\s+", "", text, flags=re.MULTILINE)
text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"\1", text)
text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
_DOMAIN_LABELS = {
    "github.com": "GitHub",
    "stackoverflow.com": "Stack Overflow",
    "developer.apple.com": "Apple Developer",
    "docs.swift.org": "Swift Docs",
}
def _shorten_url(m):
    url = m.group(0)
    try:
        from urllib.parse import urlparse
        host = urlparse(url).hostname or ""
    except Exception:
        host = ""
    for domain, label in _DOMAIN_LABELS.items():
        if host == domain or host.endswith("." + domain):
            return label + " link"
    if host:
        short = host.removeprefix("www.")
        return short.split(".")[0] + " link"
    return "link"
text = re.sub(r"https?://[^\s)\]>\"]+", _shorten_url, text)
text = text.replace("—", " — ")
text = text.replace("–", " – ")
text = re.sub(r"\n{3,}", "\n\n", text)
text = re.sub(r"[^\S\n]+", " ", text)
text = re.sub(r" ?\n ?", "\n", text)
text = text.strip()

if len(text) < 3:
    sys.exit(0)

body = json.dumps({
    "text": text,
    "project_id": os.environ.get("CODEX_PROJECT_DIR") or os.getcwd(),
    "agent_id": "codex-stop-hook",
}).encode()

req = urllib.request.Request(
    read_url,
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=2.0).read()
except Exception:
    pass
' "$VOXCLAW_PORT" || true

exit 0
