# cc-statusline

A compact, informative status line for [Claude Code](https://claude.com/claude-code).

```
OP │ my-project (main ✓) │ ⚑ apple-ui · dataviz │ 5h 24% 2h13m │ ctx 62k/400k (15%) │ $0.42
```

## What it shows

| Segment | Meaning |
|---|---|
| `OP` | Current model, shortened (`OP` Opus, `SO` Sonnet, `HA` Haiku, `FA` Fable) |
| `my-project (main ✓)` | Directory + git branch (`✓` clean, `✗` dirty) |
| `⚑ apple-ui · dataviz` | Skills invoked so far this session; hidden when none have run |
| `5h 24% 2h13m` | Percentage of your **5-hour usage limit** used, and time until it resets |
| `ctx 62k/400k (15%)` | Current context size vs your auto-compact budget; shows `⚠ compact soon` at ≥90% |
| `$0.42` | Session cost |

<img width="1016" height="198" alt="image" src="https://github.com/user-attachments/assets/847063b7-9634-40f2-a9b3-b6a778efa114" />


Usage segments turn **yellow ≥70%** and **red ≥90%**.

The `5h` segment is Claude.ai **Pro/Max only** and appears after the first model
response in a session. The context and cost segments work on any plan.

The `⚑` segment lists unique skills in order of first use, keeping the last
three (`+2 · a · b · c` when more have run). It comes from `Skill` tool calls in
the session transcript, so it counts skills Claude actually invoked - not the
ones merely available. Subagent skill calls in the same session are included.

Each name is a link that opens its `SKILL.md` in your editor. Personal, project,
and plugin skills all resolve; Claude Code's built-in skills are embedded in the
binary and have no file, so those render as plain text.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/anetrebskii/cc-statusline/main/install.sh | bash
```

This downloads `statusline.sh` to `~/.claude/hooks/` and sets the `statusLine`
key in `~/.claude/settings.json`. Start a new Claude Code session to see it.

### Manual install

1. Copy `statusline.sh` to `~/.claude/hooks/statusline.sh` and `chmod +x` it.
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/hooks/statusline.sh"
  }
}
```

## Configuration

The context budget denominator (`400k` above) is the auto-compact threshold. It
reads `CLAUDE_CODE_AUTO_COMPACT_WINDOW` and falls back to `400000`. To measure
against the model's full window instead, edit `LIMIT` at the top of the script
(e.g. `1000000` for a 1M-context model).

`CC_STATUSLINE_SKILLS` sets how many skill names the `⚑` segment shows before
collapsing the rest into `+N` (default `3`). Both read the environment, so set
them in the `env` block of `~/.claude/settings.json`:

```json
{ "env": { "CC_STATUSLINE_SKILLS": "5" } }
```

## Updating

The script updates itself. Once a day it fetches the latest `statusline.sh` from
`main` in the background and swaps it in, so every machine you installed it on
stays current without you touching them.

The replacement only happens if the download is non-empty, starts with a
shebang, and passes `bash -n` - a captive-portal login page or a truncated
download can't replace a working script. The swap is an atomic rename in the
same directory, so a session rendering at that moment keeps the old file.

| Variable | Effect |
|---|---|
| `CC_STATUSLINE_AUTOUPDATE=0` | Turn self-update off |
| `CC_STATUSLINE_UPDATE_URL=...` | Update from your own fork or a pinned tag instead of `main` |

Two caveats worth knowing:

- Auto-update only exists from this version on. A machine running an older copy
  has no updater in it, so it needs `install.sh` run once more to pick this up.
  After that it keeps itself current.
- It runs whatever is on `main` at fetch time. Anything pushed there executes on
  every installed machine within a day. Point `CC_STATUSLINE_UPDATE_URL` at a
  tag (`.../cc-statusline/v1.2.0/statusline.sh`) if you'd rather cut deliberate
  releases than ship every commit.

## Requirements

`jq`, `git`, and standard coreutils - all data comes from the JSON that Claude
Code pipes to the status line command on stdin (requires Claude Code >= 2.1.x).

## License

MIT
