#!/usr/bin/env bash
# Installer for the Claude Code status line.
# Downloads statusline.sh to ~/.claude/hooks/ and wires it into settings.json.
set -euo pipefail

REPO="anetrebskii/cc-statusline"
BRANCH="main"
HOOK_DIR="$HOME/.claude/hooks"
SCRIPT="$HOOK_DIR/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null || { echo "jq is required (brew install jq / apt install jq)"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

mkdir -p "$HOOK_DIR"
echo "Downloading statusline.sh -> $SCRIPT"
curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/statusline.sh" -o "$SCRIPT"
chmod +x "$SCRIPT"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp=$(mktemp)
jq --arg cmd "$SCRIPT" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

echo "Done. statusLine set in $SETTINGS"
echo "Restart Claude Code (or start a new session) to see it."
