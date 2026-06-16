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

# huddle_relpath CWD PATH -> PATH relative to the git toplevel of CWD.
# Used so a touched/contract path is comparable across agents in the same repo.
# Falls back to the absolute path when CWD is not in a git repo.
huddle_relpath() {
  local cwd="$1" p="$2" top
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || top=""
  case "$p" in /*) : ;; *) p="$cwd/$p" ;; esac
  if [ -n "$top" ] && [ "${p#"$top"/}" != "$p" ]; then printf '%s' "${p#"$top"/}"; else printf '%s' "$p"; fi
}

# huddle_surface RELPATH -> shared-surface class (api|schema|types|config|deps),
# or empty if the path is not a cross-agent contract surface. These are the files
# whose change breaks a *sibling* working in different files — what plain worktree
# isolation can't catch. Kept tight to avoid false positives.
huddle_surface() {
  local p="$1"
  case "$p" in
    *openapi.*|*swagger.*|*.proto|*.graphql|*.graphqls) echo api; return ;;
    migrations/*|*/migrations/*|*schema.sql|*schema.prisma|*/schema.rb) echo schema; return ;;
    *.d.ts|*/types/*|packages/types/*) echo types; return ;;
    *.env.example|*.env.sample) echo config; return ;;
    package.json|*/package.json|go.mod|*/go.mod|Cargo.toml|*/Cargo.toml|pyproject.toml|*/pyproject.toml) echo deps; return ;;
    *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*go.sum|*uv.lock|*poetry.lock|*requirements*.txt) echo deps; return ;;
  esac
  case "$(basename "$p")" in
    .env.example|.env.sample) echo config; return ;;
  esac
}

# How long a touch stays "live" (seconds). A touch older than this is treated as
# the agent having moved on, so overlap warnings decay instead of lingering.
HUDDLE_TOUCH_TTL="${HUDDLE_TOUCH_TTL:-900}"

# huddle_safe STRING -> filename-safe form (used for agent in file names).
huddle_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

# huddle_record_touch ROOMDIR AGENT RELPATH
# Append RELPATH to this agent's rolling touched-set, deduped to one (latest)
# line per path and pruned of entries older than the TTL. The set is a plain
# `<epoch>\t<relpath>` file, dot-prefixed so the *.md board scans ignore it.
huddle_record_touch() {
  local rdir="$1" agent="$2" rel="$3" f now cutoff tmp
  f="$rdir/.touched-$(huddle_safe "$agent")"
  now=$(date -u +%s); cutoff=$((now - HUDDLE_TOUCH_TTL))
  tmp=$(mktemp "$rdir/.touched.XXXXXX") || return 0
  if [ -f "$f" ]; then
    awk -F'\t' -v c="$cutoff" -v p="$rel" '$1>=c && $2!=p' "$f" > "$tmp" 2>/dev/null || true
  fi
  printf '%s\t%s\n' "$now" "$rel" >> "$tmp"
  mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
}

# huddle_touched_paths_file FILE -> TTL-valid relpaths in a touched-set file.
huddle_touched_paths_file() {
  local f="$1" cutoff
  [ -f "$f" ] || return 0
  cutoff=$(( $(date -u +%s) - HUDDLE_TOUCH_TTL ))
  awk -F'\t' -v c="$cutoff" '$1>=c {print $2}' "$f" 2>/dev/null || true
}

# huddle_touched_paths ROOMDIR AGENT -> TTL-valid relpaths this agent has touched.
huddle_touched_paths() {
  huddle_touched_paths_file "$1/.touched-$(huddle_safe "$2")"
}
