English | [Русский](ORCHESTRATOR.ru.md)

# Orchestrator: the session that coordinates the others and calls the human

Status: design from 2026-09-08, stages 1 and 3 implemented 2026-09-09 (version 0.4.0, section 11),
cut back to its present size in 0.6.0 (section 0 below). Built on the verified facts in section 7;
anything unverified is marked explicitly.

## 0. 0.6.0: what was removed, and why

The layer was sold as "autonomous driving toward a goal". It is not that, and it does not need to be:
driving **one** session toward a condition an evaluator can check is what Claude Code's own `/goal`
does, with a real evaluator, which this has never had. What is left is what nothing else does -
several windows, a board between them, and a dialog that reaches the human on top of whatever they are
looking at.

- **`budget`** (the 5-hour usage rule, section 6) is gone. It halted every session on this machine from
  an undocumented endpoint and the OAuth token out of the login keychain: a version change breaks it, a
  first tick greets the user with a Keychain dialog, and Claude Code enforces its own window anyway.
  `longrun halt` stays for "stop everyone", which was the pain worth solving.
- **`interrupt`** is gone. It killed another session's processes by walking the process tree, was never
  verified inside the desktop app, and the human has Esc and Stop in that window. The orchestrator now
  names the stuck window instead of offering to kill it.
- **`fact`** is no longer a command: a fact is an item of the same `board.json` as a task, so it is
  `longrun board add --fact "..."`, `board ls --facts`, `board ack F3 "decision"`.
- **The watcher keeps two rules of five**: a tool running past `stuck_tool_min`, and an unanswered
  permission prompt or dialog past `stuck_wait_min`. A turn over an hour is what a long normal turn
  looks like; three identical FAILs are what the turn card already puts in front of that session, with
  the command in it; a context near the window already reaches both the session and the orchestrator by
  other paths. All three are still SESSIONS flags - shown, not reported as a fault.
- **The duties block in the digest** is six lines. The rest moved into `longrun orchestrate help`,
  which is where a session that has taken the role is already looking.

Sections 6 and 12 below describe the budget rule as it was; they are kept as the record of why it
existed and what replaced it, not as documentation of anything that runs.

## 1. Why

Today a project has an HQ, shared notes and a session status, but the human still walks the
sessions himself: asks what is done, hands out items, notices stuck processes, keeps an eye on
context and on the usage limit. There is so much text that it does not fit in one head.

We want one session per project that:

1. keeps a short "done / doing / left" list within the goal;
2. hands tasks to sessions, starts new ones (or asks the human to) and collects reports;
3. notices snags: a tool has been spinning too long, a run is no longer needed, a session is
   going in circles, is waiting for a confirmation nobody sees;
4. keeps the sessions' context below a threshold and orders a compaction with notes saved;
5. tracks spending of the 5-hour window: if we burn one and a half times faster than the plan,
   stops everything and reports;
6. brings clarifications, doubts and decisions to the human through a dialog in front of every
   window (bypassing "do not disturb"), instead of waiting for him to look into the chat;
