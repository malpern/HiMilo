---
name: voxclaw-read-task-summary
description: Speak a concise final task summary aloud with VoxClaw after completing work.
homepage: https://github.com/malpern/VoxClaw
metadata: {"requires":{"bins":["bash"]}}
---

# VoxClaw Read Task Summary

Use this skill when the user would benefit from hearing the finished result out loud.

## Workflow

1. Write a short spoken summary first.
2. Keep it to 1 to 3 sentences.
3. Prefer outcome, verification status, and any blocker.
4. Speak it with the plugin helper:

```bash
plugins/voxclaw/scripts/voxclaw-say "Task complete. I updated the parser and the tests passed."
```

You can also pipe generated text:

```bash
printf '%s\n' "Task complete. The release build succeeded." | plugins/voxclaw/scripts/voxclaw-say
```

## Style

- Keep spoken text shorter than written text.
- Expand symbols and abbreviations when they would sound awkward aloud.
- Avoid reading file paths unless they matter to the user.
- Mention failed verification clearly when tests were not run or did not pass.
