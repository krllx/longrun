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


def transcripts_for(project, tdir):
    key = os.path.abspath(project).replace("/", "-")
    return sorted(glob.glob(os.path.join(tdir, key + "*", "*.jsonl")))


def known_projects():
    """Every longrun project on this machine: the registered external stores and the directories that
    hold a `.longrun` of their own, as far as the session store knows about them."""
    out = []
    for d in (LR.registry().get("links") or {}):
        out.append(d.rstrip("/"))
    for p in sorted(glob.glob(os.path.join(LR.GLOBAL_DIR, "sessions", "*"))):
        for mp in sorted(glob.glob(os.path.join(p, "*", "meta.json")))[:1]:
            cwd = (LR.read_json(mp) or {}).get("cwd") or ""
            if cwd and cwd not in out:
                out.append(cwd)
    return out


def replay(store, files, stat, mix, fire_mix, where, samples):
    for f in files:
        turns = terms_of(f)
        if not turns:
            continue
        stat["sessions"] += 1
        # One meta per session. `files`/`opened` stay empty, so the "skip what this session has already
        # read" exclusion is never exercised: a live session accumulates those, which means the real
        # firing rate is at or below what this prints. The bias is deliberate and runs the safe way for
        # a noise question - but it is a bias, and it used to be described here as what a live session has.
        m = {"skey": "replay", "files": [], "opened": [], "recalled": [], "recall_hints": 0}
        for calls in turns:
            m["recall_hints"] = 0                       # the per-turn budget
            for name, ti in calls:
                stat["searches"] += 1
                mix[name] += 1
                if not LR.search_terms([(name, ti)]):
                    stat["no_term"] += 1
                    continue
                out = LR.recall_hint(store, m, [(name, ti)])
                if out:
                    stat["fired"] += 1
                    fire_mix[name] += 1
                    line = out.splitlines()[1] if len(out.splitlines()) > 1 else ""
                    where["archive" if "archive/" in line else ("sessions" if "sessions/" in line else "doc file")] += 1
                    if len(samples) < 12:
                        q = ti.get("pattern") or ti.get("query") or ti.get("description") or ""
                        samples.append((name, str(q)[:60], out.splitlines()[0][:110], line.strip()[:110]))


def fresh_meta():
    return {"skey": "replay", "files": [], "opened": [], "recalled": [], "recall_hints": 0}


def reach(store):
    """Can the hint find what IS written down? One simulated `Grep` per stored line.

    Synthetic, and says so: nobody searched for these words. But it measures the half a replay of real
    searches cannot, because a replay only shows what the sessions happened to look for. For every line
    of the material the hint scans, the most specific word in it is used as a one-word Grep pattern - the
    commonest shape of a real search - and the question is simply whether the line comes back.

    A mechanism tuned for quiet is easy to tune into silence, and silence looks identical to "no noise"
    in every count above."""
    stat, missed = collections.Counter(), []
    for f, kind in LR.recall_scan_files(store, fresh_meta()):
        for i, line in enumerate(LR.read(f).splitlines(), 1):
            if kind == "notes":
                tag = LR.RECALL_TAG_RE.search(line)
                if not tag or tag.group(1) not in LR.RECALL_TAGS:
                    continue
            words = [w for w in LR.RECALL_WORD_RE.split(line)
                     if len(w) >= LR.RECALL_MIN_TERM and not w.isdigit() and LR.term_names_something(w)]
            if not words:
                stat["no_specific_word"] += 1
                continue
            stat["lines"] += 1
            word = max(words, key=len)
            out = LR.recall_hint(store, fresh_meta(), [("Grep", {"pattern": word})])
            if out:
                stat["found"] += 1
            else:
                stat["lost"] += 1
                if len(missed) < 6:
                    missed.append((word, LR.recall_label(store, f), i, line.strip()[:90]))
    return stat, missed


