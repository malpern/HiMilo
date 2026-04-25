---
name: voxclaw-read-test-failures
description: Speak a concise summary of failing tests or build errors with VoxClaw.
homepage: https://github.com/malpern/VoxClaw
metadata: {"requires":{"bins":["bash"]}}
---

# VoxClaw Read Test Failures

Use this skill when tests or builds fail and the user wants audible notification.

## Workflow

1. Condense the failure into one short spoken summary.
2. Lead with pass or fail status.
3. Mention the failing suite or subsystem, not the full log.
4. Mention the likely cause only if it is already clear.
5. Speak it with the helper:

```bash
plugins/voxclaw/scripts/voxclaw-say "Tests failed. External playback controller tests are failing after the browser control changes."
```

## Style

- Do not read stack traces or long assertion bodies aloud by default.
- Prefer one actionable sentence over exhaustive detail.
- If multiple failures share one cause, summarize the cause once.
