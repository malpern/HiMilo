# VoxClaw Plugin

Give your coding agent a voice. This plugin packages VoxClaw integration for both **Claude Code** and **OpenAI Codex**.

## Quick setup

### Claude Code (one command)

```bash
plugins/voxclaw/setup-claude-code.sh
```

This installs two hooks into `~/.claude/settings.json`:
- **Stop** → speaks each assistant response aloud via VoxClaw
- **UserPromptSubmit** → acknowledges the response (skips reading if you already replied)

### Codex

Drop this plugin folder into your Codex workspace. The `.codex-plugin/plugin.json` manifest and bundled skills handle the rest.

## What it does

- Every agent response is spoken aloud through the VoxClaw macOS app
- Multiple agents get distinct voices (per-project voice binding)
- A project badge shows which agent is speaking when multiple are active
- If you respond to an agent while it's speaking, VoxClaw plays a click sound and moves on
- Polite mode: waits for Zoom/Teams/FaceTime calls and mic-active transcription tools before speaking

## Helper script

```bash
plugins/voxclaw/scripts/voxclaw-say "Hello from the agent"
plugins/voxclaw/scripts/voxclaw-say --health
plugins/voxclaw/scripts/voxclaw-say --url http://192.168.1.50:4140/read "Hello"
plugins/voxclaw/scripts/voxclaw-say --project-id /Users/me/myproject "Project update"
plugins/voxclaw/scripts/voxclaw-say --voice nova --rate 1.2 "Heads up"
```

Reads from stdin too:

```bash
printf '%s\n' "Task complete." | plugins/voxclaw/scripts/voxclaw-say
```

Resolution order: explicit `--url` → local listener on `localhost:4140` → local `voxclaw` CLI.

## HTTP API

```bash
# Health check
curl http://localhost:4140/status

# Speak text
curl -X POST http://localhost:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello","project_id":"/Users/me/proj","agent_id":"my-agent"}'

# Acknowledge (user already read it, skip speaking)
curl -X POST http://localhost:4140/ack \
  -H 'Content-Type: application/json' \
  -d '{"project_id":"/Users/me/proj"}'
```

## Included skills

- `voxclaw` — general voice output
- `voxclaw-read-task-summary` — speak a short completion summary
- `voxclaw-read-test-failures` — speak a short failure summary

## Files

```
plugins/voxclaw/
  .codex-plugin/plugin.json    Codex plugin manifest
  hooks/                       Claude Code hook scripts (bundled)
    voxclaw-stop-speak.sh      Stop hook: speak assistant responses
    voxclaw-ack.sh             UserPromptSubmit hook: ack on reply
  scripts/
    voxclaw-say                Helper script (curl + fallback)
    smoke-test                 Quick verification
  skills/                      Agent skills
  setup-claude-code.sh         One-command Claude Code installer
  README.md
  DEMO.md
```
