#!/usr/bin/env bash
# UserPromptSubmit: inject only sibling entries that appeared since this
# session last looked. Keeps long sessions aware of siblings without re-dumping
# the whole board every turn. Self-posts are skipped.
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

marker="$rdir/.seen-${sid:-none}"
# No baseline yet (e.g. resumed session) — establish one and stay quiet.
if [ ! -f "$marker" ]; then touch "$marker" 2>/dev/null || true; exit 0; fi

me=$(huddle_agent "$cwd")
mapfile -t files < <(find "$rdir" -maxdepth 1 -name '*.md' -newer "$marker" -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk '{print $2}')
touch "$marker" 2>/dev/null || true
[ "${#files[@]}" -gt 0 ] || exit 0

out="NEW huddle updates from siblings in room \"$room\" since your last turn:"
shown=0
for f in "${files[@]}"; do
  agent=$(huddle_field "$f" agent)
  [ "$agent" = "$me" ] && continue   # don't echo our own posts back
  kind=$(huddle_field "$f" kind)
  ts=$(huddle_field "$f" ts)
  body=$(huddle_firstline "$f")
  out+=$'\n'"• [$ts] ${agent}/${kind}: ${body}"
  shown=$((shown + 1))
done
[ "$shown" -gt 0 ] && printf '%s\n' "$out" || true
exit 0
