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

A published before/after needs both halves to be reproducible from this repository, so an older script can
be measured alongside the shipped one:

    git show 208f713:skill/longrun/scripts/longrun > /tmp/v062
    python3 research/measure-recall.py --all-projects --against /tmp/v062

The two versions are then run over the SAME lines and the same probe words: the population of stored lines
comes from the shipped script for both, and only the hint under test changes. It cannot come from each
version's own scan - 0.6.2 also scanned journals and compaction archives, so "the same lines" would not be
the same lines - and it cannot be called through the old API either, whose `recall_scan_files` returns
paths where this one returns (path, kind) pairs.

Usage: python3 research/measure-recall.py [--project .] [--transcripts <dir>] [--against <script>]
"""
import argparse
import collections
import glob
import importlib.machinery
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(HERE, "..", "skill", "longrun", "scripts", "longrun")


def load_cli(path, name):
    """A longrun script as a module. It has no .py suffix, so the loader has to be named explicitly."""
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# LR is the shipped script. It is both a version under test and the harness itself: the project store, the
# notes and - for an A/B - the population of lines are read through it, so that an older script is asked
# about the same material and not about whatever its own scan happened to cover.
LR = load_cli(CLI, "longrun_cli")


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


def replay(store, files, stat, mix, fire_mix, where, samples, mod=None):
    mod = mod or LR
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
                if not mod.search_terms([(name, ti)]):
                    stat["no_term"] += 1
                    continue
                out = mod.recall_hint(store, m, [(name, ti)])
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


# The probe words are the experiment's INPUT, so they are chosen here and not by the version under test:
# pointed at an older script for an A/B, the same lines must be searched for the same words. (It is the
# same rule the shipped script uses; the assert says so out loud, and only for a script that has one.)
WORD_RE = re.compile(r"[^0-9A-Za-z_Ѐ-ӿ]+")
MIN_TERM = 5
assert getattr(LR, "RECALL_WORD_RE", WORD_RE).pattern == WORD_RE.pattern, "the shipped tokenizer moved"
assert getattr(LR, "RECALL_MIN_TERM", MIN_TERM) == MIN_TERM, "the shipped minimum term length moved"


def stored_lines(store):
    """The population: every stored line with a word long enough to search for, read through the SHIPPED
    script. One population for every version under test - an older one scanned journals and compaction
    summaries as well, and comparing each version over its own idea of the material compares two things
    at once."""
    out = []
    for f, kind in LR.recall_scan_files(store, fresh_meta()):
        for i, line in enumerate(LR.read(f).splitlines(), 1):
            if kind == "notes":
                tag = LR.RECALL_TAG_RE.search(line)
                if not tag or tag.group(1) not in LR.RECALL_TAGS:
                    continue
            words = [w for w in WORD_RE.split(line) if len(w) >= MIN_TERM and not w.isdigit()]
            out.append((f, i, line, words))
    return out


def reach(store, mod=None):
    """Can the hint find what IS written down? Two simulated one-word `Grep`s per stored line.

    Synthetic, and says so: nobody searched for these words. But it measures the half a replay of real
    searches cannot, because a replay only shows what the sessions happened to look for.

    Two probes rather than one, because the choice of word IS the result. Searching each line for its
    LONGEST word flatters the mechanism - long words are the rare ones, and rare is exactly what gets
    past the "found on more than RECALL_COMMON_HITS lines" filter. So the same line is also searched for
    its SHORTEST eligible word, which is the unlucky end of what a real session might type. The truth is
    between them, and a single number here used to hide that.

    The population is every stored line with any word of RECALL_MIN_TERM characters or more - not only
    lines holding a word that NAMES something. Since 0.6.3 a one-word pattern stands on its own whether
    it names anything or not, so restricting the sample to naming words measured a rule the pattern path
    no longer uses, and dropped two thirds of the material out of the denominator.

    A mechanism tuned for quiet is easy to tune into silence, and silence looks identical to "no noise"
    in every count above."""
    mod = mod or LR
    stat, missed = collections.Counter(), []
    for f, i, line, words in stored_lines(store):
        if not words:
            stat["no_word_to_search_for"] += 1
            continue
        stat["lines"] += 1
        names = getattr(mod, "term_names_something", None)   # 0.6.3 and later; absent when this is
        if names and any(names(w) for w in words):           # pointed at an older script for an A/B
            stat["lines_with_a_naming_word"] += 1
        for which, word in (("best", max(words, key=len)), ("worst", min(words, key=len))):
            # "The hint fired" is not the claim. The claim is that THIS line comes back, and a hint
            # that fired on some other line of some other file answers a different question - it is
            # counted below as noise, not here as reach. The hint prints "<label>:<line>: <text>".
            out = mod.recall_hint(store, fresh_meta(), [("Grep", {"pattern": word})])
            if ("%s:%d:" % (mod.recall_label(store, f), i)) in out:
                stat["found_" + which] += 1
            elif which == "best":
                stat["lost"] += 1
                if len(missed) < 6:
                    missed.append((word, mod.recall_label(store, f), i, line.strip()[:90]))
    return stat, missed


def noise(store, tdir, own, mod=None):
    """Real `Grep`/`Glob` patterns from OTHER projects, replayed against this one.

    Every fire here is a coincidence by construction: nobody searching in another repository was asking
    this project's questions. So this is a false-positive rate, measured on the tool the corpus of real
    longrun sessions happens not to contain.

    Each pattern gets a FRESH session state, and that is the whole point of the measurement rather than a
    detail. Sharing one state across the replay silently applied `RECALL_PER_TURN` to all of it: after two
    fires `recall_hint` returns "" for everything that follows, so the count could never exceed 2 and the
    "rate" was really 2 divided by however many patterns happened to be in the corpus. Both 0.6.2 and
    0.6.3 measured exactly 2/197 that way and the table in REFERENCE read it as "unchanged". A rate that
    cannot move is not a measurement. What a false-positive rate asks is "given one pattern, how often
    does it fire wrongly", and that question is asked one pattern at a time."""
    mod = mod or LR
    own_keys = {os.path.abspath(p).replace("/", "-") for p in own}
    pats, stat = [], collections.Counter()
    for d in sorted(glob.glob(os.path.join(tdir, "*"))):
        if any(os.path.basename(d).startswith(k) for k in own_keys):
            continue
        for f in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            for calls in terms_of(f):
                pats += [(n, ti) for n, ti in calls if n in ("Grep", "Glob")]
    for n, ti in pats:
        stat["patterns"] += 1
        if mod.recall_hint(store, fresh_meta(), [(n, ti)]):
            stat["fired"] += 1
    return stat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--transcripts", default="")
    ap.add_argument("--all-projects", action="store_true",
                    help="replay every longrun project on this machine, not just one")
    ap.add_argument("--against", default="",
                    help="a second longrun script (an older version) to measure over the same lines")
    a = ap.parse_args()
    mods = [("%s (this tree)" % LR.VERSION, LR)]
    if a.against:
        old = load_cli(os.path.abspath(a.against), "longrun_old")
        mods.append(("%s (%s)" % (getattr(old, "VERSION", "?"), os.path.basename(a.against)), old))

    tdir = a.transcripts or os.path.expanduser("~/.claude/projects")
    wanted = known_projects() if a.all_projects else [a.project]
    # Several directories - a hub and its worktrees - can share one store, and each of them has its own
    # transcript directory. They are one project with one set of notes: merged here, or its reach and its
    # false-positive rate would be measured (and printed) once per directory.
    byst, skipped = collections.OrderedDict(), []
    for p in wanted:
        local = LR.resolve_local(os.path.abspath(p), use_env=False)
        files = transcripts_for(p, tdir) if local else []
        if local and files:
            cur = byst.setdefault(os.path.realpath(local), [LR.Store(local), [], p])
            cur[1] += files
        else:
            skipped.append((p, "not a longrun project" if not local else "no transcripts"))
    jobs = [tuple(v) for v in byst.values()]
    if not jobs:
        sys.exit("nothing to replay (%s)" % "; ".join("%s: %s" % s for s in skipped) or "no projects")

    for store, files, p in jobs:
        print("project %-24s %3d notes, %2d doc pointers, %2d archive files, %3d transcripts"
              % (store.name, len(LR.load_notes(LR.notes_target(store, True))), len(LR.doc_entries(store)),
                 len(glob.glob(os.path.join(store.archive, "**", "*.md"), recursive=True)), len(files)))
    for p, why in skipped:
        print("skipped  %-24s %s" % (os.path.basename(p.rstrip("/"))[:24], why))
    for label, mod in mods:
        report_replay(jobs, label, mod)
    report_synthetic(jobs, mods, tdir)


