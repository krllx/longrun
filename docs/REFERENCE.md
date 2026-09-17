English | [Русский](REFERENCE.ru.md)

> Reference: every command and flag, file formats, hooks, budgets, verified facts. How it works and why is in [README.md](../README.md).

# longrun - reference

Version 0.6.2. Verified on Claude Code 2.1.238 (CLI) and 2.1.260 (desktop) on macOS; the Linux half of the platform layer (the systemd and cron timers, the choice of dialog and notification program) was verified on Ubuntu 24.04 with python3 3.12, where all four suites pass as well. See section 12. Facts about hooks and the app were captured from live runs and checked against the official docs; raw material in [research/VERIFIED.md](../research/VERIFIED.md) and [research/hook-payloads/](../research/hook-payloads/).

## 1. Entities

- **Project** - the `.longrun/` directory. Shared memory of every session that started inside the project or in a directory linked to it. The project name is the parent folder name (`shop`) or the `name` key in `config.json`.
- **Session** - one Claude Code conversation. The session key is the first 8 characters of its first CLI id. It belongs to one project: the binding is written on `SessionStart` to `~/.claude/longrun/sessions/_index/<CLI id>.json` and from then on every hook follows it rather than cwd (the cwd in a hook payload is the shell's cwd after `cd`).
- **Directory** - where the session started. It determines the project: walk up the tree to `.longrun/` (a directory or a pointer file with the path on its first line), otherwise `~/.claude/longrun/registry.json` by the longest matching prefix. The directory stores nothing.

### How session identity is resolved

| Event | What longrun does |
|---|---|
| `SessionStart` with a known CLI id (compaction, resume from the CLI, `/clear` without an id change) | the same key as in `_index` |
| New CLI id whose app file has `priorCliSessionIds` (resume in the app; arrives as `source=startup`) | the key of the previous id in the chain; whatever was already written under the new id (for example a journal line from `watch`) is merged into the chain's directory |
| New CLI id with `source=clear` | the key of the session that ended with reason `clear` in the same cwd no more than three minutes ago |
| New CLI id for which the app has not yet written metadata | its own key for now; on every turn the hook re-reads the app files, and as soon as the chain is visible it re-binds the session and shows its own notes once, marked "continued from CLI id ..." |
| `source=fork`, the app file has `forkedFromSessionId` | its own key, the parent's own notes are copied once |

App files: `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json` (macOS; on Linux `$XDG_CONFIG_HOME/Claude/...`, `LONGRUN_DESKTOP_DIR` overrides both), fields `sessionId` (the stable id of the sidebar entry), `cliSessionId`, `priorCliSessionIds`, `forkedFromSessionId`, `title`, `cwd`, `isArchived`, `lastActivityAt`. As of 07.09.2026, in 193 of 210 entries `cliSessionId` differs from `sessionId`, and five have a `priorCliSessionIds` chain: the app id is its own, not a former CLI id.

## 2. Files and formats

### Project `<root>/.longrun/` (or `~/.claude/longrun/projects/<slug>/` with `--external`)

| File | Format |
|---|---|
| `NOTES.md` | a heading and lines `- [n<id>] MM-DD <tag> (<author>): <text>`. The author is the session title from the sidebar (up to 24 characters), otherwise the directory name. Foreign lines (manual edits, `## headings`) are preserved as entries without an id |
| `inbox/*.md` (and `inbox/` in the session directory, see watch) | `<ts>-msg-to-<address>-from-<sid8>.md` (messages to sessions; the address is `d<8 characters of the app id>` or `sid8`), `<ts>-report-<scope>-<sid8>.md`, `<ts>-ask-...`. Delivered and acknowledged ones move to `inbox/.archive/` |
| `config.json` | project setting overrides, see section 6 |
| `state.json` | `next_note`, `last_gc` |
| `stale.json` | id -> `{why, at, by}` for entries a session marked as no longer true |
| `archive/compact/<session key>-<ts>.md` | the compaction summary verbatim, including the `<analysis>` block that is absent from the transcript |
| `archive/precompact/<key>-<ts>.md` | the snapshot before compaction: the `/compact ...` text, the last user requests longer than 40 characters, edited files, FAIL lines |
| `archive/notes.md` | deleted, replaced and aged-out entries, one line each with the full date; lines marked `legacy <path>` are notes from version 0.2 worktree stores |
| `archive/sessions/` | `<key>.journal.md` (trimmed journal tails) and `<key>/` (directories of sessions silent longer than `session_dead_days`) |

### Session `~/.claude/longrun/sessions/<project key>/<session key>/`

The project key is the project directory path with non-letter characters replaced by `-` (the last 90 characters).

| File | Format |
|---|---|
| `notes.md` | like `NOTES.md`, but `[s<id>]` and no author |
| `journal.md` | `MM-DD HH:MM <line>`, written by the hooks and by the commands that change something: `session <source>`, `FAIL \`<command>\` -> Exit code N ...`, `compaction ...`, `summary archived ...`, `send -> ...`, `watch wN ...`, `session end (<reason>)` |
| `meta.json` | `sid` (current CLI id), `skey`, `cwd`, `scope`, `started`, `last_seen`, `ended`, `tools`, `turns`, `edit_tools_since_note`, `fails`, `files` (edited), `compactions`, `last_status` (the first 200 characters of the last reply, `Stop` hook), `permission_mode`, `desktop_id`, `shared_seen` (id -> hash of text plus stale mark of the shared entries the session has already seen), `muted`, `swept_at`, `sessions_seen` (skey -> state and last reply already reported), `last_note`, `turn_files`/`turn_fails`/`turn_tools`/`turn_notes`/`turn_card` (what the current turn changed, how much work was in it and what it wrote down, plus the frozen copy of the same for the turn that just ended), `carded_at_turns`/`carded_at_tools` |
| `state.json`, `archive/notes.md` | the id counter of own notes; deleted own entries |

### Global `~/.claude/longrun/`

`registry.json` (`links`: directory -> project directory), `config.json` (global overrides), `sessions/_index/<CLI id>.json` (`local`, `cwd`, `skey`, `at`), `watch/` (`w<N>.json`, `env.json` with a PATH snapshot, `state.json`, `run.log`, and the scheduler's own log: `launchd.log`, `systemd.log` or `cron.log`).

## 3. Commands

Exit codes: 0 ok, 1 not found / check did not pass, 2 invalid arguments or over budget, 3 no project or session.

### Setup

- `longrun init [--external]` - make cwd a project. `--external` puts the directory under `~/.claude/longrun/projects/` and registers cwd in `registry.json`. (`--hq` and `--no-hq`, which used to switch the ledger and inbox layer on, are accepted and ignored since 0.6.0.)
- `longrun link <root | root/.longrun>` - sessions starting in cwd belong to this project. Writes only to `registry.json`. The project directory must already exist. A version 0.2 store in this cwd, if any, is folded in: its notes go to the project's `archive/notes.md`, the file is renamed to `NOTES.legacy.md`.
- `longrun unlink` - remove the entry from the registry without deleting anything.
- `longrun where` - project, mode, session and its directory.

### Notes

- `longrun add [--own] -t dead|decision|fact|ctx|pin|doc [-s <author>] "<text>"` - one line up to 400 characters, **into the project's shared notes by default** since 0.6.0: a fact worth writing down is usually worth it for whoever comes next, and `--shared` on every call was a step the model skipped. `--own` keeps an entry in this session's notes, for what belongs to this conversation alone (requires a known session: `LONGRUN_SESSION` from the session environment or the freshest heartbeat with the same cwd). `--shared` is still accepted and does nothing. A duplicate by text is not added. On overflow - exit code 2 and a list of deletion candidates.
- `longrun rm s3 n12 ...` - delete; the lines go to the archive. A number without a prefix is treated as an own note.
- `longrun replace s3|n12 "<text>"` - rewrite; the old text goes to the archive.
- `longrun notes [--shared | --own | --session <who>]` - show; both files by default.
- `longrun prune [--auto] [--shared]` - deletion candidates (entries marked stale first, then `ctx`, `fact`, `dead`/`decision`, then `doc`; `pin` is never touched); `--auto` archives down to 60% of the budget.
- `longrun doc add <path> "<what is in it>"` - long material stays in a file and the shared notes carry one line pointing at it: `- [n12] 09-16 doc (session): research/X.md - what is in it`. The path is stored relative to the project root, so it resolves the same way from every worktree; a file outside the project, a file that does not exist, and a second pointer to the same file are refused. `doc ls` lists them with size and mtime, `doc touch n12 "..."` rewrites the description and keeps the path, `doc rm n12` drops the pointer (never the file).
- `longrun stale n12 "<why it stopped being true>"` - a thumbs-down, not a delete: the entry keeps showing, with `(STALE since ... : why)`, so every session sees the doubt, and `prune`/`gc` take marked entries first whatever their tag (a marked `pin` included). `stale --clear n12` takes the mark back, `stale ls` lists them. Nothing has to remember to ask: every half an ageing window a session's turn opens with the count of shared notes nobody has looked at since, and the command to mark one. Marks live in `<project>/stale.json`, beside `NOTES.md` rather than inside it, because the note format is what every existing project's entries are written in. A mark never outlives its entry.
- `longrun mute n12 [n13 ...]` / `longrun unmute [n12|--all]` - stop injecting a shared entry into THIS session's digest. Nothing changes on disk and nothing changes for any other session; the block head says how many are hidden. It is not the "pull back what is needed" half of the memory - that is `doc`, the docs delta and `recall` - but its per-session inverse: one session deciding an entry is not worth carrying, without deciding that for anybody else.
- `longrun compact-hint [--set "<text>" | --clear]` - what the `PreCompact` hook will tell the summariser to keep (section 4), printed exactly as it will be sent; `--set` adds one line of this session's own, `--clear` removes it. The project-wide version of the same thing is `longrun config set compact_instructions "..."`.
- `longrun recall <word> [...] [-n 12] [--no-transcript]` - search. Order: shared and own notes, the files `doc` entries point at, other sessions' own notes and journals, inbox, archives; then six of the project's transcripts (newest first, plus the subagent transcripts of the current session). The transcript is Claude Code's internal format, the parser is defensive: if the format changes there will be fewer matches, not a crash.

### Sessions

- `longrun status [--all]` - the project's sessions: key, name, state (`alive`, `alive+sock`, `stale Nm`, `active?`, `ended(reason)`), scope, number of own notes, counters, last reply. Sessions with no turns, calls, notes or replies are hidden as app noise. `--all` also brings back the sessions the user archived or deleted in the desktop app, saying which of the two happened.
- `longrun send [--list] [--inbox] [--resume [--max-turns N] [--model M] [--mode <permission mode>] [--timeout S]] <who> "<text>"|-` - the recipient: a sidebar title, a name from the Claude Code registry, an id or its prefix, `local_<id>`. Running - an envelope into its socket; not running - a file in the recipient's (not the sender's) project inbox; `--inbox` - always a file; `--resume` - `claude -p "<text>" --resume <id>` in the recipient's cwd, the reply is printed. An ambiguous name - refusal with a list.
- `longrun important [on | next | N | off] [--to <who>]` - flag a session whose turn ends must not be missed: while the flag is on, the end of a turn there notifies whatever `notify_turn_end` is set to and whichever window is in front. `on` holds until `off`, `next` arms one turn end, `N` arms a counter that is spent one per turn end and clears itself at zero. No argument prints the flag of that session plus every other flagged session of the project; `--to` takes the same names as `send`. The flag is stored in the session's `meta.json` (`important: {mode, left}`), so it survives compaction, `/clear` and a resume, and it is shown as a `status` flag and in the digest head.
- `longrun ask "<text>" [--options "A,B"] [--default A] [--text] [--wait SEC] [--expire MIN]` - a dialog in front of every window; `ask ls`, `ask answer Q3 "..."`.

### watch

`longrun watch add [--to <who>] [--every 5m] [--for 7d] [--wake [--wake-mode M] [--wake-turns N]] [--no-notify] [--no-test] --then "<what to do>" -- <check>`

| Check | Condition met |
|---|---|
| `pr-merged <id|branch>` | the PR is merged. GitHub: `gh pr view --json state` in the repository the watch was registered from; Arcadia: `arc pr status --json` from `arc_root`. The tool is chosen at registration (key `pr_tool`: `auto` looks at the folder, `.arc` -> arc, `.git` -> gh) and recorded in the check. `closed`/`discarded` - a hard error |
| `pr-status <id|branch> <open|merged|closed>` | the status equals the given one (`discarded` = `closed`) |
| `at 'YYYY-MM-DD HH:MM' | HH:MM | +2h` | the moment has come (HH:MM in the past = tomorrow) |
| `file /path` | the file exists |
| `http URL [--expect TEXT] [--token-file ~/.tokens/x] [--auth-scheme OAuth]` | a 2xx response and, if given, it contains the text; 401/403/404 - a hard error, everything else - "not yet" |
| `cmd '<shell>'` | exit code 0 = done, 1 = not yet, 3 = give up. Absolute paths, no aliases, no Touch ID or ssh: runs from the timer with the PATH captured from the shell at `add` |

Under the macOS timer the interpreter may have no access to `~/Documents` (TCC): reading such a project's config then yields an empty config, and the message file is written to the second inbox `~/.claude/longrun/sessions/<project>/<session>/inbox/`, which hooks read on a par with the project inbox (`delivered.how` = `session-inbox:`). A delivery error of any other kind is recorded in the watch entry (`delivered.how` = `error: ...`) and in a desktop notification, the state is saved, the tick carries on: the watch does not hang in pending and does not fire twice.

Behaviour: the check runs immediately (`--no-test` disables this): already true - nothing is registered; a hard error - refusal. Then a tick every `--every` (no more often than the timer itself, 5 minutes). Three hard errors in a row - state `broken`, the `--for` deadline passed - `expired`; in both cases the recipient gets one message. Delivery: the socket if the recipient is running; `claude -p --resume` with `--wake`; otherwise a file in the inbox. Plus a desktop notification. The entry stores the recipient's stable app id, so renaming and resume do not get in the way. Other subcommands: `ls [--all]`, `rm <id>`, `test -- <check>`, `sessions`, `run [--force] [id]`, `install [--every 5m]`, `uninstall`, `status`.

### Service commands

`longrun digest [--source startup|compact|...]` (what the hook prints), `longrun gc` (clean up now), `longrun hook <Event>` (called by hooks, JSON on stdin), `longrun help`, `longrun rules`, `longrun version`.

`longrun onboard` prints a brief for the first conversation about the skill: what it does, the caveats, the machine's state (project, the timer, the auto-compact window in Claude Code versus the `autocompact_window` key) and the list of settings worth asking the user about, with their current values and meaning. The agent retells it in the user's language, asks one at a time and applies the answers via `config set`; `longrun onboard done` writes `onboarded_at` into the global config, after which the digest stops suggesting `longrun onboard`.

`longrun config` shows the effective settings and where each comes from (default / global / project); `longrun config set KEY VALUE` writes to the project's `config.json`, with `--global` to `~/.claude/longrun/config.json`; `longrun config unset KEY [--global]` restores the default. The value type is checked against the key's default (integer, float, true/false), an unknown key is rejected.

## 4. Hooks

Twelve entries in `~/.claude/settings.json`, all calling `longrun hook <Event>`. The project is resolved via `_index` for every event except `SessionStart(startup|resume|fork)`, where it is resolved by cwd and written to `_index`. Outside a project the hook silently exits with code 0.

| Event | What it does | What it prints into the context |
|---|---|---|
| `SessionStart` (all sources) | binding the CLI id to the session (resume chain, `/clear`, fork), heartbeat, a journal line, export of `LONGRUN_SESSION`, `LONGRUN_DIR`, `LONGRUN_SCOPE`, `LONGRUN_TRANSCRIPT` via `CLAUDE_ENV_FILE`, gc once an hour, the "all shared entries shown" mark | the digest (section 5) |
| `UserPromptSubmit` | turn counter; clearing what is measured per turn (the edited-file list behind the docs delta, the hint budgets); finishing reading the app metadata and re-binding the chain | messages from the inbox; own notes once on re-binding; the shared notes delta; the sessions delta (one appeared, ended or said something new); the docs delta; the turn card (section 5c), at most once per 8 turns; the housekeeping question (are any of the old shared notes no longer true?), which has its own conditions and none of the card's - not in the first 4 turns of a session, at most once per half an ageing window, and only when something is old enough to re-read |
| `PostToolUse` (Edit, Write, MultiEdit, NotebookEdit, Bash, PowerShell, Agent, Task, Workflow, Grep, Glob, WebSearch, mcp__*) | counters; only the four editing tools count as edits; the list of edited files. The three search tools move no counter - they are matched for the query inside them and nothing else | messages from the inbox as `additionalContext`; the shared and docs deltas, so a peer's note does not wait for the user to press Enter (at most once per 5 calls, and only somebody else's changes); the recall hint (section 5a); the poll hint (section 5b); the same card for the turn in progress, once a window of 40 calls has passed since the last note or card |
| `PostToolBatch` (no matcher) | one event per batch of parallel calls, after all of them resolve. Records the files the batch opened, Reads included - the `PostToolUse` matcher deliberately does not pay a process for those. Newer than the other events: where the CLI does not know it, the entry is inert and `PostToolUse` carries the hint alone | the recall hint for the whole batch, as `additionalContext` |
| `PostToolUseFailure` (Bash, PowerShell; async) | a `FAIL` line in the journal, the last 40 kept | - |
| `PreToolUse` (all tools) | under `halt` a refusal `permissionDecision: deny` with a reason (except calls to `longrun` itself); for Bash, PowerShell, Agent, Task, Workflow and MCP tools an entry in the meta's `running` (command, start) | the refusal with a reason under halt, otherwise nothing |
| `PermissionRequest` (async) | `waiting_since` / `waiting_what = permission (<tool>)` in the meta | - |
| `Notification` (permission_prompt, idle_prompt, agent_needs_input, elicitation_*; async) | waiting for confirmation or input in the meta; `idle_prompt` clears `turn_started` | - |
| `PreCompact` | a snapshot in `archive/precompact/` | the instructions for the summariser (below) |
| `PostCompact` (async) | the summary in `archive/compact/` | - |
| `Stop` | the last reply in `last_status`; the turn is frozen into `turn_card` for the next prompt | - |
| `SessionEnd` | the reason in the heartbeat, a journal line | - |

