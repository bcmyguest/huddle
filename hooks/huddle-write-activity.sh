#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): when an edit lands on a shared-surface file
# (api / schema / types / config / deps), publish a `contract` entry so siblings
# see the surface moved. This is the cross-agent breaker that worktree isolation
# can't catch — agents in *different* files, one breaking the other's assumption.
# Fresh by construction (rides the edit). Superseded in place per (agent, path),
# so the board carries one current entry per surface, not a history. Silent: the
# entry is for siblings, surfaced by their read hooks, not echoed to this agent.
set -euo pipefail

HOOK_JSON=$(cat)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=huddle-lib.sh
. "$DIR/huddle-lib.sh"

tool=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_name // empty')
case "$tool" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac

cwd=$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty'); [ -n "$cwd" ] || cwd="$PWD"
fp=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.file_path // empty')
[ -n "$fp" ] || exit 0

rel=$(huddle_relpath "$cwd" "$fp")
surface=$(huddle_surface "$rel")
[ -n "$surface" ] || exit 0   # not a shared surface -> nothing to publish

room=$(huddle_room "$cwd")
me=$(huddle_agent "$cwd")
rdir=$(huddle_room_dir "$room")
mkdir -p "$rdir"
safe_agent=$(printf '%s' "$me" | tr -c 'A-Za-z0-9_.-' '_')

# Supersede: drop this agent's prior contract entry for the same path.
for old in "$rdir"/*-"${safe_agent}"-contract.md; do
  [ -e "$old" ] || continue
  [ "$(huddle_field "$old" path)" = "$rel" ] && rm -f "$old"
done

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Nanosecond stamp: contract fires on every surface edit, so a 1-second epoch
# would collide and clobber when several land in the same second.
stamp=$(date -u +%s%N)
file="$rdir/${stamp}-${safe_agent}-contract.md"

{
  printf -- '---\n'
  printf 'agent: %s\n' "$me"
  printf 'room: %s\n' "$room"
  printf 'kind: contract\n'
  printf 'surface: %s\n' "$surface"
  printf 'path: %s\n' "$rel"
  printf 'status: active\n'
  printf 'ts: %s\n' "$ts"
  printf -- '---\n\n'
  printf 'changed %s (%s surface) — re-check your assumptions about it.\n' "$rel" "$surface"
} > "$file"

exit 0