7. accepts new facts from outside (a review comment, a messenger message, the human's words)
   even mid-work, records them and decides with them in mind from then on.

## 2. Entities

| Entity | What it is | Where it lives |
| --- | --- | --- |
| Orchestrator | an ordinary project session that took the role; one per project | lock `.longrun/orchestrator.json` (session, pid, since when, goal) |
| Worker | any other project session; learns nothing new except `board take/done/block` | as today |
| Board | goal + tasks with statuses todo / doing (who, since when) / blocked (why) / done (result) / dropped | `.longrun/board.json`, rendered into every session's digest |
| Watcher | the timer tick `longrun watch`, already exists; gets rules about snags and budget | as today |
| Asker | MCP server `longrun-ask`: a dialog in front of every window, the answer arrives in the session as a turn | new, separate binary |

The lock is taken with `longrun orchestrate start --goal "..."`; a second session is refused with
the holder's name. The lock expires when the session has ended (SessionEnd) or the pid is dead, then
`start` in another session takes it over. The workers' digest shows the line
`ORCHESTRATOR: <name> alive since ...`, so everyone knows whom to report to.

## 3. What the orchestrator sees: telemetry without tokens

All signals are collected by hooks and the watcher into the session's `meta.json`; the orchestrator
reads them through `longrun status` and its own digest. The worker's model is not involved.

| Signal | Source | How it is computed |
| --- | --- | --- |
| Context, % | transcript: `usage` of the last assistant message | `input + cache_read + cache_creation` divided by the model window (1M for Fable, Sonnet 5, Opus 5; 200k for 4.6); written by the Stop/PostToolUse hook |
| Turn running for N minutes | UserPromptSubmit sets `turn_started`, Stop clears it | age of the mark |
| Tool spinning for N minutes | new PreToolUse hook writes `tool_started` + the command, PostToolUse clears it; plus the process tree: children of the session pid (the pid is in `~/.claude/sessions/<pid>.json`) | age of the mark, `etime` of the child |
| Waiting for confirmation N minutes | hooks `PermissionRequest` and `Notification(permission_prompt)` | not verified that they fire in the app (see section 7) |
| Idle with a task in doing | Stop without a new prompt for longer than N minutes while a task is in doing | by `last_seen` |
| Going in circles | journal: FAIL with the same command 3 times in a row | by the journal |
| Board movement | events `take / done / block` | written by the CLI |
| 5-hour window spending | section 6 | watcher |

In the orchestrator's SESSIONS block it looks like this:

```
PR D [dd4a4da6] alive, task T7 doing 2h10m, ctx 41%, tool `ya make ...` 38m, fail x3 same cmd
PR H [dda66bb1] stale 3h, task T9 doing, ctx 12%
Payments testing [8a7610a4] alive, waiting permission 12m
```

The orchestrator does not read the workers' transcripts: that bloats its context. To dig into one
case there is the app's `list_events`, on demand.

## 4. What the orchestrator can do: levers

| Lever | Mechanism | State |
| --- | --- | --- |
| Write to a worker | `longrun send`: to a live session via the socket (a turn starts immediately), to the rest via inbox (read on the next event, costs no tokens) | exists |
| Assign a task | `longrun board assign T7 <session>`: the worker sees `YOUR TASK` in its digest on the next event | new |
| Ask the human | the asker's `ask` tool: a dialog in front of the windows, the answer arrives as a turn | new, section 5 |
| Start a session | in the desktop app the `spawn_task` chip: the orchestrator leaves a button with a self-contained prompt and the human's click opens the session (the click is the confirmation); in the terminal a dialog or the chat with a ready first line `longrun take T7`; `claude --bg "..."` for self-contained unattended tasks (documented: supervisor, `claude agents --json` with `state` and `waitingFor`) | exists in Claude Code |
| Stop everyone | `longrun halt "reason"`: the PreToolUse hook forbids any tool in every session of the account, the model sees the reason; `longrun resume` lifts it | new, documented `permissionDecision: deny` |
| Interrupt a tool | kill the tool's child process of the session; the worker gets "interrupted by the orchestrator: reason" through PostToolUseFailure | new, only with the human's confirmation, not verified in the app |
| Order a compaction | not possible directly: a slash command in a cross-session message arrives as text and is not executed (documented). The threshold is held by the auto-compaction window: `/autocompact 300k` is saved in `autoCompactWindow` and applies to all sessions; longrun's PreCompact/PostCompact hooks take a snapshot and return the digest. The orchestrator asks the worker in advance to write its notes, and offers the human a compaction with a custom prompt as one button in the dialog | exists, the human sets the threshold |

## 5. Flows

The orchestrator is event-driven, not polling: it wakes up when something has happened and sleeps
for free the rest of the time.

**Start.** `longrun orchestrate start --goal "..."` takes the lock, writes the goal, optionally seeds
the board from a list. The orchestrator's digest: GOAL + BOARD + SESSIONS with flags + INBOX,
without long notes.

**Assignment.** The orchestrator picks the next todo, assigns it, the worker sees the task on its
next event, takes it with `board take T7`, works, closes it with `board done T7 "result"`.
The worker's Stop hook sends an event to the orchestrator. An event that needs a decision (done,
blocked, question) wakes the orchestrator through the socket; the rest lands in the inbox.

