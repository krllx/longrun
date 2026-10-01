---
name: longrun
description: Keep project notes, dead ends, decisions, session state, messages and a shared task board on disk across long Codex or Claude Code sessions. Use for work spanning context compactions or several conversations, when recalling previous attempts, or when the user asks to record findings, inspect session status, hand off authorized work or set up longrun.
metadata:
  short-description: Persistent project notes and session coordination
---

# longrun

When loading this skill, get this conversation's `CODEX_THREAD_ID` from the shell environment if it is not already known. Use the MCP `run` tool with `args: ["where"]` and then `["digest", "--source", "skill"]`, passing that `session_id` and the target project's absolute `cwd` on every call. This keeps session writes outside the workspace sandbox in the installed MCP integration. If the project is not initialized, the digest explains setup; create it when requested or needed for long work.

All `longrun ...` examples in the protocol are argv for MCP `run` as well: `longrun add -t fact "text"` becomes `args: ["add", "-t", "fact", "text"]`. If MCP is unavailable and the shell permits the session-store writes, use the CLI. If `longrun` is missing from PATH, use this installed skill's `scripts/longrun` by absolute path. A sandbox refusal is a reason to use or register the MCP integration; do not change sandbox settings to make notes work.

Read [references/protocol.md](references/protocol.md) and apply it. For Codex behavior and setup, read [references/codex.md](references/codex.md).

If the user supplied a subcommand after `$longrun`, run the corresponding `longrun` command and act on its output. Otherwise apply the protocol.

Use the `CODEX_THREAD_ID` provided to shell tools as this conversation's identity. For MCP `ask` or `notify`, pass `session_id` and `cwd` explicitly when the call needs session context, because Codex may share an MCP process across conversations. Prefer the CLI when those values are unavailable.

Hooks supply updates on startup, resume, compaction and tool calls after the user trusts them in `/hooks`. If hooks are disabled or unavailable, run `longrun digest --source manual` at the start of a turn and after compaction, and before relying on shared state. Refresh before reading messages; record findings as they happen. Manual operation cannot track every tool call or enforce HALT across tools: honor the HALT instruction yourself.

longrun does not grant permission to create goals or chats, delegate, send messages, wake another session, interrupt work or change sandbox/approval settings. Follow the user's authorization and the host's controls.
