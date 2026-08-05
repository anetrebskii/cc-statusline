#!/usr/bin/env bash
# SessionStart hook. Keeps ~/.claude/hooks/statusline.sh in sync with the copy bundled in the
# plugin, and points settings.json at it. Runs on every session start, so it must stay quiet
# and must never fail the session - every path exits 0.
set -uo pipefail

SRC="${CLAUDE_PLUGIN_ROOT:-}/statusline.sh"
DEST_DIR="$HOME/.claude/hooks"
DEST="$DEST_DIR/statusline.sh"
MARKER="$DEST_DIR/.cc-statusline-plugin-managed"
SETTINGS="$HOME/.claude/settings.json"

[ -f "$SRC" ] || exit 0
mkdir -p "$DEST_DIR" 2>/dev/null || exit 0

# cmp covers both first run and "a plugin update changed the script"
if ! cmp -s "$SRC" "$DEST"; then
  tmp="$DEST.tmp.$$"
  if cp "$SRC" "$tmp" 2>/dev/null && chmod +x "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$DEST" 2>/dev/null   # atomic: a session rendering right now keeps the old inode
  fi
  rm -f "$tmp" 2>/dev/null
fi

# tells statusline.sh to leave its own curl updater off - the plugin is the source of truth
: > "$MARKER" 2>/dev/null

# Wire up statusLine. Only when it is unset or already ours, so a status line the user points
# somewhere else is never clobbered.
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS" 2>/dev/null || exit 0

cur=$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null) || exit 0
if [ -z "$cur" ]; then
  tmp="$SETTINGS.tmp.$$"
  if jq --arg cmd "$DEST" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$SETTINGS" 2>/dev/null
  fi
  rm -f "$tmp" 2>/dev/null
fi

exit 0