**A task and nobody to give it to.** The orchestrator does not open sessions on its own. In the
desktop app it leaves a `spawn_task` chip: the title is the task, the prompt is self-contained (what
to do and why, the first line `longrun board take T7`, and `longrun link <project root>` in case the
app opens the session in a fresh worktree, where `longrun where` says not initialised). Nothing runs
until the human clicks the chip, so no dialog precedes it; the orchestrator names the chips it left
in its reply. In the terminal there is no chip: a dialog or the chat with the first line to paste.

**Snag.** Every 5 minutes the watcher computes the flags from section 3. A rule fired
(a tool longer than 30 minutes, a turn longer than an hour, three identical FAILs, waiting for
confirmation longer than 10 minutes) -> a message to the orchestrator with a wake-up. The
orchestrator decides: write to the worker, ask the human, offer to interrupt.

**Question to the human.** The worker sets `board block T7 "question"`. The orchestrator either
answers itself from the shared notes or calls `ask`. The answer arrives as a turn, the orchestrator
forwards it to the worker via `send` and lifts the block.

**Stop on budget.** The watcher sees overspending (section 6) -> `longrun halt` -> a dialog to the
human with a report: how much was spent, who made how many turns in the last hour, what is in doing
right now. The human lifts it with `longrun resume` or from the dialog.

**The orchestrator's context.** It reads compact state files, not transcripts, so it grows slowly.
The auto-compaction window and the longrun hooks serve it the same way as the workers.

The asker (implemented, section 13): `longrun ask` and the `ask` tool of the `longrun mcp` MCP server show a dialog through
`osascript` from their own process (`display dialog` / `choose from list`, brings itself to the front, sound; Focus cuts
notifications, not windows). The asking party waits for the answer up to `ask_wait_sec` (90 s) and gets it right away; later the answer arrives as a turn
into the session's socket (or into the inbox), the dialog is held by a detached process. The `notify(text)` tool is for messages without an answer.

## 5a. Facts from outside: delivery and recording

Delivery, both channels verified 2026-09-08:

- the human writes straight into the orchestrator's chat, even while it is working: the message
  is queued and reaches the model between tool calls (in the transcript it is the
  `queued_command` attachment), not after the end of the turn;
- any session, script or the watcher sends `longrun send` into the socket: a busy orchestrator
  receives it between tool calls (verified by sending to itself mid-turn), a sleeping one
  starts a turn.

Recording, so that the decision does not depend on the model's memory: the command
`longrun fact "text" [--task T7] [--source review|msngr|user|watch]`:

1. writes a record of kind fact into `board.json` (source, time, task, handled=false) and a
   line into the journal;
2. if a task is given, its worker will see `NEW FACT for T7` in its digest on the next
   event;
3. wakes the orchestrator (socket if alive; otherwise inbox).

The orchestrator's digest shows `FACTS unhandled` on every wake-up until the orchestrator
disposes of it: `longrun fact ack <id> "what was decided"` (forwarded to the worker, changed the
board, asked the human, or "accepted, no action"). An unhandled fact does not drop out of sight.
Long-lived facts the orchestrator moves into the shared notes (`add --shared -t fact`),
the rest are archived N days after ack.

A fact thrown into the chat in words, without a command, the orchestrator by the role's protocol
first records through `longrun fact --source user` and only then decides. The digest reminds of this
with the counter of unhandled facts.

Automatic sources are watcher rules (zero tokens while waiting):

- `msngr <chat_id>`: `msngr-mcp cli read-new --chat-id ...` (a corporate messenger) returns only what arrived since the
  previous call, the cursor is local; new -> `longrun fact --source msngr`;
