---
name: longrun
description: "A project that keeps its own state on disk, maintained by Claude Code and Codex sessions: notes every session sees and prunes, who else is working and what they changed, work handed to the session with the context, waiting that costs no tokens, one session driving the rest. Use in any session over an hour, with several sessions on one project, when re-trying something already tried, or on \"запиши\", \"что мы уже пробовали\", \"статус сессий\", \"передай другой сессии\", \"раздай задачи\", \"настрой longrun\"."
argument-hint: "status | notes | add | doc | recall TERM | send WHO | watch | board | onboard | help"
allowed-tools: Bash(longrun:*)
---

# longrun

Current state (live, produced when the skill loads):

!`longrun where 2>&1 || true`

!`longrun digest --source skill 2>&1 || true`

`$ARGUMENTS` names a subcommand -> run `longrun <it>` and act on what it prints; nothing -> apply the protocol.

Read [references/protocol.md](references/protocol.md) and apply it. This entrypoint is for Claude Code; Codex uses the separately installed `SKILL.codex.md` entrypoint with the same protocol.
