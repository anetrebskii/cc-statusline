#!/usr/bin/env bash
# Claude Code status line: model · dir(branch) · 5h limit (+reset) · context · cost
# All data comes from the statusLine JSON on stdin (Claude Code >= 2.1.x).
input=$(cat)

# Context budget before auto-compact (matches CLAUDE_CODE_AUTO_COMPACT_WINDOW, default 400k)
LIMIT=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-400000}

sep() { printf "\033[90m │ \033[0m"; }

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
read -r five reset ctx cost <<<"$(echo "$input" | jq -r '[
  (.rate_limits.five_hour.used_percentage // -1),
  (.rate_limits.five_hour.resets_at // -1),
  (.context_window.total_input_tokens // -1),
  (.cost.total_cost_usd // -1)] | @tsv')"

# short model tag
case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
  *opus*)   model=OP ;;
  *sonnet*) model=SO ;;
  *haiku*)  model=HA ;;
  *fable*)  model=FA ;;
esac

# color by fill: green <70%, yellow <90%, red otherwise
col() { if [ "$1" -ge 90 ]; then printf 31; elif [ "$1" -ge 70 ]; then printf 33; else printf 32; fi; }

out=""

# model
out+=$(printf "\033[35m%s\033[0m" "$model")

# dir + git
out+=$(sep)
out+=$(printf "\033[36m%s\033[0m" "$(basename "$cwd")")
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null && git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then st="✓"; else st="✗"; fi
  out+=$(printf " \033[33m(%s %s)\033[0m" "$branch" "$st")
fi

# 5h usage limit (Pro/Max only, present after first response)
if [ "$five" != "-1" ]; then
  fi5=$(printf "%.0f" "$five")
  left=""
  if [ "$reset" != "-1" ]; then
    secs=$(( ${reset%.*} - $(date +%s) )); [ "$secs" -lt 0 ] && secs=0
    left=$(printf " %dh%02dm" $(( secs / 3600 )) $(( secs % 3600 / 60 )))
  fi
  out+=$(sep); out+=$(printf "\033[%sm5h %d%%%s\033[0m" "$(col "$fi5")" "$fi5" "$left")
fi

# context window usage vs auto-compact budget
if [ "$ctx" != "-1" ]; then
  pct=$(( ctx * 100 / LIMIT )); ck=$(( ctx / 1000 )); lk=$(( LIMIT / 1000 ))
  [ "$pct" -ge 90 ] && warn=" ⚠ compact soon" || warn=""
  out+=$(sep); out+=$(printf "\033[%smctx %dk/%dk (%d%%)%s\033[0m" "$(col "$pct")" "$ck" "$lk" "$pct" "$warn")
fi

# session cost
if [ "$cost" != "-1" ]; then
  out+=$(sep); out+=$(printf "\033[90m\$%.2f\033[0m" "$cost")
fi

printf "%s" "$out"
