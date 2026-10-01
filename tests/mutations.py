#!/usr/bin/env python3
"""Disable each added mechanism in a temporary CLI copy; its behavioral test must fail."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "skill/longrun/scripts/longrun").read_text()
MUTATIONS = [
    ("startup selection", '    choice = policy.get(str(e["id"]))', '    return True\n    choice = policy.get(str(e["id"]))',
     "test_memory_layers_lifecycle"),
    ("explicit selection", '    choice = policy.get(str(e["id"]))', '    choice = None',
     "test_memory_selection_is_shared_and_reversible"),
    ("deferred hint scan", '[(store.notes, "deferred")] + ', '', "test_deferred_notes_hint_including_ctx"),
    ("Codex rg extraction", 'queries, verbatim = rg_queries(ti.get("command")), True', 'queries, verbatim = [], True',
     "test_codex_rg_hint_payload"),
    ("policy change delivery", 'str(memory_resident(e, policy)) +', '"" +', "test_memory_peer_changes_and_selection_delivery"),
    ("on-demand delta", '        if memory_resident(e, policy):', '        if True:',
     "test_memory_peer_changes_and_selection_delivery"),
    ("empty rg result", 'rg_miss = str(code) == "1" and bool(rg_queries(ti.get("command")))', 'rg_miss = False',
     "test_rg_variants_through_hook"),
    ("command identity guard", '    if not argv or (argv[0] != "rg" and not (os.path.isabs(argv[0]) and os.path.basename(argv[0]) == "rg")):',
     '    if not argv:', "test_rg_quiet_unsafe_unrelated_and_repeated"),
    ("shell syntax guard", 'elif quote == \'"\' and c in "$`":', 'elif False:',
     "test_rg_quiet_unsafe_unrelated_and_repeated"),
]


def main():
    with tempfile.TemporaryDirectory(prefix="longrun-mutants-") as tmp:
        for label, before, after, test in MUTATIONS:
            if SOURCE.count(before) != 1:
                raise AssertionError("mutation must match once: " + label)
            cli = Path(tmp) / "longrun"
            cli.write_text(SOURCE.replace(before, after, 1))
            cli.chmod(0o755)
            env = dict(os.environ, LONGRUN_TEST_CLI=str(cli))
            r = subprocess.run([sys.executable, str(ROOT / "tests/codex.py"), "CodexTests." + test],
                               env=env, text=True, capture_output=True, timeout=60)
            if r.returncode != 1 or "AssertionError" not in r.stderr or "FAILED" not in r.stderr:
                raise AssertionError("mutation survived or did not reach its assertion: %s\n%s%s" % (label, r.stdout, r.stderr))
            print("killed: " + label, flush=True)
    print("%d/%d mechanisms detected" % (len(MUTATIONS), len(MUTATIONS)))


if __name__ == "__main__":
    main()
