# Terminal Integration Research

Explored whether VoxClaw could show speaking status or word-by-word
highlighting directly inside the terminal where Claude Code is running,
rather than (or in addition to) the floating overlay panel.

---

## Word-by-word highlighting in the terminal

### Kitty markers (most viable approach investigated)

`kitty @ create-marker regex 1 \bword\b` highlights regex matches in a
Kitty window. An external process could shift markers word-by-word as
speech advances.

**Limitations that make this impractical:**
- Markers highlight ALL matches of a pattern, not a specific positional
  instance. If "the" appears 40 times, all 40 highlight.
- Only one marker set active per window at a time.
- Constructing unique-enough regexes per word (using context/lookaround)
  is fragile.
- Claude Code owns the screen buffer and re-renders frequently —
  markers get clobbered.
- ~50-100ms latency per remote-control round-trip.

### ANSI re-rendering

Could rewrite terminal lines with ANSI color codes to simulate
highlighting. Not viable: Claude Code owns the buffer and would conflict
with any overwritten content.

### Kitty kittens (Python plugins)

Kittens can create overlay windows and read the screen buffer, but there
is no API to partially restyle existing screen content. Kittens are
designed for interactive UIs (like `icat`, `diff`), not continuous
background sync.

### Kitty graphics protocol

Designed for inline images/animations. Cannot style or overlay text
regions.

**Conclusion:** word-by-word terminal highlighting is not practically
achievable. The floating overlay panel remains the right solution for
this.

---

## Tab-title status indicator (viable, lightweight)

### Kitty

`kitty @ set-tab-title` via remote control. Can target a specific window
using `--match "id:$KITTY_WINDOW_ID"`. Each Claude Code session's hooks
inherit the window ID, so multi-agent setups would show per-tab
indicators without cross-talk.

**Prerequisites:** `allow_remote_control yes` in `kitty.conf`.

**Implementation:** one line in the existing Stop hook:
```bash
kitty @ set-tab-title --match "id:$KITTY_WINDOW_ID" "🦞 speaking" 2>/dev/null || true
```

Degrades silently on non-Kitty terminals (`2>/dev/null || true`).

**Unresolved: clearing the indicator.** The hook fires when speech is
queued, not when it finishes. Without a callback from VoxClaw, the
title stays stale. Options explored:

| Approach | Pros | Cons |
|---|---|---|
| Timer-based reset (sleep 2s, clear) | Simple, no stale state | Doesn't reflect actual speech duration |
| Ack hook clears on user reply | Accurate for responded-to updates | Stale if user never responds |
| Pass KITTY_WINDOW_ID in /read, VoxClaw clears on finish | Accurate | Couples VoxClaw to Kitty; protocol change |
| Claude Code re-render overwrites | Zero effort | Only works when user interacts with that tab |

**Recommendation if pursued:** 2-second flash (set title, sleep 2s,
reset). Zero protocol changes, no stale state, gives users a quick
"VoxClaw got this" signal. Low value-to-effort though — the floating
panel already provides this feedback.

### Ghostty

Ghostty does **not** have Kitty-style remote control. No IPC socket, no
`ghostty @` CLI, no plugin system, no exposed window IDs. The only
option is the standard ANSI escape sequence `\e]0;title\a` from within
the shell, which:
- Works for setting the title from the hook process
- Cannot target a specific window (applies to the TTY the hook runs in)
- Gets overwritten by Claude Code's own title updates

**Conclusion:** Ghostty integration is significantly more limited than
Kitty. ANSI title escapes are the only mechanism and they're unreliable
due to Claude Code overwriting them.

### Other terminals (iTerm2, Terminal.app, Warp, Alacritty)

- **iTerm2:** has proprietary escape sequences for badges and tab color.
  Could show a brief colored badge. Most capable after Kitty.
- **Terminal.app:** ANSI title only. Same limitations as Ghostty.
- **Warp:** no remote control API.
- **Alacritty:** no remote control API. ANSI title only.

---

## Decision

**Not implementing terminal integration for now.** The floating overlay
panel is terminal-agnostic, pixel-precise, and already ships. Terminal
status indicators are a nice-to-have with limited reach (Kitty-only for
the good version) and unresolved cleanup semantics.

If revisited, the Kitty tab-title flash is the lowest-effort option (one
line in the hook, graceful degradation). File as a potential v2
enhancement.

---

## Prior art

No GitHub projects implement real-time word-by-word highlighting in any
terminal synchronized with audio. The closest related project is
`kitty-scrollback.nvim` (Neovim integration with Kitty scrollback), but
it serves a different use case.