def noise(store, tdir, own):
    """Real `Grep`/`Glob` patterns from OTHER projects, replayed against this one.

    Every fire here is a coincidence by construction: nobody searching in another repository was asking
    this project's questions. So this is a false-positive rate, measured on the tool the corpus of real
    longrun sessions happens not to contain."""
    own_keys = {os.path.abspath(p).replace("/", "-") for p in own}
    pats, stat = [], collections.Counter()
    for d in sorted(glob.glob(os.path.join(tdir, "*"))):
        if any(os.path.basename(d).startswith(k) for k in own_keys):
            continue
        for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            for calls in terms_of(f):
                pats += [(n, ti) for n, ti in calls if n in ("Grep", "Glob")]
    m = fresh_meta()
    for n, ti in pats:
        stat["patterns"] += 1
        if LR.recall_hint(store, m, [(n, ti)]):
            stat["fired"] += 1
    return stat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--transcripts", default="")
    ap.add_argument("--all-projects", action="store_true",
                    help="replay every longrun project on this machine, not just one")
    a = ap.parse_args()

    tdir = a.transcripts or os.path.expanduser("~/.claude/projects")
    wanted = known_projects() if a.all_projects else [a.project]
    jobs, skipped = [], []
    for p in wanted:
        local = LR.resolve_local(os.path.abspath(p), use_env=False)
        files = transcripts_for(p, tdir) if local else []
        if local and files:
            jobs.append((LR.Store(local), files, p))
        else:
            skipped.append((p, "not a longrun project" if not local else "no transcripts"))
    if not jobs:
        sys.exit("nothing to replay (%s)" % "; ".join("%s: %s" % s for s in skipped) or "no projects")

    stat, mix, fire_mix, where, samples = (collections.Counter(), collections.Counter(),
                                           collections.Counter(), collections.Counter(), [])
    for store, files, p in jobs:
        print("project %-24s %3d notes, %2d doc pointers, %2d archive files, %3d transcripts"
              % (store.name, len(LR.load_notes(LR.notes_target(store, True))), len(LR.doc_entries(store)),
                 len(glob.glob(os.path.join(store.archive, "**", "*.md"), recursive=True)), len(files)))
        replay(store, files, stat, mix, fire_mix, where, samples)
    for p, why in skipped:
        print("skipped  %-24s %s" % (os.path.basename(p.rstrip("/"))[:24], why))

    print("\n== replay over %d sessions, %d searches" % (stat["sessions"], stat["searches"]))
    print("   carried no usable term (short, or a bare path):  %6d" % stat["no_term"])
    print("   the hint fired:                                  %6d  (%.1f%% of searches, %.1f per session)"
          % (stat["fired"], 100.0 * stat["fired"] / max(1, stat["searches"]), stat["fired"] / max(1, stat["sessions"])))

    # What the sample is MADE OF, printed whether or not anybody asks. A replay of one project once
    # reported a comfortable rate over a corpus that turned out to hold 38 subagent descriptions, 5 web
    # queries and not one single Grep - so it measured the sentence path and none of the pattern path the
    # design is mostly about, and nothing in the output said so.
    print("\n   what was searched, and how often each kind fired:")
    for k in sorted(mix, key=lambda k: -mix[k]):
        print("     %-10s %5d searches  ->  %4d fired  (%s)"
              % (k, mix[k], fire_mix[k], ("%.0f%%" % (100.0 * fire_mix[k] / mix[k])) if mix[k] else "-"))
    for k in ("Grep", "Glob", "WebSearch", "Task", "Agent"):
        if not mix[k]:
            print("     %-10s %5d searches      <- NOT EXERCISED by this sample" % (k, 0))
    if where:
        print("\n   where the answer was found (this is the O2 question):")
        for k, v in where.most_common():
            print("     %-10s %5d  (%.0f%%)" % (k, v, 100.0 * v / sum(where.values())))
    if samples:
        print("\n== what it would have said (judge these by hand: nothing here can score relevance)")
        for tool, q, head, line in samples:
            print("   [%s] %s\n        %s\n        %s" % (tool, q, head, line))

    # The two halves a replay of real searches cannot answer on its own.
    for store, _files, p in jobs:
        rs, missed = reach(store)
        print("\n== reach of %s: one simulated one-word Grep per stored line (synthetic)" % store.name)
        print("   lines with a word specific enough to search for: %4d   (%d had none)"
              % (rs["lines"], rs["no_specific_word"]))
        print("   the hint brings the line back:                   %4d  (%.0f%%)"
              % (rs["found"], 100.0 * rs["found"] / max(1, rs["lines"])))
        print("   ...does not:                                     %4d" % rs["lost"])
        for w, lab, i, line in missed:
            print("     lost  %-22s %s:%d: %s" % (w, lab, i, line))
        ns = noise(store, tdir, [x[2] for x in jobs])
        if ns["patterns"]:
            print("\n== noise against %s: %d real Grep/Glob patterns from OTHER projects, %d fired (%.1f%%)"
                  % (store.name, ns["patterns"], ns["fired"], 100.0 * ns["fired"] / ns["patterns"]))
            print("   every fire there is a coincidence by construction: nobody was asking this project's questions")


if __name__ == "__main__":
    main()
