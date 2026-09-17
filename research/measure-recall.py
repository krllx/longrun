#!/usr/bin/env python3
"""Replay the real search terms of this project's history through the 0.6.2 recall hint.

Two questions at once:

  1. Noise. How often does the hint actually fire per session, on real searches rather than on a test
     fixture? A mechanism that fires on every third Grep is a nag; one that never fires is dead code.
  2. O2. The live notes are injected whole at every start and the archive is only reachable on purpose.
     The hint changes that: archived material now comes back by itself when somebody searches for it. If
     the replay shows the archive being reached, shrinking the live notes stops being a loss.

The hint's own functions are imported from the shipped script, so this measures what was shipped rather
than a second implementation of it.

Usage: python3 research/measure-recall.py [--project .] [--transcripts <dir>]
"""
import argparse
import collections
import glob
import importlib.machinery
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(HERE, "..", "skill", "longrun", "scripts", "longrun")
# The CLI has no .py suffix, so the loader has to be named explicitly.
SPEC = importlib.util.spec_from_loader("longrun_cli", importlib.machinery.SourceFileLoader("longrun_cli", CLI))
LR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LR)


def terms_of(path):
    """Every search term this transcript's session typed, in order, one list per turn."""
    out, cur = [], []
    try:
        fh = open(path, errors="replace")
    except OSError:
        return out
    with fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("isSidechain"):
                continue
            if row.get("type") == "user" and not row.get("isMeta"):
                c = (row.get("message") or {}).get("content")
                if isinstance(c, str) or (isinstance(c, list) and not any(
                        isinstance(b, dict) and b.get("type") == "tool_result" for b in c)):
                    if cur:
                        out.append(cur)
                    cur = []
                    continue
            c = (row.get("message") or {}).get("content")
            for b in (c if isinstance(c, list) else []):
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Grep", "Glob", "WebSearch", "Task", "Agent"):
                    cur.append((b.get("name"), b.get("input") or {}))
    if cur:
        out.append(cur)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--transcripts", default="")
    a = ap.parse_args()

    local = LR.resolve_local(os.path.abspath(a.project), use_env=False)
    if not local:
        sys.exit("%s is not a longrun project" % a.project)
    store = LR.Store(local)
    tdir = a.transcripts or os.path.expanduser("~/.claude/projects")
    key = os.path.abspath(a.project).replace("/", "-")
    files = sorted(glob.glob(os.path.join(tdir, key + "*", "*.jsonl")))
    if not files:
        sys.exit("no transcripts for %s under %s" % (a.project, tdir))

    stat = collections.Counter()
    where = collections.Counter()
    samples = []
    for f in files:
        turns = terms_of(f)
        if not turns:
            continue
        stat["sessions"] += 1
        # one meta per session, as a live session would have: no files read, budget refilled per turn
        m = {"skey": "replay", "files": [], "opened": [], "recalled": [], "recall_hints": 0}
        for calls in turns:
            m["recall_hints"] = 0                       # the per-turn budget
            for name, ti in calls:
                stat["searches"] += 1
                if not LR.search_terms([(name, ti)]):
                    stat["no_term"] += 1
                    continue
                out = LR.recall_hint(store, m, [(name, ti)])
                if out:
                    stat["fired"] += 1
                    line = out.splitlines()[1] if len(out.splitlines()) > 1 else ""
                    where["archive" if "archive/" in line else ("sessions" if "sessions/" in line else "doc file")] += 1
                    if len(samples) < 8:
                        samples.append((os.path.basename(f)[:8], out.splitlines()[0][:120], line.strip()[:120]))

    print("project %s: %d shared notes, %d doc pointers, archive %d files"
          % (store.name, len(LR.load_notes(LR.notes_target(store, True))), len(LR.doc_entries(store)),
             len(glob.glob(os.path.join(store.archive, "**", "*.md"), recursive=True))))
    print("\n== replay over %d sessions, %d searches" % (stat["sessions"], stat["searches"]))
    print("   carried no usable term (short, or a bare path):  %6d" % stat["no_term"])
    print("   the hint fired:                                  %6d  (%.1f%% of searches, %.1f per session)"
          % (stat["fired"], 100.0 * stat["fired"] / max(1, stat["searches"]), stat["fired"] / max(1, stat["sessions"])))
    if where:
        print("\n   where the answer was found (this is the O2 question):")
        for k, v in where.most_common():
            print("     %-10s %5d  (%.0f%%)" % (k, v, 100.0 * v / sum(where.values())))
    if samples:
        print("\n== what it would have said")
        for sid, head, line in samples:
            print("   [%s] %s\n        %s" % (sid, head, line))


if __name__ == "__main__":
    main()