Order of events around compaction: `SubagentStop` (the summariser) -> `SessionStart(compact)` -> `PostCompact`. That is why the digest after compaction names the archive directory rather than a file: the current summary lands there a moment after the digest.

### Steering the compaction itself

Automatic compaction and `/compact <text>` build the **same** summariser prompt (the eight-section one: request and intent, technical concepts, files and code, errors and fixes, problem solving, every user message, pending tasks, current work). The only difference is that a non-empty instruction text is appended to it as a trailing `Additional Instructions:` block. So automatic compaction is not a different, dumber mechanism - it is the same one, without the steering the user types by hand.

The stdout of a `PreCompact` command hook becomes that block. Verified by reading Claude Code 2.1.238: hook results with exit code 0 and non-empty stdout are joined with a newline into `newCustomInstructions`, merged with whatever the user typed after `/compact`, and passed into the prompt builder; the matcher fires for `trigger: "auto"` as well as `"manual"`. Two consequences: the text costs no context (a script writes it, not the model), and the user no longer has to catch the moment before a compaction to steer it.

`longrun` prints it from `compact_hint()`: four fixed lines (keep dead ends with the reason; keep exact strings rather than descriptions; drop what one Read brings back; keep the user's own wording), then what is derived from the session state - the tasks this session owns on the board, the files it has edited, the ids of the notes that are re-injected by themselves right after the compaction - then the project line `compact_instructions` and the session line from `longrun compact-hint --set`. Over `compact_hint_max_bytes` the derived lines go first (files, notes, tasks, the lead-in), the fixed core and the two human lines stay. `longrun compact-hint` prints exactly what the hook will send; `compact_hint false` turns it off.

Caveats: stdout that parses as JSON is read as a hook decision object instead (and `decision: "block"` cancels the compaction - the session then continues uncompacted), so the text is plain; the same ~10000-character inline limit on hook output applies here too; the text is also shown in the transcript as the hook's result line.

## 5. Digest and budgets

Composition, in order: the header `<longrun v… project=… session=<name> [<key>] source=…>`; MESSAGE (undelivered messages); `SHARED notes (project X) N entries used/cap`; `OWN notes (this session)`; `SESSIONS of project X` (up to 6 other sessions: name, key, state, scope, number of own notes, the last two directories it has been editing in, last reply; live ones first - "hand it to a more relevant session" needs relevance to be visible, and a window's title is whatever the user happened to call it); `WATCH n pending`; under an orchestrator also `ORCHESTRATOR`, `BOARD`, `YOUR TASK`, `FACTS unhandled`, the duties block and `ASKED` (section 11); `HANDOFF` (only after compaction: FAIL lines, `FOCUS:` from `/compact <text>`, `ASK:` the last requests, `FILES:`); the journal tail (after compaction, resume, `/clear`, fork and on a continued chain); a line about the archived summary; a command hint.

Default budgets: shared notes 5000 bytes, own 3000, digest 9000 (only ~10000 characters of hook output reach a session inline: past that Claude Code 2.1.238 writes the rest to a file and leaves a pointer, and older builds simply truncated), sessions block 700, HANDOFF 1100, shared notes delta per turn 1200. On overflow the digest drops blocks in this order: watch, journal, the orchestrator's duties, sessions, ASKED, facts, board, HANDOFF.

Only then do the notes give way, and they give way by **shedding their oldest entries one at a time**, `pin` and `doc` exempt (a `doc` line is the index of material deliberately kept out of the context, so dropping it hides a whole file rather than one fact), oldest first across both files, with a line saying how many were left out. Cutting the rendered tail instead - which is what happened until 0.6.0 - removed exactly the entries written last. If even that is not enough, the text is cut with a closing tag.

`notes_max_bytes` is the hard cap of the *file*, which `add` refuses to go past. What actually reaches a session is bounded by `inject_max_bytes`, so everything that judges "this file is getting too big" - the `PRUNE NEEDED` line, the `gc` autoprune - measures against `inject_max_bytes` minus 600 bytes of head and hints, split between the two files in proportion to their caps when they ask for more than that. `config set` refuses a combination where `notes_max_bytes + session_notes_max_bytes + 600` is above `inject_max_bytes`: those bytes are not a preference to honour later, they are entries no session would ever see. A project configured before that check existed, or edited by hand, can still be in that state and looks healthy from the outside - so the notes block head says `(only ~N B of these fit a digest: longrun config)` whenever the cap is larger than what can be injected, and `longrun config` prints the whole arithmetic as a warning under the settings.

The SESSIONS block is a SessionStart snapshot, so a per-turn delta carries what changed since: a session appeared, a session ended, or one of them gave a new last reply (`sessions_delta_max_bytes`, coarse on purpose - a running tool or a context percentage changes every minute and is not worth a line). Sessions the user archived or deleted in the desktop app are left out of both, and out of `longrun status` unless `--all` is passed, which also says which of the two happened; `gc` archives the directory of a deleted one at once instead of waiting out `session_dead_days`, and of an archived one never, because the user can unarchive it.

The per-turn delta obeys `shared_delta_max_bytes` the same way: it shows the changed entries oldest first, marks **only what it printed** as seen, and says `(+N more on your next turn)`. Whatever did not fit comes on the following turn instead of being silently skipped - it used to be marked seen and then clipped away, which meant a session never saw it at all.

**The docs layer.** A `doc` entry is the lazy half of the memory: the long material stays in a file under the project, the shared notes carry one line with its path and what is in it, and a session reads the file only when it needs it. Three things keep the pointer honest, all from one `stat` per entry: a file written after its description renders as `(file changed MM-DD HH:MM, this line may be stale)`, a file that is gone renders as `(MISSING: no such file now)` and is archived by `gc` after seven days, and a file that changed since a session last looked shows up on that session's next turn as `DOCS changed`.

The reference for "after its description" is the file's mtime at the moment `doc add` or `doc touch` ran, kept per entry in `<project>/docs.json`. It used to be the note's own date, and a note carries no time of day - so a change made hours later on the **same day** read as no change at all, which is exactly the case that matters: another window rewrote the material while this session was closed. A project written before `docs.json` existed has no stamps and falls back to the old day-granularity comparison rather than going quiet. `gc` drops stamps whose pointer is gone.

`DOCS changed` reads the change in two directions: somebody else's change is an offer to read the file if the task needs it (`~`), while a file **this** session edited is a debt - the description every other session is reading still describes the old file, so the line asks for `doc touch n<id>` (`!`). Attribution comes from this session's own edit tools **in the turn that just ended**; it used to be a rolling list for the whole session, so once a session had touched a file, every later change by anybody was still signed "you". Mid-turn only the `~` half is delivered: a peer's change is news worth having at once, while the debt would otherwise fire after every save of the same file. `recall` searches inside the files the pointers name, ranked right after the notes themselves. Age alone never archives a `doc`: the file it names may be months old and still exactly right.

Cost: the digest is 350-2000 tokens depending on how full it is; per turn - only the delta and messages, usually zero.

## 5a. The recall hint

Everything else offers the saved material **before** the fact: the digest at every start, the doc pointers in it, the docs delta when a file moves. The other direction - pulling it back in at the moment it turns out to be needed, which is point 2 of the manifesto - rested on the model remembering `longrun recall`, that is, on an instruction rather than a mechanism. The recall hint is the mechanism.

The signal is the session naming its own question: a `Grep` or `Glob` `pattern`, a `WebSearch` query, a subagent's one-line `description`. A `Read` carries no question and a path is not one either - guessing intent from a path is how a hint like this turns into noise, and by then the session is already looking in the right place.

What it searches is the **curated** part of what `recall` searches, minus what is already in the context: the files behind doc pointers, other sessions' notes, and the notes the archive kept when they were pruned. The shared notes and this session's own notes are injected whole at every start, so a hit in them is the digest read back, not news. Files the session has already opened are skipped for the same reason; on a CLI with `PostToolBatch` that includes the ones it merely Read.

Journals, pre-compaction snapshots and compaction summaries are **not** searched, and that boundary was measured rather than guessed. `recall` does search them, and should: a human asked and can judge what came back. An unprompted hint cannot. Replaying this project's real search history (`research/measure-recall.py`) through the first version showed it firing on half of all searches with two thirds of the hits being journal lines like "PR #8 opened" or an archived `ctx` note about a branch - words matched, no question answered.

Two rules do the rest of the filtering, and both came from the same replay:

- **In a notes file, only the tags another session is owed count**: `dead`, `decision`, `fact`, `pin`, `doc`. `ctx` and `todo` are one conversation's own bookkeeping - a single archived `ctx` note was the source of a third of all the noise in the first version.
- **In a doc file, one word is not enough.** Prose matches an ordinary word by accident; two distinct search terms on the same line much less often. So a single-word `Grep` never points into prose, while a subagent's description or a multi-word query can.

Four more things keep the volume down: a term must be at least 5 characters; a term found on more than 6 lines is a word rather than a term; the same (term, file) pair is never pointed at twice; and at most two hints fire per turn, the budget refilling at the turn boundary. One pass over the material is capped at 600 kB whatever the project holds. The hint quotes at most two lines and hands over to `longrun recall <term>` for the rest. On the replay corpus that comes to about 1.5 hints per session.

## 5b. The poll hint

`watch` exists because a session that waits by hand spends a model turn per check and stops waiting when the conversation does. Choosing it was advice in `SKILL.md` and nothing else. Now a `Bash` or `PowerShell` call that sleeps 30 seconds or more, or loops around a sleep, or repeats the same command for the third time in a turn, is answered once per turn with what `watch` would do instead. A hint, never a refusal: a long sleep is sometimes exactly right, and nothing here can tell which.

## 5c. The turn card, and its two ways in

After a turn, the next prompt may open with what that turn did and the one question the skill exists for: is any of it something the next session, or you after a compaction, could not get back with one command? It replaced a counter that said "40 tool calls since the last note" - a number nobody can act on, which invites filler notes written to silence it.

**A turn that changed or broke something.** Gated on `nudge_edit_tools` (6 edits) or any failed command, because reading around is not activity worth a note and 40 `ls` calls prove nothing. Fires at the turn boundary and, once a window of `nudge_tools` calls has passed, mid-turn as well.

**A turn that changed nothing but did real work.** Added in 0.6.2 and measured before it was built. `research/measure-cards.py` reads 725 transcripts and asks the question backwards: rather than judging which turns *should* have written a note, it counts the turns that *did*, since a note written unprompted is the strongest evidence a turn was worth asking about. Of 351 such turns, 182 (52%) happened in turns the edit gate is silent in, and 124 had no edit and no failure at all. The gate was aimed at less than half the territory notes come from.

The rule the same data points at is length, which is the only thing a hook knows before the fact:

| tool calls in a read-only turn | wrote | silent | note rate |
|---|---|---|---|
| 1-2 | 10 | 96 | 9% |
| 3-5 | 19 | 92 | 17% |
| 6-10 | 46 | 76 | 38% |
| 11-20 | 23 | 42 | 35% |
| 21+ | 27 | 26 | 51% |

(counted in the calls a `PostToolUse` hook is actually fired for - `Read` is deliberately not one of them, and it makes almost no difference: a turn that reads a lot also runs plenty of `Bash`, `Grep` and MCP calls.)

So `NUDGE_READ_TOOLS` is 6, a fixed number rather than a setting, because it came from a measurement that can be re-run rather than from a preference. It reaches 144 turns that currently write nothing, about 1.2 per session, in the band where the note rate is already 38-51%. Lowering `nudge_edit_tools` instead would reach 85 turns and none of the 124. This way in fires **only** at the turn boundary: a turn that has read six things may still be on its way to editing the seventh, and only at `Stop` is it known to have been reading all along. Its question is different too - there is no file to name, so it asks for the conclusion the reading reached.

`card_due` keeps both ways to one card per window between them, so an editing session is not asked twice and an analysis session gets the slot the edit card is not using.

**"Did this turn write anything" is counted, not inferred.** It used to be `last_note >= turn_started`. Both are stamped to the minute, so a note written moments *before* a turn compared equal and was read as written during it - and the `Stop` hook dropped `turn_started` before asking, so the comparison ran against a sentinel and answered "no" for every turn there has ever been. The edit-gated card hid this: a note write also resets `edit_tools_since_note`, which silenced the card by another route. The read-only card has no such second gate, which is how it surfaced. `turn_notes` counts the writes instead.

## 6. Configuration

Eight keys have been retired and are now fixed numbers in the script: `strict_stop` and `auto_init` (both off, and both a mode nobody ran), `journal_tail_lines` (12), `handoff_max_bytes` (1100), `fail_keep` (40), `recall_transcripts` (6), `ctx_sample_every` (5) in 0.6.0, and `compact_hint_max_bytes` (1200) in 0.6.1. A setting that has never been changed is not a setting. What 0.6.2 added is fixed for the same reason: the housekeeping question waits 4 turns, the mid-turn delta runs at most once per 5 tool calls, the recall hint allows 2 per turn over terms of 5 characters or more found on at most 6 lines, the poll hint triggers on a 30-second sleep or a third identical command, and the read-only turn card wants 6 tool calls. A retired key left in a config.json is ignored, shown as retired by `longrun config`, and removed by `config unset`; `config set` on one says what replaced it instead of "unknown key".

`~/.claude/longrun/config.json` (global) and `<project>/config.json`; the project value overrides the global one. View and change: `longrun config`, `longrun config set KEY VALUE [--global]`, `longrun config unset KEY [--global]`. Keys and defaults:

| Key | Value | Meaning |
|---|---|---|
| `notes_max_bytes` | 5000 | shared notes budget |
| `session_notes_max_bytes` | 3000 | own notes budget |
| `notes_warn_pct` | 80 | above it - PRUNE NEEDED in the digest |
| `notes_autoprune_pct` | 90 | above it - gc archives entries marked stale, then `ctx`, down to `notes_warn_pct`; 0 disables |
| `notes_max_age_days` | 14 | older entries go to the archive (except `pin`) |
| `journal_max_lines` | 200 | journal length before the tail is archived |
| `inject_max_bytes`, `sessions_block_bytes`, `shared_delta_max_bytes`, `sessions_delta_max_bytes` | 9000, 700, 1200, 500 | digest budgets; the last two are per-turn slices |
| `archive_keep_days`, `compact_keep` | 30, 40 | archive retention; maximum summaries per project |
| `compact_hint` | true | whether `PreCompact` sends the summariser its instructions (section 4); their cap is a fixed 1200 B |
| `compact_instructions` | empty | one more line for them, the same for every session of the project ("keep every SQL query in full") |
| `session_stale_min`, `session_dead_days` | 30, 7 | when a session is `stale`; when its directory moves to the archive |
| `nudge_turns`, `nudge_tools`, `nudge_edit_tools` | 8, 40, 6 | the turn card: how often at most (turns), the mid-turn window (tool calls), and the edits it takes for a turn that changed something to be worth asking about (the read-only way in has its own fixed threshold, section 5c). Both windows are measured from where the counters stood at the last card, never taken modulo: a counter that steps OVER the boundary (`PostToolUseFailure` charges one without looking at the card) used to skip a whole window |
| `name` | not set | project name instead of the folder name |
| `pr_tool` | `auto` | what to query PR status with in `pr-merged`/`pr-status` checks: `gh` (GitHub CLI), `arc` (Arcadia), `auto` - by the folder the watch was registered from |
| `arc_root` (global only) | `~/arcadia` | where to call `arc pr status` from, Arcadia only |
| `watch_timer` (global only) | `auto` | what runs the watch tick: `launchd` (macOS), `systemd` (a user timer), `cron`, `none` (nothing runs it; `longrun watch run` is yours to schedule). `auto` - launchd on macOS, a systemd user timer on Linux, cron where there is no user systemd |
| `notifier` (global only) | `auto` | what draws a desktop notification: `terminal-notifier`, `osascript`, `notify-send`, `none`. `auto` - terminal-notifier when it is installed (on macOS osascript is delivered but never drawn, section 12), else the OS default. `longrun notify --test` says what this machine actually does |
| `notify_turn_end` (global only) | `off` | a notification when a session finishes a turn: `off`, `unfocused` (only while the Claude app is not the application in front), `always`. The app sends this event itself, but silent and with `interruptionLevel: passive`, so macOS files it into Notification Center without drawing a banner - this is the loud, clickable version of the same thing |
| `autocompact_window` | 0 | where Claude Code auto-compacts, as set by `/autocompact N`; accepts `300k`, `1M`. 0 - follow Claude Code (the `CLAUDE_CODE_AUTO_COMPACT_WINDOW` variable, then `autoCompactWindow` in settings.json, then the model's window). The key is the user's intent: a hook cannot run `/autocompact`, so `onboard` compares it with settings.json and asks the user to type the command themselves |
| `board_block_bytes`, `facts_block_bytes` | 900, 900 | room in the digest for the board and for unhandled facts |
| `ctx_warn_before` | 50000 | how many tokens before the auto-compact window to warn the session (the size itself is read from the transcript every fifth tool call, which is no longer a setting) |
| `stuck_tool_min`, `stuck_wait_min` | 30, 10 | the watcher's two thresholds: a tool call still running, an unanswered permission prompt or dialog (minutes) |
| `stuck_fail_streak` | 3 | identical FAILs in a row before the SESSIONS line says `fail x3` (a flag, not a report) |
| `wake_on_stuck` | true | a stuck report starts a turn at the orchestrator (otherwise it lands in the inbox) |
| `ask_wait_sec`, `ask_expire_min`, `ask_beep` | 90, 360, true | how many seconds `ask` waits for an inline answer; after how many minutes the dialog closes by itself (0 = never); a sound before showing |
| `note_max_chars` | 400 | longer - `add` refuses: one fact, one line |
| `watch_ttl_days`, `watch_check_timeout_sec`, `watch_hard_errors` (global only: the tick runs without a project) | 7, 90, 3 | default watch lifetime (`--for` overrides); timeout of one check; how many hard errors in a row until "broken" |

## 7. Messages between sessions (mechanics)

The Claude Code session registry: `~/.claude/sessions/<pid>.json` (`sessionId`, `name`, `cwd`, `messagingSocketPath`). A live session accepts one JSON line on a unix socket `{"msgV":1,"msg_id":…,"type":"user","message":{"role":"user","content":…},"priority":"next","from":"uds:…"}`; without `priority: "next"` an idle session does not start a turn. The body is wrapped in `<cross-session-message from-name=… from-mode=…>`, the way Claude Code 2.1.260's own `SendMessage` does it; the recipient sees `Message from @<name>` and keeps its own permissions. The format was taken from the binary, not from the docs.

An inbox file is delivered by the recipient's hooks: `SessionStart` (in the digest), `UserPromptSubmit`, `PostToolUse` (`additionalContext`). The file is addressed by the stable app id when it is known, so it survives resume; hooks read both addresses. The message is placed in the recipient's project via `_index`, even if the sender is in another project.

`--resume`: `claude -p "<text>" --resume <id> --max-turns N` in the recipient's cwd, with `LONGRUN_*` and `CLAUDE_ENV_FILE` removed from the environment so the spawned session binds to its own project. No permission dialogs: fine for "check and report", not for "deploy".

## 8. Migration from 0.2

Automatic, on first access:

- a worktree store (`~/.claude/longrun/projects/<slug>/` with `config.hub`) - the hub becomes the project; the old store's notes go to the project's `archive/notes.md` marked `legacy`, the file is renamed to `NOTES.legacy.md`; on the next `longrun link` the registry entry starts pointing straight at the project;
- flat session files `<sid8>.json` and `<sid8>.md` are laid out as `<sid8>/meta.json` and `<sid8>/journal.md`; the `sessions/` directory inside a version 0.1 project moves there too;
- hub notes stay as the project's shared notes as they are (the `n…` ids do not change); old sessions have no own notes, they appear with the first `longrun add`.

Sessions running at the moment of the upgrade lose nothing: every hook first migrates the files of the old layout and only then reads them, and if the session has already written something in the new layout, old and new are merged (counters are summed, journal lines go in order).

What changes in habits: `rm`/`replace` accept `s3` and `n12`, the shared notes budget is 5000 instead of 6000, and a session now has notes of its own - `longrun add --own`. (In 0.3.0-0.5.1 `add` wrote to those own notes unless told `--shared`; since 0.6.0 it is the other way round, see section 3.)

## 9. Tests

`bash tests/run.sh` - 222 regression checks on synthetic data without API calls: setup and worktree linking, shared and own notes (deduplication, budget, refusal at the boundary, prune, rm, replace), the docs layer and the stale marks, all hooks on real payload shapes, compaction snapshot and archive, the instructions the PreCompact hook hands to the summariser, HANDOFF, binding hooks to the session when the shell leaves for another directory, the turn card and its cadence, the housekeeping question standing on its own in a turn with no edits, the digest with every budget full (and that a `doc` pointer is never what gives way), recall ranking, 20 parallel writers into both files, gc and ageing, migration of three old layouts, notes-only mode, send into a socket and into an inbox with delivery by all three hooks, resume by sidebar title, watch with a tick and no timer, the config command (set, unset, --global, type check, limits from settings, the warning for a budget that was set before the check, a retired key), onboard (the brief, the hint in the digest, done), gh/arc selection for PR checks, and the platform layer (which scheduler this OS gets, the cron schedule and crontab editing, the systemd units, which dialog program, which program draws a notification and whether the machine can say it was really shown, the click target of a notification, the turn-end rule and how the front application is read, the important-session flag through the Stop hook: arming, counting down, clearing itself, and beating both gates).

`bash tests/scenarios.sh` - 37 checks in nine scenarios, one per task from the README: orientation of a new session, own notes through compaction, the shared notes delta per turn, two sessions in one folder, resume under a new CLI id (immediately and with delayed app metadata), `/clear`, fork, handing over work (inbox, socket, watch by name), and the live picture of the other sessions (one appears, one ends, one is archived in the app). Output of the last runs: [tests/last-run.txt](../tests/last-run.txt), [tests/last-run-scenarios.txt](../tests/last-run-scenarios.txt).

`bash tests/orchestrator.sh` - 51 checks of the orchestrator layer (lock and mirror, board, facts, halt via PreToolUse, telemetry, the watcher's two stuck rules). `bash tests/ask.sh` - 27 checks of the dialog and the MCP server on a fixture (answer inline and by a turn, cancel/expire/failure, exclusion from halt, the flag at the watcher, JSON-RPC over stdio). All suites run with `LONGRUN_NO_UI=1`: the tests show no real dialogs or notifications.

A live run on `claude -p` (costs money): [tests/e2e-claude.md](../tests/e2e-claude.md).

## 10. What is guaranteed, what is probabilistic, what breaks on a version change

**By mechanics:** notes and the journal return to the context on every `SessionStart`, including compaction, `/clear`, resume and fork (verified on the transcript); every compaction summary is archived in full; failed commands land in the journal; budgets cannot be exceeded via the CLI; parallel writes are not lost (`flock` + atomic replace); messages are delivered once; the shared notes delta is computed from text hashes, not from time.

**Only probabilistic:** that the model will write a note, mark with `--shared` what others need, call `recall` instead of re-investigating, will delete. Anthropic closed as not planned the request to give the model a guaranteed turn before compaction (issue anthropics/claude-code#43733). The separation from auto-memory rests on an instruction.

**Breaks on a Claude Code version change:** the transcript format (recall, the pre-compaction snapshot: fewer matches, a shorter snapshot); the socket and session registry format (`send` into a live session; the inbox queue will keep working); the app file format (the resume chain, name resolution from the sidebar; without them a session resumed in the app starts with empty own notes, the old ones stay on disk and in `recall`); hook event field names; the ~10000-character inline limit on hook output (undocumented, and its overflow behaviour already changed once: truncation, then spill-to-file in 2.1.238); `CLAUDE_ENV_FILE` (without it the session is determined by cwd, which breaks with two sessions in one folder); hot pickup of hooks (verified empirically, not promised in the docs).

**Not covered:** subagents do not receive the digest; Windows was not tested (`fcntl`, unix sockets, none of the three schedulers); `/rewind` does not roll back notes; on resume two digests remain in the history until the next compaction (Claude Code behaviour); two sessions that ran `/clear` in one folder within three minutes may bind to the wrong key.

**Simpler, if all you need is re-injection:** the line `@.longrun/NOTES.md` in `CLAUDE.md` arrives after compaction without hooks and without the hook output limit. Hooks are needed for own notes, the summary archive, the failure journal, HANDOFF, sessions and messages.

## 11. Orchestration (0.4.0, cut back in 0.6.0)

One session of the project takes the role, the others report through the board, and it is the one that calls the human when only the human can decide. It is not autonomous driving: one session toward one checkable condition is Claude Code's own `/goal`, which has a real evaluator. What 0.6.0 removed from this layer, and why, is section 0 of [ORCHESTRATOR.md](ORCHESTRATOR.md); the full design is the rest of that file.

### Files

| File | Who writes | What is inside |
|---|---|---|
| `<project>/board.json` | `board` | `goal`, `items` (tasks `T<n>`: text, state todo/doing/blocked/done/dropped, owner/owner_name, assigned, since, why, outcome, after; facts `F<n>`: text, source, task, handled, ack), counters `next_t`, `next_f` |
| `<project>/orchestrator.json` and the mirror `~/.claude/longrun/projects/<key>/orchestrator.json` | `orchestrate start/stop` | skey, sid, name, pid, since, cwd, local; the watcher reads the mirror (a project under `~/Documents` is inaccessible to it) |
| `~/.claude/longrun/halt.json` | `halt`, `resume` | reason, at, by, local (empty = all projects) |
| `<session>/meta.json`, new fields | hooks | `running` {tool_use_id: tool, cmd, started}, `turn_started`, `waiting_since`, `waiting_what`, `ctx_tokens`, `ctx_model`, `ctx_window`, `ctx_at`, `ctx_warned`, `ctx_told`, `board_mtime`, `board_seen`, `asked` |
| `~/.claude/longrun/watch/state.json`, key `stuck` | the watcher | raised flags `<project key>:<skey>:<tool|wait|ask>` -> time; cleared when the condition goes away |
| `<project>/archive/board.md` | `board rm` | deleted tasks |
| `<session>/asks.json` | `ask`, the detached process `ask _wait` | questions `Q<n>`: q, options, default, free_text, state pending/answered/cancelled/expired/failed, answer, text, asked, answered, claimed (the asker is still waiting inline), delivered (socket / inbox:<file> / spool:<file>) |
| `~/.claude/longrun/ask.log` | the detached dialog processes | output and errors of osascript, zenity or kdialog |

### Commands

| Command | What it does |
|---|---|
| `board [ls [--all] [--facts]]` | goal, doing, blocked, next todo, counters; `--all` adds done/dropped, `--facts` lists the facts instead |
| `board goal "..."` | the project goal |
| `board add "..." [--after T3,T4] [--for WHO] [--wake]` | a task; `--for` assigns it to a session at once (a message to the inbox, `--wake` into the socket) |
| `board take T7 [--force]` | take; refused if the task is waiting on `--after` or another session is doing it |
| `board done T7 ["outcome"]`, `board block T7 "why"` | close / block; wake the orchestrator (the socket if it is alive, otherwise the inbox); `--quiet` does not wake |
| `board drop|release|edit|rm T7 [...]` | drop, return to todo, rewrite the text, delete |
| `board assign T7 WHO [--quiet] [--force]` | assign to a session: a `YOUR TASK` message into its socket (the turn starts immediately) or into the inbox |
| `board add --fact "..." [--task T7] [--source user\|review\|msngr\|watch\|session] [--wake]` | record something learned from outside; it reaches the orchestrator's inbox (`--wake` into the socket). A fact is an item of the same `board.json`, so since 0.6.0 it is a `board` subcommand, not a command of its own |
| `board ls --facts [--all]`, `board ack F3 ["decision"]` | the ones nobody handled yet; mark one handled with what was decided |
| `orchestrate [status]` | who the orchestrator is, halt, board, facts, sessions with flags |
| `orchestrate start [--goal "..."] [--force]`, `orchestrate stop [--force]` | take the role (one per project) / give it up |
| `halt "why" [--project]`, `resume` | forbid tools in all sessions (or only in this project) / lift |
| `ask "question" [--options "Yes,No"] [--default Yes] [--text] [--title T] [--wait SEC] [--expire MIN] [--icon note|caution|stop]` | a dialog above all windows (osascript from its own process with a sound on macOS, zenity or kdialog on Linux); the answer inline if it arrived within `--wait` (default `ask_wait_sec`), otherwise `PENDING Q<n>` and the answer as a turn into the socket or inbox; lines `ANSWER|CANCELLED|EXPIRED|FAILED Q<n>` |
| `ask ls`, `ask answer Q3 "..."` | this session's questions; record an answer the human gave in chat when the dialog went missing |
| `mcp` | a stdio MCP server with the tools `ask` and `notify`; `install.sh` registers it as `longrun` in user scope (`claude mcp add --scope user longrun -- ~/.local/bin/longrun mcp`) |
| `notify "text" [--title T]` | one desktop notification, the same call `halt` and a fired watch make; prints the program it went through, exit 1 when there was none |
| `notify --test` | send a probe and say whether the screen really showed it: on macOS the answer is read back from the Notification Center database, not guessed. `presented=0` means delivered and silently dropped, and the output then says how to fix it |

### What every session sees

In the digest: the line `ORCHESTRATOR: <name> [skey] alive|idle|stale|ended since ...`, the `BOARD` block, `YOUR TASK` for assigned tasks, `HALT in force` during a stop, flags in the `SESSIONS` lines. On every turn and after tools: `BOARD changes for you` (assigned and changed tasks, new facts on own tasks; own edits are not repeated), the warning `context Nk of the Mk auto-compact window` `ctx_warn_before` before the window, once per 20k of growth. The orchestrator additionally gets `role=orchestrator` in the header, the `FACTS unhandled` block and the list of duties. A session that asked a question via `ask` sees the `ASKED, waiting for the user` block until the answer, the others - the flag `asking the user Q3 12m` in its SESSIONS line.

### The watcher

Every tick after the checks, `stuck_scan`: for every project with an orchestrator mirror and a live role, for every session except the orchestrator, two rules - a tool running longer than `stuck_tool_min`, and waiting for a permission answer or an `ask` answer longer than `stuck_wait_min`. Both mean the same thing: this session is not moving and nobody inside it can tell. Three further rules were dropped in 0.6.0 - a turn over an hour (which is what a long normal turn looks like), three identical FAILs (the turn card already puts those in front of that session, with the command in it), and a context near the window (already sent to the session as a warning and to the orchestrator through `ctx_told`). All three are still shown as SESSIONS flags. If the session has a live pid but there is no shell-snapshot wrapper in the process tree, the `tool` flag is not raised (the meta is stale). Every flag is reported once per episode: `STUCK? <name> [skey]: ... Options: ...`, delivered into the socket (`wake_on_stuck`) or the inbox.

### Context window

`autocompact_window(model)`: `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, otherwise `autoCompactWindow` from `~/.claude/settings.json` (written by `/autocompact 300k`), otherwise the model's window (1M for Fable, Sonnet 5, Opus 5; 200k for the rest); never more than the model's window. Context size = `input + cache_read + cache_creation` of the last assistant reply from the transcript tail (256 KB), the same formula the status line uses.

### Dialog with the human

`ask` shows the dialog with the program the OS has (section 12). On macOS that is `osascript` from its own process: no Automation permission is needed, the window comes to the front by itself (verified 09.09.2026), Focus mode hides notifications, not windows; a `beep` before showing. Up to three options - `display dialog` buttons (a button named Cancel and Esc give `CANCELLED`), more - a `choose from list` list, `--text` adds a field. The question is registered in `asks.json` and the journal, the dialog is held by the detached process `longrun ask _wait Q<n>` (setsid, survives the end of the Bash and MCP call). The asker waits for the answer up to `--wait` and returns it inline; when that runs out it clears `claimed`, and the dialog process delivers the answer itself via `deliver_to`: the session's socket (the turn starts immediately, even mid-turn), otherwise the inbox, otherwise the spool. The race between them is closed by the shared session lock: the answer either goes inline or as a message, but is never lost. `--expire` (default 360 min) closes the dialog by itself (`giving up after`, for the list - the process timeout).

The MCP server `longrun mcp`: JSON-RPC over stdio, one line per message, no dependencies; the methods initialize, tools/list, tools/call, ping, anything else - error -32601; tool calls run in threads so that cancellation and a second call do not wait for the first. It finds the session by the parent pid in `~/.claude/sessions/<pid>.json` (the server is a child process of `claude`; walks up to six levels), the project by the session index, otherwise by cwd; without a project the dialog is shown inline without late delivery. Per the Claude Code docs: the default MCP tool timeout is about 28 hours, the idle timeout of a stdio server is 30 minutes without a reply, a call longer than 2 minutes in an interactive session goes to a background task; hence `wait_sec` is capped at 1500 s. During halt the `mcp__longrun__*` tools are not forbidden.

Environment variables for tests: `LONGRUN_ASK_FIXTURE=<json {"button","text","state"}>` replaces the dialog, `LONGRUN_ASK_FIXTURE_DELAY=<sec>` delays the answer, `LONGRUN_NO_UI=1` forbids real dialogs and notifications (without a fixture `ask` answers `FAILED`), `LONGRUN_NO_TIMER=1` forbids touching launchd, systemd and crontab, `LONGRUN_DESKTOP_DIR=<dir>` replaces the desktop app metadata directory.

---

## 12. Platform: macOS and Linux

Everything except four things is plain POSIX python with no dependencies, and works the same on both. The four things are decided at runtime, once, by what the machine actually has.

**The timer that runs the tick.** `install.sh` installs it (`--no-timer` skips it), and the first `watch add` installs it if it is missing; `longrun watch install` writes whichever the config key `watch_timer` says, and by default the one this OS provides:

| OS | What is created | Where | State |
|---|---|---|---|
| macOS | a launchd agent `com.longrun.watch`, `StartInterval`, `RunAtLoad` | `~/Library/LaunchAgents/com.longrun.watch.plist` | `launchctl print gui/<uid>/com.longrun.watch` |
| Linux with a systemd user manager | `longrun-watch.service` (`Type=oneshot`) plus `longrun-watch.timer` (`OnUnitActiveSec`, `OnBootSec=1min`), enabled with `--now` and started once immediately | `~/.config/systemd/user/` | `systemctl --user list-timers longrun-watch.timer`, `journalctl --user -u longrun-watch.service` |
| Linux without one (a container, WSL1, a bare `su`) | one line in the user's crontab, marked with a comment so `uninstall` removes exactly it and nothing else | `crontab -l` | `longrun watch status` |

A timer of any kind starts a check with an almost empty environment, which is why the PATH is snapshotted from a real shell into `watch/env.json` at `add` and `install` time; on Linux `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` are snapshotted too, so a notification from the tick can still reach the desktop. Interval accuracy: launchd catches up missed intervals on wake, `OnUnitActiveSec` is measured on `CLOCK_BOOTTIME` and behaves the same, cron simply has a floor of one minute. A systemd **user** timer only runs while the user has a session: on a server without `loginctl enable-linger <user>` it stops at logout, and `watch install` says so when linger is off.

**The dialog behind `ask` and `mcp__longrun__ask`.** macOS: `osascript`. Linux: `zenity`, else `kdialog`, and only when `DISPLAY` or `WAYLAND_DISPLAY` is set. Neither program can show buttons and a text field at once, so with `--text` on Linux the field wins and the button reported back is the default one. zenity maps the options onto `--question` (`--ok-label` is the default option, `--extra-button` the middle one), more than three onto `--list`, and honours `--expire` through its own `--timeout`; kdialog uses `--yesno` and `--menu`, and its expiry is the kill of the process. A machine with no dialog at all - a server, an ssh session, no zenity installed - is not an error state: `ask` returns `FAILED Q<n>` with the reason, and the skill tells the agent to ask in the chat instead.

**The desktop notification** behind `halt`, a fired watch and the MCP tool `notify`. It is optional on both systems and longrun depends on neither program: every message a notification would carry also reaches the session itself through its socket or inbox, so a machine with nothing installed is a supported configuration - all four suites run that way. The config key `notifier` pins the program; `auto` takes `terminal-notifier` whenever it is installed, otherwise `osascript` on macOS and `notify-send` on a Linux desktop, otherwise nothing at all - which is a normal state on a server, not an error: the message still reaches the session through its socket or inbox.

terminal-notifier comes first because of a macOS trap that is invisible from the outside. `osascript -e 'display notification'` posts on behalf of Script Editor, which holds no notification authorisation of its own (no `auth` key in `com.apple.ncprefs`), so macOS files the notification and draws nothing: verified here on 2026-09-10, where 25 of 25 osascript notifications sat in the Notification Center database with `presented = 0` while the Claude app's own notifications showed fine. No error is printed anywhere - `osascript` exits 0. terminal-notifier ships its own signed bundle, so it gets its own entry and its own permission; after `brew install terminal-notifier` the bundle has to be registered once (`lsregister -f` plus one `open`), otherwise it answers `Could not request notification permission`.

**The turn-end notification.** Claude.app sends one itself, but with `silent: true` and `interruptionLevel: "passive"` - which on macOS means the system files it into Notification Center without lighting the screen, playing a sound or drawing a banner. Only the other kind, `needs_input` ("Claude is waiting for your input"), goes out as `active` and pops. There is no setting for this: the app's own `notificationLevels` only chooses `off | badge | banner` and does not touch the interruption level. So `notify_turn_end` sends the loud version from the `Stop` hook. `unfocused` asks Launch Services (`lsappinfo front`, no Automation permission and no prompt, unlike the `System Events` route) which application is in front and stays quiet while that is Claude. A session running in a terminal cannot tell whose window is in front, so `unfocused` behaves like `always` there. Verified against Claude.app 2.1.260 on 2026-09-10.

**Important sessions.** Both gates above are global, and both have the same blind spot: while you work in one Claude session, the app is in front, so `unfocused` stays quiet about *every* session - including the long one you are actually waiting for. `longrun important` marks one session as the exception: the `Stop` hook notifies whatever `notify_turn_end` says and whoever is in front, and the notification's title is prefixed with `*` so it is recognisable among the others. The flag has three shapes - `on` (until dropped), `next` (one turn end) and `N` (a counter) - and lives in the session's own `meta.json`, next to the counters, which is what makes it survive a compaction, a `/clear` and a resume (the session key follows the resume chain, the CLI id does not). A counted flag is spent inside the same lock that writes the turn's meta, so two hooks racing cannot spend it twice, and every send is recorded in the session journal together with the program that delivered it - or with `NOT sent: no notifier here`, which is how a machine with no notifier says so instead of failing.

**The icon and the sender name.** Both come from the bundle that posted the notification, and macOS offers no way to override either per notification - terminal-notifier 3.1.0 dropped `-appIcon` and `-sender` for exactly that reason. Until 0.6.0 longrun built its own copy of terminal-notifier.app to get its own icon; that was removed as more moving parts than the icon was worth, so a banner now carries terminal-notifier's own name and icon.

**Where a click lands.** A longrun notification carries the deep link of the session it is about, so clicking it opens that session in the app rather than just raising the window: `claude://code/continue?session=local_<uuid>&source=desktop_action`. Claude.app registers the `claude` scheme itself and validates the parameter against `/^local_[A-Za-z0-9-]+/` - exactly the id longrun already stores as `desktop_id`, and the same URL the app builds for its own notifications. Only terminal-notifier can carry a click target (`-open`); osascript and notify-send have no equivalent and simply drop it. A session with no app entry (CLI-only, or the app has not written its metadata yet) gets no link and the notification is still sent.

`install.sh` asks whether to set notifications up (`--notify` / `--no-notify` answer in advance, and a run with no terminal to ask from skips them); after a yes it does all of this for you - on macOS it brew-installs terminal-notifier when it is missing, and says so; `--no-notify` skips the lot. `longrun notify --test` is the check: it prints the click target and sends a probe, and on macOS tries to read the `presented` flag back out of `~/Library/Group Containers/group.com.apple.usernoted/db2/db` instead of guessing. `presented=1` - the banner was really drawn; `presented=0` - delivered and dropped, and the output prints the fix. That database is in WAL mode and the system checkpoints it lazily, so it is copied with its `-wal` and the copy is opened read-write for sqlite to replay; the row can still be missing (the table holds what Notification Center currently has, and the system drops rows of its own accord), and then the command says the answer is unknown and asks you to look at the screen.


Smaller differences, all handled the same way: the desktop app's metadata lives under `~/Library/Application Support/Claude` on macOS and `$XDG_CONFIG_HOME/Claude` on Linux (no desktop app at all simply means no sidebar titles - addressing by session id keeps working); a spawned check gets `LANG=en_US.UTF-8` on macOS and `LANG=C.UTF-8` on Linux; the PATH snapshot also looks into `/home/linuxbrew/.linuxbrew/bin` and `/usr/local/sbin`.
