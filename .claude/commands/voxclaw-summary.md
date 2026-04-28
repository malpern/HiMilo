---
description: Speak a final VoxClaw summary after work completes
argument-hint: [spoken-summary]
allowed-tools: Bash(plugins/voxclaw/scripts/voxclaw-say *)
---

Read the completed work aloud with VoxClaw after you finish.

Write a 1 to 3 sentence spoken summary that leads with the outcome, then verification status, then any blocker.

Run this command:

```bash
printf '%s\n' "$ARGUMENTS" | plugins/voxclaw/scripts/voxclaw-say --kind summary
```
