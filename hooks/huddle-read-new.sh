#!/usr/bin/env bash
# UserPromptSubmit: surface what changed for siblings since this session last
# looked, filtered to what's relevant to *me*:
#   1. new sibling board entries (plans, contracts) since my last turn;
#      a contract on a file I'm currently touching is flagged ⚠.
#   2. spatial overlap: a sibling editing a file I'm also editing (touched-set
#      intersection), warned once per session per (sibling, path).
# Self-posts are skipped. Stays quiet when nothing relevant moved.
set -euo pipefail

HOOK_JSON=$(cat)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=huddle-lib.sh
. "$DIR/huddle-lib.sh"

cwd=$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty'); [ -n "$cwd" ] || cwd="$PWD"
sid=$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // empty')
room=$(huddle_room "$cwd")
rdir=$(huddle_room_dir "$room")
[ -d "$rdir" ] || exit 0
me=$(huddle_agent "$cwd")
me_safe=$(huddle_safe "$me")
marker="$rdir/.seen-${sid:-none}"

# My current working set (TTL-valid), for relevance + overlap checks.
declare -A mine=()
while IFS= read -r p; do [ -n "$p" ] && mine["$p"]=1; done < <(huddle_touched_paths "$rdir" "$me")

# 1. New sibling board entries since the last turn.
new_lines=""
if [ -f "$marker" ]; then
  mapfile -t files < <(find "$rdir" -maxdepth 1 -name '*.md' -newer "$marker" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
  for f in "${files[@]}"; do
    agent=$(huddle_field "$f" agent)
    [ "$agent" = "$me" ] && continue   # don't echo our own posts back
    kind=$(huddle_field "$f" kind)
    ts=$(huddle_field "$f" ts)
    body=$(huddle_firstline "$f")
    flag=""
    if [ "$kind" = "contract" ]; then
      cpath=$(huddle_field "$f" path)
      [ -n "$cpath" ] && [ -n "${mine[$cpath]:-}" ] && flag="⚠ "
    fi
    new_lines+=$'\n'"• ${flag}[$ts] ${agent}/${kind}: ${body}"
  done
fi
# Establish/refresh the baseline (first turn just sets it and shows nothing here).
touch "$marker" 2>/dev/null || true

# 2. Spatial overlap: a sibling editing a file I'm also editing. Warn once per
# session per (sibling, path) so it doesn't repeat every turn.
overlap_lines=""
if [ "${#mine[@]}" -gt 0 ]; then
  ovmark="$rdir/.seen-overlap-${sid:-none}"
  for tf in "$rdir"/.touched-*; do
    [ -e "$tf" ] || continue
    sib=${tf##*/.touched-}
    [ "$sib" = "$me_safe" ] && continue
    while IFS= read -r p; do
      { [ -n "$p" ] && [ -n "${mine[$p]:-}" ]; } || continue
      key="${sib}	${p}"
      grep -qxF "$key" "$ovmark" 2>/dev/null && continue
      printf '%s\n' "$key" >> "$ovmark"
      overlap_lines+=$'\n'"• ⚠ ${sib} is also editing ${p} — coordinate before you both change it."
    done < <(huddle_touched_paths_file "$tf")
  done
fi

body_all="${new_lines}${overlap_lines}"
[ -n "$body_all" ] || exit 0
printf 'NEW huddle updates relevant to you in room "%s":%s\n' "$room" "$body_all"
exit 0
