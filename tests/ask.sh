#!/bin/bash
# The dialog layer: `longrun ask` (inline answer, late answer as a message, cancelled/expired/failed, the HQ ledger
# fallback), the session flags and the digest block, the halt exemption, the watcher's stop dialog and the stdio MCP
# server. The dialog itself is replaced by LONGRUN_ASK_FIXTURE; LONGRUN_NO_UI keeps notifications off. No API calls.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LR="$HERE/../skill/longrun/scripts/longrun"
T="$(mktemp -d /tmp/longrun-ask.XXXXXX)"
export CLAUDE_CONFIG_DIR="$T/claude" HOME="$T/home" LONGRUN_NO_TIMER=1 LONGRUN_NO_UI=1
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/sessions"
unset LONGRUN_DIR LONGRUN_SESSION LONGRUN_SCOPE LONGRUN_TRANSCRIPT CLAUDE_ENV_FILE LONGRUN_ASK_FIXTURE LONGRUN_ASK_FIXTURE_DELAY
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
waitfor(){ local i=0; while ! eval "$1"; do i=$((i+1)); [ $i -ge ${2:-40} ] && return 1; sleep 0.25; done; return 0; }
A=aaaa1111-0000-4000-8000-000000000001; B=bbbb2222-0000-4000-8000-000000000002
P="$T/proj"; mkdir -p "$P"; cd "$P"; "$LR" init >/dev/null; L="$P/.longrun"
SESS="$CLAUDE_CONFIG_DIR/longrun/sessions"
start(){ printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1" "${2:-$P}" | "$LR" hook SessionStart >/dev/null; }
pre(){ printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"x"},"tool_use_id":"%s"}' "$1" "$P" "$2" "$3" | "$LR" hook PreToolUse; }
FX="$T/ask.json"; export LONGRUN_ASK_FIXTURE="$FX"
fixture(){ printf '{"button":"%s","text":"%s","state":"%s"}' "$1" "${2:-}" "${3:-answered}" > "$FX"; }
asks(){ cat "$SESS"/*/"${1:0:8}"/asks.json; }
start $A; start $B

echo "== ask: the answer inline, the record, the journal"
fixture Yes; OUT="$(LONGRUN_SESSION=$B "$LR" ask "Deploy now?" --options "Yes,No" --wait 5)"
check "ANSWER Q1: Yes" "echo \"\$OUT\" | grep -q '^ANSWER Q1: Yes'"
check "asks.json: answered, taken inline (no delivery)" "asks $B | grep -q '\"state\": \"answered\"' && ! asks $B | grep -q 'inbox:'"
check "journal has the question and the answer" "grep -q 'ask Q1: Deploy now?' '$SESS'/*/bbbb2222/journal.md && grep -q 'Q1 answered: Yes' '$SESS'/*/bbbb2222/journal.md"
fixture Sure "with a note"; OUT="$(LONGRUN_SESSION=$B "$LR" ask "Free text too?" --text --wait 5)"
check "free text comes back after the button" "echo \"\$OUT\" | grep -q '^ANSWER Q2: Sure; text: with a note'"

echo "== ask: a late answer arrives as a message; flags and the digest meanwhile"
fixture No "later please"; OUT="$(LONGRUN_ASK_FIXTURE_DELAY=2 LONGRUN_SESSION=$B "$LR" ask "Merge PR 42?" --options "Yes,No" --text --wait 0)"
check "PENDING Q3 returned at once" "echo \"\$OUT\" | grep -q '^PENDING Q3'"
check "status flags the session as asking the user" "LONGRUN_SESSION=$A '$LR' status | grep -q 'asking the user Q3'"
check "the asker's digest carries ASKED" "LONGRUN_SESSION=$B '$LR' digest | grep -q 'ASKED, waiting for the user: Q3 \"Merge PR 42?\"'"
check "the answer lands in the asker's inbox (no socket in tests)" "waitfor \"ls '$L'/inbox/ 2>/dev/null | grep -q 'msg-to-bbbb2222-from-longrun-ask'\" 40 && grep -q 'ANSWER Q3: No; text: later please' '$L'/inbox/*msg-to-bbbb2222-from-longrun-ask*"
check "record: answered, delivered to the inbox, flag gone" "asks $B | grep -q '\"delivered\": \"inbox:' && ! (LONGRUN_SESSION=$A '$LR' status | grep -q 'asking the user')"
OUT="$(LONGRUN_SESSION=$B "$LR" ask ls)"; check "ask ls lists all three with answers" "echo \"\$OUT\" | grep -q '^Q1 .* answered: Deploy now? -> Yes' && echo \"\$OUT\" | grep -q '^Q3 .* answered: Merge PR 42? -> No later please'"

echo "== ask: declined, expired, failed; an answer typed in the chat"
fixture "" "" cancelled; OUT="$(LONGRUN_SESSION=$B "$LR" ask "Rebase?" --options "Yes,No" --wait 5)"
check "CANCELLED tells the model not to re-ask" "echo \"\$OUT\" | grep -q '^CANCELLED Q4: the user closed the dialog' && echo \"\$OUT\" | grep -q 'Do not re-ask'"
fixture "" "" expired; OUT="$(LONGRUN_SESSION=$B "$LR" ask "Still there?" --expire 7 --wait 5)"
check "EXPIRED names the limit" "echo \"\$OUT\" | grep -q '^EXPIRED Q5: no answer within 7 min'"
rm -f "$FX"; OUT="$(LONGRUN_SESSION=$B "$LR" ask "Broken?" --wait 5)"
check "no dialog possible: FAILED, ask in the chat" "echo \"\$OUT\" | grep -q '^FAILED Q6: the dialog could not be shown (fixture missing)'"
fixture Ok; OUT="$(LONGRUN_ASK_FIXTURE_DELAY=30 LONGRUN_SESSION=$B "$LR" ask "Lost dialog?" --wait 0)"
OUT="$(LONGRUN_SESSION=$B "$LR" ask answer Q7 "yes, go")"
check "ask answer records the chat answer, no message" "echo \"\$OUT\" | grep -q '^ANSWER Q7: yes, go' && ! ls '$L'/inbox/ | grep -q 'Q7'"
OUT="$(LONGRUN_SESSION=$B "$LR" ask 2>&1)"; RC=$?; check "no question: usage, exit 2" "test $RC -eq 2 && echo \"\$OUT\" | grep -q 'usage: longrun ask'"

echo "== ask: an unanswered question goes to the HQ ledger"
P2="$T/hq"; mkdir -p "$P2"; cd "$P2"; "$LR" init --hq >/dev/null; C=cccc3333-0000-4000-8000-000000000003; start $C "$P2"
fixture "" "" expired; OUT="$(LONGRUN_ASK_FIXTURE_DELAY=1 LONGRUN_SESSION=$C "$LR" ask "Approve the release?" --wait 0)"
check "PENDING first" "echo \"\$OUT\" | grep -q '^PENDING Q1'"
check "then the ledger item owned by the user" "waitfor \"grep -q 'Approve the release?' '$P2/.longrun/ledger.md'\" 40 && grep 'Approve the release?' '$P2/.longrun/ledger.md' | grep -q 'user'"
OUT="$(LONGRUN_SESSION=$C "$LR" ask --ledger "Need the token from you")"; check "ask --ledger is the old shortcut (ledger + report)" "grep -q 'Need the token from you' '$P2/.longrun/ledger.md' && ls '$P2/.longrun/inbox/' | grep -q 'ask\|report'"
cd "$P"

echo "== halt: the MCP tools stay allowed; the stop dialog lifts the halt"
LONGRUN_SESSION=$A "$LR" halt "manual stop" >/dev/null
check "mcp__longrun__ask is not refused during a halt" "test -z \"\$(pre $B mcp__longrun__ask t1)\""
check "Bash still is" "pre $B Bash t2 | grep -q '\"permissionDecision\": \"deny\"'"
fixture "Keep stopped"; "$LR" ask _halt_dialog "manual stop" >/dev/null; check "Keep stopped keeps it" "test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json'"
python3 - "$CLAUDE_CONFIG_DIR/longrun/halt.json" <<'PY'
import json, sys, time
p = sys.argv[1]; h = json.load(open(p)); h["kind"] = "budget"; h["resets_at"] = time.time() + 3600; json.dump(h, open(p, "w"))
PY
LONGRUN_SESSION=$A "$LR" orchestrate start --goal g >/dev/null 2>&1; rm -f "$L"/inbox/*msg-to-aaaa1111*
fixture "Resume all"; "$LR" ask _halt_dialog "budget stop" /tmp/report.md >/dev/null
check "Resume all lifts the halt, snoozes the budget rule, tells the orchestrator" "! test -f '$CLAUDE_CONFIG_DIR/longrun/halt.json' && grep -q 'snoozed_until' '$CLAUDE_CONFIG_DIR/longrun/budget.json' && grep -l 'RESUMED by the user (stop dialog)' '$L'/inbox/*msg-to-aaaa1111* >/dev/null"
check "the watcher log records the dialog" "grep -q 'stop dialog: answered Resume all' '$CLAUDE_CONFIG_DIR/longrun/watch/log.txt' 2>/dev/null || grep -rq 'stop dialog: answered Resume all' '$CLAUDE_CONFIG_DIR/longrun/watch/'"

echo "== watcher: a question the user ignores is a stuck report to the orchestrator"
fixture Later; OUT="$(LONGRUN_ASK_FIXTURE_DELAY=20 LONGRUN_SESSION=$B "$LR" ask "Ignored for long?" --wait 0)"
python3 - "$(ls "$SESS"/*/bbbb2222/asks.json)" <<'PY'
import json, sys, datetime
p = sys.argv[1]; a = json.load(open(p))
for it in a["items"]:
    if it["state"] == "pending":
        it["asked"] = (datetime.datetime.now() - datetime.timedelta(minutes=15)).strftime("%Y-%m-%d %H:%M")
