---
description: Speak an opt-in VoxClaw progress update
argument-hint: [spoken-progress-update]
allowed-tools: Bash(plugins/voxclaw/scripts/voxclaw-say *)
---

Read a short progress update aloud with VoxClaw.

Use this only when the human explicitly opted into hearing progress while work is ongoing. Keep it to one sentence.

Run this command:

```bash
printf '%s\n' "$ARGUMENTS" | plugins/voxclaw/scripts/voxclaw-say --kind progress
```