def report_replay(jobs, label, mod):
    stat, mix, fire_mix, where, samples = (collections.Counter(), collections.Counter(),
                                           collections.Counter(), collections.Counter(), [])
    for store, files, p in jobs:
        replay(store, files, stat, mix, fire_mix, where, samples, mod)

    print("\n== replay through the hint of %s over %d sessions, %d searches"
          % (label, stat["sessions"], stat["searches"]))
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


def report_synthetic(jobs, mods, tdir):
    # The two halves a replay of real searches cannot answer on its own. With --against, every version
    # under test answers them over the same population of lines and the same patterns, one after another.
    for store, _files, p in jobs:
        for label, mod in mods:
            rs, missed = reach(store, mod)
            print("\n== reach of %s, hint of %s: simulated one-word Greps per stored line (synthetic)"
                  % (store.name, label))
            print("   lines with any word long enough to search for:   %4d   (%d had none; %s hold a word that NAMES something)"
                  % (rs["lines"], rs["no_word_to_search_for"],
                     rs["lines_with_a_naming_word"] if hasattr(mod, "term_names_something") else "n/a, this script has no naming rule -"))
            print("   searched for the line's LONGEST word, it comes back: %4d  (%.0f%%)  <- the lucky end"
                  % (rs["found_best"], 100.0 * rs["found_best"] / max(1, rs["lines"])))
            print("   searched for its SHORTEST one:                       %4d  (%.0f%%)  <- the unlucky end"
                  % (rs["found_worst"], 100.0 * rs["found_worst"] / max(1, rs["lines"])))
            print("   a real search sits between the two; quoting only the first is how this flattered itself")
            print("   a line counts as reached only when the hint prints THAT line; one found and left in")
            print("   its \"(+N more lines)\" tail counts as lost, so both columns are floors")
            for w, lab, i, line in missed:
                print("     lost  %-22s %s:%d: %s" % (w, lab, i, line))
            ns = noise(store, tdir, [x[2] for x in jobs], mod)
            if ns["patterns"]:
                print("\n== noise against %s, hint of %s: %d real Grep/Glob patterns from OTHER projects, %d fired (%.1f%%)"
                      % (store.name, label, ns["patterns"], ns["fired"], 100.0 * ns["fired"] / ns["patterns"]))
                print("   one fresh session state per pattern, so the 2-per-turn budget cannot cap the count")
                print("   every fire there is a coincidence by construction: nobody was asking this project's questions")


if __name__ == "__main__":
    main()