- `pr-comments <id>`: `arc pr` has no command for comments, it needs the Arcanum REST with an
  OAuth token (not verified) or a check from the worker's session through the devtools MCP;
- `pr-status` and `pr-merged` already exist, their firing also goes through `fact`.

The watcher does not decide whether a fact matters: it records and wakes. To avoid waking on every
chat message, a rule has `--wake-on <regex>`: without a match the fact lands in the inbox and waits
for the next wake-up.

## 6. The 5-hour window budget (REMOVED in 0.6.0, see section 0)

Off by default (`budget_on: false`; `longrun budget on` turns it on, and `orchestrate start`
offers it when several sessions start sharing one window). Policy: plan `pace` percent per hour
(default 20 = the whole window in 5 hours), tolerance `factor` (1.5). On every tick the watcher compares `used%` with `hours_elapsed * pace`;
exceeding it by `factor` times after the first 30 minutes of the window -> `halt` + dialog + report.
Spending is counted per account, not per project, so this is a global watcher rule, not a
property of the orchestrator.

Where to take `used%` from, in decreasing order of reliability:

1. `rate_limits.five_hour.used_percentage` and `resets_at` from the status line JSON.
   Documented, but the status line lives in the terminal UI, while the app launches the CLI
   as `--output-format stream-json --input-format stream-json`, without a TUI. Most likely the
   statusLine command is not executed in the app; verify once with a logger script.
2. The endpoint `https://api.anthropic.com/api/oauth/usage` with the token from Keychain
   (`Claude Code-credentials`, field `claudeAiOauth.accessToken`, header
   `anthropic-beta: oauth-2025-04-20`). Not documented, but verified 2026-09-09: it returns
   `five_hour` and `seven_day`, each with `utilization` (percent, a decimal number) and `resets_at`
   (ISO-8601 with a zone). This is the source in the implementation: the watcher reads the token via
   `/usr/bin/security` after a one-time "Always Allow" in the Keychain dialog, polls every 5 minutes,
   the token is not written anywhere.
3. An estimate from the transcripts of all sessions: the sum of new input, cache-creation and output
   tokens over the window. The unit does not match the limit's percent, but the "one and a half
   times faster than the plan" pace is visible from it; calibrated against `/usage` readings.

Claude Code's built-in behaviour on exhaustion (`autoContinueAtUsageLimit`, the
`quota_auto_resume_*` notifications) works only after hitting the limit and does not solve the
"stop in advance" task.

## 7. Verified and unverified

Verified (documentation or live on this machine, 2026-09-08):

- a slash command in another session's message is not executed, it arrives as text; a message
  cannot confirm anything and cannot change settings;
- the app launches the CLI in stream-json mode with `--permission-prompt-tool stdio`;
- the transcript stores `usage` of every reply, context is computed exactly; this session after
  compaction is at 99k tokens with a 1M window on Fable;
- the process tree: the Bash tool is a child process of the session's `claude`, the session pid is
  in `~/.claude/sessions/<pid>.json` and in `claude agents --json`;
- PreToolUse can do `permissionDecision: deny` with a reason the model sees;
  UserPromptSubmit can do `additionalContext`;
- the auto-compaction window: `/autocompact <tokens>` (saved in settings), the
  `--autocompact` flag, the `CLAUDE_CODE_AUTO_COMPACT_WINDOW` variable; by default compaction is at
  the edge of the model window;
- `claude --bg "prompt"`, `claude agents --json`, `claude attach|logs|stop|respawn`,
  state in `~/.claude/jobs/<id>/state.json`;
- notification types `permission_prompt` (after ~6 s of waiting), `idle_prompt` (60 s after
  the reply), `agent_needs_input`, `quota_auto_resume_*`; the `PermissionRequest` event;
- the usage endpoint returns data for the local token (the user's probe 2026-09-09: 5h 11%,
  week 42%; reading the Keychain from an agent session is blocked by the classifier, so the probe and
  the first `longrun budget check` are run by the human);
- a message into the socket of a busy app session reaches the model between tool calls
  (sending to itself mid-turn), the app's queue delivers it as the `queued_command`
  attachment the same way;
