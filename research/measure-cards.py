#!/usr/bin/env python3
"""O1: how often does a turn that wrote nobody's edits still carry something worth writing?

The turn card only fires when a turn edited at least `nudge_edit_tools` files or failed a command. The
open question is whether that gate silences turns that had something to record - analysis, review, a
decision taken in conversation.

This answers it from data that already exists, with no model in the loop, by reading the question
backwards: instead of judging whether a turn SHOULD have written a note, count the turns that DID. A
note the session wrote by itself is the strongest available evidence that the turn was worth asking
about. So: of every turn that wrote one, how many would the card have been silent in?

Turns are segmented at real user messages in the transcript (tool results and meta rows are not turns).
Subagent sidechains are skipped: they have their own card-less loop.

Usage: python3 research/measure-cards.py [--projects-dir ~/.claude/projects] [--min-edits 6]
"""
import argparse
import collections
import glob
import json
import os
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
WRITE_CMDS = ("longrun add", "longrun doc add", "longrun doc touch", "longrun replace", "longrun stale")
# What the PostToolUse matcher in hooks.json fires on. `Read` is deliberately not in it - a hook is a
# process per call. Since 0.6.3 `PostToolBatch`, which has no matcher, counts the calls PostToolUse does
# not, so the size of a turn is ALL of its calls again and the `tools` table below is the one the code
# uses. The `hooked` table is kept because it is what the threshold was originally chosen against.
SEEN_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "PowerShell", "Agent", "Task",
              "Workflow", "Grep", "Glob", "WebSearch"}


def seen(name):
    return name in SEEN_TOOLS or (name or "").startswith("mcp__")


def is_interrupt(block):
    """A command the user stopped is not a command that failed, and `PostToolUseFailure` skips it."""
    c = block.get("content")
    return "interrupt" in (c if isinstance(c, str) else json.dumps(c)).lower()


def blocks(row):
    c = (row.get("message") or {}).get("content")
    return c if isinstance(c, list) else []


def is_real_user_turn(row):
    """A prompt the human typed, not a tool result and not the harness talking to itself."""
    if row.get("type") != "user" or row.get("isMeta") or row.get("isSidechain"):
        return False
    c = (row.get("message") or {}).get("content")
    if isinstance(c, str):
        return bool(c.strip()) and not c.lstrip().startswith("<system-reminder>")
    return isinstance(c, list) and not any(b.get("type") == "tool_result" for b in c if isinstance(b, dict))


class Turn:
    __slots__ = ("edits", "fails", "notes", "tools", "hooked", "gate")

    def __init__(self):
        self.edits = self.fails = self.notes = self.tools = self.hooked = 0
        self.gate = False   # was the card's REAL gate open in this turn - see scan()

    def carded(self, min_edits):
        """The gate as this script used to model it: edits made in THIS turn.

        Kept only to be compared against `gate`. It is not what the code does, and the difference is not
        academic: `edit_tools_since_note` and `fails_since_note` accumulate across turns and are reset by
        a note write, so a read-only turn that follows an editing turn nobody wrote anything down in IS
        carded, and this model calls it silent."""
        return (self.edits or self.fails) and (self.edits >= min_edits or self.fails)


