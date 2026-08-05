#!/usr/bin/env bash
# Claude Code status line: model · dir(branch) · 5h limit · context · last request · cost
# All data comes from the statusLine JSON on stdin (Claude Code >= 2.1.x).
input=$(cat)

# Context budget before auto-compact (matches CLAUDE_CODE_AUTO_COMPACT_WINDOW, default 400k)
LIMIT=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-400000}

# How many skill names to show before collapsing the rest into a "+N" counter
SKILLS_MAX=${CC_STATUSLINE_SKILLS:-3}

# Self-update: once a day, refresh this script from the repo in the background so machines that
# installed it stay current. CC_STATUSLINE_AUTOUPDATE=0 disables it.
UPDATE_URL=${CC_STATUSLINE_UPDATE_URL:-https://raw.githubusercontent.com/anetrebskii/cc-statusline/main/statusline.sh}
stamp="${TMPDIR:-/tmp}/cc-statusline-update"
if [ "${CC_STATUSLINE_AUTOUPDATE:-1}" = 1 ] && [ -f "$0" ] && [ -w "$0" ] &&
   { [ ! -f "$stamp" ] || [ -n "$(find "$stamp" -mmin +1440 2>/dev/null)" ]; }; then
  : > "$stamp"   # stamp before fetching, so a broken network doesn't retry on every render
  ( t="$0.tmp.$$"
    # only swap in something that is non-empty, starts with a shebang and actually parses,
    # so a captive-portal HTML page or a truncated download can never replace a working script
    if curl -fsSL --max-time 10 "$UPDATE_URL" -o "$t" && [ -s "$t" ] &&
       IFS= read -r l < "$t" && [ "${l#\#!}" != "$l" ] &&
       bash -n "$t" 2>/dev/null && ! cmp -s "$t" "$0"; then
      chmod +x "$t" && mv -f "$t" "$0"   # same dir: atomic, and running instances keep the old inode
    fi
    rm -f "$t"
  ) </dev/null >/dev/null 2>&1 &
fi

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

transcript=$(echo "$input" | jq -r '.transcript_path // ""')
[ -f "$transcript" ] || transcript=""

# fallback: derive context tokens from the session transcript when not provided inline
if [ "$ctx" = "-1" ] && [ -n "$transcript" ]; then
  ctx=$(jq -s '[.[] | select(.message.usage != null) | .message.usage
    | (.input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | last // -1' "$transcript" 2>/dev/null)
  [ -z "$ctx" ] && ctx=-1
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

# percent-encode a path for an editor URI, keeping / literal
enc() { local u; u=$(jq -rn --arg s "$1" '$s|@uri'); printf '%s' "${u//%2F//}"; }

# locate a skill's SKILL.md. Built-ins are embedded in the claude binary and have no file,
# so an empty result just means "render the name without a link".
skill_uri() {
  local n=${1#*:} p d
  for d in "$proj/.claude" "$HOME/.claude"; do
    for p in "$d/skills/$n/SKILL.md" "$d/skills/$n.md" "$d/commands/$n.md"; do
      [ -f "$p" ] && { enc "$p"; return; }
    done
  done
  p=$(find "$HOME/.claude/plugins" -maxdepth 9 \
        \( -path "*/skills/$n/SKILL.md" -o -path "*/commands/$n.md" \) -print -quit 2>/dev/null)
  [ -n "$p" ] && enc "$p"
}

# ===== skills invoked this session, scraped from Skill tool_use records in the transcript =====
# Transcripts are append-only, so cache the scan and only read bytes added since the last render.
# Cache holds "name<TAB>uri" so each name resolves to a file at most once per session.
LF=$'\n'
skills=""
if [ -n "$transcript" ]; then
  sid=$(echo "$input" | jq -r '.session_id // ""')
  [ -z "$sid" ] && sid=$(printf '%s' "$transcript" | cksum | cut -d' ' -f1)
  cf="${TMPDIR:-/tmp}/cc-statusline-skills"; mkdir -p "$cf"; cf="$cf/$sid"
  size=$(stat -f%z "$transcript" 2>/dev/null || stat -c%s "$transcript" 2>/dev/null || echo 0)
  off=0; seen=""
  if [ -f "$cf" ]; then
    IFS= read -r off < "$cf"; seen=$(tail -n +2 "$cf")
    # garbled cache, or a transcript that shrank: start over
    case "$off" in ''|*[!0-9]*) off=0; seen="" ;; esac
    [ "$off" -gt "$size" ] && { off=0; seen=""; }
  fi
  if [ "$off" -lt "$size" ]; then
    # first render of an already-huge transcript: scan only the recent tail, else this blocks for seconds
    [ "$off" -eq 0 ] && [ "$size" -gt 20000000 ] && off=$((size - 20000000))
    known="$LF$(printf '%s' "$seen" | cut -f1)$LF"
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      case "$known" in *"$LF$s$LF"*) continue ;; esac
      known+="$s$LF"
      seen+="${seen:+$LF}$s"$'\t'"$(skill_uri "$s")"
    done < <(tail -c "+$((off + 1))" "$transcript" \
               | grep -oE '"name":"Skill","input":\{"skill":"[^"]+"' \
               | sed -E 's/.*"skill":"//; s/"$//')
    printf '%s\n%s\n' "$size" "$seen" > "$cf"
  fi
  if [ -n "$seen" ]; then
    n=$(printf '%s\n' "$seen" | wc -l | tr -d ' ')
    while IFS=$'\t' read -r s u; do
      [ -n "$u" ] && [ -n "$scheme" ] &&
        s=$(printf '\033]8;;%s://file%s\a%s\033]8;;\a' "$scheme" "$u" "$s")
      skills+="${skills:+ · }$s"
    done <<<"$(printf '%s\n' "$seen" | tail -"$SKILLS_MAX")"
    [ "$n" -gt "$SKILLS_MAX" ] && skills="+$((n - SKILLS_MAX)) · $skills"
  fi
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

if [ -n "$skills" ]; then
  add2 "$(printf "\033[36m⚑ %s\033[0m" "$skills")"
fi

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
