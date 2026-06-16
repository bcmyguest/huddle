import type { Plugin } from "@opencode-ai/plugin"
import { existsSync } from "node:fs"
import { join } from "node:path"

// huddle — opencode adapter.
//
// Same shared board as the Claude Code plugin, same on-disk store. This is a
// thin bridge: the three bash hooks in ../hooks own all store logic (format,
// rooms, identity, incremental reads), and this plugin maps opencode's event
// model onto them. An opencode agent and a Claude Code agent whose cwd is in the
// same repo share one room.
//
// Mapping (opencode hook -> the Claude Code hook it stands in for):
//   chat.message + experimental.chat.system.transform  ->  SessionStart + UserPromptSubmit
//   event:session.idle (plan agent)                     ->  PostToolUse(ExitPlanMode)
//   tool.execute.after (edit|write)                     ->  PostToolUse(Edit|Write|MultiEdit)
//   event:session.deleted                               ->  SessionEnd
//
// opencode has no ExitPlanMode tool; its plan agent is the structural twin of
// Claude's plan mode, so a finished plan-agent turn stands in for "a plan was
// approved". Build-mode-only sessions read the board but do not post. opencode's
// edit/write tools are the twins of Claude's Edit/Write; its multi-file `patch`
// tool is not mirrored (different arg shape), so edits made through it publish no
// contract. A session being deleted is the nearest thing opencode has to a session
// end, so it stands in for marker cleanup.
//
// FAIL OPEN: if the hook scripts can't be found, or any call errors, the plugin
// does nothing — it never blocks a prompt and never drops a turn.

type Json = Record<string, unknown>

