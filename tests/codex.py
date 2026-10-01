#!/usr/bin/env python3
"""Isolated Codex/Claude integration tests. No API calls, real UI or scheduler."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLI = Path(os.environ.get("LONGRUN_TEST_CLI", ROOT / "skill/longrun/scripts/longrun"))
CLAUDE = "11111111-2222-4333-8444-555555555555"
CODEX = "aaaaaaaa-2222-4333-8444-555555555555"
OTHER = "bbbbbbbb-2222-4333-8444-555555555555"


class CodexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="longrun-codex-")
        self.base = Path(self.tmp.name).resolve()
        self.project = self.base / "project"
        self.project.mkdir()
        self.fake_home = self.base / "home with 'quotes"
        self.fake_home.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("LONGRUN_", "CLAUDE_", "CODEX_"))}
        self.env.update({"HOME": str(self.fake_home), "CLAUDE_CONFIG_DIR": str(self.fake_home / ".claude"),
                         "CODEX_HOME": str(self.fake_home / ".codex"), "LONGRUN_NO_TIMER": "1", "LONGRUN_NO_UI": "1",
                         "XDG_CONFIG_HOME": str(self.fake_home / ".config"),
                         "LONGRUN_DESKTOP_DIR": str(self.base / "desktop"), "LONGRUN_STUB_LOG": str(self.base / "calls.jsonl")})
        self.run_cli("init")

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, sid=None, cwd=None, expected=0, input=None):
        env = dict(self.env)
        if sid:
            env["CODEX_THREAD_ID"] = sid
        r = subprocess.run([str(CLI), *args], cwd=cwd or self.project, env=env,
                           input=input, text=True, capture_output=True, timeout=20)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout

    def hook(self, event, sid=CODEX, client="codex", **fields):
        payload = dict(session_id=sid, cwd=str(self.project), transcript_path=None, hook_event_name=event)
        payload.update(fields)
        return self.run_cli("hook", "--client", client, event, input=json.dumps(payload))

    def meta(self, sid=CODEX):
        return json.loads(next((self.fake_home / ".claude/longrun/sessions").glob("*/%s/meta.json" % sid[:8])).read_text())

    def journal(self, sid=CODEX):
        return next((self.fake_home / ".claude/longrun/sessions").glob("*/%s/journal.md" % sid[:8])).read_text()

    def stubs(self):
        bindir = self.base / "stubs"
        bindir.mkdir()
        for name in ("claude", "codex"):
            p = bindir / name
            p.write_text("""#!/usr/bin/env python3
import json, os, sys
with open(%r, 'a') as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + '\\n')
if 'resume' in sys.argv:
    print('resumed ' + os.path.basename(sys.argv[0]))
