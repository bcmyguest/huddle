#!/usr/bin/env bash
# SessionStart: inject the full active huddle board for this repo's room.
# Plain stdout becomes injected session context.
set -euo pipefail

HOOK_JSON=$(cat)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=huddle-lib.sh
. "$DIR/huddle-lib.sh"

cwd=$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty'); [ -n "$cwd" ] || cwd="$PWD"
sid=$(printf '%s' "$HOOK_JSON" | jq -r '.session_id // empty')
room=$(huddle_room "$cwd")
rdir=$(huddle_room_dir "$room")

# Mark current state as "seen" so the per-prompt hook only surfaces newer entries.
mkdir -p "$rdir" 2>/dev/null || true
[ -n "$sid" ] && touch "$rdir/.seen-$sid" 2>/dev/null || true

# Newest 15 entries, newest first.
mapfile -t files < <(ls -1t "$rdir"/*.md 2>/dev/null | head -15)
[ "${#files[@]}" -gt 0 ] || exit 0

out="HUDDLE BOARD — room \"$room\". Other agents working this repo have posted the plans/handoffs below. Review before you act; if your work overlaps or conflicts with an entry, say so instead of silently diverging."
for f in "${files[@]}"; do
  agent=$(huddle_field "$f" agent)
  kind=$(huddle_field "$f" kind)
  ts=$(huddle_field "$f" ts)
  body=$(huddle_firstline "$f")
  out+=$'\n'"• [$ts] ${agent}/${kind}: ${body}"
done
printf '%s\n' "$out"