- `msngr-mcp cli read-new --chat-id` reads new messages from a chat from the terminal, without MCP.

Not verified:

- whether the `Notification` and `PermissionRequest` hooks fire in the app (in the terminal they do);
- whether the app runs the statusLine (checking via atime did not work: the volume does not update
  atime on read);
- whether killing the child process interrupts a tool cleanly in the app;
- the MCP tool timeout for a blocking dialog;
- `spawn_task` for projects without git (for example `shop`, an Obsidian vault folder, a project without git).

Endpoint probe, the token does not reach the output:

```bash
python3 -c 'import subprocess,json,urllib.request;t=json.loads(subprocess.run(["security","find-generic-password","-s","Claude Code-credentials","-w"],capture_output=True,text=True).stdout)["claudeAiOauth"]["accessToken"];r=urllib.request.urlopen(urllib.request.Request("https://api.anthropic.com/api/oauth/usage",headers={"Authorization":"Bearer "+t,"anthropic-beta":"oauth-2025-04-20"}),timeout=15);print(r.read().decode()[:800])'
```

## 8. What we do not do and why

- Claude Code agent teams: one team per session, the lead is fixed, teammates live inside the
  lead's process and do not survive resume, there is no project-level team. Not suitable for
  long-lived app sessions that live for days. Inside one worker, for a parallel subtask, it can
  be used.
- Timer polling (`/loop`, CronCreate) as the main loop: every wake-up costs tokens, and often
  there are no events between ticks. Only as a safety heartbeat every 30-60 minutes through
  `longrun watch`.
- The orchestrator reading the workers' transcripts: bloats its context.
- All questions to the human only through the orchestrator: decided otherwise, the dialog is available
  to any session. To avoid spam, a worker calls `ask` itself only when it cannot wait (an action by the
  human is needed right now: confirmation, access, a message to someone), while questions about the
  goal and priorities go onto the board through `block`, and the orchestrator collects them.

## 9. Stages

1. Only longrun, no new MCP: the board, the orchestrator role and lock, telemetry in SESSIONS
   (context, turn, tool, repeated FAILs), worker events to the orchestrator, `fact` and
   `fact ack`, `halt` and `resume`, the snag rule in the watcher, a recommendation on the
   auto-compaction window. Already gives items 1-4, 7 and half of 3.
2. The asker `longrun-ask` with a dialog and delivery of the answer as a turn. Gives item 6.
3. Budget: the `used%` source (after the endpoint probe), the pace policy, stop with a report.
   Gives item 5.
4. Optional: interrupting a tool with confirmation, unattended workers through
   `claude --bg`, checking the confirmation hooks in the app, automatic fact sources
   (`msngr`, `pr-comments`).

## 10. Decisions (2026-09-09)

| Question | Decision | Consequence in the design |
| --- | --- | --- |
| Context threshold | auto-compaction window 300k for all sessions, a warning 50k before it | the human runs `/autocompact 300k` once (saved in `autoCompactWindow`); the longrun hooks read the window from settings and from 250k ask the worker to write its notes, an event goes to the orchestrator |
| Budget pace | 20% per hour, tolerance 1.5 | default values in the watcher config; the rule stays silent for the first 30 minutes of the window |
| Dialog | `osascript` (macOS), `zenity` / `kdialog` (Linux) | `display dialog` and `choose from list`, activation through System Events, sound; nothing to install |
| Who shows dialogs | any project session | the `longrun-ask` server is registered in user scope; the answer is returned to the asking session through its socket, the server finds the session by the parent pid in `~/.claude/sessions/<pid>.json` |
| Where the orchestrator lives | the project's HQ folder | the lock in `.longrun/orchestrator.json` plus a mirror in `~/.claude/longrun/projects/<key>/`, because launchd under ~/Documents is unreliable (EPERM, see note n9) |
| Automatic sources | none for now; wake only by `--wake-on` | a `fact` from the watcher lands in the inbox, a wake-up only on a `--wake-on` match; msngr and pr-comments stay in stage 4 |
| Kill tool processes | not decided | by default the watcher only suggests, killing is with the human's confirmation |