export const HuddleOpencodePlugin: Plugin = async ({ $, directory }) => {
  // Locate the bash hooks. HUDDLE_ROOT (the huddle repo) is the reliable
  // contract; fall back to this file's repo layout (opencode/ next to hooks/),
  // which only works when the plugin is loaded from inside the repo unsymlinked.
  const resolveHooks = (): string | null => {
    const here = typeof import.meta.dir === "string" ? import.meta.dir : ""
    const candidates = [
      process.env.HUDDLE_ROOT ? join(process.env.HUDDLE_ROOT, "hooks") : "",
      here ? join(here, "..", "hooks") : "",
      here ? join(here, "hooks") : "",
    ].filter(Boolean)
    for (const d of candidates) {
      if (existsSync(join(d, "huddle-write-plan.sh"))) return d
    }
    return null
  }

  const hooks = resolveHooks()
  if (!hooks) {
    console.warn(
      "[huddle] hook scripts not found — set HUDDLE_ROOT to the huddle repo. Plugin disabled.",
    )
    return {}
  }

  // Run one bash hook, feeding `payload` as JSON on stdin (the same shape the
  // Claude Code hooks receive). Returns trimmed stdout; "" on any error. stdin
  // is a Blob: Bun's shell has no writable `.stdin`, but `< ${Blob}` works.
  const run = async (script: string, payload: Json): Promise<string> => {
    try {
      const stdin = new Blob([JSON.stringify(payload)])
      const res = await $`bash ${join(hooks, script)} < ${stdin}`.quiet().nothrow()
      return res.stdout.toString().trim()
    } catch {
      return ""
    }
  }

  const started = new Set<string>() //                sessions that got the full board
  const pending = new Map<string, string>() //        sessionID -> board text to inject this turn

  // Publish-side state, rebuilt from the event stream.
  const mode = new Map<string, string>() //           sessionID -> latest assistant agent/mode
  const cwd = new Map<string, string>() //            sessionID -> latest assistant cwd
  const curMsg = new Map<string, string>() //         sessionID -> latest assistant messageID
  const partText = new Map<string, Map<string, string>>() // messageID -> partID -> text
  const lastPub = new Map<string, string>() //        sessionID -> last published body (dedup)

  return {
    // READ (decide): first prompt of a session pulls the full board and sets the
    // per-session "seen" baseline; every prompt after pulls only sibling entries
    // newer than that baseline. Same incremental scheme as the Claude hooks,
    // collapsed into opencode's per-prompt path.
    "chat.message": async (input) => {
      const sid = input.sessionID
      const script = started.has(sid) ? "huddle-read-new.sh" : "huddle-read.sh"
      started.add(sid)
      const out = await run(script, { cwd: directory, session_id: sid })
      if (out) pending.set(sid, out)
      else pending.delete(sid)
    },

    // READ (inject): push the stashed board as system context, not a user part,
    // so it reads as injected guidance — the opencode twin of Claude's injected
    // hook stdout. chat.message can't reach the system prompt, so they hand off.
    "experimental.chat.system.transform": async (input, output) => {
      if (!input.sessionID) return
      const out = pending.get(input.sessionID)
      if (!out) return
      pending.delete(input.sessionID)
      output.system.push(out)
    },

    // PUBLISH (contract): opencode's edit/write tools are the twins of Claude's
    // Edit/Write. After one runs, hand the path to the activity hook — it records
    // a touch and, when the path is a shared surface, publishes (and supersedes)
    // a contract entry. Same per-edit cadence as the Claude PostToolUse hook.
    "tool.execute.after": async (input) => {
      const tool_name = input.tool === "edit" ? "Edit" : input.tool === "write" ? "Write" : ""
      if (!tool_name) return
      const fp = (input.args as Json | undefined)?.filePath
      if (typeof fp !== "string" || !fp) return
      await run("huddle-write-activity.sh", {
        cwd: cwd.get(input.sessionID) ?? directory,
        tool_name,
        tool_input: { file_path: fp },
      })
    },

    // PUBLISH: track the assistant agent + text from the event stream, and when
    // a plan-agent turn goes idle, publish its plan to the room.
    event: async ({ event }) => {
      const e = event as { type: string; properties?: any }

      if (e.type === "message.updated") {
        const info = e.properties?.info
        if (info?.role === "assistant") {
          const sid: string = info.sessionID
          mode.set(sid, info.mode ?? "")
          if (info.path?.cwd) cwd.set(sid, info.path.cwd)
          const prev = curMsg.get(sid)
          if (prev && prev !== info.id) partText.delete(prev) // bound memory to ~1 msg/session
          curMsg.set(sid, info.id)
        }
        return
      }

      if (e.type === "message.part.updated") {
        const part = e.properties?.part
        if (part?.type === "text" && typeof part.text === "string") {
          let m = partText.get(part.messageID)
          if (!m) {
            m = new Map()
            partText.set(part.messageID, m)
          }
          m.set(part.id, part.text)
        }
        return
      }

      if (e.type === "session.idle") {
        const sid: string | undefined = e.properties?.sessionID
        if (!sid || mode.get(sid) !== "plan") return // post only on a finished plan turn
        const msg = curMsg.get(sid)
        const m = msg ? partText.get(msg) : undefined
        const plan = m ? [...m.values()].join("\n").trim() : ""
        if (!plan || lastPub.get(sid) === plan) return // nothing new to post
        lastPub.set(sid, plan)
        if (msg) partText.delete(msg)
        await run("huddle-write-plan.sh", {
          cwd: cwd.get(sid) ?? directory,
          tool_name: "ExitPlanMode",
          tool_input: { plan },
        })
        return
      }

      // A compaction restarts from a summary; re-send the full board next turn.
      if (e.type === "session.compacted") {
        const sid: string | undefined = e.properties?.sessionID
        if (sid) started.delete(sid)
        return
      }

      // CLEANUP: a deleted session is opencode's nearest thing to a session end.
      // Drop its transient markers (and sweep orphans) the way Claude's SessionEnd
      // hook does, and release the per-session bookkeeping held here.
      if (e.type === "session.deleted") {
        const info = e.properties?.info
        const sid: string | undefined = info?.id
        if (!sid) return
        const dir = info?.directory ?? cwd.get(sid) ?? directory
        started.delete(sid)
        pending.delete(sid)
        mode.delete(sid)
        const msg = curMsg.get(sid)
        if (msg) partText.delete(msg)
        curMsg.delete(sid)
        lastPub.delete(sid)
        cwd.delete(sid)
        await run("huddle-end.sh", { cwd: dir, session_id: sid })
      }
    },
  }
}

export default HuddleOpencodePlugin