""" % str(self.base / "calls.jsonl"))
            p.chmod(0o755)
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]

    def install(self, *args, expected=0):
        r = subprocess.run(["bash", str(ROOT / "install.sh"), *args, "--no-notify", "--no-timer"],
                           env=self.env, cwd=self.project, text=True, capture_output=True, timeout=30)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout

    def test_both_clients_share_notes_but_keep_own_notes(self):
        self.hook("SessionStart", sid=CLAUDE, client="claude", source="startup")
        self.hook("SessionStart", source="startup")
        self.run_cli("add", "-t", "decision", "Use one store across clients", sid=CODEX)
        self.run_cli("memory", "keep", "n1", sid=CODEX)
        self.run_cli("add", "--own", "-t", "ctx", "Only the Codex conversation", sid=CODEX)
        restored = self.hook("SessionStart", source="compact")
        self.assertIn("Use one store across clients", restored)
        self.assertIn("Only the Codex conversation", restored)
        claude = self.hook("SessionStart", sid=CLAUDE, client="claude", source="resume")
        self.assertIn("Use one store across clients", claude)
        self.assertNotIn("Only the Codex conversation", claude)
        self.assertEqual(self.meta()["client"], "codex")
        self.assertEqual(self.meta(CLAUDE)["client"], "claude")
        self.assertEqual(self.meta()["compactions"], 1)
        # Claude's /clear chain must not adopt another client's own notes.
        self.hook("SessionEnd", reason="clear")
        cleared = self.hook("SessionStart", sid=OTHER, client="claude", source="clear")
        self.assertNotIn("Only the Codex conversation", cleared)
        self.run_cli("add", "--own", "-t", "ctx", "Only the Claude conversation", sid=CLAUDE)
        self.hook("SessionEnd", sid=CLAUDE, client="claude", reason="clear")
        fresh = self.hook("SessionStart", sid="cccccccc-2222-4333-8444-555555555555", source="clear")
        self.assertNotIn("Only the Claude conversation", fresh)

    def test_manual_codex_binds_identity_and_project(self):
        self.run_cli("add", "--own", "-t", "ctx", "Manual fallback", sid=CODEX)
        self.assertEqual(self.meta()["client"], "codex")
        elsewhere = self.base / "elsewhere"
        elsewhere.mkdir()
        self.run_cli("init", cwd=elsewhere)
        self.run_cli("add", "-t", "fact", "Original project after cd", sid=CODEX, cwd=elsewhere)
        self.assertIn("Original project after cd", (self.project / ".longrun/NOTES.md").read_text())
        self.assertNotIn("Original project after cd", (elsewhere / ".longrun/NOTES.md").read_text())
        self.assertIn(CODEX, self.run_cli("where", sid=CODEX))

    def test_hooks_attach_to_an_already_open_codex_thread(self):
        self.hook("PostToolUse", tool_name="read_file", tool_use_id="r1", tool_input={})
        self.assertEqual(self.meta()["client"], "codex")
        self.run_cli("add", "--own", "-t", "ctx", "Attached to existing thread", sid=CODEX)
        self.assertIn("Attached to existing thread", self.hook("SessionStart", source="compact"))

    def test_patch_records_all_paths_and_shell_failures(self):
        self.hook("SessionStart", source="startup")
        self.hook("UserPromptSubmit", prompt="Make the change")
        patch = "*** Begin Patch\n*** Update File: a.py\n*** Move to: moved a.py\n*** Add File: b.py\n*** Delete File: c.py\n*** End Patch"
        self.hook("PostToolUse", tool_name="apply_patch", tool_use_id="p1", tool_input={"command": patch})
        self.assertEqual(set(self.meta()["turn_files"]), {str(self.project / p) for p in ("a.py", "moved a.py", "b.py", "c.py")})
        self.hook("PreToolUse", tool_name="Bash", tool_use_id="s1", tool_input={"command": "make check"})
        self.hook("PostToolUse", tool_name="Bash", tool_use_id="s1", tool_input={"command": "make check"},
                  tool_response="Process exited with code 2\nOutput:\nmissing dependency")
        m = self.meta()
        self.assertEqual(m["fails"], 1)
        self.assertEqual(m["turn_tools"], 2)
        self.assertEqual(m["running"], {})
        self.assertIn("FAIL `make check`", self.journal())

    def test_structured_success_and_failure(self):
        self.hook("SessionStart", source="startup")
        self.hook("PostToolUse", tool_name="exec_command", tool_use_id="s1", tool_input={"cmd": "false"},
                  tool_response={"exit_code": 1, "output": "failed"})
        self.hook("PostToolUse", tool_name="Bash", tool_use_id="s2", tool_input={"command": "true"},
                  tool_response={"exit_code": 0, "output": "ok"})
        self.hook("PostToolUse", tool_name="Bash", tool_use_id="s3", tool_input={"command": "long command"},
                  tool_response={"session_id": 123, "output": "running"})
        self.assertEqual(self.meta()["fails"], 1)
        self.assertEqual(self.meta()["turn_tools"], 3)

    def test_codex_rg_hint_payload(self):
        self.run_cli("add", "-t", "dead", "payment_callback retries reuse an invalid idempotency key")
        self.hook("SessionStart", source="startup")
        self.hook("UserPromptSubmit", prompt="Find the retry path")
        out = self.hook("PostToolUse", tool_name="exec_command", tool_use_id="rg1",
                        tool_input={"cmd": "rg -n 'payment_callback' src", "workdir": str(self.project)},
                        tool_response={"exit_code": 0, "output": "src/callback.py:42"})
        self.assertIn("already written down", out)
        self.assertIn("NOTES.md", out)
        self.assertIn("invalid idempotency key", out)
        self.assertIn("longrun recall payment_callback", out)
        self.assertEqual(self.meta()["turn_tools"], 1)

    def test_memory_layers_lifecycle(self):
        self.run_cli("add", "-t", "pin", "Release branch codex/memory-layer")
        (self.project / "design.md").write_text("payment_callback needs a fresh idempotency key\n")
        self.run_cli("doc", "add", "design.md", "Callback contract and retry experiments")
        self.run_cli("add", "-t", "dead", "payment_callback: reused keys are rejected after a decline")
        self.run_cli("add", "-t", "ctx", "callback_scratch: comparison of the failed payloads")
        path = self.project / ".longrun/NOTES.md"
        original = path.read_bytes()
        for client, sid in (("codex", CODEX), ("claude", CLAUDE)):
            self.hook("SessionStart", sid=sid, client=client, source="startup")
            self.run_cli("add", "--own", "-t", "ctx", "Active investigation checkpoint", sid=sid)
            for source in ("startup", "resume", "compact"):
                with self.subTest(client=client, source=source):
                    out = self.hook("SessionStart", sid=sid, client=client, source=source)
                    self.assertIn("Release branch", out)
                    self.assertIn("design.md - Callback contract", out)
                    self.assertIn("Active investigation checkpoint", out)
                    self.assertIn("2 resident, 2 on demand", out)
                    self.assertNotIn("reused keys are rejected", out)
                    self.assertNotIn("callback_scratch", out)
                    for term in ("payment_callback", "callback_scratch", "Release branch", "Active investigation"):
                        self.assertIn(term, self.run_cli("recall", term, "--no-transcript", sid=sid))
        self.assertEqual(path.read_bytes(), original)

    def test_project_context_measurement(self):
        spec = importlib.util.spec_from_file_location("measure_memory_test", ROOT / "research/measure-memory.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.measure(None)
        self.assertEqual(result["entries"], 21)
        self.assertEqual(result["resident"], 4)
        self.assertGreater(result["reduction_pct"], 50)
        self.assertTrue(result["recall_and_hook_hint"])

    def test_memory_selection_is_shared_and_reversible(self):
        self.run_cli("add", "-t", "decision", "callback_selection: use the explicit retry contract")
        original = (self.project / ".longrun/NOTES.md").read_bytes()
        self.run_cli("memory", "keep", "n1")
        self.assertIn("callback_selection", self.hook("SessionStart", sid=OTHER, source="startup"))
        self.assertIn("(explicit)", self.run_cli("memory", "ls"))
        self.run_cli("memory", "defer", "n1")
        self.assertNotIn("callback_selection", self.hook("SessionStart", sid=OTHER, source="resume"))
        self.run_cli("memory", "auto", "n1")
        self.assertNotIn("(explicit)", self.run_cli("memory", "ls"))
        self.assertIn("callback_selection", self.run_cli("recall", "callback_selection", "--no-transcript"))
        self.run_cli("memory", "keep", "s1", expected=2)
        self.run_cli("memory", "defer", "n999", expected=2)
        self.assertEqual((self.project / ".longrun/NOTES.md").read_bytes(), original)

    def test_deferred_notes_hint_including_ctx(self):
        self.run_cli("add", "-t", "ctx", "callback_scratch: payload comparison explains the failed retry")
        self.hook("SessionStart", source="startup")
        out = self.hook("PostToolUse", tool_name="Grep", tool_input={"pattern": "callback_scratch"})
        self.assertIn("payload comparison explains", out)
        self.assertIn("NOTES.md", out)
        self.assertIn("longrun recall callback_scratch", out)

    def test_memory_peer_changes_and_selection_delivery(self):
        self.run_cli("add", "-t", "fact", "callback_contract: legacy retry detail")
        self.hook("SessionStart", source="startup")
        self.hook("SessionStart", sid=OTHER, source="startup")
        self.hook("UserPromptSubmit", prompt="Investigate")
        text = "callback_contract: " + "retry analysis " * 8 + "the definitive outcome"
        self.run_cli("replace", "n1", text, sid=OTHER)
        out = self.hook("UserPromptSubmit", prompt="Continue")
        self.assertIn("n1", out)
        self.assertIn("on demand", out)
        self.assertNotIn("the definitive outcome", out)
        self.assertIn("the definitive outcome", self.run_cli("recall", "callback_contract", "--no-transcript", sid=CODEX))
        self.assertNotIn("callback_contract", self.hook("UserPromptSubmit", prompt="Continue"))
        self.run_cli("memory", "keep", "n1", sid=OTHER)
        out = self.hook("UserPromptSubmit", prompt="Continue")
        self.assertIn("the definitive outcome", out)
        self.run_cli("memory", "defer", "n1", sid=OTHER)
        out = self.hook("UserPromptSubmit", prompt="Continue")
        self.assertIn("on demand", out)
        self.assertNotIn("the definitive outcome", out)
        self.run_cli("add", "-t", "fact", "callback_midturn: retry budget is exhausted", sid=OTHER)
        out = "".join(self.hook("PostToolUse", tool_name="read_file", tool_use_id="r%d" % i,
                                tool_input={}) for i in range(5))
        self.assertIn("callback_midturn", out)
        self.assertIn("on demand", out)
        self.assertIn("retry budget is exhausted", self.run_cli("recall", "callback_midturn", "--no-transcript", sid=CODEX))

    def test_rg_variants_through_hook(self):
        self.run_cli("add", "-t", "dead", "payment_callback: cache retry uses a fresh idempotency key")
        commands = ["rg payment_callback", "rg -n 'payment_callback' src", 'rg -nS "payment_callback" src',
                    "rg -n --glob '*.py' --type py payment_callback src", "rg --color=never -A 3 payment_callback",
                    "rg -e payment_callback -e absent_query src", "rg -eabsent_query --regexp=payment_callback src",
                    "rg --regexp payment_callback -- src", "rg -- payment_callback src", "/usr/local/bin/rg -nFi payment_callback",
                    "rg -e cache -e retry src", "rg -n '\\bpayment_callback\\b' src"]
        for i, cmd in enumerate(commands):
            sid = "rgtest%02d-2222-4333-8444-555555555555" % i
            with self.subTest(cmd=cmd):
                self.hook("SessionStart", sid=sid, source="startup")
                out = self.hook("PostToolUse", sid=sid, tool_name="exec_command", tool_use_id="r1",
                                tool_input={"cmd": cmd}, tool_response={"exit_code": 0, "output": ""})
                self.assertIn("already written down", out)
                self.assertIn("fresh idempotency key", out)
        # Empty rg results still reach recall, with no spurious failure telemetry.
        self.hook("SessionStart", sid=OTHER, source="startup")
        out = self.hook("PostToolUse", sid=OTHER, tool_name="exec_command", tool_input={"cmd": "rg payment_callback"},
                        tool_response={"exit_code": 1, "output": ""})
        self.assertIn("already written down", out)
        self.assertEqual(self.meta(OTHER)["fails"], 0)
        # The existing Claude Bash handler uses the same literal argv parser.
        self.hook("SessionStart", sid=CLAUDE, client="claude", source="startup")
        self.assertIn("already written down", self.hook("PostToolUse", sid=CLAUDE, client="claude", tool_name="Bash",
                      tool_input={"command": "rg -e payment_callback"}, tool_response={}))

    def test_rg_quiet_unsafe_unrelated_and_repeated(self):
        for term in ("payment_callback", "retry_budget", "callback_contract"):
            self.run_cli("add", "-t", "fact", term + ": recorded outcome")
        self.hook("SessionStart", source="startup")
        marker = self.base / "must-not-exist"
        commands = ["echo payment_callback", "cat payment_callback", "rg --files payment_callback",
                    "rg --files -g '*payment_callback*'", "rg --unknown payment_callback", "rg -g payment_callback",
                    "rg -e", "rg -e '' payment_callback", "rg 'payment_callback", "rg $QUERY",
                    'rg "payment_callback $(true)"', 'rg "$(touch %s)payment_callback"' % marker, "rg `touch %s` payment_callback" % marker,
                    "rg payment_callback; touch %s" % marker, "rg payment_callback | head", "cd src && rg payment_callback",
                    "rg payment_callback > out", "rg payment_callback\necho done", "rg payment_*", "rg unrelated_query",
                    "rg --glob payment_callback unrelated_query src"]
        for cmd in commands:
            with self.subTest(cmd=cmd):
                out = self.hook("PostToolUse", tool_name="exec_command", tool_input={"cmd": cmd},
                                tool_response={"exit_code": 0, "output": ""})
                self.assertNotIn("already written down", out)
        self.assertFalse(marker.exists())
        for term in ("payment_callback", "retry_budget"):
            self.assertIn("already written down", self.hook("PostToolUse", tool_name="exec_command",
                          tool_input={"cmd": "rg " + term}, tool_response={"exit_code": 0}))
        self.assertNotIn("already written down", self.hook("PostToolUse", tool_name="exec_command",
                         tool_input={"cmd": "rg callback_contract"}, tool_response={"exit_code": 0}))
        self.hook("UserPromptSubmit", prompt="Continue")
        self.assertNotIn("already written down", self.hook("PostToolUse", tool_name="exec_command",
                         tool_input={"cmd": "rg payment_callback"}, tool_response={"exit_code": 0}))
        self.assertIn("already written down", self.hook("PostToolUse", tool_name="exec_command",
                      tool_input={"cmd": "rg callback_contract"}, tool_response={"exit_code": 0}))

    def test_read_turn_card_and_interrupt(self):
        self.hook("SessionStart", source="startup")
        self.hook("UserPromptSubmit", prompt="Inspect the project")
        for i in range(6):
            self.hook("PostToolUse", tool_name="read_file", tool_use_id="r%d" % i, tool_input={})
        self.hook("Stop", last_assistant_message=None)
        self.assertIn("6 tool calls", self.hook("UserPromptSubmit", prompt="Continue"))
        self.hook("PreToolUse", tool_name="Bash", tool_use_id="s1", tool_input={"command": "make"})
        self.hook("Interrupt", turn_id="turn1")
        self.assertEqual(self.meta()["running"], {})
        self.assertNotIn("turn_started", self.meta())
        self.assertIn("turn interrupted", self.journal())

    def test_inbox_delivery_between_clients_once(self):
        self.hook("SessionStart", source="startup")
        self.hook("SessionStart", sid=CLAUDE, client="claude", source="startup")
        env = dict(self.env, LONGRUN_SESSION=CLAUDE)
        r = subprocess.run([str(CLI), "send", CODEX, "A cross-client handoff"], env=env, cwd=self.project,
                           text=True, capture_output=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("A cross-client handoff", self.hook("PostToolUse", tool_name="update_plan", tool_use_id="u1"))
        self.assertNotIn("A cross-client handoff", self.hook("UserPromptSubmit", prompt="Next"))
        self.run_cli("send", CLAUDE, "Codex to Claude", sid=CODEX)
        self.assertIn("Codex to Claude", self.hook("UserPromptSubmit", sid=CLAUDE, client="claude", prompt="Next"))

    def test_compaction_snapshot_summary_and_recall(self):
        rollout = self.base / "rollout.jsonl"
        records = [dict(type="response_item", payload=dict(type="message", role="user", content=[
            dict(type="input_text", text="Keep the migration reversible and retain the old Claude installation.")])),
            dict(type="compacted", payload=dict(message="Codex summary: migration remains reversible")),
            dict(type="event_msg", payload=dict(type="token_count", info=dict(last_token_usage=dict(input_tokens=123456), model_context_window=500000)))]
        rollout.write_text("broken line\n" + "\n".join(json.dumps(r) for r in records))
        self.hook("SessionStart", source="startup", transcript_path=str(rollout))
        self.assertEqual(self.hook("PreCompact", trigger="auto", transcript_path=str(rollout)), "")
        self.hook("PostCompact", trigger="auto", transcript_path=str(rollout))
        restored = self.hook("SessionStart", source="compact", transcript_path=str(rollout))
        self.assertIn("migration reversible", restored)
        archives = list((self.project / ".longrun/archive/compact").glob("*.md"))
        self.assertEqual(len(archives), 1)
        self.assertIn("Codex summary", archives[0].read_text())
        self.assertIn("reversible", self.run_cli("recall", "reversible", sid=CODEX))
        self.hook("Stop", transcript_path=str(rollout), last_assistant_message="Ready")
        self.assertEqual(self.meta()["ctx_tokens"], 123456)
        self.assertEqual(self.meta()["ctx_window"], 500000)

    def test_halt_and_resume_keep_native_denial_shape(self):
        self.hook("SessionStart", source="startup")
        self.run_cli("halt", "User requested a pause", "--project", sid=CODEX)
        response = json.loads(self.hook("PreToolUse", tool_name="apply_patch", tool_input={"command": "*** Begin Patch"}))
        self.assertEqual(response["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(self.hook("PreToolUse", tool_name="Bash", tool_input={"command": "longrun resume"}), "")
        self.run_cli("resume", sid=CODEX)
        self.assertEqual(self.hook("PreToolUse", tool_name="apply_patch", tool_input={"command": "*** Begin Patch"}), "")

    def test_resume_and_watch_route_to_codex(self):
        self.stubs()
        self.hook("SessionStart", source="startup")
        self.hook("SessionStart", sid=OTHER, source="startup")
        self.assertIn("resumed codex", self.run_cli("send", "--resume", "--model", "test-model", OTHER, "Continue", sid=CODEX))
        calls = [json.loads(l) for l in (self.base / "calls.jsonl").read_text().splitlines()]
        self.assertEqual(calls[0][:4], ["codex", "exec", "resume", OTHER])
        self.assertIn("test-model", calls[0])
        self.run_cli("send", "--resume", "--mode", "bypassPermissions", OTHER, "Continue", sid=CODEX, expected=2)
        self.run_cli("watch", "add", "--to", OTHER, "--no-test", "--wake", "--then", "Continue", "--", "cmd", "true", sid=CODEX)
        self.run_cli("watch", "run", "--force")
        calls = [json.loads(l) for l in (self.base / "calls.jsonl").read_text().splitlines()]
        self.assertEqual(calls[-1][:4], ["codex", "exec", "resume", OTHER])

    def test_mcp_explicit_context_routes_late_answers(self):
        loader = importlib.machinery.SourceFileLoader("longrun_test", str(CLI))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        module.GLOBAL_DIR = str(self.fake_home / ".claude/longrun")
        self.hook("SessionStart", source="startup")
        self.hook("SessionStart", sid=OTHER, source="startup")
        self.assertEqual(module.mcp_context(CODEX)["sid"], CODEX)
        self.assertEqual(module.mcp_context(OTHER)["store"].local, str(self.project / ".longrun"))
        for tool in module.MCP_TOOLS:
            self.assertIn("session_id", tool["inputSchema"]["properties"])

    def test_mcp_run_keeps_each_threads_notes_and_reports_errors(self):
        self.hook("SessionStart", source="startup")
        self.hook("SessionStart", sid=OTHER, source="startup")
        env = dict(self.env, LONGRUN_CLIENT="codex")
        with subprocess.Popen([str(CLI), "mcp"], cwd=self.project, env=env, text=True,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as p:
            def call(mid, sid, args):
                request = dict(jsonrpc="2.0", id=mid, method="tools/call", params=dict(name="run", arguments=dict(
                    session_id=sid, cwd=str(self.project), args=args)))
                p.stdin.write(json.dumps(request) + "\n")
                p.stdin.flush()
                self.assertTrue(select.select([p.stdout], [], [], 10)[0], "MCP did not answer")
                result = json.loads(p.stdout.readline())
                self.assertEqual(result["id"], mid)
                return result["result"]
            self.assertFalse(call(1, CODEX, ["add", "--own", "-t", "ctx", "Only first thread"])["isError"])
            self.assertFalse(call(2, OTHER, ["add", "--own", "-t", "ctx", "Only second thread"])["isError"])
            first = call(3, CODEX, ["notes", "--own"])["content"][0]["text"]
            second = call(4, OTHER, ["notes", "--own"])["content"][0]["text"]
            self.assertIn("Only first thread", first)
            self.assertNotIn("Only second thread", first)
            self.assertIn("Only second thread", second)
            self.assertNotIn("Only first thread", second)
            self.assertTrue(call(5, CODEX, ["unknown-command"])["isError"])
            self.assertTrue(call(6, CODEX, ["hook", "SessionEnd"])["isError"])
            p.stdin.close()
            p.wait(timeout=10)

    def test_relocated_store_and_uninstall_preserve_other_client(self):
        self.stubs()
        data = self.base / "shared data"
        self.env["LONGRUN_HOME"] = str(data)
        self.install("--both")
        calls = [json.loads(line) for line in (self.base / "calls.jsonl").read_text().splitlines()]
        registrations = [call for call in calls if call[1:3] == ["mcp", "add"]]
        self.assertEqual({call[0] for call in registrations}, {"claude", "codex"})
        for call in registrations:
            self.assertIn("LONGRUN_HOME=" + str(data), call)
        self.hook("SessionStart", source="startup")
        self.assertTrue((data / "sessions/_index" / (CODEX + ".json")).exists())
        self.assertFalse((self.fake_home / ".claude/longrun/sessions/_index" / (CODEX + ".json")).exists())
        self.install("--claude", "--uninstall")
        self.assertTrue((self.fake_home / ".agents/skills/longrun/SKILL.md").exists())
        self.assertTrue((self.fake_home / ".local/bin/longrun").is_file())
        self.assertTrue(data.exists())
        self.install("--codex", "--purge")
        self.assertFalse(data.exists())
        self.assertFalse((self.fake_home / ".local/bin/longrun").exists())
        self.assertTrue((self.project / ".longrun/NOTES.md").exists())

    def test_install_idempotent_and_single_client_uninstall(self):
        self.stubs()
        # A user-chosen skill root need not have a directory named "skills".
        codex_skills = self.base / "custom 'skill root"
        self.env["LONGRUN_CODEX_SKILLS_DIR"] = str(codex_skills)
        cc = self.fake_home / ".claude/settings.json"
        cx = self.fake_home / ".codex/hooks.json"
        foreign = dict(type="command", command="echo external hook")
        old = dict(type="command", command="/old/skills/longrun/scripts/longrun hook Stop")
        for p in (cc, cx):
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(dict(custom="keep", hooks=dict(Stop=[dict(hooks=[foreign, old])]))))
        self.install("--both")
        installed = [json.loads(p.read_text()) for p in (cc, cx)]
        self.install("--both")
        self.assertEqual(installed, [json.loads(p.read_text()) for p in (cc, cx)])
        for d in installed:
            self.assertEqual(d["custom"], "keep")
            self.assertEqual(d["hooks"]["Stop"][0]["hooks"], [foreign])
        self.assertEqual(len(installed[0]["hooks"]), 12)
        self.assertEqual(len(installed[1]["hooks"]), 10)
        # Execute installed hook commands: verifies shell quoting with spaces and apostrophes.
        handler = installed[1]["hooks"]["SessionStart"][-1]["hooks"][0]["command"]
        r = subprocess.run(handler, shell=True, env=self.env, cwd=self.project,
                           input=json.dumps(dict(session_id=CODEX, cwd=str(self.project), source="startup")),
                           text=True, capture_output=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("<longrun", r.stdout)
        self.install("--codex", "--purge", expected=2)
        self.assertTrue((codex_skills / "longrun/SKILL.md").exists())
        self.install("--codex", "--uninstall")
        self.assertTrue((self.fake_home / ".claude/skills/longrun/SKILL.md").exists())
        self.assertFalse((codex_skills / "longrun/SKILL.md").exists())
        self.assertTrue((self.fake_home / ".local/bin/longrun").is_file())
        self.assertEqual(json.loads(cx.read_text())["hooks"]["Stop"][0]["hooks"], [foreign])
        self.assertTrue((self.fake_home / ".claude/longrun").exists())

    def test_default_install_stays_claude_and_bad_config_is_untouched(self):
        self.stubs()
        self.install()
        self.assertTrue((self.fake_home / ".claude/skills/longrun/SKILL.md").exists())
        self.assertFalse((self.fake_home / ".codex/hooks.json").exists())
        invalid = self.fake_home / ".codex/hooks.json"
        invalid.parent.mkdir(parents=True)
        invalid.write_text("invalid json")
        before = (self.fake_home / ".claude/settings.json").read_bytes()
        self.install("--both", expected=1)
        self.assertEqual((self.fake_home / ".claude/settings.json").read_bytes(), before)
        self.assertEqual(invalid.read_text(), "invalid json")


if __name__ == "__main__":
    unittest.main(verbosity=2)
