# Verified facts (2026-09-04), Claude Code CLI 2.1.238 + desktop 2.1.260

Source of each fact: E = empirical (hook payload captured on `claude -p`, files in hook-payloads/),
D = official docs (docs/*.md, raw markdown from code.claude.com), B = strings in the binary.

## Hooks that matter for longrun
- SessionStart: input {session_id, transcript_path, cwd, hook_event_name, source: startup|resume|clear|compact|fork, model?}. Plain stdout is added to context (E, D). Fires after EVERY compaction with source=compact and its stdout lands in the compacted context (E: transcript shows hook_success attachment "SessionStart:compact"; D: context-window.md "What survives compaction"). CLAUDE_ENV_FILE is set only here (+Setup/CwdChanged/FileChanged); `export X=..` appended there reaches later Bash calls (E: env=envfile-works-77).
- UserPromptSubmit: input {..., prompt}. Plain stdout added to context as a system reminder, no visible transcript entry (E, D). Timeout default 30s (D).
- PreCompact: input {..., trigger: manual|auto, custom_instructions: string|null}. Can block (exit 2 / decision:block). Cannot modify the summary or pass instructions to the summarizer (D: no such field). systemMessage/continue discarded (D).
- PostCompact: input {..., trigger, compact_summary: <full summary text>} (E: 3173 chars in test; real sessions 20-26K chars = 5-6.5K tokens). No decision control (D). Compaction itself runs as a subagent: a SubagentStop with agent_type "" and last_assistant_message = summary fires right before PostCompact (E).
- Stop: input {..., stop_hook_active, last_assistant_message, background_tasks, session_crons}. `{"decision":"block","reason":..}` keeps Claude going; second Stop has stop_hook_active=true; 8-consecutive-continuation cap (E, D). `hookSpecificOutput.additionalContext` on Stop = softer variant (D).
- SessionEnd: input {..., reason: clear|resume|logout|prompt_input_exit|other}. All SessionEnd hooks share a 1.5 s budget (raised to per-hook timeout, max 60 s) (D). Must be fast.
- SubagentStart/SubagentStop: {agent_id, agent_type, agent_transcript_path, last_assistant_message} (E). longrun no longer registers a SubagentStop hook: the only thing it produced was a journal line, and half its body was a filter for the compaction summariser.
- **Event order around a compaction is SubagentStop -> SessionStart(compact) -> PostCompact** (E: payload timestamps 1788545687100980000 / ...128840000 / ...142533000, 14 us apart). SessionStart therefore runs *before* the current summary is written, so nothing injected there can name the file it lands in.
- Hook output strings (stdout, additionalContext) capped at 10,000 characters; overflow saved to file + preview (D hooks.md:913).
- CLAUDE_SESSION_ID is NOT in the hook env (E: empty); session_id comes on stdin. CLAUDE_PROJECT_DIR is set (E).
- Hooks added to settings.json are picked up by already-running sessions without a restart (E 2026-09-05, desktop 2.1.260: a freshly installed PostToolUse hook fired in a session started before the install). Docs never promise this; a `ConfigChange` event with matcher `user_settings` exists (D). A running session does not get a fresh SessionStart injection until its next SessionStart.
- `async: true` hooks: output discarded, no additionalContext (D). Fine for archiving, wrong for injection.
- Skill frontmatter `hooks:` registers hooks for the rest of the session once the skill is invoked; `once: true` honored only there (D).

## Compaction facts
- Transcript JSONL (undocumented, "internal, changes between versions" D sessions.md): entries `system/subtype=compact_boundary` with compactMetadata{trigger, preTokens, preservedSegment}, `user` with isCompactSummary=true, attachments `compact_file_reference` (files re-read after compaction) (E on user's real transcripts).
- After compaction Claude Code re-injects from disk: root CLAUDE.md + unscoped rules, auto memory MEMORY.md, plan file, up to 5 recently read/edited files (each <5,000 tokens, else path only), invoked skill bodies (5,000 tok/skill, 25,000 total), SessionStart(compact) hook output. Context added by hooks EARLIER is summarized away (D context-window.md).
- Real summaries in the user's sessions: 20-26K chars, sections "Primary Request", "Key Technical Concepts", "Files", "Errors and fixes", "Problem Solving", "All user messages", "Pending Tasks", "Current Work", "Next Step" (E).
- /compact <text> passes text as custom_instructions (E). /compact works in `claude -p --resume <id> "/compact ..."` (E, num_turns 0).
- `--autocompact <auto|tokens>` flag, `/autocompact 500k`, env CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, CLAUDE_CODE_AUTO_COMPACT_WINDOW, DISABLE_AUTO_COMPACT exist in binary (B); only /autocompact + --autocompact documented (D).

## Auto memory: location
- ~/.claude/projects/<project>/memory/MEMORY.md; per git repo root (shared across worktrees); outside git: project root = cwd. Re-injected after compaction. Disable: autoMemoryEnabled=false or CLAUDE_CODE_DISABLE_AUTO_MEMORY=1. autoMemoryDirectory setting exists.
- Arc worktrees are not git: each worktree cwd = separate <project> slug.

## Sessions / orchestration (D)
- `claude -p --resume <id>`, `--session-id <uuid>`, `--fork-session`, `--name`, `--bg` (background session under supervisor; not with -p), `claude agents --json` (fields cwd, kind, startedAt, id, state working|blocked|done|failed|stopped, pid, status, waitingFor, sessionId, name), `claude logs|stop|respawn|rm <id>`.
- Cross-session messaging: ListAgents/SendMessage over per-session unix socket (/tmp/cc-socks*/, env CLAUDE_CODE_MESSAGING_SOCKET + CLAUDE_CODE_MESSAGING_TOKEN exported to hooks and Bash); `-p` workers receive only with settings crossSessionInbound=accept; `notify_when_idle` gives one notice when a session goes idle; delivered between tool calls or as a new turn when idle; a message cannot approve permissions or change config; inbox holds 100 msgs.
- Agent teams: experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1), interactive only, no resume of in-process teammates, one team per session.
- In-session scheduling tools present in this build: CronCreate (session-only or durable .claude/scheduled_tasks.json, 7-day expiry), ScheduleWakeup (/loop dynamic), desktop scheduled tasks (~/.claude/scheduled-tasks/<id>/SKILL.md).

