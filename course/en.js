/* English strings for the scenario data: overrides titles, captions, node labels and file descriptions of window.COURSE. Terminal output is shared. */
(function (C) {
  const N = C.N;
  Object.assign(N.U, { title: 'Human', sub: ['terminal, chat, dialog'] });
  Object.assign(N.A, { title: 'Session A', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.B, { title: 'Session B', sub: ['Claude Code', 'longrun hooks'] });
  Object.assign(N.P, { title: 'Project shop/.longrun', sub: ['NOTES.md  shared', 'inbox/  board.json', 'archive/'] });
  Object.assign(N.SA, { title: 'own of A', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.SB, { title: 'own of B', sub: ['notes.md', 'journal, meta'] });
  Object.assign(N.L, { title: 'timer, every 5 min', sub: ['watch, watcher, budget'] });
  Object.assign(N.G, { title: '~/.claude/longrun', sub: ['watch/, halt.json'] });
  Object.assign(N.D, { title: 'osascript dialog', sub: ['in front of every window'] });

  C.PROJ.label = 'shop/.longrun/  (shared, inside the project)';
  const PF = {
    'NOTES.md': ['Shared notes [n1], [n2]... one line each, with the author. Budget 5000 bytes.', 'Written by the agent: add --shared, rm, replace, prune --shared'],
    'config.json': ['Project settings: hq mode, budgets, thresholds.', 'init; longrun config set'],
    'state.json': ['Counters for note and task ids.', 'CLI'],
    'inbox/<msg>.md': ['A message for a session that is not running now. Delivered ones move to inbox/.archive/.', 'send, watch, board, ask; read by the recipient\'s hooks'],
    'archive/precompact/<sid>-<time>.md': ['Snapshot before compaction: the user\'s last requests, edited files, recent FAILs. The HANDOFF block (a hand-over to yourself after compaction) is built from it.', 'PreCompact hook'],
    'archive/compact/<sid>-<time>.md': ['The compaction summary verbatim. longrun recall finds them.', 'PostCompact hook'],
    'board.json': ['The orchestrator\'s board: goal, tasks T<n>, facts F<n>.', 'board, fact'],
    'orchestrator.json': ['Who holds the orchestrator role and with what goal.', 'orchestrate start/stop'],
  };
  C.OWN.label = '~/.claude/longrun/sessions/shop/<session>/  (own, outside the repo)';
  const OF = {
    'aaaaaaaa/meta.json': ['Turn and call counters, cwd, last answer, what of the shared notes was already shown, telemetry (running tool, waiting).', 'hooks on every event'],
    'aaaaaaaa/journal.md': ['Milestones (longrun log) and mechanical lines: start, end, failed commands, compactions, sends.', 'hooks and longrun log'],
    'aaaaaaaa/notes.md': ['Own notes [s1], [s2]... Budget 3000 bytes.', 'the agent: add, rm, replace, prune'],
    'aaaaaaaa/asks.json': ['Questions this session asked the user: Q<n>, state, answer.', 'longrun ask'],
    'bbbbbbbb/meta.json': ['The same for session B.', 'hooks'],
    'bbbbbbbb/journal.md': ['Journal of session B.', 'hooks, longrun log'],
    '_index/<cli sid>.json': ['CLI id -> project and session key. This is how a resume under a new id finds the old directory.', 'SessionStart hook'],
  };
  C.GLOB.label = '~/.claude/longrun/  (global)';
  const GF = {
    'watch/w1.json': ['One deferred check: what to check, whom to tell and what, when it expires.', 'watch add; the timer tick updates it'],
    'halt.json': ['Stop for every session of every project: who, when, why.', 'halt / resume, the budget watcher'],
    'budget.json': ['Samples of the 5-hour window and the plan (20% per hour).', 'the watcher every 5 minutes'],
  };
  [[C.PROJ, PF], [C.OWN, OF], [C.GLOB, GF]].forEach(([r, m]) => r.files.forEach(f => { if (m[f.path]) { f.what = m[f.path][0]; f.who = m[f.path][1]; } }));

  function steps(sc, list) { list.forEach((t, i) => { const s = sc.steps[i]; if (!s) return; s.title = t[0]; s.who = t[1]; s.caption = t[2]; }); }
  steps(C.s1, [
    ['The folder becomes a project', 'human or agent', 'Once, in the project folder, the one open in Claude Code. A <b>.longrun/</b> directory appears: that is the "project", the shared memory of every session in this folder.'],
    ['Session A starts: the SessionStart hook prints the digest', 'hook', 'The hook finds the project (up the tree to .longrun/), creates the session directory outside the repo and prints a digest into the model\'s context. Empty so far.'],
    ['A dead end: the agent writes it down for itself', 'agent', 'A test hung, the cause is found. Compaction loses this first, so one line goes to disk right away. Without <code>--shared</code> the note is own: <b>[s1]</b>.'],
    ['A fact for everyone: into the shared notes', 'agent', 'The PR number and the type decision are needed by any session of the project. <code>--shared</code> puts them into the project\'s NOTES.md: <b>[n1]</b>, <b>[n2]</b>, with the author label.'],
    ['A milestone: into the journal, not the notes', 'agent', 'Progress ("tests green", "PR opened") goes to the session journal. Notes are for what cannot be re-derived; the journal is the timeline.'],
    ['Compaction: the mechanics snapshot and archive', 'hooks', 'The context overflowed, Claude Code squeezes the history into a summary. <b>PreCompact</b> saves a snapshot (the user\'s last requests, edited files, FAILs), <b>PostCompact</b> archives the summary verbatim. The model does nothing here.'],
    ['After compaction: the notes come back into the context', 'hook', 'SessionStart again, now with <code>source=compact</code>. The digest prints the shared and own notes and the journal tail. The Redis dead end is <b>back in the context</b>, even if the summary dropped it.'],
    ['A detail is missing: recall, not re-exploration', 'agent', 'The search covers the shared and own notes of every session, the journals, archived summaries and the project\'s transcripts. This first, re-reading the code only then.'],
  ]);
  steps(C.s2, [
    ['Session B opens in the same folder', 'hook', 'B has done nothing yet, but already knows the PR number, the Decimal decision and that A works nearby. That is the <b>SESSIONS</b> block: who is there, alive or not, how many own notes, what each did last.'],
    ['B learns a fact about the environment and shares it', 'agent B', 'The Stripe key is not where the env file says. It cost effort and everyone needs it: <code>--shared -t fact</code>.'],
    ['A\'s next turn: only the difference arrives', 'hook', 'The <b>UserPromptSubmit</b> hook compares NOTES.md with what A has already seen and prints the delta: <code>+</code> added, <code>~</code> rewritten, <code>-</code> removed. A session\'s own lines are never shown back to it.'],
    ['Who does what: status', 'agent', 'All from state files, without reading transcripts: name, alive or not, own notes, calls, compactions, failures, last answer.'],
    ['The budget is hard: add refuses, prune cleans', 'agent', 'Shared notes: 5000 bytes, own: 3000. A full file does not silently evict old lines: <code>add</code> refuses and names the cheapest entries to drop. The habit: <code>rm</code> what is done, <code>replace</code> instead of a second line, <code>prune</code> when the digest says PRUNE NEEDED.'],
  ]);
  steps(C.s3, [
    ['A hands work to B: the recipient is stopped', 'agent A', 'The recipient is named the way the human sees it: the sidebar title, a registry name or an id prefix. B is not running now, so the text lands as a file in the project\'s <b>inbox</b>.'],
    ['B wakes up: the message arrives as a turn', 'hook', 'The first hook of B (a turn, a tool call or a start) takes the file from the inbox and prints it into the context. For the model it is a request from a peer, not from the human: its permissions stay its own.'],
    ['And if B is running right now: the socket', 'CLI', 'A running session listens on a unix socket. The text goes there and shows up in B as a user turn between tool calls, no inbox. <code>--resume</code> wakes a stopped session through <code>claude -p --resume</code>.'],
    ['Waiting for an event: watch instead of polling', 'agent A', '"Check in two hours", "when the PR merges": no sleep loops, no reminders to the human. A deterministic check is registered. <code>add</code> tries it once right away: already true means nothing is registered, act now.'],
    ['The timer checks every 5 minutes, no model', 'timer', 'A tick costs zero tokens. The condition is not met: the record is updated and that is all. A laptop asleep catches up on wake. Three hard errors in a row or an expired deadline give one message "broken" or "expired".'],
    ['The condition is met: a message to the recipient', 'timer', 'The tick delivers the <code>--then</code> text the same ways as <code>send</code>: into the socket of a running session or into the inbox. The session reads "From longrun watch w1" and does what it says. It wrote that text itself, maybe before a compaction.'],
  ]);
  steps(C.s4, [
    ['A takes the orchestrator role', 'agent A, on the human\'s word', 'One session per project drives the goal. It gets the list of duties and <b>polls nothing</b>: events wake it. A second session is refused with the holder\'s name.'],
    ['The board: tasks and hand-outs', 'orchestrator', 'Tasks T<n> with states todo / doing / blocked / done / dropped. <code>assign</code> puts a task into a live session\'s socket, or into the inbox of a stopped one.'],
    ['B receives the task as a turn', 'hook', 'A worker session needs only three commands: <code>take</code>, <code>done</code>, <code>block</code>. It learns nothing else.'],
    ['B works and closes the task; a fact from outside', 'agent B', '<code>done</code> and <code>block</code> wake the orchestrator. A reviewer asked to rename a field: that is a <b>fact from outside</b>. The rule: record first (<code>fact</code>), decide second. The fact goes to the orchestrator too.'],
    ['The orchestrator wakes up and disposes', 'orchestrator', 'Reads the board and the facts, not transcripts: its own context must stay small. Every fact is closed explicitly: relayed, re-planned or asked the user.'],
    ['Telemetry without tokens: flags in SESSIONS', 'hooks and the watcher', 'The PreToolUse, PostToolUse, Stop, PermissionRequest and Notification hooks write into meta.json when a tool started and ended and whether the session waits for a permission. The watcher (the timer) compares with the thresholds every 5 minutes and reports to the orchestrator once per episode.'],
    ['Stop everyone: halt', 'orchestrator, on the human\'s word', 'The halt.json file is global. The <b>PreToolUse</b> hook of every session answers with a refusal and the reason; the model sees it and tells the human what it was about to do. Only the human lifts it, in words, in the conversation: <code>longrun resume</code>.'],
    ['A question to the human in front of every window', 'agent B', 'Only for what cannot wait: a confirmation, an access, an action only the human can take. The dialog is drawn by osascript from a separate process: on top of every window, with a beep, no permissions needed. An answer within 90 seconds comes back inline.'],
    ['The human is away: the answer arrives later as a turn', 'waiting', 'After 90 seconds the command returns PENDING and the session goes on. The dialog stays open (6 hours by default); the click goes into the session\'s socket or its inbox. Cancel, Esc or expiry: CANCELLED / EXPIRED, the question is not repeated but put on the board.'],
    ['The 5-hour window budget', 'the watcher', 'Every 5 minutes the watcher reads the window usage (the usage endpoint with the Claude Code token) and compares with the plan: 20% per hour. A 1.5x breach: halt for every project, a report to the orchestrator, a dialog to the human with Keep stopped / Resume all.'],
  ]);
  /* Russian comment lines inside terminal panels */
  const TERM = {
    '# SessionStart (source=startup) -> в контекст модели:': '# SessionStart (source=startup) -> into the model context:',
    '# PreCompact (trigger=auto), PostCompact -> файлы, вывода в контекст нет': '# PreCompact (trigger=auto), PostCompact -> files, nothing printed into the context',
    '# SessionStart (source=compact) -> в контекст модели:': '# SessionStart (source=compact) -> into the model context:',
    '# SessionStart в сессии B:': '# SessionStart in session B:',
    '# UserPromptSubmit в сессии A -> в контекст:': '# UserPromptSubmit in session A -> into the context:',
    '# UserPromptSubmit в сессии B -> в контекст:': '# UserPromptSubmit in session B -> into the context:',
    '# у адресата это выглядит так:': '# what the recipient sees:',
    '# другие проверки: pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'': '# other checks: pr-merged 15470896 | file /path | http URL | cmd \'/abs/path ...\'',
    '# 13:05, в контексте сессии A:': '# 13:05, in the context of session A:',
    '# UserPromptSubmit в B:': '# UserPromptSubmit in B:',
    '# строки SESSIONS в дайджесте оркестратора (пример):': '# SESSIONS rows in the orchestrator digest (example):',
    '# что делает оркестратор: longrun send сессии, или предлагает человеку interrupt': '# what the orchestrator does: longrun send to the session, or proposes an interrupt to the human',
    '# PreToolUse в сессии B (Bash "pytest") -> Claude Code:': '# PreToolUse in session B (Bash "pytest") -> Claude Code:',
    '# ... на экране диалог с кнопками Да / Нет, человек нажимает Да': '# ... a dialog with Да / Нет buttons on screen, the human clicks Да',
    '# то же самое из MCP: тул mcp__longrun__ask (сервер `longrun`, регистрирует install.sh)': '# the same through MCP: the mcp__longrun__ask tool (server `longrun`, registered by install.sh)',
    '# ... позже, в контексте B:': '# ... later, in the context of B:',
    '# при стопе: HALT + уведомление macOS + диалог Keep stopped / Resume all; `longrun resume` снимает и усыпляет правило до сброса окна': '# on a stop: HALT + a macOS notification + the Keep stopped / Resume all dialog; `longrun resume` lifts it and snoozes the rule until the window resets',
  };
  [C.s1, C.s2, C.s3, C.s4].forEach(sc => sc.steps.forEach(s => (s.term || []).forEach(t => { if (t.dim && TERM[t.dim]) t.dim = TERM[t.dim]; })));
  /* the ask dialog buttons in scenario 4 */
  C.s4.steps.forEach(s => (s.term || []).forEach(t => ['cmd', 'dim', 'out'].forEach(f => {
    if (typeof t[f] === 'string') t[f] = t[f].replace(/Да,Нет/g, 'Yes,No').replace(/Да \/ Нет/g, 'Yes / No').replace(/Да/g, 'Yes').replace(/Нет/g, 'No');
  })));
})(window.COURSE);
