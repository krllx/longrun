# Memory layers and Codex search verification

Verified on 2026-10-01. Requirements: `MANIFESTO.ru.md`, remaining O1/O2 in `BACKLOG.md`.

## Loading rule

Shared `pin` and `doc` entries form the resident layer. Other shared entries are on demand.
`longrun memory keep|defer|auto n12 [n13 ...]` changes the shared choice; `memory ls` shows it.
Overrides live in `memory.json`; existing text and IDs remain in `NOTES.md`. Own notes stay in
the active conversation's context. Selection does not change ageing or archive retention.

The protocol keeps standing constraints and useful pointers resident, loads investigations by topic,
and asks the agent to review the choice when the task changes or housekeeping/budget reminders arrive.
Changed deferred records are announced with an 80-character preview and a recall command. Resident
changes are delivered in full; residency and tag changes also reach peers through the existing deltas.

## Context comparison

The offline fixture describes this actual project's components: hooks, failure tracking, document
stamps, inbox delivery, watches, compaction and coordination. It contains 21 shared entries (four
resident, 17 deferred) and copies of `docs/REFERENCE.md` and `docs/ORCHESTRATOR.md`. It has no live
session history, dialogs, scheduler or API connections. This is a realistic project fixture, not a
measurement of a live client or an import of the user's working store.

| Startup digest | Before, CLI at `61092111ae5c0341bfad077a9510875918e88476` | After |
| --- | ---: | ---: |
| UTF-8 bytes | 3632 | 1136 |
| Estimated tokens (`est_tokens`, not a tokenizer) | 908 | 284 |

The digest shrank by 68.7%. `watch_timer` is absent at startup, but `recall watch_timer` returns it
and a literal `rg watch_timer` search produces the saved explanation through `recall_hint`.

Reproduce against the preceding implementation:

```bash
git show 61092111ae5c0341bfad077a9510875918e88476:skill/longrun/scripts/longrun > /tmp/longrun-before
python3 research/measure-memory.py --against /tmp/longrun-before
```

Without `--against`, the script performs an all-resident ablation of the current code. That keeps the
formatting constant and measures the selection rule separately; it is also an automated test.

## Automated evidence

- `tests/run.sh`: 293 checks, including the read-only turn card, budgeting, recall, compaction and
  the unchanged Claude Code search behavior. Legacy full-load fixtures explicitly keep their notes
  so they still exercise budget shedding and mute/unmute instead of passing on an empty shared layer.
- `tests/scenarios.sh`: 47 goal checks, including peer delivery at the turn boundary and mid-turn.
- `tests/orchestrator.sh`: 53 checks.
- `tests/ask.sh`: 27 checks.
- `tests/codex.py`: 23 tests. New coverage includes both clients at startup/resume/compaction,
  preservation of note bytes, reversible shared selection, deferred shared `ctx`, change delivery,
  context reduction, real-shaped Codex `PostToolUse` payloads, quoted/flagged/multi-expression `rg`,
  exit code 1, unsafe/unrelated commands, repeat suppression and the two-hint limit.
- `tests/course.sh`: 21 checks, zero skipped; all course locales include the new selection example.
- `tests/mutations.py`: nine of nine temporary mutations detected by assertion failures. Disabled
  mechanisms: startup selection, explicit overrides, deferred hint scanning, Codex rg extraction,
  residency-change delivery, abbreviated deferred deltas, empty-rg result handling, command identity
  guard and shell syntax guard. Production code is never rewritten by the mutation harness.

Before the fix, `CodexTests.test_codex_rg_hint_payload` failed because the handler returned an empty
string. Its payload has `tool_name=exec_command`, `tool_input.cmd="rg -n 'payment_callback' src"`
and a structured `tool_response`. The same handler test now returns the deferred note and a recall
command. All suites use isolated stores; scheduler/UI actions are disabled and API clients are stubs
or fixtures. Unix-socket tests require permission to bind a local test socket outside the restrictive
shell sandbox; that does not connect to the running clients.

Python sources parse with the Python 3.9 grammar. Claude frontmatter parses as YAML; the installed
Codex entrypoint passes the skill validator. The generic Codex validator does not accept Claude's
existing `argument-hint` field, so it is applied to the actual Codex entrypoint, not by removing a
valid Claude field.

## Limits and live-client boundary

Hints remain heuristic and bounded: five-character minimum terms, rejection of terms matching more
than six lines, two hints per turn, a bounded history of term/file pairs, and a 600 kB scan cap.
Unknown rg flags, wrappers, expansion, pipelines, redirects and malformed quoting stay silent.
Only literal query arguments are used; paths and option values are not query expressions. Explicit
`recall` and `notes --shared` remain the route when a hint is absent or its excerpt is too short.
The resident layer still obeys the digest budget; deferring does not increase the notes file cap.

O1 is implemented, with its real limits: a read-only card appears at the following turn boundary,
requires at least six calls and no note, and still obeys the common reminder window. Pure conversation
with no tool calls is not measured and the hook cannot judge whether a conclusion is valuable.

No new live-client installation, hook-trust UI, rendered hint delivery or natural compaction check
was performed. The current checkout is the reviewed result; installed client copies were not changed.
