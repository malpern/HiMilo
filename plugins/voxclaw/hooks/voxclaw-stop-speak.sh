#!/usr/bin/env bash
# Stop hook. Extract the last assistant message, strip markdown/code, and post
# it to VoxClaw's /read endpoint so it gets spoken aloud. All failure paths are
# silent — this hook must never block the session.

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

transcript_path = data.get("transcript_path") or ""
if not transcript_path:
    sys.exit(0)

read_url = f"http://localhost:{port}/read"

# Brief delay: Claude Code can fire Stop before the final assistant entry is
# fully flushed to the transcript. Without this, we sometimes read a partial
# transcript and miss the trailing text block of a multi-part response.
import time
time.sleep(0.5)

try:
    with open(transcript_path, "r") as f:
        lines = f.readlines()
except OSError:
    sys.exit(0)

# Walk backwards through the transcript collecting text from every "assistant"
# entry until we hit the user prompt that started this turn. A single response
# is split across many assistant entries (one per text block / tool call), so
# we have to accumulate them. "user"-typed entries that are tool_result wrappers
# are skipped; only a real user prompt (text content) terminates the walk.
collected = []  # list of (chunks_for_one_assistant_entry)
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
        # Either a real user prompt (stop) or a tool_result wrapper (skip).
        is_tool_result = False
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    is_tool_result = True
                    break
        if is_tool_result:
            continue
        # Real prompt - reached the start of the turn.
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
        # Walking backwards through file: insert at front to preserve original order.
        collected.insert(0, "\n".join(chunks))

last_text = "\n\n".join(collected).strip()

if not last_text:
    sys.exit(0)

text = last_text
text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
text = re.sub(r"`([^`]*)`", lambda m: " ".join("​" + w for w in m.group(1).split()), text)
text = re.sub(r"^\s{0,3}#{1,6}\s*", "", text, flags=re.MULTILINE)
text = re.sub(r"^\s*[-*+]\s+", "", text, flags=re.MULTILINE)
text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"\1", text)
text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
# Shorten long URLs to spoken-friendly labels
_DOMAIN_LABELS = {
    "github.com": "GitHub",
    "stackoverflow.com": "Stack Overflow",
    "developer.apple.com": "Apple Developer",
    "docs.swift.org": "Swift Docs",
    "linear.app": "Linear",
    "notion.so": "Notion",
    "figma.com": "Figma",
    "slack.com": "Slack",
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

# Normalize em-dashes with surrounding spaces for natural TTS pacing
text = text.replace("—", " — ")
text = text.replace("–", " – ")
# Preserve paragraph breaks as newlines; collapse horizontal whitespace only
text = re.sub(r"\n{3,}", "\n\n", text)
text = re.sub(r"[^\S\n]+", " ", text)
text = re.sub(r" ?\n ?", "\n", text)
text = text.strip()

if len(text) < 3:
    sys.exit(0)

body = json.dumps({
    "text": text,
    "project_id": os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(),
    "agent_id": "claude-code-stop-hook",
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
