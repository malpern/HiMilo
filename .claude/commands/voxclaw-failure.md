---
description: Speak a concise VoxClaw failure summary
argument-hint: [spoken-failure-summary]
allowed-tools: Bash(plugins/voxclaw/scripts/voxclaw-say *)
---

Read a concise failure summary aloud with VoxClaw.

Condense the failure into one short sentence. Lead with fail or blocked status. Mention the failing suite, subsystem, or primary cause, not the full log.

Run this command:

```bash
printf '%s\n' "$ARGUMENTS" | plugins/voxclaw/scripts/voxclaw-say --kind failure
```
