#!/bin/bash
# Orchestrator layer: board, facts, the orchestrator lock, halt/resume, telemetry hooks, the watcher's stuck scan,
# interrupt. Synthetic, no API calls, nothing outside a temp dir (the interrupt test kills only a child of this shell).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LR="$HERE/../skill/longrun/scripts/longrun"
T="$(mktemp -d /tmp/longrun-orch.XXXXXX)"
export CLAUDE_CONFIG_DIR="$T/claude" HOME="$T/home" LONGRUN_NO_TIMER=1
export LONGRUN_NO_UI=1                     # never a real dialog or notification from a test
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/sessions"
unset LONGRUN_DIR LONGRUN_SESSION LONGRUN_SCOPE LONGRUN_TRANSCRIPT CLAUDE_ENV_FILE CLAUDE_CODE_AUTO_COMPACT_WINDOW
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
A=aaaa1111-0000-4000-8000-000000000001; B=bbbb2222-0000-4000-8000-000000000002; C=cccc3333-0000-4000-8000-000000000003
P="$T/proj"; mkdir -p "$P"; cd "$P"; "$LR" init >/dev/null; L="$P/.longrun"
SESS="$CLAUDE_CONFIG_DIR/longrun/sessions"
start(){ printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" "${2:-/x.jsonl}" "$P" | "$LR" hook SessionStart; }
turn(){ printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"go"}' "$1" "$P" | "$LR" hook UserPromptSubmit; }
pre(){ printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"},"tool_use_id":"%s"}' "$1" "$P" "$2" "$3" "$4" | "$LR" hook PreToolUse; }
post(){ printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"x"},"tool_use_id":"%s","tool_response":{}}' "$1" "${3:-/x.jsonl}" "$P" "$2" | "$LR" hook PostToolUse; }
stop(){ printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s"}' "$1" "${3:-/x.jsonl}" "$P" "$2" | "$LR" hook Stop; }
meta(){ cat "$SESS"/*/"${1:0:8}"/meta.json; }
start $A >/dev/null; start $B >/dev/null; start $C >/dev/null

echo "== orchestrator lock: one per project, mirrored outside the project"
LONGRUN_SESSION=$A "$LR" orchestrate start --goal "ship the informer" > /tmp/lo-out 2>&1
check "start prints the role" "grep -q 'ORCHESTRATOR' /tmp/lo-out && grep -q 'ship the informer' '$L/board.json'"
check "lock in the project and its mirror" "test -f '$L/orchestrator.json' && ls '$CLAUDE_CONFIG_DIR'/longrun/projects/*/orchestrator.json >/dev/null 2>&1"
LONGRUN_SESSION=$B "$LR" orchestrate start > /tmp/lo-out 2>&1; RC=$?
check "a second session is refused with the holder's name (exit 2)" "test $RC -eq 2 && grep -q 'is the orchestrator' /tmp/lo-out"
LONGRUN_SESSION=$B "$LR" orchestrate start --force >/dev/null 2>&1; check "--force takes over" "grep -q 'bbbb2222' '$L/orchestrator.json'"
LONGRUN_SESSION=$A "$LR" orchestrate start --force >/dev/null 2>&1
check "status names the orchestrator" "LONGRUN_SESSION=$C '$LR' orchestrate | grep -q 'orchestrator: .*aaaa1111.*since'"

echo "== board: add / assign / take / done / block / dependencies"
LONGRUN_SESSION=$A "$LR" board add "write the informer" >/dev/null
LONGRUN_SESSION=$A "$LR" board add "release it" --after T1 >/dev/null
LONGRUN_SESSION=$A "$LR" board add "write docs" --for $C --quiet >/dev/null
check "tasks T1..T3 on the board, T3 assigned to C" "grep -q '\"T3\"' '$L/board.json' && grep -q '\"assigned\": \"cccc3333\"' '$L/board.json'"
check "assignment queued in C's inbox" "ls '$L/inbox/' | grep -q 'msg-to-cccc3333'"
LONGRUN_SESSION=$A "$LR" board assign T1 $B --quiet >/dev/null
OUT="$(turn $B)"; check "B's next turn shows YOUR TASK T1 with the take command" "echo \"\$OUT\" | grep -q 'YOUR TASK T1' && echo \"\$OUT\" | grep -q 'board take T1'"
LONGRUN_SESSION=$B "$LR" board take T2 >/tmp/lo-out 2>&1; RC=$?; check "a task waiting on another is refused (exit 2)" "test $RC -eq 2 && grep -q 'waits for T1' /tmp/lo-out"
LONGRUN_SESSION=$B "$LR" board take T1 >/dev/null; check "take -> doing with owner" "grep -q '\"state\": \"doing\"' '$L/board.json' && grep -q '\"owner\": \"bbbb2222\"' '$L/board.json'"
LONGRUN_SESSION=$C "$LR" board take T1 >/tmp/lo-out 2>&1; RC=$?; check "taking someone else's doing task is refused" "test $RC -eq 2 && grep -q 'being done by' /tmp/lo-out"
LONGRUN_SESSION=$B "$LR" board block T1 "which field name: informer_id or id?" >/dev/null
check "block -> message to the orchestrator's inbox" "ls '$L/inbox/' | grep -q 'msg-to-aaaa1111' && grep -l 'BLOCKED T1' '$L/inbox/'*msg-to-aaaa1111* >/dev/null"
LONGRUN_SESSION=$B "$LR" board take T1 >/dev/null
LONGRUN_SESSION=$B "$LR" board done T1 "merged as PR 42" >/dev/null
check "done -> state done with outcome, T2 unblocked" "grep -q '\"outcome\": \"merged as PR 42\"' '$L/board.json' && ! LONGRUN_SESSION=$C '$LR' board | grep -q 'T2 .*waits for'"
check "board listing: goal, counts" "'$LR' board | grep -q 'GOAL: ship the informer' && '$LR' board | grep -q 'done 1, todo 2'"
OUT="$(turn $A)"; check "the orchestrator's turn carries the DONE message and the board changes" "echo \"\$OUT\" | grep -q 'DONE T1' && echo \"\$OUT\" | grep -q 'BOARD changes'"
OUT="$(turn $A)"; check "nothing repeats on the next turn" "! echo \"\$OUT\" | grep -q 'BOARD changes'"
LONGRUN_SESSION=$B "$LR" board done T1 --quiet >/dev/null 2>&1; OUT="$(turn $B)"; check "a session's own board change is not echoed back to it" "! echo \"\$OUT\" | grep -q 'BOARD changes'"

echo "== facts: record, reach the orchestrator, ack"
LONGRUN_SESSION=$B "$LR" fact "reviewer asks to rename field foo to informer_id" --task T2 --source review >/tmp/lo-out
check "fact F1 recorded and sent to the orchestrator" "grep -q 'F1 recorded -> orchestrator via inbox' /tmp/lo-out && grep -q '\"source\": \"review\"' '$L/board.json'"
LONGRUN_SESSION=$B "$LR" fact "x" --source bogus >/dev/null 2>&1; check "bad source refused" "test $? -eq 2"
D="$(LONGRUN_SESSION=$A "$LR" digest)"; check "orchestrator digest: role, FACTS unhandled, role text" "echo \"\$D\" | grep -q 'role=orchestrator' && echo \"\$D\" | grep -q 'FACTS unhandled (1)' && echo \"\$D\" | grep -q 'You are this project.s ORCHESTRATOR'"
D="$(LONGRUN_SESSION=$C "$LR" digest)"; check "worker digest: ORCHESTRATOR line, BOARD, no FACTS block" "echo \"\$D\" | grep -q 'ORCHESTRATOR: .*aaaa1111' && echo \"\$D\" | grep -q 'BOARD (' && ! echo \"\$D\" | grep -q 'FACTS unhandled'"
LONGRUN_SESSION=$A "$LR" fact ack F1 "relayed to B" >/dev/null; check "ack marks handled with the decision" "grep -q '\"ack\": \"relayed to B\"' '$L/board.json' && LONGRUN_SESSION=$A '$LR' fact ls | grep -q '(0 unhandled)'"

echo "== halt / resume through PreToolUse"
LONGRUN_SESSION=$A "$LR" halt "5h usage at 45% after 1.5h" >/dev/null
OUT="$(pre $B Bash "ls -la" t1)"; check "halt: PreToolUse denies with the reason" "echo \"\$OUT\" | grep -q '\"permissionDecision\": \"deny\"' && echo \"\$OUT\" | grep -q '45% after 1.5h'"
OUT="$(pre $B Read "" t2)"; check "halt: every tool, not only Bash" "echo \"\$OUT\" | grep -q 'deny'"
OUT="$(pre $B Bash "cd /tmp && longrun resume" t3)"; check "halt: the longrun CLI itself is exempt" "test -z \"\$OUT\""
OUT="$(turn $B)"; check "halt: the turn injection says so" "echo \"\$OUT\" | grep -q 'HALT in force'"
D="$(LONGRUN_SESSION=$C "$LR" digest)"; check "halt: the digest says so" "echo \"\$D\" | grep -q 'HALT in force'"
"$LR" resume >/dev/null; OUT="$(pre $B Bash "ls" t4)"; check "resume: tools run again (nothing printed)" "test -z \"\$OUT\" && ! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"

echo "== telemetry: running tools, turn age, waiting, ctx from the transcript"
pre $B Bash "ya make -tt" t5 >/dev/null; check "PreToolUse records the running tool" "meta $B | grep -q '\"cmd\": \"ya make -tt\"'"
pre $B Bash "longrun status" t6 >/dev/null; check "a longrun CLI call is not recorded" "! meta $B | grep -q 'longrun status'"
post $B t5 >/dev/null; check "PostToolUse clears it by tool_use_id" "! meta $B | grep -q 'ya make -tt'"
printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' "$B" "$P" | "$LR" hook PermissionRequest
check "PermissionRequest marks waiting" "meta $B | grep -q '\"waiting_what\": \"permission (Bash)\"'"
printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Notification","notification_type":"agent_needs_input","message":"x"}' "$B" "$P" | "$LR" hook Notification
check "Notification(agent_needs_input) marks waiting for input" "meta $B | grep -q '\"waiting_what\": \"input\"'"
post $B t9 >/dev/null; check "PostToolUse clears waiting" "! meta $B | grep -q 'waiting_since'"
turn $B >/dev/null; check "UserPromptSubmit stamps turn_started" "meta $B | grep -q 'turn_started'"
TR="$T/tr.jsonl"; python3 - "$TR" <<'PY'
import json,sys
lines=[{"type":"user","message":{"role":"user","content":"hi"}},
       {"type":"assistant","message":{"model":"claude-fable-5-1","usage":{"input_tokens":3,"cache_read_input_tokens":250000,"cache_creation_input_tokens":12000,"output_tokens":50}}},
       {"type":"user","message":{"role":"user","content":[{"tool_use_id":"x","type":"tool_result","content":"ok"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(l) for l in lines)+"\n")
PY
echo '{"autoCompactWindow": "300k"}' > "$CLAUDE_CONFIG_DIR/settings.json"
stop $B "working" "$TR" >/dev/null; check "Stop samples ctx: 262k of the 300k window from the user settings" "meta $B | grep -q '\"ctx_tokens\": 262003' && meta $B | grep -q '\"ctx_window\": 300000'"
check "Stop clears turn_started and running" "! meta $B | grep -q 'turn_started' && meta $B | grep -q '\"running\": {}'"
OUT="$(post $B t7 "$TR")"; check "PostToolUse warns near the window (once) and tells the orchestrator" "echo \"\$OUT\" | grep -q 'context 262k of the 300k' && ls '$L/inbox/' | grep -c 'msg-to-aaaa1111' | grep -q '[1-9]'"
OUT="$(post $B t8 "$TR")"; check "the warning does not repeat every call" "! echo \"\$OUT\" | grep -q 'context 262k'"
check "status and the sessions block show flags" "LONGRUN_SESSION=$A '$LR' status | grep -q 'ctx 262k/300k (87%)' && LONGRUN_SESSION=$A '$LR' digest | grep -q 'ctx 262k/300k'"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 python3 -c "import sys; sys.argv=['x']; exec(open('$LR').read().split('def main(argv)')[0]); print(autocompact_window('claude-fable-5-1'))" | grep -q '^200000$' && ok "env window wins over the setting" || bad "env window wins over the setting"
python3 -c "exec(open('$LR').read().split('def main(argv)')[0]); print(model_window('claude-opus-4-6'), model_window('claude-sonnet-5'))" | grep -q '^200000 1000000$' && ok "model windows: 200k for 4.6, 1M for Sonnet 5" || bad "model windows"

echo "== watcher: stuck report once per episode, to the orchestrator"
pre $C Bash "ya make -A" t10 >/dev/null
python3 - "$SESS" <<'PY'
import json,glob,sys,datetime
old=(datetime.datetime.now()-datetime.timedelta(minutes=45)).strftime("%Y-%m-%d %H:%M")
for f in glob.glob(sys.argv[1]+"/*/cccc3333/meta.json"):
    m=json.load(open(f))
    for v in m.get("running",{}).values(): v["started"]=old
    m["turn_started"]=(datetime.datetime.now()-datetime.timedelta(minutes=70)).strftime("%Y-%m-%d %H:%M")
    json.dump(m,open(f,"w"))
PY
rm -f "$L"/inbox/*msg-to-aaaa1111*
"$LR" watch run --quiet; N1=$(ls "$L/inbox/" | grep -c 'from-longrun-watch'); check "tick: tool age and turn age reported" "grep -l 'STUCK?.*ya make -A.*running 4[5-7]m' '$L'/inbox/*watch* >/dev/null && grep -l 'turn running 7[0-2]m' '$L'/inbox/*watch* >/dev/null"
"$LR" watch run --quiet; N2=$(ls "$L/inbox/" | grep -c 'from-longrun-watch'); check "second tick: nothing new" "test $N1 -eq $N2"
post $C t10 >/dev/null; stop $C "done" >/dev/null; "$LR" watch run --quiet
check "flags clear when the condition does" "! python3 -c \"import json;print(json.load(open('$CLAUDE_CONFIG_DIR/longrun/watch/state.json')).get('stuck'))\" | grep -q 'cccc3333'"
for i in 1 2 3; do printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"ya make -tt"},"error":"Exit code 1\\nboom","tool_use_id":"f%s"}' "$C" "$P" "$i" | "$LR" hook PostToolUseFailure; done
"$LR" watch run --quiet; check "three identical FAILs in a row are reported as a loop" "grep -l 'failed 3 times in a row' '$L'/inbox/*watch* >/dev/null"

echo "== interrupt: dry run, then kill with --yes (a child of this test shell stands in for the session)"
bash -c 'sleep 120; echo shell-snapshots-stand-in' & SLEEPER=$!
printf '{"pid":%d,"sessionId":"%s","cwd":"%s","name":"worker-c","messagingSocketPath":""}' $$ "$C" "$P" > "$CLAUDE_CONFIG_DIR/sessions/$$.json"
LONGRUN_SESSION=$A "$LR" interrupt worker-c --match "sleep 120" > /tmp/lo-out 2>&1; RC=$?
check "dry run lists the process and refuses to kill without --yes" "test $RC -eq 0 && grep -q 'would interrupt' /tmp/lo-out && grep -q 'sleep 120' /tmp/lo-out && kill -0 $SLEEPER 2>/dev/null"
LONGRUN_SESSION=$A "$LR" interrupt worker-c --match "sleep 120" --yes --why "test" > /tmp/lo-out 2>&1
sleep 0.5; check "--yes kills it and tells the session why" "! kill -0 $SLEEPER 2>/dev/null && grep -q 'SIGTERM' /tmp/lo-out && grep -l 'interrupted by' '$L'/inbox/*msg-to-cccc3333* >/dev/null"
check "the interruption is in the target's journal" "grep -q 'interrupted by' '$SESS'/*/cccc3333/journal.md"
wait $SLEEPER 2>/dev/null
rm -f "$CLAUDE_CONFIG_DIR/sessions/$$.json"

echo "== orchestrate stop"
LONGRUN_SESSION=$B "$LR" orchestrate stop >/tmp/lo-out 2>&1; RC=$?; check "only the holder (or --force) stops" "test $RC -eq 2"
LONGRUN_SESSION=$A "$LR" orchestrate stop >/dev/null; check "stop clears the lock and its mirror" "! test -f '$L/orchestrator.json' && ! ls '$CLAUDE_CONFIG_DIR'/longrun/projects/*/orchestrator.json >/dev/null 2>&1"
D="$(LONGRUN_SESSION=$C "$LR" digest)"; check "digest without an orchestrator still shows the board" "echo \"\$D\" | grep -q 'ORCHESTRATOR: none' && echo \"\$D\" | grep -q 'BOARD ('"

echo "== budget: the 5-hour pace rule (endpoint replaced by a fixture)"
LONGRUN_SESSION=$A "$LR" orchestrate start --force >/dev/null 2>&1
FX="$T/usage.json"; export LONGRUN_BUDGET_FIXTURE="$FX"
fixture(){ python3 - "$FX" "$1" "$2" <<'PY'
import json,sys,datetime
util, hours_left = float(sys.argv[2]), float(sys.argv[3])
ra = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=hours_left)).isoformat()
json.dump({"five_hour": {"utilization": util, "resets_at": ra}, "seven_day": {"utilization": 42.0, "resets_at": ra}}, open(sys.argv[1], "w"))
PY
}
fixture 30 4.8; "$LR" budget check >/tmp/lo-out 2>&1; RC=$?
check "12 minutes into the window: quiet period, no halt" "test $RC -eq 0 && grep -q 'quiet period' /tmp/lo-out && ! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
fixture 20 3.5; "$LR" budget check >/tmp/lo-out 2>&1
check "20% after 1.5h (expected 30%): no halt, ratio shown" "grep -q 'ratio x0.67' /tmp/lo-out && ! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
rm -f "$L"/inbox/*msg-to-aaaa1111*
fixture 50 3.5; "$LR" budget check >/tmp/lo-out 2>&1
check "50% after 1.5h (x1.67): BUDGET STOP printed, halt.json kind=budget" "grep -q 'BUDGET STOP' /tmp/lo-out && grep -q '\"kind\": \"budget\"' '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
check "report file and a wake for the orchestrator (inbox here: no socket in tests)" "ls '$CLAUDE_CONFIG_DIR'/longrun/budget-report-*.md >/dev/null 2>&1 && grep -l 'BUDGET STOP' '$L'/inbox/*msg-to-aaaa1111* >/dev/null"
OUT="$(pre $B Bash "ls" t20)"; check "tools are refused with the usage reason" "echo \"\$OUT\" | grep -q 'usage pace: 5h window 50% used'"
check "budget status shows the stop" "'$LR' budget | grep -q 'last budget stop'"
"$LR" resume >/dev/null; check "resume lifts the halt and snoozes the rule until the window resets" "! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json' && grep -q 'snoozed_until' '$CLAUDE_CONFIG_DIR/longrun/budget.json'"
fixture 60 3.0; "$LR" budget check >/tmp/lo-out 2>&1; check "snoozed: a worse sample does not halt again" "! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json' && '$LR' budget | grep -q 'rule snoozed until'"
python3 -c "import json;p='$CLAUDE_CONFIG_DIR/longrun/budget.json';b=json.load(open(p));b['snoozed_until']=0;json.dump(b,open(p,'w'))"
"$LR" budget off >/dev/null; "$LR" budget check >/tmp/lo-out 2>&1; check "budget off: samples but never halts" "grep -q 'budget rule: off' /tmp/lo-out && ! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
"$LR" budget on >/dev/null; "$LR" budget set pace 25 >/dev/null; "$LR" budget set factor 2 >/dev/null
"$LR" budget check >/tmp/lo-out 2>&1; check "pace 25/factor 2: 60% after 2h (limit 100%) is fine" "grep -q 'plan 25%/h, breach at x2.0' /tmp/lo-out && ! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
"$LR" budget set pace 20 >/dev/null; "$LR" budget set factor 1.5 >/dev/null
rm -f "$FX"; "$LR" budget check >/tmp/lo-out 2>&1; RC=$?; check "a missing source is an error, not a halt" "test $RC -eq 1 && grep -q 'fixture missing' /tmp/lo-out && '$LR' budget | grep -q 'FAILED'"
fixture 10 4.0; python3 -c "import json;p='$CLAUDE_CONFIG_DIR/longrun/budget.json';b=json.load(open(p));b['sampled_at_epoch']=0;json.dump(b,open(p,'w'))"
"$LR" watch run --quiet; check "the watcher tick samples too" "'$LR' budget | grep -q '5h window 10% used'"
unset LONGRUN_BUDGET_FIXTURE
LONGRUN_SESSION=$A "$LR" orchestrate stop >/dev/null 2>&1

echo; echo "PASS=$PASS FAIL=$FAIL  (tmp: $T)"
[ $FAIL -eq 0 ] && rm -rf "$T"
exit $FAIL