What is needed from the human before stage 3: run the usage endpoint probe from section 7 and
send back the reply (the token does not get into it).

## 11. Implemented: stage 1 (2026-09-09, version 0.4.0)

Everything only in longrun, no new MCP:

- the board `.longrun/board.json`: `board goal|add|take|done|block|drop|release|edit|rm|assign`, dependencies `--after`, handing out with `--for`/`assign` with a message into the socket or inbox;
- facts: `fact "..." [--task] [--source] [--wake]`, `fact ls`, `fact ack`; unhandled ones hang in the orchestrator's digest, the task's worker sees `NEW FACT`;
- the role and lock: `orchestrate start|stop|status`, the `orchestrator.json` file in the project and a mirror in `~/.claude/longrun/projects/<key>/`; the orchestrator's digest gets `role=orchestrator`, the FACTS block and the list of duties;
- telemetry in `meta.json`: `running` (PreToolUse/PostToolUse), `turn_started` (UserPromptSubmit/Stop), `waiting_*` (PermissionRequest, Notification), `ctx_tokens/ctx_window` (tail of the transcript, the window from `autoCompactWindow`); flags in SESSIONS and in `longrun status`;
- a warning to the session `ctx_warn_before` (50k) before the window, once per 20k of growth, plus a message to the orchestrator;
- `halt`/`resume`: `~/.claude/longrun/halt.json`, PreToolUse replies `permissionDecision: deny`, the only exception is `longrun` itself;
- the watcher: `stuck_scan` on every tick, thresholds `stuck_tool_min` 30, `stuck_turn_min` 60, `stuck_wait_min` 10, `stuck_fail_streak` 3, cross-checked against the process tree, one report per episode, `wake_on_stuck` wakes by default;
- `interrupt <session> [--match] [--yes]`: the session's process tree by the pid from the registry, the shell-snapshot wrappers and their descendants, SIGTERM then SIGKILL, a journal entry for the target and a message to it; verified live on an app session 2026-09-09;
- new hooks PreToolUse, PermissionRequest, Notification (11 in total), the PostToolUse matcher extended to Agent/Task/Workflow/mcp__*;
- tests `tests/orchestrator.sh` (52 checks), the regression and scenario suites untouched.

What is needed from the human after installation: `./install.sh`, once `/autocompact 300k` in any session, `longrun orchestrate start --goal "..."` in the HQ session.

Not included (next stages): the dialog in front of the windows (`longrun-ask`), the 5-hour window budget (after the endpoint probe), automatic fact sources, checking the confirmation hooks in the app.

## 12. Implemented: stage 3, budget (2026-09-09, version 0.4.0; REMOVED in 0.6.0, see section 0)

- `budget_scan` on every watcher tick: a sample from the endpoint no more often than `budget_check_every` (300 s), the verdict `budget_verdict` (window start = `resets_at - 5h`, expected = `budget_pace_pct_per_hour` x hours, violation = used >= `budget_factor` x expected, the first `budget_quiet_min` minutes of the window without a verdict);
- on violation: `halt.json` with `kind: budget` (all projects), a report in `~/.claude/longrun/budget-report-<ts>.md` and into the socket/inbox of every orchestrator (used, elapsed, expected, until reset, week, live sessions with flags), a macOS notification, a line in the watcher's journal;
- `longrun resume` after a budget stop snoozes the rule until the window resets (`snoozed_until`), otherwise the next tick would stop everything again;
- `longrun budget [status|check|on|off|set pace|factor|quiet|every N]`: state, a manual sample, settings in the global config; status also shows the pace over the latest samples;
- in tests the source is substituted with `LONGRUN_BUDGET_FIXTURE=<file>`; 12 checks in `tests/orchestrator.sh`.

