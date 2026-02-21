---
name: voxclaw
description: Give your agent a voice. Send text to a Mac running VoxClaw and hear it spoken aloud with OpenAI neural voices or Apple TTS.
homepage: https://github.com/malpern/VoxClaw
metadata: {"clawdbot":{"emoji":"🦀","requires":{"bins":["curl"]}}}
---

# VoxClaw — Voice Output for OpenClaw

VoxClaw is a macOS app that speaks text aloud. It runs on the user's Mac as a menu bar app and listens for text over HTTP. Send text from any machine on the LAN and VoxClaw reads it using OpenAI neural voices or Apple's built-in TTS.

This is useful when your agent runs on a remote server or headless machine and you want voice output on the user's local Mac.

## How It Works

VoxClaw runs an HTTP listener (default port 4140) on the user's Mac. To speak text, POST to the `/read` endpoint. The user hears the text immediately through their Mac speakers with a teleprompter overlay showing synchronized word highlighting.

## Fast Handoff (Human -> Agent)

If the human shares a `🦞 VoxClaw setup pointer`, use it directly. It includes:
- website pointer (`https://voxclaw.com/`)
- integration doc (`SKILL.md`)
- machine-specific `Speak URL` (`/read`)
- machine-specific `Health URL` (`/status`)

Prefer those provided URLs over guessed hostnames when both are available.
Never auto-switch to `.local` hostnames. Use numeric LAN IP URLs unless a human explicitly provides a `.local` target.
If `health_url` and `speak_url` are present in the pointer, do not ask for LAN IP or run discovery first; call `health_url` immediately, then use `speak_url`.

Reliable connect order:
1. Confirm on VoxClaw Mac: `curl -sS http://localhost:4140/status`
2. Confirm from agent host: `curl -sS http://<lan-ip>:4140/status`
3. Send speech to `<lan-ip>:4140/read`
4. If step 1 passes but step 2 fails, treat as network/firewall issue (not app API issue).

## API

### Speak Text

```bash
curl -X POST http://<mac-ip>:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello from your agent!"}'
```

**Parameters (JSON body):**

| Field   | Type   | Required | Description                                      |
|---------|--------|----------|--------------------------------------------------|
| `text`  | string | yes      | The text to speak (max 50,000 characters)        |
| `voice` | string | no       | OpenAI voice name: alloy, echo, fable, onyx, nova, shimmer |
| `rate`  | number | no       | Speech rate multiplier (e.g. 1.5 for faster)     |

**Plain text** also works:

```bash
curl -X POST http://<mac-ip>:4140/read -d 'Hello from your agent!'
```

**Response:**

```json
{"status": "reading"}
```

### Check Status

```bash
curl http://<mac-ip>:4140/status
```

**Response:**

```json
{
  "status": "ok",
  "service": "VoxClaw",
  "reading": true,
  "state": "playing",
  "word_count": 42,
  "website": "https://voxclaw.com/",
  "skill_doc": "https://github.com/malpern/VoxClaw/blob/main/SKILL.md",
  "discovery": "_voxclaw._tcp",
  "speak_url": "http://192.168.1.50:4140/read",
  "health_url": "http://192.168.1.50:4140/status"
}
```

States: `idle`, `loading`, `playing`, `paused`, `finished`.

## Setup

The user installs VoxClaw on their Mac:

1. Download from [GitHub Releases](https://github.com/malpern/VoxClaw/releases/latest/download/VoxClaw.zip)
2. Move to Applications, launch once to complete onboarding
3. Enable "Network Listener" in Settings (or launch with `voxclaw --listen`)

The listener binds to all interfaces on port 4140 by default. The port is configurable in Settings or via `--port`.

**OpenAI API key is optional.** Without a key, VoxClaw uses Apple's built-in voices. With a key, it uses OpenAI's neural voices (the user provides their own key during onboarding or in Settings).

## Discovery

VoxClaw advertises itself via Bonjour as `_voxclaw._tcp` on the local network. Agents can discover it without knowing the IP address.

## Errors

| Status | Meaning                                    |
|--------|--------------------------------------------|
| 200    | Text accepted, now reading                 |
| 400    | Missing or empty text, or text too long    |
| 404    | Unknown endpoint (use POST /read or GET /status) |
| 413    | Request body too large (max 1 MB)          |

Error responses are JSON: `{"error": "description"}`.

**CORS:** The HTTP API allows requests from `http://localhost` only. For cross-machine access, use `curl` or any HTTP client directly (CORS only applies to browsers).

## Examples

**Speak a summary after a task completes:**

```bash
curl -X POST http://192.168.1.50:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text": "Task complete. I deployed the new version and all tests passed."}'
```

**Use a specific voice at faster speed:**

```bash
curl -X POST http://192.168.1.50:4140/read \
  -H 'Content-Type: application/json' \
  -d '{"text": "Heads up — the build failed on CI.", "voice": "nova", "rate": 1.3}'
```

**Check if VoxClaw is available before sending:**

```bash
curl -s http://192.168.1.50:4140/status | grep -q '"status":"ok"' && \
  curl -X POST http://192.168.1.50:4140/read -d 'Ready to go.'
```
