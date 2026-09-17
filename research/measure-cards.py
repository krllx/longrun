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
# What the PostToolUse matcher in hooks.json actually fires on. `Read` is deliberately not in it - a hook
# is a process per call - so a threshold in "tool calls" has to be read in these, not in all of them.
SEEN_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "PowerShell", "Agent", "Task",
              "Workflow", "Grep", "Glob", "WebSearch"}


def seen(name):
    return name in SEEN_TOOLS or (name or "").startswith("mcp__")


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
    __slots__ = ("edits", "fails", "notes", "tools", "hooked")

    def __init__(self):
        self.edits = self.fails = self.notes = self.tools = self.hooked = 0

    def carded(self, min_edits):
        return (self.edits or self.fails) and (self.edits >= min_edits or self.fails)


def scan(path, min_edits):
    turns, cur, pending = [], None, {}
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
                    turns.append(cur)
                cur = Turn()
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
                    cmd = str(ti.get("command") or "")
                    if name in ("Bash", "PowerShell"):
                        pending[b.get("id")] = cmd
                        if any(w in cmd for w in WRITE_CMDS):
                            cur.notes += 1
                elif b.get("type") == "tool_result" and b.get("is_error"):
                    if b.get("tool_use_id") in pending:
                        cur.fails += 1
    if cur is not None:
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
                    st["wrote_carded" if t.carded(a.min_edits) else "wrote_silent"] += 1
                    if not (t.edits or t.fails):
                        st["wrote_no_activity"] += 1
                elif t.carded(a.min_edits):
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
    buckets = [(1, 2), (3, 5), (6, 10), (11, 20), (21, 10 ** 6)]

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

    table("tools", "counted in ALL tool calls (what the transcript shows):")
    hooked = table("hooked", "counted in the calls a PostToolUse hook is fired for (Read is not one):")
    # The threshold the skill can actually use is the second one. Say what each candidate would card.
    print("\n   a read-only card at N hooked calls would reach, per threshold:")
    for n in (3, 4, 5, 6, 8):
        w = sum(v[0] for b, v in hooked.items() if b[0] >= n)
        s = sum(v[1] for b, v in hooked.items() if b[0] >= n)
        print("     >= %-3d  %4d silent turns carded, in a band whose note rate is %s"
              % (n, s, ("%.0f%%" % (100.0 * w / (w + s))) if w + s else "-"))


if __name__ == "__main__":
    main()
