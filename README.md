# huddle

**A shared, hook-enforced board so parallel coding agents stay aware of each
other.** Run one agent on the frontend and another on the backend, in the same
repo, on separate features. `huddle` lets each see what the other is about to
build, without a daemon, a server, or the agents having to remember to check in.

Works for **Claude Code** and **opencode**, and across them: a Claude Code agent
and an opencode agent whose `cwd` is in the same repo share one board.

It's a thin memory layer the agents *can't forget to use*: the reads (and, on
Claude Code, the plan-writes) are driven by editor hooks, not by the model
choosing to.

Pairs with [`handoff`](https://github.com/bcmyguest/baton) (capture state) and
[`pickup`](https://github.com/bcmyguest/baton) (resume state). Where those move
work *across time*, `huddle` shares it *across concurrent agents*.

## What it does

One file store. No daemon, no server. The editor's hooks drive it:

| Moment | Effect |
|--------|--------|
| session begins | injects the room's active board into context |
| every turn | injects only sibling entries new since your last turn |
| a plan is approved | publishes that plan to the room |

Reads are guaranteed (injected context, the model can't skip them). The plan
write is hook-driven. Cadence is **milestone-based**, not per-turn: the board
only gains an entry when a plan is published, so it stays low-noise.

### Claude Code

Three hooks, each enforced so the model can't skip a read or forget to post:

| Hook | Fires | Effect |
|------|-------|--------|
| `SessionStart` | session begins | injects the room's active board into context |
| `UserPromptSubmit` | every turn | injects only sibling entries new since your last turn |
| `PostToolUse` (`ExitPlanMode`) | you approve a plan | publishes that plan to the room |

### opencode

The same store, reached through opencode's plugin API. `opencode/huddle.ts` is a
thin bridge that shells out to the same three scripts, so the on-disk format and
rooms are identical and the two editors interoperate.

- **Reads** map to `chat.message` + `experimental.chat.system.transform`: the
  full board is injected on your first prompt, then only new sibling entries on
  every prompt after. Same guarantee as Claude Code.
- **Publish** maps to `session.idle` for opencode's **plan agent**, the
  structural twin of Claude's plan mode: when a plan-mode turn finishes, its
  plan is posted to the room. opencode has no `ExitPlanMode` event, so this is
  the closest faithful trigger. Build-mode-only sessions still read the board
  but do not post, so run the planning turn in plan mode to publish.

## Rooms

A **room** = the git repo basename of your working directory. Two agents whose
`cwd` is in the same repo automatically share a room, regardless of which editor
each runs. (Monorepo split by sub-package is a later addition.)

## Agent identity

Each entry is tagged with who wrote it. Identity resolves as:

1. `HUDDLE_AGENT` env var (export it per terminal: `export HUDDLE_AGENT=frontend`)
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

### Claude Code

No clone needed — add the repo as a plugin marketplace:

```bash
claude plugin marketplace add bcmyguest/huddle
claude plugin install huddle@huddle
# restart Claude Code so hooks load
```

(Cloned it already? `/plugin` from a session adds the local directory instead.)

### opencode

```bash
# 1. point huddle at this repo so the plugin can find the hook scripts
export HUDDLE_ROOT=/path/to/huddle

# 2. load the plugin (globally here; or drop it in a project's .opencode/plugin/)
ln -s "$HUDDLE_ROOT/opencode/huddle.ts" ~/.config/opencode/plugin/huddle.ts
```

Put `export HUDDLE_ROOT=...` (and `HUDDLE_AGENT`) in each terminal's shell rc so
opencode inherits them, then restart opencode. The plugin fails open: if it
can't find the scripts it disables itself and never blocks a prompt.

Then in each terminal you spawn an agent in (either editor):

```bash
export HUDDLE_AGENT=frontend   # or backend, infra, ...
```

## Limits (by design)

- Not real-time. A sibling's plan reaches you at your **next prompt**, not mid-turn.
- Sync points are plan-approve only. A long-running agent that never re-plans goes
  quiet until it does. (Hooking into `handoff` is a planned second sync point.)
- On opencode, only plan-agent turns post; build-mode-only sessions read but don't
  write, since opencode exposes no plan-approval hook.
- No locking. Entries are append-only files; concurrent writes don't collide
  because each is a uniquely named file.
- `jq` and GNU `find`/`date` required (Linux/standard dev box). The opencode
  plugin additionally needs opencode's Bun runtime (it ships with one).
