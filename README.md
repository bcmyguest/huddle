# huddle

**A shared, hook-enforced board so parallel Claude Code agents stay aware of each
other.** Run one agent on the frontend and another on the backend, in the same
repo, on separate features — `huddle` lets each see what the other is about to
build, without a daemon, a server, or the agents having to remember to check in.

It's a thin memory layer the agents *can't forget to use*: the reads and the
plan-writes are driven by Claude Code hooks, not by the model choosing to.

Pairs with [`handoff`](https://github.com/bcmyguest/personal-skills) (capture
state) and [`pickup`](https://github.com/bcmyguest/personal-skills) (resume
state) — where those move work *across time*, `huddle` shares it *across
concurrent agents*.

## What it does

Three hooks, one file store. No daemon, no server.

| Hook | Fires | Effect |
|------|-------|--------|
| `SessionStart` | session begins | injects the room's active board into context |
| `UserPromptSubmit` | every turn | injects only sibling entries new since your last turn |
| `PostToolUse` (`ExitPlanMode`) | you approve a plan | publishes that plan to the room |

Reads are guaranteed (injected context — the model can't skip them). The plan
write is guaranteed (hook-driven). Cadence is **milestone-based**, not per-turn:
the board only gains an entry when a plan is approved, so it stays low-noise.

## Rooms

A **room** = the git repo basename of your working directory. Two agents whose
`cwd` is in the same repo automatically share a room. (Monorepo split by
sub-package is a later addition.)

## Agent identity

Each entry is tagged with who wrote it. Identity resolves as:

1. `HUDDLE_AGENT` env var — **export it per terminal**: `export HUDDLE_AGENT=frontend`
2. else the current git branch
3. else `unknown`

Set `HUDDLE_AGENT` in each terminal so the board reads `frontend/plan`,
`backend/plan`, etc.

## Store

```
~/.claude/huddle/<repo>/
  <epoch>-<agent>-plan.md     # one file per entry, append-only
  .seen-<session_id>          # per-session marker for incremental reads
```

Override the root with `HUDDLE_HOME`. Entries are plain markdown with frontmatter:

```markdown
---
agent: backend
room: acme
kind: plan
status: active
ts: 2026-06-15T14:03:00Z
---
Adding `role` field to /users response. Frontend: expect it nullable until migration N.
```

## Install

```bash
# from a Claude Code session:
/plugin            # add this directory as a local plugin, then enable "huddle"
# restart Claude Code so hooks load
```

Then in each terminal you spawn an agent in:

```bash
export HUDDLE_AGENT=frontend   # or backend, infra, ...
```

## Limits (by design)

- Not real-time. A sibling's plan reaches you at your **next prompt**, not mid-turn.
- Sync points are plan-approve only. A long-running agent that never re-plans goes
  quiet until it does. (Hooking into `handoff` is a planned second sync point.)
- No locking. Entries are append-only files; concurrent writes don't collide
  because each is a uniquely named file.
- `jq` and GNU `find`/`date` required (Linux/standard dev box).
