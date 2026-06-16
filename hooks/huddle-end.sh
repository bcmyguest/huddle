#!/usr/bin/env bash
# SessionEnd: clean up this session's transient bookkeeping. Board entries
# (plans, contracts) are durable history and are left untouched — only the
# per-session marker files are removed. Also sweeps markers left behind by
# sessions that ended without firing this hook, so the store doesn't grow
# unbounded. Touched-sets self-prune by TTL at read time, so they're left alone.
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

# This session's markers.
[ -n "$sid" ] && rm -f "$rdir/.seen-$sid" "$rdir/.seen-overlap-$sid" 2>/dev/null || true

# Orphans: marker files untouched for >7 days (sessions that never fired this hook).
find "$rdir" -maxdepth 1 -type f -name '.seen-*' -mtime +7 -delete 2>/dev/null || true

exit 0