## Skills (D docs-skills.md, snapshot taken 2026-09-06)
- Frontmatter: name, description (+when_to_use; combined cap 1,536 chars), argument-hint, disable-model-invocation, user-invocable, allowed-tools, model, effort, context: fork, agent, background, hooks, paths, shell. Substitutions: $ARGUMENTS, $N, ${CLAUDE_SESSION_ID}, ${CLAUDE_SKILL_DIR}, ${CLAUDE_PROJECT_DIR}. Dynamic context: !`command` lines run before the body is sent. Body loads only on invocation; description always in context (unless disable-model-invocation).
- `allowed-tools` **pre-approves, it does not restrict**: "It does not restrict which tools are available: every tool remains callable" (D skills.md). The grant lasts the invoking turn only.
- **An injected !`command` that is not pre-approved aborts the whole skill invocation**: "Injected commands never prompt for permission. When a command's permission check returns anything other than allow, Claude Code aborts the invocation... A matching ask or deny rule still aborts the invocation regardless of allowed-tools" (D skills.md:676-678). Bash permission rules are matched per subcommand, so `foo | head` and `foo || echo` need `head` and `echo` allowed too - which is why longrun's own !`lines` are single `longrun ...` commands with no pipes or fallbacks.

## Auto memory (D docs-memory.md, snapshot taken 2026-09-06)
- Loaded every session: first 200 lines of `MEMORY.md` or the first 25KB, whichever comes first (D memory.md:30,401). Toggle `autoMemoryEnabled` in user or project settings (D memory.md:357).
- Same lifetime as the project, no budget, no pruning policy, no notion of "this task". longrun deliberately overlaps: SKILL.md tells the model which store a given fact belongs in.

