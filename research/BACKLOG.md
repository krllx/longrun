# Backlog

Open items moved out of the shared notes on 2026-09-16: the digest had reached 9791 of its
9800-byte budget, and anything added past that is dropped silently. The originals stay in
`.longrun/archive/notes.md` (`longrun recall <term>` finds them). One pointer note in the
shared notes replaces them all.

Source of every item below: the user, unless stated otherwise. Dates are when it was raised.

## B1. The digest drops the NEWEST notes when it overflows (bug, 09-15)

`build_digest()` sheds optional blocks in a fixed order and then hard-clips the rendered tail
at `inject_max_bytes`. Notes render oldest-first, so what the clip eats is the newest own
notes and then the newest shared ones - the entries most likely to matter.

Worse, the two safety valves never fire first: `notes_warn_pct` (80) and
`notes_autoprune_pct` (90) are measured against `notes_max_bytes` (15000 in this project),
i.e. 12000 and 13500 bytes - far above the ~9k the digest can actually inject.

Fix: shed the oldest/cheapest entries to fit instead of cutting the tail, and validate the
budgets against each other in `config set` (a `notes_max_bytes` above `inject_max_bytes`
is a misconfiguration, not a preference).

## B2. Keep the SESSIONS block live (feature, 09-15)

Today the block is a SessionStart-only snapshot. `UserPromptSubmit` injects the shared-notes
delta, the inbox, the board delta and the context warning - sessions are not among them, so a
window opened later never shows up until a compaction, a resume or a manual `longrun status`.

Want a per-turn sessions delta: a session appeared, a session ended, what each is doing now.
On change only, with its own byte budget like `shared_delta_max_bytes`.

## B3. A first-class DOCS layer (feature, 09-15)

Long material belongs in files under the project, with a one-line pointer and summary in the
shared notes, loaded only on demand. Today this exists only as prose ("put long material in a
file and reference it", printed when `add` refuses a long entry) and as note text: no index,
no staleness check, nothing that nudges a session to load one.

This is the lazy-loading half of the original design (see `MANIFESTO.ru.md`, points 2 and 4)
and it is still missing. Both this backlog file and the manifesto were filed by hand, which is
the demonstration.

## B4. Drop archived and deleted sessions from the table (feature, 09-16)

`gc` archives a session directory only after `session_dead_days` (7) of silence, so a window
the user archived or deleted in the desktop app today keeps showing in the SESSIONS block and
in `longrun status` for a week. Read the app's session metadata for archived/deleted and skip
those rows.

## B5. Mark a note stale instead of deleting it (feature, 09-16)

Something like `longrun stale n12 [why]`: a thumbs-down that records "probably obsolete" so a
later sweep - `gc`, the watcher timer, another session, or the user on request - clears the
marked ones.

What exists today is age- and tag-based only: `age_notes()` archives non-pin entries older
than `notes_max_age_days` (14), and the autoprune above `notes_autoprune_pct` takes `todo` and
`ctx` entries only. Nothing lets a session say "this particular fact stopped being true".

## D1. Positioning: lead with the manifesto, not with compaction (decision, 09-16)

The README leads with "Notes that survive compaction", which is the weakest differentiator the
project has - and it got weaker when 0.5.1 taught the PreCompact hook to steer the summariser
itself. The lead should come from `MANIFESTO.ru.md`: the project keeps its own state on disk,
every session sees the project and the other sessions, work can be handed to a more relevant
session, waiting is reliable and free, and one session can drive the rest and call the human.

Where the neighbours actually sit (checked against the Claude Code 2.1.238 binary, where the
ProposeGoal tool is described as "Propose a session goal condition, with one-keypress user
approval; once set, Claude keeps working until a separate evaluator confirms it is met"):

- **Workflows and subagents** - parallelism inside one turn. Ephemeral children, a join, schema
  validation, retries; no human inside, nothing survives the turn.
- **`/goal`** - autonomy inside one session, toward one condition, with a real evaluator.
- **longrun** - continuity and coordination across sessions and across time; the unit of work is
  a window a human can sit in.

Honest consequence: the orchestrator overlaps `/goal` most, and loses on single-session
autonomy - `/goal` has an evaluator, we have a board and persuasion. What stays ours by
construction: several windows instead of one, a board between them, state that outlives every
turn, waiting that costs no tokens and cannot be slept through, and a dialog that reaches the
human on top of whatever they are doing.

So the orchestrator should be sold as "coordinator of several windows plus the line to the
human", not as "autonomous driving toward a goal", and the skill should say plainly: one
session to a condition -> `/goal`; decompose work inside one turn -> workflows; several windows
over hours and days -> longrun.

Applies to: README.md and its four translations, the SKILL.md description, the first page of
the course. Not started - the promo window is 15.09-05.10.2026, so this is the urgent half.
