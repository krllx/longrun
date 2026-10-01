#!/usr/bin/env python3
"""Compare startup context on a realistic longrun project fixture, entirely offline."""
import argparse
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "skill/longrun/scripts/longrun"


def load_cli(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


def measure(against):
    with tempfile.TemporaryDirectory(prefix="longrun-memory-") as tmp:
        base = Path(tmp)
        project = base / "longrun"
        project.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith(("LONGRUN_", "CLAUDE_", "CODEX_"))}
        env.update(HOME=str(base / "home"), LONGRUN_HOME=str(base / "store"),
                   CLAUDE_CONFIG_DIR=str(base / "home/.claude"), CODEX_HOME=str(base / "home/.codex"),
                   XDG_CONFIG_HOME=str(base / "home/.config"), LONGRUN_DESKTOP_DIR=str(base / "desktop"),
                   LONGRUN_NO_TIMER="1", LONGRUN_NO_UI="1")
        def run(*args):
            return subprocess.run([str(CLI), *args], cwd=project, env=env, text=True,
                                  capture_output=True, check=True, timeout=20).stdout
        run("init")
        for tag, text in json.loads((ROOT / "tests/fixtures/memory.json").read_text()):
            run("add", "-t", tag, text)
        for src in ("docs/REFERENCE.md", "docs/ORCHESTRATOR.md"):
            (project / src).parent.mkdir(parents=True, exist_ok=True)
            (project / src).write_bytes((ROOT / src).read_bytes())
            run("doc", "add", src, "Commands and operational contracts" if "REFERENCE" in src else "Coordination and authorization")
        with patch.dict(os.environ, env, clear=True):
            current = load_cli(CLI, "memory_current")
            store = current.Store(str(project / ".longrun"))
            after = current.build_digest(store, "", "startup", cwd=str(project))
            if against:
                old = load_cli(against, "memory_before")
                before = old.build_digest(old.Store(store.local), "", "startup", cwd=str(project))
                baseline = "previous CLI"
            else:
                # A controlled ablation; preserves all formatting and changes only selection.
                with patch.object(current, "memory_resident", return_value=True):
                    before = current.build_digest(store, "", "startup", cwd=str(project))
                baseline = "all-resident ablation"
            assert "watch_timer" in before and "watch_timer" not in after
            assert "watch_timer" in run("recall", "watch_timer", "--no-transcript")
            hint = current.recall_hint(store, {}, [("Bash", {"command": "rg watch_timer"})])
            assert "supports launchd" in hint
            policy = current.memory_policy(store)
            entries = current.load_notes(current.notes_target(store, True))
            before_bytes, after_bytes = len(before.encode()), len(after.encode())
            return dict(baseline=baseline, entries=len(entries), resident=sum(current.memory_resident(e, policy) for e in entries),
                        before_bytes=before_bytes, after_bytes=after_bytes,
                        reduction_pct=round(100 * (1 - after_bytes / before_bytes), 1),
                        before_est_tokens=current.est_tokens(before), after_est_tokens=current.est_tokens(after),
                        recall_and_hook_hint=True, live_client=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--against", type=Path, help="Previous longrun CLI, read-only; otherwise use an all-resident ablation")
    print(json.dumps(measure(parser.parse_args().against), indent=2))