What is needed from the human: after installation the first watcher tick will ask for Keychain access on behalf of `security`, press "Always Allow"; or run `longrun budget check` once by hand from the terminal. To disable the rule: `longrun budget off`.

Not included: stage 2 (see section 13), stage 4.

## 13. Implemented: stage 2, the asker (2026-09-09, version 0.4.0)

No new binary: the dialog and the MCP server live in the same `longrun` script.

- `longrun ask "question" [--options "Yes,No"] [--default Yes] [--text] [--title T] [--wait SEC] [--expire MIN] [--icon note|caution|stop]`: a dialog through `osascript` from its own process (no Automation permission, brings itself to the front, verified 09.09.2026; sound `beep`; Focus cuts notifications, not windows). Up to three options - `display dialog` buttons, more - a `choose from list` list, `--text` adds an input field. The question is written into `<session>/asks.json` (`Q<n>`, state pending/answered/cancelled/expired/failed) and into the journal; the dialog is held by a detached process (`ask _wait`, setsid, output to `~/.claude/longrun/ask.log`).
- The answer: the asking party waits `ask_wait_sec` (90 s) and gets the line `ANSWER Q3: Yes; text: ...` right away. If it did not wait long enough - it prints `PENDING Q3`, drops claimed, and the answer arrives as a turn: into the session's socket (a turn starts even mid-turn), otherwise into the inbox, from where the next hook will hand it over. Esc or the Cancel button -> `CANCELLED`, `--expire` (360 min) elapsed -> `EXPIRED`, no osascript or fixture -> `FAILED`; in all three cases the text asks not to ask again but to decide on its own or set `board block`. An unanswered question in a project with an HQ lands in the ledger as an item on the user; the previous semantics of `ask` (ledger + report, no dialog) is kept behind the `--ledger` flag.
- `ask ls` and `ask answer Q3 "..."` (the dialog disappeared after a reboot, the user answered in the chat).
- The MCP server `longrun mcp`: stdio JSON-RPC with no dependencies, tools `ask` (the same fields: question, options, default, free_text, title, wait_sec, expire_min, icon) and `notify`. It finds the session by the parent pid in `~/.claude/sessions/<pid>.json` (the server is a child process of `claude`), the project by the session index, otherwise by cwd; without a project it shows the dialog and waits for the answer inline. Registered by `install.sh`: `claude mcp add --scope user longrun -- ~/.local/bin/longrun mcp`; the server appears in sessions started after registration. Per the documentation the default MCP tool timeout is 28 hours, the stdio server idle timeout is 30 minutes, and a call longer than 2 minutes in an interactive session goes into a background task; therefore `wait_sec` is capped at 1500 s, and a late answer arrives as a message in any case.
- Telemetry: the flag `asking the user Q3 12m` in the SESSIONS lines, the block `ASKED, waiting for the user` in the asking party's digest, the `ask` flag at the watcher (a question unanswered longer than `stuck_wait_min` -> `STUCK?` to the orchestrator).
- Halt: the `mcp__longrun__*` tools are not forbidden (asking the user is a way to lift the stop). A budget stop also shows the `STOP by longrun budget` dialog with buttons Keep stopped / Resume all: Resume all lifts the halt, snoozes the rule until the window resets and notifies the orchestrators of all projects; from a watcher tick the dialog is launched as a detached process, the tick does not wait.
- Tests: `tests/ask.sh` (30 checks): the fixture `LONGRUN_ASK_FIXTURE=<json>` instead of the dialog, `LONGRUN_ASK_FIXTURE_DELAY` for a late answer, `LONGRUN_NO_UI=1` in all suites, so that a test never shows a real dialog or notification.

Not included: stage 4 (automatic fact sources). Verified live 09.09.2026 23:00 from an app session: `longrun ask ... --wait 0` showed the dialog in front of the windows, the answer went into the socket and arrived in the session as a cross-session-message from 'longrun ask' in the middle of a Bash call; the dialog process exited on its own, in asks.json state=answered, delivered=socket. Not verified live: the dialog from a launchd tick and the automatic move of a long `ask` call into a background task in the app.
