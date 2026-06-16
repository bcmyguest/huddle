#!/usr/bin/env bash
# PostToolUse(ExitPlanMode): publish the approved plan to the room so siblings
# see what this agent is about to build. Hook-enforced — no agent cooperation.
set -euo pipefail

HOOK_JSON=$(cat)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=huddle-lib.sh
. "$DIR/huddle-lib.sh"

tool=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_name // empty')
[ "$tool" = "ExitPlanMode" ] || exit 0
plan=$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.plan // empty')
[ -n "$plan" ] || exit 0

cwd=$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty'); [ -n "$cwd" ] || cwd="$PWD"
room=$(huddle_room "$cwd")
me=$(huddle_agent "$cwd")
rdir=$(huddle_room_dir "$room")
mkdir -p "$rdir"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
epoch=$(date -u +%s)
safe_agent=$(printf '%s' "$me" | tr -c 'A-Za-z0-9_.-' '_')
file="$rdir/${epoch}-${safe_agent}-plan.md"

{
  printf -- '---\n'
  printf 'agent: %s\n' "$me"
  printf 'room: %s\n' "$room"
  printf 'kind: plan\n'
  printf 'status: active\n'
  printf 'ts: %s\n' "$ts"
  printf -- '---\n\n'
  printf '%s\n' "$plan"
} > "$file"

printf 'huddle: published plan to room "%s" as agent "%s".\n' "$room" "$me"
exit 0
