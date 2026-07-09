#!/usr/bin/env bash
# Claude Code status line: model · dir(branch) · 5h limit · context · last request · cost
# All data comes from the statusLine JSON on stdin (Claude Code >= 2.1.x).
input=$(cat)

# Context budget before auto-compact (matches CLAUDE_CODE_AUTO_COMPACT_WINDOW, default 400k)
LIMIT=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-400000}

sep() { printf "\033[90m │ \033[0m"; }

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
read -r five reset ctx cost added removed <<<"$(echo "$input" | jq -r '[
  (.rate_limits.five_hour.used_percentage // -1),
  (.rate_limits.five_hour.resets_at // -1),
  (.context_window.total_input_tokens // -1),
  (.cost.total_cost_usd // -1),
  (.cost.total_lines_added // -1),
  (.cost.total_lines_removed // -1)] | @tsv')"

# fallback: derive context tokens from the session transcript when not provided inline
if [ "$ctx" = "-1" ]; then
  transcript=$(echo "$input" | jq -r '.transcript_path // ""')
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    ctx=$(jq -s '[.[] | select(.message.usage != null) | .message.usage
      | (.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | last // -1' "$transcript" 2>/dev/null)
    [ -z "$ctx" ] && ctx=-1
  fi
fi

# short model tag
case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
  *opus*)   model=OP ;;
  *sonnet*) model=SO ;;
  *haiku*)  model=HA ;;
  *fable*)  model=FA ;;
esac

# color by fill: green <70%, yellow <90%, red otherwise
col() { if [ "$1" -ge 90 ]; then printf 31; elif [ "$1" -ge 70 ]; then printf 33; else printf 32; fi; }

# project root + stable per-project color (hash path -> readable 256-color)
proj=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // "."')
palette=(39 45 51 75 81 111 117 147 153 183 189 213 219 210 216 222 228 156 120 84)
phash=$(printf '%s' "$proj" | cksum | cut -d' ' -f1)
pcol=${palette[$(( phash % ${#palette[@]} ))]}

# editor scheme for the clickable [code] link (trae > cursor > vscode)
scheme=""
if command -v trae >/dev/null 2>&1; then scheme=trae
elif command -v cursor >/dev/null 2>&1; then scheme=cursor
elif command -v code >/dev/null 2>&1; then scheme=vscode
fi

# ===== line 1: identity (model · project(branch) · code link) =====
l1=$(printf "\033[35m%s\033[0m" "$model")
l1+=$(sep)
l1+=$(printf "\033[1;38;5;%sm%s\033[0m" "$pcol" "$(basename "$proj")")
# subpath, when cwd is deeper than the project root
if [ "$cwd" != "$proj" ]; then
  case "$cwd" in "$proj"/*) l1+=$(printf "\033[90m/%s\033[0m" "${cwd#"$proj"/}") ;; esac
fi
# git branch + dirty + ahead/behind
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null && git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then st="✓"; else st="✗"; fi
  updown=""
  if ab=$(git -C "$cwd" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null); then
    behind=${ab%%[[:space:]]*}; ahead=${ab##*[[:space:]]}
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null || [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && updown+=" ↑$ahead"
      [ "${behind:-0}" -gt 0 ] 2>/dev/null && updown+=" ↓$behind"
    else
      updown=" ≡"
    fi
  fi
  l1+=$(printf " \033[33m(%s %s%s)\033[0m" "$branch" "$st" "$updown")
fi
# clickable [code] link -> open the PROJECT ROOT as a workspace via OSC 8 hyperlink.
# percent-encode the path (spaces / non-ASCII) so the URI stays valid; keep / literal.
# ?windowId=_blank forces a new window so the click never replaces the current one.
if [ -n "$scheme" ]; then
  uri=$(jq -rn --arg s "$proj" '$s|@uri'); uri=${uri//%2F//}
  l1+=$(sep)
  l1+=$(printf "\033]8;;%s://file%s?windowId=_blank\a\033[34m</> %s\033[0m\033]8;;\a" "$scheme" "$uri" "$scheme")
fi

# ===== line 2: metrics (5h · context · lines · cost) =====
l2=""
add2() { [ -n "$l2" ] && l2+=$(sep); l2+=$1; }

if [ "$five" != "-1" ]; then
  fi5=$(printf "%.0f" "$five")
  left=""
  if [ "$reset" != "-1" ]; then
    secs=$(( ${reset%.*} - $(date +%s) )); [ "$secs" -lt 0 ] && secs=0
    left=$(printf " %dh%02dm" $(( secs / 3600 )) $(( secs % 3600 / 60 )))
  fi
  add2 "$(printf "\033[%sm⧗ %d%%%s\033[0m" "$(col "$fi5")" "$fi5" "$left")"
fi

if [ "$ctx" != "-1" ]; then
  pct=$(( ctx * 100 / LIMIT )); ck=$(( ctx / 1000 )); lk=$(( LIMIT / 1000 ))
  [ "$pct" -ge 90 ] && warn=" ⚠ compact soon" || warn=""
  add2 "$(printf "\033[%sm▦ %dk/%dk%s\033[0m" "$(col "$pct")" "$ck" "$lk" "$warn")"
fi

if [ "$added" != "-1" ] && { [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; }; then
  add2 "$(printf "\033[32m+%d\033[0m \033[31m-%d\033[0m" "$added" "$removed")"
fi

if [ "$cost" != "-1" ]; then
  add2 "$(printf "\033[90m\$%.2f\033[0m" "$cost")"
fi

if [ -n "$l2" ]; then printf "%s\n%s" "$l1" "$l2"; else printf "%s" "$l1"; fi
