#!/usr/bin/env bash
# Shared helpers for the huddle plugin hooks.
# Sourced by huddle-read.sh, huddle-read-new.sh, huddle-write-plan.sh.

# Root of the shared store. Override with HUDDLE_HOME for testing or relocation.
HUDDLE_HOME="${HUDDLE_HOME:-$HOME/.claude/huddle}"

# huddle_room CWD -> room name (git repo basename, else cwd basename).
# All agents whose cwd resolves to the same repo share one room.
huddle_room() {
  local cwd="$1" top
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || top=""
  if [ -n "$top" ]; then basename "$top"; else basename "$cwd"; fi
}

# huddle_agent [CWD] -> this agent's identity.
# HUDDLE_AGENT env wins (export per terminal, e.g. HUDDLE_AGENT=frontend);
# falls back to git branch, then "unknown".
huddle_agent() {
  if [ -n "${HUDDLE_AGENT:-}" ]; then printf '%s' "$HUDDLE_AGENT"; return; fi
  local b; b=$(git -C "${1:-$PWD}" branch --show-current 2>/dev/null) || b=""
  printf '%s' "${b:-unknown}"
}

# huddle_room_dir ROOM -> absolute path to that room's directory.
huddle_room_dir() { printf '%s/%s' "$HUDDLE_HOME" "$1"; }

# huddle_field FILE NAME -> value of a "NAME: value" frontmatter line.
huddle_field() { awk -F': ' -v k="^$2:" '$0 ~ k {print $2; exit}' "$1"; }

# huddle_firstline FILE -> first non-empty line of the body (after frontmatter).
huddle_firstline() {
  awk 'BEGIN{fm=0} /^---/{fm++; next} fm>=2 && NF {print; exit}' "$1"
}
