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