def scan(path, min_edits):
    """Turns of one transcript, each with the card's real gate evaluated at the moment it matters.

    For a turn that wrote a note that moment is just before the write - what the counters stood at when
    the session decided the turn was worth recording. For a turn that wrote nothing it is the end of the
    turn, which is when `UserPromptSubmit` reads them for the card."""
    turns, cur, pending = [], None, {}
    es = fs = 0        # edit_tools_since_note / fails_since_note: session-wide, reset by a note write
    gate_at_note = None
    try:
        fh = open(path, errors="replace")
    except OSError:
        return turns
    with fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("isSidechain"):
                continue
            if is_real_user_turn(row):
                if cur is not None:
                    cur.gate = gate_at_note if cur.notes else (es >= min_edits or fs > 0)
                    turns.append(cur)
                cur, gate_at_note = Turn(), None
                continue
            if cur is None:
                continue
            for b in blocks(row):
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    name, ti = b.get("name"), (b.get("input") or {})
                    cur.tools += 1
                    if seen(name):
                        cur.hooked += 1
                    if name in EDIT_TOOLS:
                        cur.edits += 1
                        es += 1
                    cmd = str(ti.get("command") or "")
                    if name in ("Bash", "PowerShell"):
                        pending[b.get("id")] = cmd
                        if any(w in cmd for w in WRITE_CMDS):
                            if gate_at_note is None:
                                gate_at_note = es >= min_edits or fs > 0
                            cur.notes += 1
                            es = fs = 0
                elif b.get("type") == "tool_result" and b.get("is_error") and not is_interrupt(b):
                    if b.get("tool_use_id") in pending:
                        cur.fails += 1
                        fs += 1
    if cur is not None:
        cur.gate = gate_at_note if cur.notes else (es >= min_edits or fs > 0)
        turns.append(cur)
    return turns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--min-edits", type=int, default=6, help="nudge_edit_tools")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.projects_dir, "*", "*.jsonl")))
    if not files:
        sys.exit("no transcripts under %s" % a.projects_dir)

    per_file, stat = {}, collections.Counter()
    for f in files:
        t = scan(f, a.min_edits)
        if t:
            per_file[f] = t
    # A session that never wrote a note may simply not have had longrun installed. Both populations are
    # reported: the honest denominator for "would the card have asked" is the sessions that do write.
    active = {f: t for f, t in per_file.items() if any(x.notes for x in t)}

    def tally(pop, label):
        st = collections.Counter()
        for turns in pop.values():
            for t in turns:
                st["turns"] += 1
                if t.notes:
                    st["wrote"] += 1
                    st["wrote_carded" if t.gate else "wrote_silent"] += 1
                    st["wrote_carded_perturn" if t.carded(a.min_edits) else "wrote_silent_perturn"] += 1
                    if not (t.edits or t.fails):
                        st["wrote_no_activity"] += 1
                elif t.gate:
                    st["carded_no_note"] += 1
        print("\n== %s: %d transcripts, %d turns" % (label, len(pop), st["turns"]))
        if not st["turns"]:
            return
        w = st["wrote"]
        print("   turns that wrote something down:            %6d  (%.1f%% of turns)" % (w, 100.0 * w / st["turns"]))
        if w:
            print("   ...of those, the card WOULD have asked:     %6d  (%.1f%%)" % (st["wrote_carded"], 100.0 * st["wrote_carded"] / w))
            print("   ...of those, the card would be SILENT:      %6d  (%.1f%%)  <- the gap O1 is about"
                  % (st["wrote_silent"], 100.0 * st["wrote_silent"] / w))
            print("      of which with no edit and no failure at all: %d" % st["wrote_no_activity"])
            # The gate accumulates across turns; modelling it per turn understates the gap, and that is
            # the direction this script used to be wrong in.
            print("   (gate modelled per turn instead, as this script used to: %d asked / %d silent = %.1f%% silent)"
                  % (st["wrote_carded_perturn"], st["wrote_silent_perturn"],
                     100.0 * st["wrote_silent_perturn"] / w))
        print("   turns the card asked about and got nothing: %6d" % st["carded_no_note"])

    tally(per_file, "every transcript")
    tally(active, "transcripts where longrun was in use (>=1 note written)")

    # How much a lower gate would cost: turns with some edits but under the threshold.
    near = collections.Counter()
    for turns in active.values():
        for t in turns:
            if t.notes or t.fails:
                continue
            if 0 < t.edits < a.min_edits:
                near["under_gate"] += 1
            elif t.edits == 0 and t.tools:
                near["read_only"] += 1
    print("\n== what lowering the gate would add (sessions in use, turns that wrote nothing)")
    print("   turns with 1..%d edits, no failure:  %6d   <- a lower nudge_edit_tools would card these"
          % (a.min_edits - 1, near["under_gate"]))
    print("   turns with tools but no edit at all: %6d   <- only a different rule reaches these" % near["read_only"])

    # If read-only turns are to be carded at all, the rule must separate the productive ones from the
    # 2-call ones. Length is the only signal a hook has before the fact, so: does it separate them?
    print("\n== read-only turns (0 edits, 0 failures) by how much work was in them, sessions in use")
    # Fine around the threshold on purpose. With 1-2 / 3-5 / 6-10 buckets the table below answered "6" and
    # "4" with exactly the same number, because both fall on a bucket edge - so the reading that the
    # threshold had been measured was more than the table could carry.
    buckets = [(1, 2), (3, 3), (4, 4), (5, 5), (6, 7), (8, 10), (11, 20), (21, 10 ** 6)]

    def table(attr, title):
        print("\n   %s" % title)
        print("   %-14s %8s %8s %8s" % ("calls", "wrote", "silent", "note rate"))
        rows = {b: [0, 0] for b in buckets}
        for turns in active.values():
            for t in turns:
                n = getattr(t, attr)
                if t.edits or t.fails or not n:
                    continue
                for b in buckets:
                    if b[0] <= n <= b[1]:
                        rows[b][0 if t.notes else 1] += 1
                        break
        cum_w = cum_s = 0
        for b in buckets:
            w, s = rows[b]
            label = "%d-%d" % b if b[1] < 10 ** 6 else "%d+" % b[0]
            print("   %-14s %8d %8d %8s" % (label, w, s, ("%.0f%%" % (100.0 * w / (w + s))) if w + s else "-"))
            cum_w, cum_s = cum_w + w, cum_s + s
        print("   %-14s %8d %8d %8s" % ("all", cum_w, cum_s, ("%.0f%%" % (100.0 * cum_w / (cum_w + cum_s))) if cum_w + cum_s else "-"))
        return rows

    rows = table("tools", "counted in ALL tool calls - what `turn_tools` counts since 0.6.3:")
    table("hooked", "counted in PostToolUse calls only - what it counted before, when Read was invisible:")
    print("\n   a read-only card at N calls would reach, per threshold:")
    for n in (3, 4, 5, 6, 8):
        w = sum(v[0] for b, v in rows.items() if b[0] >= n)
        s = sum(v[1] for b, v in rows.items() if b[0] >= n)
        print("     >= %-3d  %4d silent turns carded, in a band whose note rate is %s"
              % (n, s, ("%.0f%%" % (100.0 * w / (w + s))) if w + s else "-"))


if __name__ == "__main__":
    main()
