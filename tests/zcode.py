#!/usr/bin/env python3
"""ZCode contract tests with isolated stores and installed hook commands, no live client."""
import json
import select
from pathlib import Path
import subprocess
import unittest

import codex
from codex import ROOT, CLI, CODEX, OTHER, CLAUDE


class ZCodeTests(unittest.TestCase):
    setUp = codex.CodexTests.setUp
    tearDown = codex.CodexTests.tearDown
    run_cli = codex.CodexTests.run_cli
    meta = codex.CodexTests.meta
    journal = codex.CodexTests.journal
    stubs = codex.CodexTests.stubs
    install = codex.CodexTests.install

    def zcli(self, *args, sid=CODEX, expected=0):
        env = dict(self.env, LONGRUN_CLIENT="zcode")
        if sid:
            env["LONGRUN_SESSION"] = sid
        r = subprocess.run([str(CLI), *args], cwd=self.project, env=env,
                           text=True, capture_output=True, timeout=20)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout

    def hook(self, event, sid=CODEX, expected=0, **fields):
        payload = dict(session_id=sid, cwd=str(self.project), hook_event_name=event)
        payload.update(fields)
        raw = self.run_cli("hook", "--client", "zcode", event, expected=expected, input=json.dumps(payload))
        if not raw:
            return {}
        result = json.loads(raw)  # ZCode discards plain stdout; exactly one JSON reply is required
        self.assertEqual(result["hookSpecificOutput"]["hookEventName"], event)
        return result["hookSpecificOutput"]

    def start(self, sid=CODEX, **fields):
        return self.hook("SessionStart", sid=sid, source="startup", **fields)

    @property
    def config_path(self):
        return self.fake_home / ".zcode/cli/config.json"

    def config(self):
        return json.loads(self.config_path.read_text())

    def write_config(self, value):
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        self.config_path.write_text(json.dumps(value))

    def test_startup_json_and_explicit_session_route(self):
        self.run_cli("add", "-t", "pin", "A shared project invariant")
        ctx = self.start()["additionalContext"]
        self.assertIn("A shared project invariant", ctx)
        self.assertIn("LONGRUN_CLIENT=zcode LONGRUN_SESSION=" + CODEX, ctx)
        self.assertEqual(self.meta()["client"], "zcode")
        # Execute the exact prefix the model sees, including paths with quotes/spaces.
        route = ctx.split("Run protocol commands with: ", 1)[1].split(" <args>.", 1)[0]
        r = subprocess.run(route + " add --own -t ctx 'Bound to the supplied conversation'", shell=True,
                           cwd=self.project, env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("Bound to the supplied conversation", self.hook("SessionStart", source="compact")["additionalContext"])

    def test_prompt_and_compaction_keep_identity_and_own_notes(self):
        self.start()
        self.zcli("add", "--own", "-t", "ctx", "Only this ZCode chat")
        self.start(sid=OTHER)
        self.zcli("add", "--own", "-t", "ctx", "Only the other ZCode chat", sid=OTHER)
        own = self.hook("SessionStart", source="compact")["additionalContext"]
        self.assertIn("Only this ZCode chat", own)
        self.assertNotIn("Only the other ZCode chat", own)
        prompt = self.hook("UserPromptSubmit", prompt="Continue")["additionalContext"]
        self.assertIn("session_id=" + CODEX, prompt)
        self.assertEqual(self.meta()["compactions"], 1)

    def test_shared_notes_across_all_clients(self):
        codex.CodexTests.hook(self, "SessionStart", sid=CLAUDE, client="claude", source="startup")
        codex.CodexTests.hook(self, "SessionStart", sid=OTHER, client="codex", source="startup")
        self.start()
        self.zcli("add", "-t", "pin", "Shared by three clients")
        self.zcli("add", "--own", "-t", "ctx", "Private ZCode state")
        for client, sid in (("claude", CLAUDE), ("codex", OTHER)):
            ctx = codex.CodexTests.hook(self, "SessionStart", sid=sid, client=client, source="compact")
            self.assertIn("Shared by three clients", ctx)
            self.assertNotIn("Private ZCode state", ctx)

    def test_no_identity_does_not_borrow_peer_or_consume_inbox(self):
        self.start()
        self.start(sid=OTHER)
        self.zcli("send", OTHER, "Pending for the other chat")
        before = self.meta(OTHER)
        self.assertEqual(self.hook("UserPromptSubmit", sid="", prompt="Continue"), {})
        self.assertEqual(self.meta(OTHER), before)
        self.assertIn("session:  none known", self.zcli("where", sid=""))
        self.zcli("add", "--own", "-t", "ctx", "Do not steal identity", sid="", expected=3)
        self.assertIn("Pending for the other chat", self.hook("UserPromptSubmit", sid=OTHER)["additionalContext"])

    def test_hook_can_bind_mid_session(self):
        self.hook("UserPromptSubmit", prompt="Existing chat")
        self.assertEqual(self.meta()["client"], "zcode")
        self.assertEqual(self.meta()["turns"], 1)

    def test_temporary_transcript_not_retained_or_used_for_context(self):
        transcript = self.base / "temporary.jsonl"
        transcript.write_text(json.dumps({"type": "assistant", "message": {"usage": {"input_tokens": 999999}, "model": "claude-opus-4-1"}}) + "\n")
        self.start(transcript_path=str(transcript))
        self.hook("Stop", transcript_path=str(transcript), last_assistant_message="Done")
        self.assertFalse(self.meta().get("transcript"))
        self.assertNotIn("ctx_tokens", self.meta())
        transcript.unlink()
        self.assertIn("source=compact", self.hook("SessionStart", source="compact")["additionalContext"])

    def test_recall_does_not_search_claude_history(self):
        self.start()
        project_key = "-".join(str(self.project).split("/"))
        history = self.fake_home / ".claude/projects" / project_key
        history.mkdir(parents=True)
        (history / (CODEX + ".jsonl")).write_text(json.dumps({"type": "user", "message": {"content": "foreign_transcript_marker"}}) + "\n")
        self.assertIn("0 transcript(s)", self.zcli("recall", "foreign_transcript_marker", expected=1))

    def test_successful_read_calls_count_without_post_tool_batch(self):
        self.start()
        self.hook("UserPromptSubmit", prompt="Read code")
        for i in range(6):
            self.hook("PostToolUse", tool_name="Read", tool_use_id="r%d" % i,
                      tool_input={"file_path": str(self.project / "source.py")}, tool_response={"content": "code"})
        self.assertEqual(self.meta()["turn_tools"], 6)
        self.hook("Stop", last_assistant_message="Read six files")
        self.assertEqual(self.meta()["turn_card"]["tools"], 6)

    def test_patch_alias_records_all_changed_files(self):
        self.start()
        paths = [str(self.project / "a.py"), str(self.project / "b.py")]
        self.hook("PostToolUse", tool_name="ApplyPatch", tool_use_id="patch1",
                  tool_input={"patch": "*** Begin Patch\n*** Update File: a.py\n*** Add File: b.py\n*** End Patch"})
        self.assertEqual(self.meta()["files"], paths)
        self.assertEqual(self.meta()["turn_files"], paths)

    def test_search_context_and_inbox_are_delivered_once(self):
        self.start()
        self.start(sid=OTHER)
        self.zcli("send", OTHER, "Review the callback contract")
        ctx = self.hook("PostToolUse", sid=OTHER, tool_name="Grep", tool_use_id="g1", tool_input={"pattern": "callback"})
        self.assertIn("Review the callback contract", ctx["additionalContext"])
        again = self.hook("UserPromptSubmit", sid=OTHER)
        self.assertNotIn("Review the callback contract", again["additionalContext"])

    def test_failed_calls_clear_running_state_and_deliver_messages(self):
        self.start()
        self.start(sid=OTHER)
        self.hook("PreToolUse", tool_name="Bash", tool_use_id="f1", tool_input={"command": "false"})
        self.zcli("send", CODEX, "Inspect this failure", sid=OTHER)
        ctx = self.hook("PostToolUseFailure", tool_name="Bash", tool_use_id="f1", tool_input={"command": "false"}, error="exit 1\nfailure")
        self.assertIn("Inspect this failure", ctx["additionalContext"])
        self.assertEqual(self.meta()["fails"], 1)
        self.assertEqual(self.meta()["turn_tools"], 1)
        self.assertFalse(self.meta()["running"])
        self.assertIn("FAIL `false`", self.journal())

    def test_failed_edit_is_counted(self):
        self.start()
        self.hook("PostToolUseFailure", tool_name="Edit", tool_use_id="failed-edit", tool_input={"file_path": "a.py"}, error="Cannot match old text")
        self.assertEqual(self.meta()["turn_tools"], 1)
        self.assertEqual(self.meta()["fails"], 1)
        self.assertIn("Edit a.py", self.journal())

    def test_interrupt_clears_marker_without_failure(self):
        self.start()
        self.hook("PreToolUse", tool_name="Bash", tool_use_id="interrupt", tool_input={"command": "sleep 10"})
        self.hook("PostToolUseFailure", tool_name="Bash", tool_use_id="interrupt", error="cancelled", is_interrupt=True)
        self.assertFalse(self.meta()["running"])
        self.assertEqual(self.meta()["fails"], 0)

    def test_halt_denies_tool_and_permission_hook_never_grants(self):
        self.start()
        self.zcli("halt", "Wait for review")
        ctx = self.hook("PreToolUse", tool_name="Write", tool_use_id="halt1", tool_input={"file_path": "a.py", "content": "x"})
        self.assertEqual(ctx["permissionDecision"], "deny")
        self.assertIn("Wait for review", ctx["permissionDecisionReason"])
        route = self.hook("UserPromptSubmit")["additionalContext"].split("Run protocol commands with: ", 1)[1].split(" <args>.", 1)[0]
        exempt = self.hook("PreToolUse", tool_name="Bash", tool_use_id="longrun-read", tool_input={"command": route + " where"})
        self.assertNotIn("permissionDecision", exempt)
        self.zcli("resume")
        self.assertEqual(self.hook("PermissionRequest", tool_name="Bash", tool_input={"command": "make"}), {})
        self.assertIn("waiting_since", self.meta())

    def test_resume_and_wake_refuse_before_mutation(self):
        self.start()
        self.start(sid=OTHER)
        self.stubs()
        self.zcli("send", "--resume", OTHER, "Resume please", expected=2)
        self.zcli("watch", "add", "--to", OTHER, "--wake", "--then", "Continue", "--", "at", "+1h", expected=2)
        self.assertFalse((self.base / "calls.jsonl").exists())
        self.assertFalse(list((self.fake_home / ".claude/longrun/watch").glob("w*.json")))

    def test_unsupported_events_refuse(self):
        self.start()
        before = self.meta()
        for event in ("PreCompact", "PostCompact", "PostToolBatch", "SessionEnd", "Interrupt"):
            self.hook(event, expected=2)
        self.zcli("compact-hint", "--set", "Do not pretend this is supported", expected=2)
        self.assertEqual(self.meta(), before)

    def test_installed_hook_command_emits_valid_json(self):
        self.install("--zcode")
        config = self.config()
        self.assertTrue(config["hooks"]["enabled"])
        command = config["hooks"]["events"]["SessionStart"][0]["hooks"][0]["command"]
        r = subprocess.run(command, shell=True, input=json.dumps({"session_id": CODEX, "cwd": str(self.project), "source": "startup"}),
                           env=self.env, cwd=self.project, capture_output=True, text=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        ctx = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual(ctx["hookEventName"], "SessionStart")
        self.assertIn(CODEX, ctx["additionalContext"])

    def test_install_idempotent_and_preserves_foreign_hooks_and_disable(self):
        foreign = {"type": "process", "command": "node", "args": ["/other/context.mjs"]}
        initial = {"model": "glm", "permissions": {"mode": "ask"}, "hooks": {"enabled": False, "timeoutMs": 9000, "maxOutputBytes": 40960,
                    "events": {"SessionStart": [{"hooks": [foreign]}]}}}
        self.write_config(initial)
        self.install("--zcode")
        first = self.config()
        self.install("--zcode")
        self.assertEqual(self.config(), first)
        self.assertFalse(first["hooks"]["enabled"])
        self.assertEqual(first["hooks"]["timeoutMs"], 9000)
        self.assertEqual(first["hooks"]["maxOutputBytes"], 40960)
        self.assertEqual(first["permissions"], initial["permissions"])
        self.assertEqual(first["hooks"]["events"]["SessionStart"][0]["hooks"], [foreign])
        self.assertTrue(list((self.fake_home / ".zcode/backups").glob("*.longrun.bak")))
        self.install("--zcode", "--uninstall")
        self.assertEqual(self.config(), initial)

    def test_uninstall_mixed_group_preserves_foreign_handler(self):
        self.install("--zcode")
        config = self.config()
        foreign = {"type": "command", "command": "echo other"}
        config["hooks"]["events"]["SessionStart"][0]["hooks"].append(foreign)
        self.write_config(config)
        self.install("--zcode", "--uninstall")
        self.assertEqual(self.config()["hooks"]["events"], {"SessionStart": [{"hooks": [foreign]}]})
        self.assertFalse((self.fake_home / ".zcode/skills/longrun").exists())

    def test_all_clients_and_uninstall_keep_surviving_cli(self):
        self.stubs()
        self.install("--all")
        for location in (".claude/skills", ".agents/skills", ".zcode/skills"):
            self.assertTrue((self.fake_home / location / "longrun/SKILL.md").exists())
        self.install("--both", "--uninstall")
        link = self.fake_home / ".local/bin/longrun"
        self.assertEqual(link.resolve(), self.fake_home / ".zcode/skills/longrun/scripts/longrun")
        self.assertTrue(link.exists())
        self.install("--zcode", "--uninstall")
        self.assertFalse(link.is_symlink())

    def test_zcode_uninstall_keeps_codex_cli(self):
        self.stubs()
        self.install("--codex")
        self.install("--zcode")
        self.install("--zcode", "--uninstall")
        self.assertEqual((self.fake_home / ".local/bin/longrun").resolve(), self.fake_home / ".agents/skills/longrun/scripts/longrun")

    def test_purge_refuses_if_unselected_client_remains(self):
        self.stubs()
        self.install("--all")
        before = self.config_path.read_bytes()
        self.install("--both", "--purge", expected=2)
        self.assertEqual(self.config_path.read_bytes(), before)
        self.install("--zcode", "--purge", expected=2)
        self.install("--all", "--purge")
        self.assertFalse((self.fake_home / ".claude/longrun").exists())
        self.assertTrue((self.project / ".longrun").exists())

    def test_invalid_config_does_not_modify_other_clients(self):
        self.stubs()
        self.install("--both")
        claude_path = self.fake_home / ".claude/settings.json"
        before = claude_path.read_bytes()
        for value in ("not json", json.dumps({"hooks": {"events": []}}), json.dumps({"hooks": {"enabled": "true"}})):
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            self.config_path.write_text(value)
            self.install("--all", expected=1)
            self.assertEqual(claude_path.read_bytes(), before)
            self.assertEqual(self.config_path.read_text(), value)
            self.assertFalse((self.fake_home / ".zcode/skills/longrun").exists())

    def test_imported_symlink_does_not_overwrite_codex(self):
        self.stubs()
        self.install("--codex")
        source = self.fake_home / ".agents/skills/longrun"
        before = (source / "SKILL.md").read_bytes()
        dest = self.fake_home / ".zcode/skills/longrun"
        dest.parent.mkdir(parents=True)
        dest.symlink_to(source, target_is_directory=True)
        self.install("--zcode")
        self.assertFalse(dest.is_symlink())
        self.assertEqual((source / "SKILL.md").read_bytes(), before)
        backups = list((self.fake_home / ".zcode/backups").glob("*.symlink"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].resolve(), source)

    def test_watch_without_wake_queues_for_next_hook(self):
        self.start()
        marker = self.base / "ready"
        self.zcli("watch", "add", "--then", "Continue after readiness", "--", "file", str(marker))
        marker.touch()
        self.zcli("watch", "run", "--force")
        ctx = self.hook("UserPromptSubmit")["additionalContext"]
        self.assertIn("Continue after readiness", ctx)
        self.assertIn("CONDITION MET", ctx)
        self.assertNotIn("Continue after readiness", self.hook("UserPromptSubmit")["additionalContext"])

    def test_board_handoff_reaches_zcode_on_read(self):
        self.start()
        self.start(sid=OTHER)
        self.zcli("board", "add", "Implement callback retries")
        self.zcli("board", "assign", "T1", OTHER)
        ctx = self.hook("PostToolUse", sid=OTHER, tool_name="Read", tool_use_id="board-read", tool_input={"file_path": "callback.py"})["additionalContext"]
        self.assertIn("Implement callback retries", ctx)
        self.zcli("board", "take", "T1", sid=OTHER)
        self.zcli("board", "done", "T1", "Verified retries", sid=OTHER)
        self.assertIn("Verified retries", self.zcli("board", "ls", "--all"))

    def test_optional_mcp_routes_explicit_zcode_identity(self):
        self.start()
        self.start(sid=OTHER)
        env = dict(self.env, LONGRUN_CLIENT="zcode")
        with subprocess.Popen([str(CLI), "mcp"], cwd=self.project, env=env, text=True,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
            def call(mid, sid, args):
                request = dict(jsonrpc="2.0", id=mid, method="tools/call", params=dict(name="run", arguments=dict(
                    session_id=sid, cwd=str(self.project), args=args)))
                proc.stdin.write(json.dumps(request) + "\n")
                proc.stdin.flush()
                self.assertTrue(select.select([proc.stdout], [], [], 10)[0], "MCP did not answer")
                response = json.loads(proc.stdout.readline())
                self.assertEqual(response["id"], mid)
                return response["result"]
            self.assertFalse(call(1, CODEX, ["add", "--own", "-t", "ctx", "MCP private state"])["isError"])
            self.assertIn("MCP private state", call(2, CODEX, ["notes", "--own"])["content"][0]["text"])
            self.assertNotIn("MCP private state", call(3, OTHER, ["notes", "--own"])["content"][0]["text"])
            self.assertTrue(call(4, "", ["add", "--own", "-t", "ctx", "Missing identity"])["isError"])
            proc.stdin.close()
            proc.wait(timeout=10)

    def test_zcode_directory_override(self):
        dest = self.base / "custom zcode"
        self.env["LONGRUN_ZCODE_DIR"] = str(dest)
        self.install("--zcode")
        self.assertTrue((dest / "skills/longrun/SKILL.md").exists())
        self.assertTrue((dest / "cli/config.json").exists())
        self.assertFalse(self.config_path.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
