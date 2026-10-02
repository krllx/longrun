---
name: longrun
description: Keep project notes, dead ends, decisions, session state, messages and a shared task board on disk across long ZCode sessions and alongside Claude Code or Codex. Use for work spanning context compactions or several conversations, when recalling previous attempts, or when the user asks to record findings, inspect session status or set up longrun.
---

# longrun

Use the `session_id` and CLI command prefix supplied by the longrun ZCode hook for this conversation. Run that prefix with `where`, then `digest --source skill`, in the target project. The prefix sets `LONGRUN_CLIENT=zcode`, `LONGRUN_SESSION`, and the shared store path explicitly; apply it to every protocol command. Hook subprocess variables do not automatically propagate into your shell. Do not use another chat's ID, the newest heartbeat or a Codex/Claude environment variable as this chat's identity.

If hooks are disabled or no ID was supplied, use `LONGRUN_CLIENT=zcode` with this skill's `scripts/longrun` by absolute path. Shared notes and the board work without an ID; session-bound commands require this conversation's actual ID. Do not invent one. If the project is not initialized, create it when requested or needed for long work.

Read [references/protocol.md](references/protocol.md) and apply it. Read [references/zcode.md](references/zcode.md) for installation, hook behavior and limitations. If the user supplied a subcommand after `$longrun`, run that command and act on its output; otherwise apply the protocol.

Hooks inject context on session start, user prompts and tool calls. Record findings as they happen. If hooks are unavailable, run `digest --source manual` at the start of a turn, after compaction and before relying on shared state. Manual operation cannot track every tool call or enforce HALT across tools: honor the HALT instruction yourself.

Queued messages arrive on the next hook or digest. ZCode targets do not support `send --resume` or watch `--wake`. A `SessionStart` with source `compact` restores notes; there is no supported pre-compaction snapshot, summary archive or context-size warning. Transcripts supplied by ZCode are temporary and are not retained or searched.

If an optional MCP server is configured, use `run` with an `args` array, this conversation's explicit `session_id` and absolute project `cwd` on every call. Do not change sandbox or approval settings to make commands work.

longrun does not grant permission to create goals or chats, delegate, send messages, wake another session, interrupt work or change approval settings. Follow the user's authorization and the host's controls.
