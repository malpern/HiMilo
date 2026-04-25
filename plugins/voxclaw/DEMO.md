# VoxClaw Plugin Demo

This plugin is meant to give Codex a stable voice-output surface during coding work.

## What to try

Health check:

```bash
plugins/voxclaw/scripts/voxclaw-say --health
```

Speak a direct message:

```bash
plugins/voxclaw/scripts/voxclaw-say "Task complete. Tests passed."
```

Speak the default final agent summary:

```bash
plugins/voxclaw/scripts/voxclaw-say --kind summary "Task complete. Tests passed."
```

Speak a failure summary:

```bash
plugins/voxclaw/scripts/voxclaw-say --kind failure "Build failed in the network listener."
```

Pipe a generated summary:

```bash
printf '%s\n' "Build failed. The parser tests are failing after the networking changes." | \
  plugins/voxclaw/scripts/voxclaw-say --kind failure
```

Use a remote VoxClaw listener:

```bash
plugins/voxclaw/scripts/voxclaw-say \
  --url http://192.168.1.50:4140/read \
  --voice nova \
  --rate 1.2 \
  "Deployment complete."
```

Use explicit live progress narration only when the user opted in:

```bash
plugins/voxclaw/scripts/voxclaw-say --kind progress "Halfway through the migration."
```

## Agent patterns

Use `voxclaw-read-task-summary` when finishing work:

```text
Summarize the completed work in 1 to 3 spoken sentences, then send it through plugins/voxclaw/scripts/voxclaw-say --kind summary.
```

Use `voxclaw-read-test-failures` when verification fails:

```text
Condense the failing tests into one short spoken sentence and send it through plugins/voxclaw/scripts/voxclaw-say --kind failure.
```

For Claude Code, the same helper can be called from project commands in `.claude/commands/`.

## Notes on manifest confidence

As of April 19, 2026, I was able to verify from OpenAI's official docs that Codex plugins are installable packages and that local marketplace entries use plugin names plus source and policy metadata. I was not able to locate a public canonical `plugin.json` schema page in official docs, so the manifest here intentionally stays minimal:

- `name`
- `description`
- `homepage`
- `interface.displayName`

That is an inference from available docs plus local plugin-creator guidance, not a directly quoted schema guarantee.