## Verified during the 2026-09-06 review (E unless noted)
- Hook input `cwd` is the Bash tool's persisted working directory, not the session root: after `cd` in one Bash call, later PostToolUse hooks of the same session reported the new directory. longrun therefore binds every hook to the store recorded at SessionStart (`~/.claude/longrun/sessions/_index/<sid>.json`) instead of resolving by cwd.
- PostToolUseFailure fires for a Bash command with a non-zero exit (desktop 2.1.260); `error` starts with `Exit code N` followed by the command output (D hooks.md:2067 says to key on that first line only).
- `claude agents --json` lists interactive sessions too (`kind: "interactive"`, fields pid/cwd/startedAt/sessionId/name), not only `--bg` ones (D agent-view.md:661: "every live session, plus background sessions").
- PostCompact `compact_summary` is a superset of what the transcript stores as the isCompactSummary entry: it also carries the summariser's `<analysis>` block (29K vs 19K chars in a real session). That block never enters the context, so archive/compact/ holds text that exists nowhere else.
- CLAUDE.md `@path` imports are re-injected after compaction together with CLAUDE.md (haiku, 5 turns, `/compact`, all tools disallowed: a fact that lived only in the imported file was answered correctly). Plain re-injection of a notes file needs no hook at all; the hooks earn their keep with the summary archive, the FAIL journal, HANDOFF and the heartbeats.
- Subagent transcripts live in `~/.claude/projects/<slug>/<session-id>/subagents/agent-*.jsonl`; the transcript JSONL stores Cyrillic raw (no \u escapes), so a raw-line prefilter works for Russian terms.
- `/compact` in `claude -p --resume` answers "Not enough messages to compact." on a 1-turn session; 5 short turns were enough.

## Cross-session messaging, verified 2026-09-06 (E)
- Registration: every session writes `~/.claude/sessions/<pid>.json` (sessionId, cwd, name, version, kind, `messagingSocketPath`); inbox sockets live in `/tmp/cc-socks/<pid>.sock`. `ListAgents` lists only sessions with a bound socket.
- Wire format for a script (from strings in the binary, works): connect to the socket and send one JSON line `{"type":"user","message":{"role":"user","content":"<text>"}}`, optionally preceded by `{"type":"auth","token":"<CLAUDE_CODE_MESSAGING_TOKEN>"}`. No reply comes back on the connection.
- A `-p` session binds a socket on the desktop binary 2.1.260 (`~/Library/Application Support/Claude/claude-code/2.1.260/claude.app/Contents/MacOS/claude`) but NOT on CLI 2.1.238 (registration lacks `messagingSocketPath`, so it is unreachable). A raw post reached a busy `-p` receiver between tool calls (after its `sleep`) and it acted on the text verbatim.
- An idle `claude --bg` session (2.1.260, `--settings '{"crossSessionInbound":"accept"}'`) received a raw-socket post as a new turn and acted on it. Launched from a desktop session's Bash, `--bg` needs `env -u CLAUDE_CODE_ENTRYPOINT`, otherwise it sits at an empty prompt in state `blocked`; a new directory also stops it on the trust dialog, so start it in an already trusted one.
- In `-p` mode the model has `SendMessage` but not `ListAgents`, and `SendMessage` by name found no peer (2.1.238). A desktop (Code tab) session has `ListAgents` but no `SendMessage` tool; the app offers `ccd_session_mgmt.send_message(session_id, message)` instead, which lands as a user turn "From <title>" in another app session (not tested on a real session).
- An exited session has no socket and is not listed. `claude -p "<instruction>" --resume <sid>` runs the instruction as a new turn in that session (file written, turn present in the transcript afterwards). The prompt must come right after `-p`; trailing positional prompts are ignored.
- Full peer envelope as `SendMessage` builds it (2.1.260 binary, verified by sending it): `{"msgV":1,"msg_id":"<uuid>","type":"user","message":{"role":"user","content":"<body>"},"priority":"next","from":"uds:<percent-encoded sender socket path>"}`. `priority:"next"` is what makes an idle session start a turn: the same message without it never reached an idle desktop session. `<body>` may be wrapped as `<cross-session-message from="uds:..." from-session="<sid>" from-name="<name>" from-mode="prompting|bypass">\n<text>\n</cross-session-message>` (attribute order fixed); the receiver strips the wrapper, shows `Message from @<from-name>`, and uses from-mode for permission-class parity. The model sees the text framed as "Another Claude session sent a message: ... not typed by your user"; the transcript entry has `origin: {kind: "peer", from, verifiedPeerPid, msg_id}`.
- `longrun send` to a real idle desktop-app session (2.1.260) started a new turn there and got an answer; the app-native `ccd_session_mgmt.send_message` also woke a session the app listed as not running.