json.dump(a, open(p, "w"))
PY
rm -f "$L"/inbox/*msg-to-aaaa1111*; "$LR" watch run --quiet
check "stuck scan names the question and its age" "grep -l \"waiting 1[45]m for the user's answer to Q8\" '$L'/inbox/*msg-to-aaaa1111* >/dev/null"

echo "== mcp: the stdio server finds its session by the parent pid"
printf '{"pid":%d,"sessionId":"%s","cwd":"%s","name":"test-b"}' $$ "$B" "$P" > "$CLAUDE_CONFIG_DIR/sessions/$$.json"
fixture "Ship it"
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
 '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ask","arguments":{"question":"Ship?","options":["Ship it","Hold"],"wait_sec":5}}}' \
 '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"notify","arguments":{"text":"hi"}}}' \
 '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}' \
 '{"jsonrpc":"2.0","id":6,"method":"resources/list"}' | (cat; sleep 3) | "$LR" mcp > /tmp/lo-mcp 2>/tmp/lo-mcp-err
check "initialize echoes the protocol version and names the server" "grep -q '\"id\": 1, \"result\": {\"protocolVersion\": \"2025-06-18\"' /tmp/lo-mcp && grep -q '\"name\": \"longrun\"' /tmp/lo-mcp"
check "tools/list: ask and notify with schemas" "grep '\"id\": 2' /tmp/lo-mcp | grep -q '\"name\": \"ask\"' && grep '\"id\": 2' /tmp/lo-mcp | grep -q '\"name\": \"notify\"' && grep '\"id\": 2' /tmp/lo-mcp | grep -q '\"required\": \\[\"question\"\\]'"
check "ask via MCP: the answer, recorded under session B" "grep '\"id\": 3' /tmp/lo-mcp | grep -q 'ANSWER Q9: Ship it' && asks $B | grep -q 'Ship?'"
check "notify answers; unknown tool and method are JSON-RPC errors" "grep '\"id\": 4' /tmp/lo-mcp | grep -q 'notified' && grep '\"id\": 5' /tmp/lo-mcp | grep -q 'unknown tool nope' && grep '\"id\": 6' /tmp/lo-mcp | grep -q '\"code\": -32601'"
check "nothing but JSON-RPC on stdout, nothing on stderr" "! grep -qv '^{' /tmp/lo-mcp && ! test -s /tmp/lo-mcp-err"
rm -f "$CLAUDE_CONFIG_DIR/sessions/$$.json"; fixture Fine
printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ask","arguments":{"question":"No session?"}}}' | (cat; sleep 2) | "$LR" mcp > /tmp/lo-mcp 2>&1
check "no session behind the server: the dialog alone, inline" "grep '\"id\": 2' /tmp/lo-mcp | grep -q 'ANSWER Q?: Fine'"
LONGRUN_SESSION=$A "$LR" orchestrate stop >/dev/null 2>&1

echo; echo "PASS=$PASS FAIL=$FAIL  (tmp: $T)"
[ $FAIL -eq 0 ] && rm -rf "$T"
exit $FAIL
