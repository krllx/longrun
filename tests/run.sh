#!/bin/bash
# Synthetic end-to-end test of the longrun CLI and its hooks. No Claude API calls, nothing outside a temp dir.
# Goal-level scenarios (what the skill is for) live in tests/scenarios.sh; this file is the regression suite.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LR="$HERE/../skill/longrun/scripts/longrun"
T="$(mktemp -d /tmp/longrun-test.XXXXXX)"
export CLAUDE_CONFIG_DIR="$T/claude"      # keeps registry/global config out of ~/.claude
export HOME="$T/home"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects/-proj"
unset LONGRUN_DIR LONGRUN_SESSION LONGRUN_SCOPE LONGRUN_TRANSCRIPT XDG_CONFIG_HOME
export LONGRUN_NO_TIMER=1                  # never register a real launchd/systemd/cron job from the test tree
export LONGRUN_DESKTOP_DIR="$HOME/desktop-sessions"   # the Claude desktop app's metadata dir, wherever this OS puts it
export LONGRUN_NO_UI=1                     # never a real dialog or notification from a test
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
SID=11111111-2222-4333-8444-555555555555
hook(){ # hook EVENT JSON
  printf "%s" "$2" | "$LR" hook "$1"
}
size(){ python3 -c "import os,sys;print(os.path.getsize(sys.argv[1]))" "$1"; }

echo "== init (project) and a linked worktree"
HUB="$T/hq"; WT="$T/wt/EDAINAPP-1375-screen"; mkdir -p "$HUB" "$WT"
( cd "$HUB" && "$LR" init >/dev/null ) && check "project init makes NOTES.md and the message inbox" "test -f '$HUB/.longrun/NOTES.md' -a -d '$HUB/.longrun/inbox'"
( cd "$WT" && "$LR" link "$HUB" >/dev/null ) && check "worktree link -> registry entry, nothing written into the worktree" "test -f '$CLAUDE_CONFIG_DIR/longrun/registry.json' && ! test -e '$WT/.longrun'"
WHERE="$(cd "$WT" && "$LR" where)"; check "where in the worktree resolves to the project" "echo '$WHERE' | grep -q 'project:  hq  ($HUB/.longrun)'"
LOCAL="$HUB/.longrun"
SESS="$(cd "$WT" && "$LR" where | sed -n 's/^sessions: //p')"
check "session state lives outside the project and the worktree" "case '$SESS' in $CLAUDE_CONFIG_DIR/longrun/sessions/*) true;; *) false;; esac"

echo "== shared notes: add / dedupe / budget / rm / replace / prune"
cd "$WT"
"$LR" add --own -t dead "no session here" >/dev/null 2>/tmp/lr-own; check "an --own note without a session is refused (exit 3) and points at the shared default" "test \$? -eq 3 && grep -q -- 'shared' /tmp/lr-own"
DEF="$T/defaultproj"; mkdir -p "$DEF"; ( cd "$DEF" && "$LR" init >/dev/null && "$LR" add -t dead "no flag, no session: this goes to the project" >/dev/null 2>&1 )
check "add without a flag writes the project's shared notes, session or no session" "grep -q 'no flag, no session' '$DEF/.longrun/NOTES.md'"
"$LR" add --shared -t dead "arc-wt add attaches nothing: same-name server branch yields an unrelated local branch; check arc log arcadia/<br> vs HEAD" >/dev/null; check "add --shared writes [n1] into the project NOTES.md" "grep -q '\[n1\] .* dead' '$LOCAL/NOTES.md'"
"$LR" add --shared -t decision "STQ v2 over v1 for payment callbacks: v1 queue creation needs a TPS ticket per env, v2 is self-serve" >/dev/null
OUT="$("$LR" add --shared -t decision "STQ v2 over v1 for payment callbacks: v1 queue creation needs a TPS ticket per env, v2 is self-serve")"; check "duplicate detected" "echo '$OUT' | grep -q 'already present as n2'"
"$LR" add --shared -t bogus x 2>/dev/null; check "bad tag rejected" "test $? -eq 2"
echo '{"notes_max_bytes": 700, "hq": true}' > "$LOCAL/config.json"
for i in 1 2 3 4 5 6 7 8; do "$LR" add --shared -t fact "filler fact number $i about host sas-$i.yp-c.yandex.net port 8081 and flag --foo=$i" >/dev/null 2>&1; done
"$LR" add --shared -t fact "one more that must not fit into a 700 byte budget at all" >/tmp/lr-out 2>/tmp/lr-err; RC=$?
check "budget refuses with exit 2 and candidates" "test $RC -eq 2 && grep -q 'does not fit' /tmp/lr-err && grep -q 'Cheapest to drop' /tmp/lr-err"
SIZE=$(size "$LOCAL/NOTES.md"); check "NOTES.md never exceeds cap ($SIZE B)" "test $SIZE -le 780"
"$LR" prune --auto --shared >/dev/null; SIZE2=$(size "$LOCAL/NOTES.md"); check "prune --auto --shared shrinks to <=60% ($SIZE2 B) and archives" "test $SIZE2 -le 480 && test -s '$LOCAL/archive/notes.md'"
check "prune keeps dead/decision over fact" "grep -q 'dead' '$LOCAL/NOTES.md' && grep -q 'decision' '$LOCAL/NOTES.md'"
# stale: a session says an entry stopped being true. Not a delete - the entry may still be right, or the
# session may be wrong - but everybody sees the mark and the next sweep takes the marked ones first.
STP="$T/staleproj"; mkdir -p "$STP"; ( cd "$STP" && "$LR" init >/dev/null )
( cd "$STP" && "$LR" add --shared -t dead "retry on 429 does not help: the limit is per org, not per key" >/dev/null
  "$LR" add --shared -t pin "PR 42 = branch feature/checkout" >/dev/null
  "$LR" add --shared -t fact "staging is sas-01, reachable only from the VPN" >/dev/null )
( cd "$STP" && "$LR" stale n3 >/dev/null 2>/tmp/lr-stale ); check "a stale mark without a reason is refused" "test \$? -eq 2 && grep -q 'say why' /tmp/lr-stale"
( cd "$STP" && "$LR" stale n3 "staging moved to vla-07 on 09-16" >/dev/null )
SD1="$(cd "$STP" && "$LR" digest)"
check "a marked entry still shows, with the mark and the reason, so other sessions see it too" "echo \"\$SD1\" | grep -q 'STALE since' && echo \"\$SD1\" | grep -q 'staging moved to vla-07' && echo \"\$SD1\" | grep -q 'sas-01'"
SP="$(cd "$STP" && "$LR" prune --shared)"; check "prune offers the marked entry first, before the cheap tags" "echo \"\$SP\" | head -2 | grep -q 'sas-01'"
( cd "$STP" && "$LR" stale ls | grep -q 'staging moved' ); check "stale ls lists the marks with who made them and when" "test \$? -eq 0"
( cd "$STP" && "$LR" stale --clear n3 >/dev/null ); check "stale --clear takes the mark back" "! (cd '$STP' && '$LR' digest | grep -q 'STALE since')"
( cd "$STP" && "$LR" stale n3 "gone for good" >/dev/null && "$LR" rm n3 >/dev/null )
check "a mark does not outlive its entry" "! grep -q 'gone for good' '$STP/.longrun/stale.json'"
# mute: take an entry out of MY digest, change nothing on disk and nothing for anyone else
MU=eeeeeeee-2222-4333-8444-555555555555; MV=ffffffff-2222-4333-8444-555555555555
for m in $MU $MV; do ( cd "$STP" && hook SessionStart "{\"session_id\":\"$m\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$STP\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null ); done
( cd "$STP" && LONGRUN_SESSION=$MU "$LR" mute n1 >/dev/null )
MD="$(cd "$STP" && LONGRUN_SESSION=$MU "$LR" digest)"
MD2="$(cd "$STP" && LONGRUN_SESSION=$MV "$LR" digest)"
check "a muted entry leaves this session's digest, and the head says how many are hidden" "! echo \"\$MD\" | grep -q 'retry on 429' && echo \"\$MD\" | grep -q '1 muted here' && echo \"\$MD\" | grep -q 'PR 42'"
check "muting changes nothing on disk and nothing for another session" "grep -q 'retry on 429' '$STP/.longrun/NOTES.md' && echo \"\$MD2\" | grep -q 'retry on 429' && ! echo \"\$MD2\" | grep -q 'muted here'"
( cd "$STP" && LONGRUN_SESSION=$MU "$LR" unmute --all >/dev/null )
check "unmute --all brings them back" "(cd '$STP' && LONGRUN_SESSION=$MU '$LR' digest | grep -q 'retry on 429')"
"$LR" rm n1 >/dev/null; check "rm n1 archives" "! grep -q '\[n1\]' '$LOCAL/NOTES.md' && grep -q 'rm | - \[n1\]' '$LOCAL/archive/notes.md'"
"$LR" replace n2 "STQ v2 chosen (self-serve queues)" >/dev/null; check "replace n2" "grep -q 'n2\] .*STQ v2 chosen' '$LOCAL/NOTES.md'"
"$LR" add --shared -t pin "never rm this" >/dev/null; check "add after prune fits" "grep -q 'pin (.*): never rm this' '$LOCAL/NOTES.md'"
check "shared entries carry the author label" "grep -q '\[n2\] .* decision (EDAINAPP-1375-screen)' '$LOCAL/NOTES.md'"

echo "== hooks with real payload shapes"
COMMON="\"session_id\":\"$SID\",\"transcript_path\":\"$CLAUDE_CONFIG_DIR/projects/-proj/$SID.jsonl\",\"cwd\":\"$WT\""
export CLAUDE_ENV_FILE="$T/env.sh"
OUT="$(hook SessionStart "{$COMMON,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"model\":\"claude-fable-5-1\"}")"
check "SessionStart prints digest with shared notes, own notes and the commands" "echo \"\$OUT\" | grep -q '<longrun v' && echo \"\$OUT\" | grep -q 'SHARED notes (project hq)' && echo \"\$OUT\" | grep -q 'OWN notes (this session) 0 entries' && echo \"\$OUT\" | grep -q 'longrun recall'"
check "SessionStart exports env for Bash" "grep -q 'LONGRUN_SESSION=$SID' '$T/env.sh' && grep -q 'LONGRUN_DIR=' '$T/env.sh'"
SD="$SESS/11111111"
check "SessionStart creates the session dir with meta + journal" "test -f '$SD/meta.json' && grep -q 'session startup' '$SD/journal.md'"
check "session index records project and key" "test -f '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/$SID.json' && grep -q '\"skey\": \"11111111\"' '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/$SID.json'"
export LONGRUN_SESSION=$SID
"$LR" add --own -t dead "own: personal v3 returns 403 V3 API is forbidden, use /v4/retrieve" >/dev/null; check "own note lands in the session dir as [s1], not in the project" "grep -q '\[s1\] .* dead: own: personal v3' '$SD/notes.md' && ! grep -q 'personal v3' '$LOCAL/NOTES.md'"
check "own note has no author label" "grep -q '\[s1\] [0-9-]* dead: own' '$SD/notes.md'"
"$LR" add --own -t todo "own todo" >/dev/null; "$LR" rm s2 >/dev/null; check "rm s2 removes an own note and archives it in the session dir" "! grep -q '\[s2\]' '$SD/notes.md' && grep -q 'rm | - \[s2\]' '$SD/archive/notes.md'"
"$LR" replace s1 "own: personal v3 is 403, v4 works" >/dev/null; check "replace s1" "grep -q 's1\] .*v4 works' '$SD/notes.md'"
check "notes shows both files" "$LR notes | grep -q 'SHARED notes' && $LR notes | grep -q 'OWN notes' && $LR notes --own | grep -q 'v4 works' && ! $LR notes --own | grep -q 'SHARED'"
# The turn card: what the turn actually did, asked once. 39 read-only commands are not activity, so
# there is nothing to ask about however many of them there are.
for i in $(seq 1 39); do hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls $i\"},\"tool_response\":{}}" >/dev/null; done
N40="$(hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls 40\"},\"tool_response\":{}}")"
check "40 read-only commands are not activity: no card, edits counter stays 0" "test -z \"\$N40\" && grep -q '\"edit_tools_since_note\": 0' '$SD/meta.json'"
# mid-turn, once a window of calls has passed and real edits exist, the card names the files
for i in $(seq 1 5); do hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/f$i.go\"},\"tool_response\":{}}" >/dev/null; done
N46="$(hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/f6.go\"},\"tool_response\":{}}")"
N47="$(hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/g.go\"},\"tool_response\":{}}")"
check "mid-turn card names the files it edited, once per window (call 46 yes, 47 no)" "echo \"\$N46\" | grep -q 'this turn so far' && echo \"\$N46\" | grep -q '6 files (f1.go, f2.go, f3.go, +3 more)' && test -z \"\$N47\""
UPS="$(hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"continue\"}")"
check "UserPromptSubmit right after a card: no second card" "! echo \"\$UPS\" | grep -q 'your last turn'"
for i in 2 3 4 5 6 7; do hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"t$i\"}" >/dev/null; done
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"edited the handler\"}" >/dev/null
hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/card.go\"},\"tool_response\":{}}" >/dev/null
hook PostToolUseFailure "{$COMMON,\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"go build ./...\"},\"error\":\"Exit code 2\\nundefined: Foo\",\"is_interrupt\":false}" >/dev/null
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"still broken\"}" >/dev/null
UPS8="$(hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"t8\"}")"
check "the card of the turn that ended names its file and its failed command, not a bare counter" "echo \"\$UPS8\" | grep -q 'your last turn' && echo \"\$UPS8\" | grep -q 'card.go' && echo \"\$UPS8\" | grep -q 'go build ./...' && echo \"\$UPS8\" | grep -q '0 notes'"
hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/card2.go\"},\"tool_response\":{}}" >/dev/null
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"more\"}" >/dev/null
UPS9="$(hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"t9\"}")"
check "and the next turn is quiet: a rate limit, not a card after every turn" "! echo \"\$UPS9\" | grep -q 'your last turn'"
"$LR" add --own -t fact "note write resets the staleness counters" >/dev/null
hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/x/read-only.go\"},\"tool_response\":{}}" >/dev/null
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"read it\"}" >/dev/null
UPS2="$(hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"go on\"}")"
check "a turn of pure reading gets no card, and a note write resets the counters" "! echo \"\$UPS2\" | grep -q 'your last turn' && grep -q '\"fails_since_note\": 0' '$SD/meta.json'"
# PostToolUseFailure charges the tool counter without ever looking at the card, so it is the event that
# steps the counter OVER the window boundary. With a modulo test that skipped the card for a whole window.
"$LR" add --own -t fact "reset the counters before the window-boundary check" >/dev/null
for i in $(seq 1 6); do hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/b$i.go\"},\"tool_response\":{}}" >/dev/null; done
for i in $(seq 7 38); do hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls $i\"},\"tool_response\":{}}" >/dev/null; done
NB39="$(hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls 39\"},\"tool_response\":{}}")"
hook PostToolUseFailure "{$COMMON,\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"make build\"},\"error\":\"Exit code 2\\nboom\",\"is_interrupt\":false}" >/dev/null
NB="$(hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls 41\"},\"tool_response\":{}}")"
check "a failed command stepping over the window boundary does not swallow the card" "test -z \"\$NB39\" && echo \"\$NB\" | grep -q 'this turn so far' && echo \"\$NB\" | grep -q 'make build'"
hook PostToolUseFailure "{$COMMON,\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"go test ./internal/services/screen/...\"},\"error\":\"Exit code 1\\n--- FAIL: TestScreen_NoPaymentMethods (0.00s)\\n    screen_test.go:41: expected 2 methods, got 0\",\"is_interrupt\":false}"
check "PostToolUseFailure -> FAIL line in journal" "grep -q 'FAIL \`go test ./internal/services/screen/...\` -> Exit code 1' '$SD/journal.md'"
# The other half of the question - what has STOPPED being true - used to ride on the turn card and so
# inherited every one of its gates. A session that only read, reviewed or talked, which is exactly the
# session with time to re-read old notes, was never asked at all. It now stands on its own.
SWP="$T/sweep"; mkdir -p "$SWP"; ( cd "$SWP" && "$LR" init >/dev/null
  "$LR" add -t fact "staging moved to vla-07 after the old host was decommissioned" >/dev/null
  "$LR" add -t fact "written today, so there is nothing to re-read about it yet" >/dev/null )
python3 - "$SWP/.longrun/NOTES.md" <<'PY'
import datetime,re,sys
p=sys.argv[1]; s=open(p).read()
old=(datetime.date.today()-datetime.timedelta(days=10)).strftime("%m-%d")
open(p,"w").write(re.sub(r"(\[n1\]) \d{2}-\d{2}", r"\1 "+old, s))
PY
SWC="\"session_id\":\"77777777-2222-4333-8444-555555555555\",\"transcript_path\":\"\",\"cwd\":\"$SWP\""
( cd "$SWP" && hook SessionStart "{$SWC,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null )
SW0="$(cd "$SWP" && hook UserPromptSubmit "{$SWC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"what do we know\"}")"
# Turn one is the worst moment to ask: the session has just been handed a task and has not yet touched
# anything the old notes are about. "At some suitable moment during the session" means a few turns in.
check "not on the first turn of a session, when the only honest answer is 'I don't know yet'" "! echo \"\$SW0\" | grep -q housekeeping"
for p in b c; do ( cd "$SWP" && hook UserPromptSubmit "{$SWC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$p\"}" >/dev/null ); done
SW1="$(cd "$SWP" && hook UserPromptSubmit "{$SWC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"and now\"}")"
check "the housekeeping question comes on its own: no edits, no failures, no card in that turn" "echo \"\$SW1\" | grep -q 'longrun, housekeeping: 1 shared note older than 7 days' && echo \"\$SW1\" | grep -q 'longrun stale n<id>' && ! echo \"\$SW1\" | grep -q 'your last turn'"
SW2="$(cd "$SWP" && hook UserPromptSubmit "{$SWC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"and now\"}")"
check "...and not again on the next turn: once per half an ageing window, not once per turn" "! echo \"\$SW2\" | grep -q housekeeping"
FRP="$T/sweep-fresh"; mkdir -p "$FRP"; ( cd "$FRP" && "$LR" init >/dev/null && "$LR" add -t fact "every note here is from today" >/dev/null )
FRC="\"session_id\":\"77777777-3333-4333-8444-555555555555\",\"transcript_path\":\"\",\"cwd\":\"$FRP\""
( cd "$FRP" && hook SessionStart "{$FRC,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null )
for p in a b c d; do ( cd "$FRP" && hook UserPromptSubmit "{$FRC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"$p\"}" >/dev/null ); done
SW3="$(cd "$FRP" && hook UserPromptSubmit "{$FRC,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}")"
check "nothing old enough to re-read: the question is not asked at all" "! echo \"\$SW3\" | grep -q housekeeping"
# transcript for precompact snapshot + recall
python3 - "$CLAUDE_CONFIG_DIR/projects/-proj/$SID.jsonl" "$SID" <<'PY'
import json,sys
p,sid=sys.argv[1],sys.argv[2]
rows=[{"type":"user","sessionId":sid,"message":{"role":"user","content":"Make the /screen handler return payment methods from EPMA; the widget client is a stub (question 5 to light checkout is open)"}},
{"type":"assistant","sessionId":sid,"message":{"role":"assistant","content":[{"type":"text","text":"Trying approach A: call personal v3"},{"type":"tool_use","name":"Edit","input":{"file_path":"/svc/internal/handlers/post_v_1_screen.go","old_string":"a","new_string":"b"}}]}},
{"type":"user","sessionId":sid,"message":{"role":"user","content":[{"type":"tool_result","content":"403 V3 API is forbidden"}]}},
{"type":"assistant","sessionId":sid,"message":{"role":"assistant","content":[{"type":"text","text":"v3 is whitelisted; switching to /v4/retrieve"}]}},
{"type":"user","sessionId":sid,"isMeta":True,"message":{"role":"user","content":"<system-reminder>meta noise</system-reminder>"}},
{"type":"user","sessionId":sid,"message":{"role":"user","content":"try again"}},
{"type":"user","sessionId":sid,"message":{"role":"user","content":"yes"}}]
open(p,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
hook PostToolUse "{$COMMON,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/svc/internal/handlers/post_v_1_screen.go\"},\"tool_response\":{}}" >/dev/null
"$LR" compact-hint --set "keep the exact 403 body verbatim" >/dev/null
PC="{$COMMON,\"hook_event_name\":\"PreCompact\",\"trigger\":\"auto\",\"custom_instructions\":\"\"}"
HINT="$(hook PreCompact "$PC")"
check "PreCompact prints the summariser instructions on stdout (this is what Claude Code appends to the compaction prompt)" "echo \"\$HINT\" | grep -q 'did not work, each with the reason it failed' && echo \"\$HINT\" | grep -q 'post_v_1_screen.go' && echo \"\$HINT\" | grep -q 'keep the exact 403 body verbatim'"
check "the hint names the notes that come back by themselves, and is plain text (JSON stdout would be read as a decision object)" "echo \"\$HINT\" | grep -q 'longrun notes .*s1' && ! echo \"\$HINT\" | head -1 | grep -q '^[[{]'"
check "the hint stays inside compact_hint_max_bytes" "test \$(printf '%s' \"\$HINT\" | wc -c) -le 1200"
PREVIEW="$("$LR" compact-hint 2>/dev/null)"
check "the compact-hint command previews exactly what the hook sends" "test \"\$PREVIEW\" = \"\$HINT\""
"$LR" compact-hint --clear >/dev/null
check "compact-hint --clear drops the session line" "! $LR compact-hint 2>/dev/null | grep -q 'keep the exact 403 body verbatim'"
"$LR" config set compact_hint false >/dev/null
OFFHINT="$(hook PreCompact "$PC")"
check "compact_hint false -> the hook prints nothing and the compaction runs unsteered" "test -z \"\$OFFHINT\""
"$LR" config unset compact_hint >/dev/null
hook PreCompact "{$COMMON,\"hook_event_name\":\"PreCompact\",\"trigger\":\"manual\",\"custom_instructions\":\"keep the EPMA decision\"}" >/dev/null
SNAP="$(ls $LOCAL/archive/precompact/11111111-*.md | head -1)"; check "PreCompact snapshot has user msgs + edited files + FAIL" "grep -q 'Make the /screen handler' '$SNAP' && grep -q 'post_v_1_screen.go' '$SNAP' && grep -q 'go test' '$SNAP'"
check "the hint is journalled with its size, so it is visible after the fact" "grep -q 'compaction auto .*hint [0-9]* B' '$SD/journal.md'"
hook PostCompact "{$COMMON,\"hook_event_name\":\"PostCompact\",\"trigger\":\"manual\",\"compact_summary\":\"Summary: we chose personal v4 because V3 API is forbidden (403). Pending: reviewers for PR B.\"}"
ARCH="$(ls $LOCAL/archive/compact/11111111-*.md | head -1)"; check "PostCompact archives the summary verbatim under the project archive, named by session" "grep -q 'V3 API is forbidden' '$ARCH'"
OUT="$(hook SessionStart "{$COMMON,\"hook_event_name\":\"SessionStart\",\"source\":\"compact\",\"model\":\"claude-fable-5-1\"}")"
check "SessionStart(compact) digest: own notes + journal tail + archive pointer" "echo \"\$OUT\" | grep -q 's1\] .*v4 works' && echo \"\$OUT\" | grep -q 'SESSION journal tail' && echo \"\$OUT\" | grep -q 'archived verbatim in archive/compact/'"
check "SessionStart(compact) digest carries the mechanical HANDOFF (failure + framing + files)" "echo \"\$OUT\" | grep -q 'HANDOFF (mechanical' && echo \"\$OUT\" | grep -q 'FAIL' && echo \"\$OUT\" | grep -q 'ASK: Make the /screen handler' && echo \"\$OUT\" | grep -q 'post_v_1_screen.go'"
check "HANDOFF skips one-word replies and carries the /compact instructions as FOCUS" "! echo \"\$OUT\" | grep -q 'ASK: try again' && ! echo \"\$OUT\" | grep -q 'ASK: yes' && echo \"\$OUT\" | grep -q 'FOCUS: keep the EPMA decision'"
"$LR" add --own -t fact "reset before the failure-as-activity check" >/dev/null
for i in 1 2 3 4 5 6 7 8; do hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"u$i\"}" >/dev/null; done
hook PostToolUseFailure "{$COMMON,\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"make lint\"},\"error\":\"Exit code 2\\nlint failed\",\"is_interrupt\":false}"
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"lint is red\"}" >/dev/null
UPSF="$(hook UserPromptSubmit "{$COMMON,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"u9\"}")"
check "a failed command alone is worth a card, with no edits in the turn at all" "echo \"\$UPSF\" | grep -q '1 failed command (make lint)' && echo \"\$UPSF\" | grep -q 'your last turn'"
check "handoff appears only after a compaction, not on plain startup" "! $LR digest --source startup | grep -q 'HANDOFF'"
check "compactions counted" "grep -q '\"compactions\": 1' '$SD/meta.json'"
# the shell cd's out of the project (hook cwd follows the shell): counters, digest and FAILs must stay with the session
ELSEWHERE="\"session_id\":\"$SID\",\"transcript_path\":\"$CLAUDE_CONFIG_DIR/projects/-proj/$SID.jsonl\",\"cwd\":\"$T\""
TB=$(python3 -c "import json;print(json.load(open('$SD/meta.json'))['tools'])")
hook PostToolUse "{$ELSEWHERE,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/elsewhere.go\"},\"tool_response\":{}}" >/dev/null
TA=$(python3 -c "import json;print(json.load(open('$SD/meta.json'))['tools'])")
check "PostToolUse with the shell cwd outside the project still counts in the session's dir" "test \$TA -eq \$((TB+1)) && grep -q 'elsewhere.go' '$SD/meta.json'"
OUTE="$(hook SessionStart "{$ELSEWHERE,\"hook_event_name\":\"SessionStart\",\"source\":\"compact\"}")"
check "SessionStart(compact) with the shell cwd elsewhere injects THIS session's shared + own notes" "echo \"\$OUTE\" | grep -q 'STQ v2 chosen' && echo \"\$OUTE\" | grep -q 'v4 works' && echo \"\$OUTE\" | grep -q 'HANDOFF'"
SOLOKEY="$(mkdir -p "$T/solo" && cd "$T/solo" && ("$LR" where 2>/dev/null || "$LR" init >/dev/null && "$LR" where) | sed -n 's/^sessions: //p')"
LONGRUN_DIR="$LOCAL" hook SessionStart "{\"session_id\":\"55555555-2222-4333-8444-555555555555\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$T/solo\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null
check "hooks ignore an inherited LONGRUN_DIR and bind to their own cwd's project" "test -f \"$SOLOKEY/55555555/meta.json\" && ! test -d '$SESS/55555555'"
check "the compaction that hit while the shell was elsewhere is counted for this session" "grep -q '\"compactions\": 2' '$SD/meta.json'"
hook Stop "{$COMMON,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"PR B pushed, waiting for reviewers. Next: EPMA timeouts.\"}"
check "Stop stores last status" "grep -q 'PR B pushed' '$SD/meta.json'"
hook SessionEnd "{$COMMON,\"hook_event_name\":\"SessionEnd\",\"reason\":\"clear\"}"
check "SessionEnd marks ended" "grep -q '\"ended\": \"clear\"' '$SD/meta.json'"

echo "== recall: notes, journal, archived summary, transcript"
export LONGRUN_TRANSCRIPT="$CLAUDE_CONFIG_DIR/projects/-proj/$SID.jsonl"
R="$("$LR" recall "V3 API" 2>&1)"; check "recall finds archived summary + transcript" "echo \"\$R\" | grep -q 'archive/compact' && echo \"\$R\" | grep -q 'transcript(tool_result)'"
R1="$("$LR" recall "v4 works" --no-transcript 2>&1)"; check "recall finds the own note first" "echo \"\$R1\" | head -1 | grep -q 'sessions/11111111/notes.md'"
R2="$("$LR" recall "screen_test.go" 2>&1)"; check "recall finds FAIL line in journal" "echo \"\$R2\" | grep -q 'sessions/11111111/journal.md'"
"$LR" recall "nothing-like-this-zzz" >/dev/null 2>&1; check "recall miss exits 1" "test $? -eq 1"

echo "== digest size cap"
python3 - "$LOCAL/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["notes_max_bytes"]=6000; d["inject_max_bytes"]=1500; json.dump(d,open(p,"w"))
PY
for i in $(seq 1 30); do "$LR" add --shared -t fact "digest cap filler $i: a moderately long line of text to inflate the notes towards the budget for the test" >/dev/null 2>&1; done
D="$("$LR" digest --source compact)"; DB=$(printf '%s' "$D" | wc -c | tr -d ' '); check "digest respects inject_max_bytes ($DB B <= 1500)" "test $DB -le 1500 && echo \"\$D\" | grep -q '</longrun>'"
# at production proportions (5000 shared + 3000 own, against a 9000 digest) both notes files must still fit whole
BOTH="$T/both"; mkdir -p "$BOTH"; ( cd "$BOTH" && "$LR" init --hq >/dev/null )
BSESS="$(cd "$BOTH" && "$LR" where | sed -n 's/^sessions: //p')"
python3 - "$BOTH/.longrun/NOTES.md" "$BOTH/.longrun/ledger.md" "$BSESS/99990000/notes.md" <<'PY'
import sys, os
n, l, o = sys.argv[1], sys.argv[2], sys.argv[3]
b, i = [], 1
while sum(len(x) + 1 for x in b) < 4900:
    b.append("- [n%d] 09-01 dead: attempt %d failed, the pgx pool deadlocks under -race on sas-%d.yp-c.yandex.net" % (i, i, i)); i += 1
open(n, "w").write("# longrun notes\n" + "\n".join(b) + "\n")
b, i = [], 1
while sum(len(x) + 1 for x in b) < 2900:
    b.append("- [s%d] 09-01 fact: own fact %d about the widget stub and the carousel proto, long enough to fill the budget" % (i, i)); i += 1
os.makedirs(os.path.dirname(o), exist_ok=True)
open(o, "w").write("# longrun notes of this session\n" + "\n".join(b) + "\n")
b, i = [], 1
while sum(len(x) + 1 for x in b) < 2900:
    who, nxt = ("user", " | next:2020-01-01") if i == 3 else ("me", "")
    b.append("- [L%d] waiting @%s 09-01: approve TVM draft 1072534%d for eats-payments%s" % (i, who, i, nxt)); i += 1
open(l, "w").write("# longrun ledger\n" + "\n".join(b) + "\n")
PY
printf '{"sid":"99990000-2222-4333-8444-555555555555","skey":"99990000","cwd":"%s","tools":3,"turns":1,"last_seen":"2026-09-06 10:00"}\n' "$BOTH" > "$BSESS/99990000/meta.json"
D2="$(cd "$BOTH" && LONGRUN_SESSION=99990000-2222-4333-8444-555555555555 "$LR" digest --source compact)"; D2B=$(printf '%s' "$D2" | wc -c | tr -d ' ')
check "all budgets full: the digest still fits ($D2B B <= 9000)" "test $D2B -le 9000 && echo \"\$D2\" | grep -q '</longrun>'"
check "all budgets full: neither notes file is what gives way" "echo \"\$D2\" | grep -q '\[n1\]' && echo \"\$D2\" | grep -q '\[s1\]' && ! echo \"\$D2\" | grep -q 'notes truncated'"
# B1: when the notes DO have to give way, they shed their oldest entries, never their newest. A tail
# clip (what this used to do) eats exactly what was written last, which is what a session needs most.
SHED="$T/shed"; mkdir -p "$SHED"; ( cd "$SHED" && "$LR" init >/dev/null )
python3 - "$SHED/.longrun/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["inject_max_bytes"]=1400; json.dump(d,open(p,"w"))
PY
printf 'material too long for a note, which is the whole point of keeping it here\n' > "$SHED/long.md"
( cd "$SHED" && "$LR" doc add long.md "where the long material of this project lives" >/dev/null
  "$LR" add --shared -t pin "PIN: PR 42 = branch feature/checkout" >/dev/null
  for i in $(seq 1 12); do "$LR" add --shared -t fact "shed filler $i: a line long enough to push this file past what one digest can carry" >/dev/null; done )
D3="$(cd "$SHED" && "$LR" digest --source compact)"; D3B=$(printf '%s' "$D3" | wc -c | tr -d ' ')
check "over budget: the digest sheds the OLDEST entries and keeps the newest ($D3B B <= 1400)" "test $D3B -le 1400 && echo \"\$D3\" | grep -q 'shed filler 12' && ! echo \"\$D3\" | grep -q 'shed filler 1:' && echo \"\$D3\" | grep -q 'older entries left out to fit'"
check "over budget: a pin is never the entry that gives way" "echo \"\$D3\" | grep -q 'PR 42 = branch feature/checkout'"
# A doc line is the index of material deliberately kept OUT of the context. Shedding it as the oldest
# entry (which is what it usually is) hides a whole file instead of costing one fact.
check "over budget: a doc pointer is not shed either, oldest or not" "echo \"\$D3\" | grep -q 'long.md - where the long material'"
check "PRUNE NEEDED is measured against what a digest can carry, not against the file cap" "echo \"\$D3\" | grep -q 'PRUNE NEEDED' && echo \"\$D3\" | grep -q 'fit a digest'"
( cd "$SHED" && "$LR" config set notes_max_bytes 9000 >/dev/null 2>/tmp/lr-budget ); check "config refuses notes budgets that cannot fit inject_max_bytes (exit 2)" "test \$? -eq 2 && grep -q 'would never reach a session' /tmp/lr-budget"
( cd "$SHED" && "$LR" config set inject_max_bytes 9000 >/dev/null && "$LR" config set notes_max_bytes 5000 >/dev/null ); check "...and accepts them once inject_max_bytes has room" "test \$? -eq 0"
# The check above only guards new writes. A project configured before it existed, or edited by hand, is
# in the same state and looks healthy from the outside: `longrun config` prints the number that was asked for.
python3 - "$SHED/.longrun/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["notes_max_bytes"]=15000; d["inject_max_bytes"]=9800; json.dump(d,open(p,"w"))
PY
CW="$(cd "$SHED" && "$LR" config)"
check "a budget written before the check is called out by longrun config, not silently honoured" "echo \"\$CW\" | grep -q 'WARNING: notes_max_bytes 15000' && echo \"\$CW\" | grep -q 'never reach anyone'"
D4="$(cd "$SHED" && "$LR" digest)"
check "...and the notes head says how much of that cap a digest can really carry" "echo \"\$D4\" | grep -q 'fit a digest'"
( cd "$SHED" && "$LR" config set compact_hint_max_bytes 900 >/dev/null 2>/tmp/lr-retired ); check "a retired key is not an unknown key: config set says what replaced it (exit 2)" "test \$? -eq 2 && grep -q 'no longer a setting' /tmp/lr-retired && grep -q 'compact_instructions' /tmp/lr-retired"
python3 - "$SHED/.longrun/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["compact_hint_max_bytes"]=900; json.dump(d,open(p,"w"))
PY
CR="$(cd "$SHED" && "$LR" config)"; check "a retired key left in a config.json is shown as retired, not obeyed" "echo \"\$CR\" | grep -q 'compact_hint_max_bytes .*retired'"
( cd "$SHED" && "$LR" config unset compact_hint_max_bytes >/dev/null ); check "config unset cleans a retired key out" "! grep -q compact_hint_max_bytes '$SHED/.longrun/config.json'"

python3 - "$LOCAL/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["inject_max_bytes"]=9000; json.dump(d,open(p,"w"))
PY

echo "== docs layer: long material in a file, one line in the notes pointing at it"
DOCP="$T/docproj"; mkdir -p "$DOCP/research"; ( cd "$DOCP" && "$LR" init >/dev/null )
printf 'The manifesto.\nPoint 4: the notes carry the paths of the long files.\nA word only in here: zanzibar.\n' > "$DOCP/research/M.md"
( cd "$DOCP" && "$LR" doc add research/M.md "the original intent of the project, in the author's words; positioning follows it" >/dev/null )
check "doc add writes one shared line with the path relative to the project root" "grep -q '\[n1\] .* doc .*: research/M.md - the original intent' '$DOCP/.longrun/NOTES.md'"
( cd "$DOCP" && "$LR" doc add research/M.md "again" >/dev/null 2>/tmp/lr-doc ); check "the same file twice is refused, and points at doc touch" "test \$? -eq 2 && grep -q 'doc touch n1' /tmp/lr-doc"
( cd "$DOCP" && "$LR" doc add research/nope.md "not written yet" >/dev/null 2>/tmp/lr-doc2 ); check "a doc must point at a file that exists" "test \$? -eq 2 && grep -q 'no such file' /tmp/lr-doc2"
( cd "$DOCP" && "$LR" doc add /etc/hosts "outside" >/dev/null 2>/tmp/lr-doc3 ); check "a file outside the project is refused (it would not resolve in another worktree)" "test \$? -eq 2 && grep -q 'outside the project' /tmp/lr-doc3"
DD="$(cd "$DOCP" && "$LR" digest)"; check "the pointer is in the digest, the file's contents are not" "echo \"\$DD\" | grep -q 'research/M.md - the original intent' && ! echo \"\$DD\" | grep -q 'zanzibar'"
RD="$(cd "$DOCP" && "$LR" recall zanzibar --no-transcript)"; check "recall reaches inside the file the pointer names" "echo \"\$RD\" | grep -q 'research/M.md:3'"
DD1="$(cd "$DOCP" && "$LR" digest)"; check "a file untouched since its line was written carries no warning" "! echo \"\$DD1\" | grep -q 'this line may be stale'"
# The reference is the file's mtime at the moment the description was written, kept in .longrun/docs.json -
# not the note's date. A note carries no time of day, so against the date a change made hours later on the
# SAME day read as no change at all: exactly the case of "another window rewrote this while I was away".
sleep 3; printf 'a line added minutes after the pointer was written\n' >> "$DOCP/research/M.md"
DD2="$(cd "$DOCP" && "$LR" digest)"; check "a change made the same day the line was written is still marked (the note's date could not tell)" "echo \"\$DD2\" | grep -q 'this line may be stale'"
check "the mark says when, to the minute" "echo \"\$DD2\" | grep -qE 'file changed [0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}'"
( cd "$DOCP" && "$LR" doc touch n1 "what is in it now, after the rewrite" >/dev/null )
check "doc touch rewrites the description and keeps the path" "grep -q 'research/M.md - what is in it now' '$DOCP/.longrun/NOTES.md'"
DD2B="$(cd "$DOCP" && "$LR" digest)"; check "...and clears the mark: the description now matches the file" "! echo \"\$DD2B\" | grep -q 'this line may be stale'"
DL="$(cd "$DOCP" && "$LR" doc ls)"; check "doc ls shows the path, the size and when it last changed" "echo \"\$DL\" | grep -q 'research/M.md' && echo \"\$DL\" | grep -q 'changed '"
OLDP="$T/oldstamp"; mkdir -p "$OLDP/research"; ( cd "$OLDP" && "$LR" init >/dev/null )
printf 'material from a project made before stamps existed\n' > "$OLDP/research/O.md"
( cd "$OLDP" && "$LR" doc add research/O.md "long material" >/dev/null && rm -f .longrun/docs.json )
python3 - "$OLDP/.longrun/NOTES.md" <<'PY'
import re,sys,datetime
p=sys.argv[1]; s=open(p).read()
old=(datetime.date.today()-datetime.timedelta(days=3)).strftime("%m-%d")
open(p,"w").write(re.sub(r"(\[n1\]) \d{2}-\d{2}", r"\1 "+old, s))
PY
DDO="$(cd "$OLDP" && "$LR" digest)"; check "a project with no stamps yet falls back to the note's date instead of going quiet" "echo \"\$DDO\" | grep -q 'this line may be stale'"
DG="\"session_id\":\"dddddddd-2222-4333-8444-555555555555\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$DOCP\""
( cd "$DOCP" && hook SessionStart "{$DG,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null
  hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"a\"}" >/dev/null )
sleep 1; printf 'a line another session added\n' >> "$DOCP/research/M.md"
DTURN="$(cd "$DOCP" && hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"b\"}")"
DTURN2="$(cd "$DOCP" && hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"c\"}")"
check "a file changed under a pointer is reported once, on the next turn" "echo \"\$DTURN\" | grep -q 'DOCS changed' && echo \"\$DTURN\" | grep -q 'n1 research/M.md' && ! echo \"\$DTURN2\" | grep -q 'DOCS changed'"
# Somebody else's change is an offer to read; your own is a debt: the line every other session reads
# still describes the file as it was before you touched it.
sleep 1; printf 'a line THIS session wrote\n' >> "$DOCP/research/M.md"
( cd "$DOCP" && hook PostToolUse "{$DG,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$DOCP/research/M.md\"},\"tool_response\":{}}" >/dev/null )
DTURN3="$(cd "$DOCP" && hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"d\"}")"
check "a file THIS session edited asks for doc touch instead of offering a read" "echo \"\$DTURN3\" | grep -q 'DOCS you changed this session' && echo \"\$DTURN3\" | grep -q 'doc touch' && echo \"\$DTURN3\" | grep -q '! n1 research/M.md'"
# The attribution lasts one turn, not the whole session. It used to be a rolling list for the session, so
# once this session had touched a file, every later change by anybody was still signed "you".
sleep 1; printf 'and now somebody ELSE changed the same file\n' >> "$DOCP/research/M.md"
DTURN3B="$(cd "$DOCP" && hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"d2\"}")"
check "a later change to a file this session edited turns ago is theirs again, not an unpaid debt" "echo \"\$DTURN3B\" | grep -q '~ n1 research/M.md' && ! echo \"\$DTURN3B\" | grep -q 'you changed'"
printf 'a second long file, this one only read here\n' > "$DOCP/research/N.md"
( cd "$DOCP" && "$LR" doc add research/N.md "the second pile of long material" >/dev/null
  hook PostToolUse "{$DG,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$DOCP/research/N.md\"},\"tool_response\":{}}" >/dev/null
  hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"e\"}" >/dev/null )
sleep 1; printf 'changed by somebody else\n' >> "$DOCP/research/N.md"
DTURN4="$(cd "$DOCP" && hook UserPromptSubmit "{$DG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"f\"}")"
check "a file this session only READ is never claimed as its work: an offer to read, not a debt" "echo \"\$DTURN4\" | grep -q 'DOCS changed since you last looked' && echo \"\$DTURN4\" | grep -q '~ n2 research/N.md' && ! echo \"\$DTURN4\" | grep -q 'you changed'"
rm "$DOCP/research/M.md"
DD3="$(cd "$DOCP" && "$LR" digest)"; check "a pointer whose file is gone says so instead of going quiet" "echo \"\$DD3\" | grep -q 'MISSING'"
python3 - "$DOCP/.longrun/NOTES.md" <<'PY'
import re,sys,datetime
p=sys.argv[1]; s=open(p).read()
old=(datetime.date.today()-datetime.timedelta(days=9)).strftime("%m-%d")
open(p,"w").write(re.sub(r"(\[n1\]) \d{2}-\d{2}", r"\1 "+old, s))
PY
( cd "$DOCP" && "$LR" gc >/dev/null )
check "gc archives a pointer whose file has been missing for a week" "! grep -q 'research/M.md' '$DOCP/.longrun/NOTES.md' && grep -q 'doc file gone' '$DOCP/.longrun/archive/notes.md'"

echo "== the poll hint: waiting by hand, told once what to do instead"
# "Never poll" was a line in SKILL.md and nothing else. A hint, never a refusal: a long sleep is sometimes
# right, and nothing here can tell which.
PLP="$T/pollhint"; mkdir -p "$PLP"; ( cd "$PLP" && "$LR" init >/dev/null )
PG="\"session_id\":\"pppppppp-2222-4333-8444-555555555555\",\"transcript_path\":\"\",\"cwd\":\"$PLP\""
pbash(){ hook PostToolUse "{$PG,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"},\"tool_response\":{}}"; }
pturn(){ hook UserPromptSubmit "{$PG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"go\"}" >/dev/null; }
( cd "$PLP" && hook SessionStart "{$PG,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null )
PH0="$(cd "$PLP" && pbash 'go build ./...')"; check "an ordinary command is not a poll" "! echo \"\$PH0\" | grep -q 'watch add'"
PH1="$(cd "$PLP" && pbash 'sleep 120 && gh pr checks 42')"
check "a long sleep is met with watch, and with the reason it is better" "echo \"\$PH1\" | grep -q 'longrun watch add' && echo \"\$PH1\" | grep -q 'waits 120s'"
PH2="$(cd "$PLP" && pbash 'sleep 120 && gh pr checks 42')"
check "...once per turn, not after every sleep" "! echo \"\$PH2\" | grep -q 'watch add'"
( cd "$PLP" && pturn )
PH3="$(cd "$PLP" && pbash 'sleep 5')"; check "a short sleep is pacing a command, not waiting for the world" "! echo \"\$PH3\" | grep -q 'watch add'"
( cd "$PLP" && pbash 'gh pr checks 42' >/dev/null; pbash 'gh pr checks 42' >/dev/null )
PH4="$(cd "$PLP" && pbash 'gh pr checks 42')"
check "the same command three times over is a poll loop even with no sleep in it" "echo \"\$PH4\" | grep -q 'longrun watch add' && echo \"\$PH4\" | grep -q 'same command 3 times'"

echo "== the recall hint: a session searching for something already written down, outside its context"
# Manifesto point 2 is the one direction nothing mechanical covered: the digest OFFERS the saved material
# at every start, but nothing noticed a session working out again what a note or a file already answers.
# The signal is the session's own search term - a Grep pattern, a Glob, a subagent's description.
RCP="$T/recallhint"; mkdir -p "$RCP/research"; ( cd "$RCP" && "$LR" init >/dev/null )
RLOCAL="$RCP/.longrun"; RSESS="$CLAUDE_CONFIG_DIR/longrun/sessions"
printf 'The retry path.\nEPMA rejects a retry when the idempotency key is reused after a decline; use a fresh key.\nUnrelated prose about deployment.\n' > "$RCP/research/R.md"
( cd "$RCP" && "$LR" doc add research/R.md "how the retry path behaves, in detail" >/dev/null )
RG="\"session_id\":\"rrrrrrrr-2222-4333-8444-555555555555\",\"transcript_path\":\"\",\"cwd\":\"$RCP\""
( cd "$RCP" && hook SessionStart "{$RG,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null )
ptu(){ hook PostToolUse "{$RG,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"$1\",\"tool_input\":$2,\"tool_response\":{}}"; }
# Another session's own notes: the commonest place an answer hides, since they are never injected here.
RPEER="$(ls -d "$RSESS"/*recallhint*/ 2>/dev/null | head -1)peer"; mkdir -p "$RPEER"
printf -- '- [s1] 09-17 dead: retrying through EPMA with a reused idempotency key is refused after a decline\n- [s2] 09-17 ctx: my own scratch note about the idempotency ticket\n' > "$RPEER/notes.md"
RH1="$(cd "$RCP" && ptu Grep '{"pattern":"idempotency"}')"
check "a Grep for what another session recorded as a dead end is met with that line and with recall" "echo \"\$RH1\" | grep -q 'already written down in this project' && echo \"\$RH1\" | grep -q 'sessions/peer/notes.md:1' && echo \"\$RH1\" | grep -q 'longrun recall idempotency'"
check "a ctx note is that conversation's own bookkeeping and is never offered to another session" "! echo \"\$RH1\" | grep -q 'my own scratch note'"
RH2="$(cd "$RCP" && ptu Grep '{"pattern":"idempotency"}')"
check "...and not again for the same term and file: one pointer, not a nag" "test -z \"\$RH2\""
RH3="$(cd "$RCP" && ptu Grep '{"pattern":"the"}')"
check "a short word is not a search term: no hint" "test -z \"\$RH3\""
printf -- '- [s3] 09-17 fact: deployment one\n- [s4] 09-17 fact: deployment two\n- [s5] 09-17 fact: deployment three\n- [s6] 09-17 fact: deployment four\n- [s7] 09-17 fact: deployment five\n- [s8] 09-17 fact: deployment six\n- [s9] 09-17 fact: deployment seven\n' >> "$RPEER/notes.md"
RH4="$(cd "$RCP" && ptu Grep '{"pattern":"deployment"}')"
check "a term on too many lines is a word, not a term: no hint" "test -z \"\$RH4\""
# Prose is not a note: one word lands on a line of it by accident, so a doc file needs two of them.
rturn(){ hook UserPromptSubmit "{$RG,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"go\"}" >/dev/null; }
printf 'The widget drawer keeps its promocode slot in a separate layout branch.\n' >> "$RCP/research/R.md"
( cd "$RCP" && rturn )
RH4B="$(cd "$RCP" && ptu Grep '{"pattern":"promocode"}')"
check "one word hitting a line of prose in a doc file is a collision, not an answer" "test -z \"\$RH4B\""
( cd "$RCP" && rturn )
RH4C="$(cd "$RCP" && ptu Grep '{"pattern":"promocode layout"}')"
check "...two of them on the same line of it is not" "echo \"\$RH4C\" | grep -q 'research/R.md:4'"
( cd "$RCP" && rturn )
RH5="$(cd "$RCP" && hook PostToolBatch "{$RG,\"hook_event_name\":\"PostToolBatch\",\"tool_calls\":[{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$RCP/research/R.md\"},\"tool_response\":{}}]}")"
check "a Read carries no question, so it is never guessed at from the path" "test -z \"\$RH5\""
RMETA="$(ls -d "$CLAUDE_CONFIG_DIR"/longrun/sessions/*recallhint*/rrrrrrrr/meta.json 2>/dev/null | head -1)"
check "a search tool moves no counter: looking around is still not activity" "test -n \"\$RMETA\" && grep -q '\"tools\": 0' \"\$RMETA\""
printf 'x\n' > "$RCP/research/R2.md"
RH6="$(cd "$RCP" && ptu Grep '{"pattern":"nothing_here_at_all"}')"
check "a term nothing answers stays silent" "test -z \"\$RH6\""
# PostToolBatch: one event for a whole batch, no matcher, and it sees the Reads too - so a file the
# session already has open is not offered back to it.
printf -- '2026-09-10 11:00 pruned | - [n9] 09-10 decision: the checkout drawer was superseded by widget v3 in PR 41\n' > "$RLOCAL/archive/notes.md"
RB1="$(cd "$RCP" && hook PostToolBatch "{$RG,\"hook_event_name\":\"PostToolBatch\",\"tool_calls\":[{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$RCP/research/R.md\"},\"tool_response\":{}},{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"supersede\"},\"tool_response\":{}}]}")"
check "PostToolBatch reads the whole batch and finds the archived answer" "echo \"\$RB1\" | grep -q 'additionalContext' && echo \"\$RB1\" | grep -q 'widget v3 in PR 41'"
printf 'the drawer also owns a promocode layout slot\n' >> "$RCP/research/R.md"
RB2="$(cd "$RCP" && hook PostToolBatch "{$RG,\"hook_event_name\":\"PostToolBatch\",\"tool_calls\":[{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"promocode layout\"},\"tool_response\":{}}]}")"
check "a file this session has already opened is not offered back to it" "test -z \"\$RB2\""
# Two pointers in a turn is help; five is a lecture. The budget refills at the turn boundary.
printf -- '2026-09-10 11:00 pruned | - [n8] 09-10 fact: the kassa callback signature is checked against the merchant key\n2026-09-10 11:00 pruned | - [n7] 09-10 dead: the courier eta endpoint answers 404 for a cancelled order\n2026-09-10 11:00 pruned | - [n6] 09-10 decision: the tariff matrix is rebuilt nightly, never on request\n' >> "$RLOCAL/archive/notes.md"
( cd "$RCP" && rturn )
RB3A="$(cd "$RCP" && ptu Grep '{"pattern":"merchant"}')"; RB3B="$(cd "$RCP" && ptu Grep '{"pattern":"courier"}')"
RB3="$(cd "$RCP" && ptu Grep '{"pattern":"tariff"}')"
check "two pointers in a turn are help; the third is held back" "echo \"\$RB3A\" | grep -q 'merchant key' && echo \"\$RB3B\" | grep -q 'cancelled order' && test -z \"\$RB3\""
( cd "$RCP" && rturn )
RB4="$(cd "$RCP" && ptu Grep '{"pattern":"tariff"}')"
check "...and the next turn gets it, instead of it being lost" "echo \"\$RB4\" | grep -q 'rebuilt nightly'"

echo "== recall ranking: curated notes are not crowded out by a noisy archive"
for k in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do echo "old summary $k mentioning pgx pool deadlock again" > "$LOCAL/archive/compact/11111111-2026010$((k%9))-$k.md"; done
"$LR" add --shared -t dead "go test -race hangs: pgx pool deadlock, run without -race" >/dev/null 2>&1
RR="$("$LR" recall deadlock -n 3 --no-transcript)"
check "recall shows the NOTES.md hit despite 15 noisier archive hits" "echo \"\$RR\" | head -1 | grep -q 'NOTES.md'"

echo "== status and concurrency"
mkdir -p "$SESS/00000000"; printf '{"sid":"00000000-noise","skey":"00000000","cwd":"%s","tools":0,"turns":0,"last_seen":"2026-09-06 10:00"}\n' "$WT" > "$SESS/00000000/meta.json"
S="$("$LR" status 2>&1)"; check "status lists the session with its state, own-note count and last status" "echo \"\$S\" | grep -q '11111111 .* ended(clear)' && echo \"\$S\" | grep -q 'notes=4'"
check "status hides a session with no tool calls and no turns (app noise), --all shows it" "! echo \"\$S\" | grep -q '00000000' && echo \"\$S\" | grep -q '1 session(s) with no tool calls' && $LR status --all | grep -q '00000000'"
python3 - "$LOCAL/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["notes_max_bytes"]=20000; d["session_notes_max_bytes"]=20000; json.dump(d,open(p,"w"))
PY
for i in $(seq 1 20); do ( "$LR" add --shared -t fact "concurrent writer $i says hello from a parallel session" >/dev/null 2>&1 ) & done; wait
CNT=$(grep -c 'concurrent writer' "$LOCAL/NOTES.md"); check "20 parallel shared adds, none lost ($CNT)" "test $CNT -eq 20"
IDS=$(grep -o '\[n[0-9]*\]' "$LOCAL/NOTES.md" | sort | uniq -d | wc -l | tr -d ' '); check "ids unique under concurrency" "test $IDS -eq 0"
for i in $(seq 1 20); do ( "$LR" add --own -t fact "own concurrent writer $i" >/dev/null 2>&1 ) & done; wait
CNT=$(grep -c 'own concurrent writer' "$SD/notes.md"); check "20 parallel own adds, none lost ($CNT)" "test $CNT -eq 20"

echo "== gc retention"
python3 - "$LOCAL/NOTES.md" "$SD/notes.md" <<'PY'
import sys,re
for p in sys.argv[1:]:
    t=open(p).read()
    t=re.sub(r"(\[[ns]\d+\]) \d\d-\d\d fact", r"\1 01-01 fact", t, count=1)   # age one fact entry by ~8 months
    open(p,"w").write(t)
PY
touch -t 202501010000 "$LOCAL/archive/precompact/"*.md
printf '2025-01-01 10:00 rm | - [n99] 01-01 fact: an ancient removal that must age out\n' >> "$LOCAL/archive/notes.md"
"$LR" gc >/tmp/lr-gc; check "gc archives expired shared and own notes and deletes old archive files" "grep -q 'shared notes: archived 1 expired' /tmp/lr-gc && grep -q 'own notes of 11111111: archived 1 expired' /tmp/lr-gc && grep -q 'deleted archive/precompact' /tmp/lr-gc"
check "archive/notes.md ages line by line: the old line is gone, recent lines stay" "! grep -q 'ancient removal' '$LOCAL/archive/notes.md' && grep -q 'rm | - \[n1\]' '$LOCAL/archive/notes.md' && grep -q 'shared notes: dropped 1 old archive lines' /tmp/lr-gc"
mkdir -p "$SESS/deadbeef"; printf '{"sid":"deadbeef-1111","skey":"deadbeef","cwd":"%s","tools":7,"turns":2,"last_seen":"2026-08-01 10:00","last_status":"long dead"}\n' "$WT" > "$SESS/deadbeef/meta.json"; touch -t 202508010000 "$SESS/deadbeef/meta.json"
"$LR" gc >/tmp/lr-gc2; check "gc archives a session silent for a week into archive/sessions/<key>/" "grep -q 'session deadbeef: archived' /tmp/lr-gc2 && test -f '$LOCAL/archive/sessions/deadbeef/meta.json' && ! test -d '$SESS/deadbeef'"

echo "== older layouts are migrated, not orphaned"
# 0.1: heartbeats inside the project dir; 0.2: flat <sid8>.md/.json in the sessions dir
OLDP="$T/oldlayout"; mkdir -p "$OLDP"; ( cd "$OLDP" && "$LR" init >/dev/null )
mkdir -p "$OLDP/.longrun/sessions"
printf '{"sid":"deadbeef-1111","cwd":"%s","tools":7,"last_seen":"2026-09-01 10:00","last_status":"pre-migration session"}\n' "$OLDP" > "$OLDP/.longrun/sessions/deadbeef.json"
printf '09-01 10:00 FAIL `make build` -> Exit code 2 undefined: OldSymbol\n' > "$OLDP/.longrun/sessions/deadbeef.md"
NEWSESS="$(cd "$OLDP" && "$LR" where | sed -n 's/^sessions: //p')"
printf '{"sid":"0badf00d-1111","cwd":"%s","tools":2,"last_seen":"2026-09-02 10:00","last_status":"flat 0.2 session"}\n' "$OLDP" > "$NEWSESS/0badf00d.json"
( cd "$OLDP" && "$LR" gc >/tmp/lr-mig 2>&1 )
# a session that keeps running across the upgrade: its next PostToolUse must migrate the flat files BEFORE reading
# them, and a journal/meta already written in the new layout is merged, not overwritten
UPG="$T/upgrade"; mkdir -p "$UPG"; ( cd "$UPG" && "$LR" init >/dev/null ); UPSESS="$(cd "$UPG" && "$LR" where | sed -n 's/^sessions: //p')"
USID=abcd1234-2222-4333-8444-555555555555
printf '{"sid":"%s","cwd":"%s","tools":50,"turns":7,"last_seen":"2026-09-07 10:00","last_status":"before upgrade"}\n' "$USID" "$UPG" > "$UPSESS/abcd1234.json"
printf '09-07 09:00 * pushed before the upgrade\n' > "$UPSESS/abcd1234.md"
hook PostToolUse "{\"session_id\":\"$USID\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$UPG\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{}}" >/dev/null
check "a running session's first hook after the upgrade migrates its flat files first (counters continue: 51)" "test -f '$UPSESS/abcd1234/meta.json' && grep -q '\"tools\": 51' '$UPSESS/abcd1234/meta.json' && ! test -f '$UPSESS/abcd1234.json'"
mkdir -p "$UPSESS/efgh5678"; printf '{"sid":"efgh5678-1","skey":"efgh5678","tools":3,"turns":1,"last_seen":"2026-09-07 11:00"}\n' > "$UPSESS/efgh5678/meta.json"; printf '09-07 11:00 written in the new layout\n' > "$UPSESS/efgh5678/journal.md"
printf '{"sid":"efgh5678-1","cwd":"%s","tools":40,"turns":5,"last_seen":"2026-09-07 10:00","last_status":"old"}\n' "$UPG" > "$UPSESS/efgh5678.json"; printf '09-07 09:30 * old journal line\n' > "$UPSESS/efgh5678.md"
( cd "$UPG" && "$LR" gc >/dev/null 2>&1 )
check "flat files meeting an existing new-layout dir are merged: counters summed, old journal lines first" "grep -q '\"tools\": 43' '$UPSESS/efgh5678/meta.json' && test \"\$(head -1 '$UPSESS/efgh5678/journal.md')\" = '09-07 09:30 * old journal line' && grep -q 'written in the new layout' '$UPSESS/efgh5678/journal.md' && ! test -f '$UPSESS/efgh5678.json'"
check "gc moves 0.1 heartbeats out of the project dir and 0.2 flat files into per-session dirs" "grep -q 'migrated' /tmp/lr-mig && test -f '$NEWSESS/deadbeef/meta.json' && test -f '$NEWSESS/deadbeef/journal.md' && test -f '$NEWSESS/0badf00d/meta.json' && ! test -d '$OLDP/.longrun/sessions'"
check "migrated history stays visible to status and recall" "(cd '$OLDP' && $LR status) | grep -q 'pre-migration session' && (cd '$OLDP' && $LR recall OldSymbol --no-transcript) | grep -q 'sessions/deadbeef/journal.md'"
# 0.2 worktree: a per-directory store under ~/.claude/longrun/projects with config.hub -> the project is the hub now
OLDWT="$T/wt/old-branch"; mkdir -p "$OLDWT"
OLDSTORE="$CLAUDE_CONFIG_DIR/longrun/projects/legacy-old-branch"; mkdir -p "$OLDSTORE/archive"
printf '{"hub": "%s"}\n' "$LOCAL" > "$OLDSTORE/config.json"
printf '# longrun notes\n- [n1] 09-01 dead (old-branch): a dead end recorded by the 0.2 worktree store\n' > "$OLDSTORE/NOTES.md"
python3 - "$CLAUDE_CONFIG_DIR/longrun/registry.json" "$OLDWT" "$OLDSTORE" <<'PY'
import json,sys,os; p=sys.argv[1]; d=json.load(open(p)); d["links"][os.path.realpath(sys.argv[2])]=sys.argv[3]; json.dump(d,open(p,"w"))
PY
W2="$(cd "$OLDWT" && "$LR" where)"
check "a 0.2 worktree store resolves to its hub as the project" "echo \"\$W2\" | grep -q 'project:  hq  ($LOCAL)'"
check "the notes it held are parked in the project archive and recall finds them" "grep -q 'legacy .*old-branch | - \[n1\] .*0.2 worktree store' '$LOCAL/archive/notes.md' && test -f '$OLDSTORE/NOTES.legacy.md' && (cd '$OLDWT' && $LR recall '0.2 worktree' --no-transcript) | grep -q 'archive/notes.md'"

echo "== a project made by plain init, and hand edits to its notes"
SOLO="$T/solo"
( cd "$SOLO" && "$LR" add --shared -t dead "notes work in a project nobody configured" >/dev/null )
check "shared notes and recall work in a plain project" "(cd '$SOLO' && $LR recall notes --no-transcript) | grep -q 'NOTES.md'"
check "the ledger layer is gone: no file, no command, no digest block" "! test -e '$SOLO/.longrun/ledger.md' && ! (cd '$SOLO' && $LR ledger add -o user x >/dev/null 2>&1) && ! (cd '$SOLO' && $LR digest) | grep -q 'LEDGER'"
( cd "$SOLO" && "$LR" init --hq >/dev/null 2>&1 ); check "the old --hq flag is accepted and ignored, so an old command line still works" "test \$? -eq 0 && ! test -e '$SOLO/.longrun/ledger.md'"
printf '## my own heading\n' >> "$SOLO/.longrun/NOTES.md"; ( cd "$SOLO" && "$LR" add --shared -t fact "written after a hand heading" >/dev/null )
check "a hand-written heading in NOTES.md is kept, not silently dropped" "grep -q 'my own heading' '$SOLO/.longrun/NOTES.md'"

echo "== gc auto-prunes cheap entries so writing never simply stops"
AP="$T/autoprune"; mkdir -p "$AP"; ( cd "$AP" && "$LR" init >/dev/null )
python3 - "$AP/.longrun/config.json" <<'PY'
import json,sys; json.dump({"notes_max_bytes": 800, "notes_autoprune_pct": 85, "notes_warn_pct": 60}, open(sys.argv[1], "w"))
PY
cd "$AP"
"$LR" add --shared -t dead "keep me: the -race approach deadlocks in pgx and must not be retried" >/dev/null
for i in 1 2 3 4 5 6 7 8; do "$LR" add --shared -t todo "cheap follow-up number $i that gc may archive when the budget gets tight" >/dev/null 2>&1; done
BEFORE=$(size "$AP/.longrun/NOTES.md")
"$LR" gc >/tmp/lr-gc 2>&1
AFTER=$(size "$AP/.longrun/NOTES.md")
check "gc auto-archived cheap todo entries ($BEFORE -> $AFTER B)" "test $AFTER -lt $BEFORE && grep -q 'auto-archived' /tmp/lr-gc"
check "gc never auto-archives a dead end" "grep -q 'keep me: the -race approach' '$AP/.longrun/NOTES.md'"
cd "$WT"

echo "== recall reaches earlier sessions' transcripts and other sessions' own notes"
OTHER="$CLAUDE_CONFIG_DIR/projects/-proj/99999999-2222-4333-8444-555555555555.jsonl"
python3 - "$OTHER" <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[
 {"type":"text","text":"we abandoned the epma-widget-stub route because the client is generated from a stale proto"}]}})+"\n")
PY
R3="$("$LR" recall epma-widget-stub 2>&1)"
check "recall finds a detail from a previous session's transcript" "echo \"\$R3\" | grep -q 'transcript@99999999' && echo \"\$R3\" | grep -q 'stale proto'"
check "recall reports how many transcripts it scanned" "echo \"\$R3\" | grep -q 'transcript(s)'"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-proj/$SID/subagents"; python3 - "$CLAUDE_CONFIG_DIR/projects/-proj/$SID/subagents/agent-deadbeef12345.jsonl" <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"the explore agent found that widget-proto-v7 is generated from a stale schema"}]}})+"\n")
PY
R4="$("$LR" recall widget-proto-v7 2>&1)"; check "recall reaches the current session's subagent transcripts" "echo \"\$R4\" | grep -q 'subagent@deadbeef' && echo \"\$R4\" | grep -q 'stale schema'"
mkdir -p "$SESS/abcdef01"; printf '# longrun notes of this session\n- [s1] 09-07 dead: another session found that the carousel widget rejects empty method lists\n' > "$SESS/abcdef01/notes.md"
R5="$("$LR" recall "carousel widget" --no-transcript 2>&1)"; check "recall reaches other sessions' own notes" "echo \"\$R5\" | grep -q 'sessions/abcdef01/notes.md'"

echo "== send: socket to a live peer, inbox to a stopped one, delivery by the target's hooks"
cd "$WT"; mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
python3 - "$T/peer.sock" "$T/peer.out" <<'PYS' &
import socket,sys
p,o=sys.argv[1],sys.argv[2]
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.bind(p); s.listen(1); s.settimeout(60)
c,_=s.accept(); c.settimeout(5); data=b""
try:
    while True:
        ch=c.recv(65536)
        if not ch: break
        data+=ch
except Exception: pass
open(o,"wb").write(data); c.close(); s.close()
PYS
PEER=$!; sleep 1
printf '{"pid":%d,"sessionId":"77777777-2222-4333-8444-555555555555","cwd":"%s","name":"wt-worker","messagingSocketPath":"%s","kind":"interactive"}\n' $PEER "$WT" "$T/peer.sock" > "$CLAUDE_CONFIG_DIR/sessions/$PEER.json"
printf '{"pid":999999,"sessionId":"66666666-2222-4333-8444-555555555555","cwd":"%s","name":"gone-worker","kind":"interactive"}\n' "$WT" > "$CLAUDE_CONFIG_DIR/sessions/999999.json"
check "send --list shows the running peer with its socket" "$LR send --list | grep -q 'wt-worker.*socket'"
"$LR" send --resume wt-worker "x" >/dev/null 2>&1; check "--resume is refused for a running session" "test \$? -eq 2"
OUT="$(CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/1.sock "$LR" send wt-worker "hello from HQ over the socket" 2>&1)"; wait $PEER
check "send to a running peer goes over its socket as a user message with a sender stamp" "echo \"\$OUT\" | grep -q 'delivered to wt-worker' && python3 -c \"import json;d=json.loads(open('$T/peer.out').read().splitlines()[0]);assert d['type']=='user' and 'hello from HQ' in d['message']['content'] and 'From longrun session' in d['message']['content'] and d['msgV']==1 and d['priority']=='next' and d['from'].startswith('uds:')\""
OUT2="$("$LR" send gone-worker "wake up and check the build" 2>&1)"
MSG=$(ls "$LOCAL/inbox/"*-msg-to-66666666-* 2>/dev/null | head -1)
check "send to a session that is not running queues a file in the project inbox" "echo \"\$OUT2\" | grep -q 'queued as inbox/' && test -n \"\$MSG\" && grep -q 'wake up and check the build' \"\$MSG\""
G="\"session_id\":\"66666666-2222-4333-8444-555555555555\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$WT\""
UPSM="$(hook UserPromptSubmit "{$G,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}")"
check "the target's UserPromptSubmit delivers the message once and archives it" "echo \"\$UPSM\" | grep -q 'MESSAGE to 66666666' && echo \"\$UPSM\" | grep -q 'wake up and check the build' && ! ls '$LOCAL/inbox/'*-msg-to-66666666-* >/dev/null 2>&1 && ls '$LOCAL/inbox/.archive/' | grep -q -- '-msg-to-66666666-'"
"$LR" send gone-worker "second: run the tests" >/dev/null 2>&1
PTM="$(hook PostToolUse "{$G,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{}}")"
check "the target's PostToolUse delivers a message between tool calls as additionalContext" "echo \"\$PTM\" | grep -q 'additionalContext' && echo \"\$PTM\" | grep -q 'second: run the tests'"
python3 -c "print('x' * 5000)" | "$LR" send gone-worker - >/dev/null 2>&1
LONGM="$(hook PostToolUse "{$G,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{}}")"
check "a message longer than the injection limit says it was cut and where the whole text is" "echo \"\$LONGM\" | grep -q 'cut off here, 5000 chars in all' && echo \"\$LONGM\" | grep -q 'inbox/.archive/'"
"$LR" send 66666666 "third: at start" >/dev/null 2>&1
SSM="$(hook SessionStart "{$G,\"hook_event_name\":\"SessionStart\",\"source\":\"resume\"}")"
check "the target's SessionStart digest carries a queued message" "echo \"\$SSM\" | grep -q 'MESSAGE to 66666666' && echo \"\$SSM\" | grep -q 'third: at start'"
mkdir -p "$T/bin"; printf '#!/bin/bash\necho "args: $*"\necho "cwd: $(pwd)"\necho "LONGRUN_DIR=[${LONGRUN_DIR:-}]"\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
RES="$(PATH="$T/bin:$PATH" LONGRUN_DIR="$LOCAL" "$LR" send --resume gone-worker --max-turns 3 "do the thing" 2>&1)"
check "--resume runs claude -p <text> --resume <sid> in the session's cwd with LONGRUN_* scrubbed" "echo \"\$RES\" | grep -q -- '-p From longrun session' && echo \"\$RES\" | grep -q -- '--resume 66666666-2222-4333-8444-555555555555 --max-turns 3' && echo \"\$RES\" | grep -q 'cwd: .*EDAINAPP-1375-screen' && echo \"\$RES\" | grep -q 'LONGRUN_DIR=\[\]'"
NOHQ="$T/nohq"; mkdir -p "$NOHQ"; ( cd "$NOHQ" && "$LR" init >/dev/null ); ( cd "$NOHQ" && "$LR" send gone-worker "no hq here" >/tmp/lr-send5 2>&1 ); check "a message from another project lands where the TARGET's hooks look (its own project inbox)" "test \$? -eq 0 && ls '$LOCAL/inbox/'*-msg-to-66666666-* >/dev/null 2>&1"
"$LR" inbox ack --all >/dev/null 2>&1; rm -f "$LOCAL/inbox/"*-msg-to-*
DSK="$LONGRUN_DESKTOP_DIR/aaaa/bbbb"; mkdir -p "$DSK"
printf '{"sessionId":"local_66666666-2222-4333-8444-555555555555","cliSessionId":"66666666-2222-4333-8444-555555555555","cwd":"%s","title":"PR E: Шторка лотереи","isArchived":false,"lastActivityAt":1788779365881}' "$WT" > "$DSK/local_66666666-2222-4333-8444-555555555555.json"
printf '{"sessionId":"local_88888888-2222-4333-8444-555555555555","cliSessionId":"88888888-2222-4333-8444-555555555555","cwd":"%s","title":"PR E: Шторка лотереи (fork)","isArchived":true,"lastActivityAt":1788779365999}' "$WT" > "$DSK/local_88888888-2222-4333-8444-555555555555.json"
"$LR" send "PR E: Шторка лотереи" "by title" >/dev/null 2>&1; check "send resolves a desktop sidebar title (archived twin ignored)" "test \$? -eq 0 && grep -l 'by title' '$LOCAL/inbox/'*-msg-to-d66666666-* >/dev/null 2>&1"
check "send --list shows desktop titles" "$LR send --list | grep -q 'PR E: Шторка лотереи'"
rm -f "$LOCAL/inbox/"*-msg-to-*

echo "== watch: deferred checks, timer-free tick, delivery to a stopped and a running session"
export LONGRUN_SESSION=$SID
WD="$CLAUDE_CONFIG_DIR/longrun/watch"
"$LR" watch test -- at +1h >/tmp/lr-wt 2>&1; check "watch test: at +1h is not yet (rc 1)" "test \$? -eq 1 && grep -q 'not yet' /tmp/lr-wt"
"$LR" watch test -- file /nonexistent/x >/dev/null 2>&1; check "watch test: missing file is not yet" "test \$? -eq 1"
"$LR" watch test -- cmd 'exit 3' >/dev/null 2>&1; check "watch test: cmd exit 3 is a hard error" "test \$? -eq 3"
"$LR" watch add --then "x" -- cmd 'exit 3' >/dev/null 2>/tmp/lr-wa; check "watch add refuses a check that fails hard" "test \$? -eq 3 && grep -q 'fails hard' /tmp/lr-wa"
OUTA="$("$LR" watch add --then "already" -- cmd 'true' 2>&1)"; check "watch add with an already-true check registers nothing" "echo \"\$OUTA\" | grep -q 'already true' && ! ls '$WD'/w*.json >/dev/null 2>&1"
FLAG="$T/flag-file"
OUT1="$("$LR" watch add --to "PR E: Шторка лотереи" --every 1m --then "the flag appeared: run the tests" -- file "$FLAG" 2>&1)"
check "watch add by sidebar title -> w1, inbox delivery announced" "echo \"\$OUT1\" | grep -q 'registered w1' && echo \"\$OUT1\" | grep -q 'PR E: Шторка лотереи \[66666666\]' && echo \"\$OUT1\" | grep -q 'inbox file' && test -f '$WD/w1.json'"
check "watch add snapshots PATH for the timer" "test -f '$WD/env.json' && grep -q '/usr/bin' '$WD/env.json'"
check "watch ls shows it pending" "$LR watch ls | grep -q 'w1   pending'"
"$LR" watch run --force >/dev/null; check "tick with the condition false keeps it pending" "grep -q '\"state\": \"pending\"' '$WD/w1.json' && grep -q '\"runs\": 2' '$WD/w1.json'"
touch "$FLAG"; "$LR" watch run --force >/tmp/lr-tick; MSGW=$(ls "$LOCAL/inbox/"*-msg-to-d66666666-from-watch.md 2>/dev/null | head -1)
check "tick fires: message queued in the TARGET's inbox with the --then text" "grep -q '1 fired' /tmp/lr-tick && test -n \"\$MSGW\" && grep -q 'CONDITION MET: file exists' \"\$MSGW\" && grep -q 'the flag appeared: run the tests' \"\$MSGW\" && grep -q '\"state\": \"fired\"' '$WD/w1.json'"
check "fired watch logged in the target's journal" "grep -q 'watch w1 fired' '$SESS/66666666/journal.md'"
G="\"session_id\":\"66666666-2222-4333-8444-555555555555\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$WT\""
SSW="$(hook SessionStart "{$G,\"hook_event_name\":\"SessionStart\",\"source\":\"resume\"}")"
check "the target's next SessionStart delivers the fired watch" "echo \"\$SSW\" | grep -q 'CONDITION MET' && echo \"\$SSW\" | grep -q 'run the tests'"
check "watch ls hides fired, --all shows it with delivery" "! $LR watch ls | grep -q 'w1 ' && $LR watch ls --all | grep -q 'delivered via inbox'"
# the app resumes a session with a NEW CLI id behind the same sidebar entry: the watch follows the entry
"$LR" watch add --to "PR E: Шторка лотереи" --no-test --then "after resume" -- file "$FLAG" >/dev/null 2>&1
printf '{"sessionId":"local_66666666-2222-4333-8444-555555555555","cliSessionId":"99999999-2222-4333-8444-555555555555","priorCliSessionIds":["66666666-2222-4333-8444-555555555555"],"cwd":"%s","title":"PR E: Шторка (renamed)","isArchived":false,"lastActivityAt":1788779365881}' "$WT" > "$DSK/local_66666666-2222-4333-8444-555555555555.json"
"$LR" watch run --force >/dev/null
check "watch follows the desktop entry to the new CLI id (rename + resume)" "grep -q '99999999-2222' '$WD/w2.json' && grep -q 'resumed: CLI id 66666666 -> 99999999' '$WD/run.log'"
G9="\"session_id\":\"99999999-2222-4333-8444-555555555555\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$WT\""
SS9="$(hook SessionStart "{$G9,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}")"
check "the resumed session (new CLI id) receives the message addressed to its desktop id" "echo \"\$SS9\" | grep -q 'after resume' && grep -q '\"desktop_id\": \"local_66666666' '$SESS/66666666/meta.json'"
check "the resumed session continues the prior's dir (priorCliSessionIds): same key, journal continues, no second dir" "grep -q '\"skey\": \"66666666\"' '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/99999999-2222-4333-8444-555555555555.json' && grep -q 'session startup' '$SESS/66666666/journal.md' && ! test -d '$SESS/99999999' && echo \"\$SS9\" | grep -q 'continued from an earlier CLI id'"
"$LR" watch add --no-test --then "handle it" -- cmd 'exit 3' >/dev/null 2>&1
"$LR" watch run --force >/dev/null; "$LR" watch run --force >/dev/null; "$LR" watch run --force >/dev/null
MSGB=$(grep -l 'WATCH BROKEN' "$LOCAL/inbox/"*-msg-to-11111111-from-watch.md 2>/dev/null | head -1)
check "three hard errors -> broken, reported to the registering session" "grep -q '\"state\": \"broken\"' '$WD/w3.json' && test -n \"\$MSGB\""
"$LR" watch add --no-test --for 60 --then "late" -- file /nonexistent/never >/dev/null 2>&1
python3 - "$WD/w4.json" <<'PYX'
import json,sys,time; p=sys.argv[1]; d=json.load(open(p)); d["expires"]=time.time()-10; json.dump(d,open(p,"w"))
PYX
"$LR" watch run --force >/dev/null; check "expired watch is reported and closed" "grep -q '\"state\": \"expired\"' '$WD/w4.json' && grep -l 'WATCH EXPIRED' '$LOCAL/inbox/'*-msg-to-11111111-from-watch.md >/dev/null 2>&1"
python3 - "$T/peer2.sock" "$T/peer2.out" <<'PYS' &
import socket,sys
p,o=sys.argv[1],sys.argv[2]
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.bind(p); s.listen(1); s.settimeout(60)
c,_=s.accept(); c.settimeout(5); data=b""
try:
    while True:
        ch=c.recv(65536)
        if not ch: break
        data+=ch
except Exception: pass
open(o,"wb").write(data); c.close(); s.close()
PYS
PEER2=$!; sleep 1
printf '{"pid":%d,"sessionId":"77777777-2222-4333-8444-555555555555","cwd":"%s","name":"wt-worker","messagingSocketPath":"%s","kind":"interactive"}\n' $PEER2 "$WT" "$T/peer2.sock" > "$CLAUDE_CONFIG_DIR/sessions/$PEER2.json"
"$LR" watch add --to wt-worker --no-notify --then "socket path" -- at "+1h" >/dev/null 2>&1
python3 - "$WD/w5.json" <<'PYX'
import json,sys,time; p=sys.argv[1]; d=json.load(open(p)); d["check"]["args"]=[str(time.time()-1)]; json.dump(d,open(p,"w"))
PYX
"$LR" watch run --force >/dev/null; wait $PEER2
check "fired watch reaches a running session over its socket as a user turn" "python3 -c \"import json;d=json.loads(open('$T/peer2.out').read().splitlines()[0]);assert d['type']=='user' and 'CONDITION MET' in d['message']['content'] and 'socket path' in d['message']['content'] and d['priority']=='next'\" && grep -q '\"how\": \"socket\"' '$WD/w5.json'"
"$LR" watch add --to nobody-like-this --then x -- at +1h >/dev/null 2>&1; check "unknown target refused" "test \$? -eq 1"
"$LR" watch add --no-test --then "cancel me" -- file /nonexistent/c >/dev/null 2>&1; "$LR" watch rm w6 >/dev/null; check "watch rm cancels" "grep -q cancelled '$WD/w6.json'"
# the launchd tick has no TCC grant for a project under ~/Documents: the message must land in the session's own spool
"$LR" watch add --to 99999999 --no-test --no-notify --then "spooled: the project inbox was not writable" -- file "$FLAG" >/dev/null 2>&1   # the renamed+resumed PR E session
chmod 000 "$LOCAL/inbox"; "$LR" watch run --force >/dev/null 2>&1; chmod 755 "$LOCAL/inbox"
SPOOL=$(ls "$SESS/66666666/inbox/"*-msg-to-d66666666-from-watch.md 2>/dev/null | head -1)
check "unwritable project inbox -> message spooled in the session dir, watch marked fired, tick exit 0" "test -n \"\$SPOOL\" && grep -q 'spooled: the project inbox' \"\$SPOOL\" && grep -q '\"how\": \"session-inbox:' '$WD/w7.json' && grep -q '\"state\": \"fired\"' '$WD/w7.json'"
SSP="$(hook SessionStart "{$G9,\"hook_event_name\":\"SessionStart\",\"source\":\"resume\"}")"
check "the target's hooks read the session spool too and archive the message" "echo \"\$SSP\" | grep -q 'spooled: the project inbox' && ! ls '$SESS/66666666/inbox/'*-from-watch.md >/dev/null 2>&1 && ls '$SESS/66666666/inbox/.archive/' | grep -q -- '-from-watch.md'"
"$LR" watch add --no-test --then 'mine' -- file /nonexistent/m >/dev/null 2>&1
python3 - "$LOCAL/config.json" <<'PYX'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["inject_max_bytes"]=60000; json.dump(d,open(p,"w"))
PYX
DG="$("$LR" digest --source startup)"; check "digest lists pending watches for this session" "echo \"\$DG\" | grep -q 'WATCH 1 pending for this session'"
rm -f "$CLAUDE_CONFIG_DIR/sessions/$PEER.json" "$CLAUDE_CONFIG_DIR/sessions/999999.json" "$CLAUDE_CONFIG_DIR/sessions/$PEER2.json"

echo "== env exports are shell-quoted"
SP="$T/sp ace/proj"; mkdir -p "$SP"; ( cd "$SP" && "$LR" init >/dev/null ); SPR="$(cd "$SP" && pwd -P)"; export CLAUDE_ENV_FILE="$T/env-sp.sh"; : > "$CLAUDE_ENV_FILE"
printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$SID" "$SP" | "$LR" hook SessionStart >/dev/null
check "a path with a space survives the env file" "bash -c 'source \"$T/env-sp.sh\" && test \"\$LONGRUN_DIR\" = \"$SPR/.longrun\"' && ! bash -c 'source \"$T/env-sp.sh\"' 2>&1 | grep -q 'not a valid identifier'"
unset CLAUDE_ENV_FILE

echo "== inert outside a project"
cd "$T"; O="$(printf '{"session_id":"x","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$T" | "$LR" hook SessionStart)"; check "hook inert when no longrun project" "test -z \"\$O\""
"$LR" add --shared x 2>/dev/null; check "cli refuses without a project (exit 3)" "test $? -eq 3"
# The skill body interpolates `!`longrun where`` and `!`longrun digest``; Claude Code throws the whole prompt
# away when one of them exits non-zero, and the turn goes silent. They must say "not set up" and exit 0.
O="$("$LR" digest --source skill 2>&1)"; check "digest outside a project: exit 0, digest-shaped, names init/link/onboard" "test \$? -eq 0 && echo \"\$O\" | grep -q '^<longrun v.* project=none source=skill>' && echo \"\$O\" | grep -q '</longrun>' && echo \"\$O\" | grep -q 'longrun init --external' && echo \"\$O\" | grep -q 'longrun link'"
"$LR" where >/dev/null 2>&1; check "where outside a project still exits 1, so a script can branch on it" "test \$? -eq 1"
check "the skill body never lets those two fail the prompt" "grep -q '^!\`longrun where .*|| true\`' '$HERE/../skill/longrun/SKILL.md' && grep -q '^!\`longrun digest .*|| true\`' '$HERE/../skill/longrun/SKILL.md'"
echo "== config command"
cd "$HUB"
"$LR" config set notes_max_bytes 6000 >/dev/null; check "config set writes the project config.json" "grep -q '\"notes_max_bytes\": 6000' '$LOCAL/config.json'"
check "config shows the value with its source" "$LR config | grep -q 'notes_max_bytes *6000 *project'"
"$LR" config set wake_on_stuck false --global >/dev/null; check "config set --global writes the global file and coerces the bool" "grep -q '\"wake_on_stuck\": false' '$CLAUDE_CONFIG_DIR/longrun/config.json'"
"$LR" config set nope 1 2>/dev/null; check "unknown key refused (exit 2)" "test \$? -eq 2"
"$LR" config set nudge_tools abc 2>/dev/null; check "non-integer refused (exit 2)" "test \$? -eq 2"
"$LR" config unset notes_max_bytes >/dev/null; check "config unset removes the key" "! grep -q '\"notes_max_bytes\"' '$LOCAL/config.json'"
"$LR" config set note_max_chars 50 >/dev/null; "$LR" add --shared -t fact "this line is definitely longer than fifty characters, yes it is" 2>/dev/null; check "note_max_chars comes from the config (exit 2)" "test \$? -eq 2"; "$LR" config unset note_max_chars >/dev/null
"$LR" config set watch_ttl_days 2 --global >/dev/null; O="$("$LR" watch add --then "x" -- at "+3h" 2>&1)"; check "watch_ttl_days sets the default --for (under 3 days instead of 7)" "echo \"\$O\" | grep -q 'expires' && python3 -c \"import json,glob,time,sys; w=[json.load(open(f)) for f in glob.glob('$CLAUDE_CONFIG_DIR/longrun/watch/w*.json')]; w=[x for x in w if x.get('then')=='x']; sys.exit(0 if w and w[-1]['expires']-time.time() < 3*86400 else 1)\""
"$LR" config unset watch_ttl_days --global >/dev/null
"$LR" config set autocompact_window 300k --global >/dev/null; check "autocompact_window accepts 300k and stores tokens" "grep -q '\"autocompact_window\": 300000' '$CLAUDE_CONFIG_DIR/longrun/config.json'"
"$LR" config set autocompact_window abc --global 2>/dev/null; check "autocompact_window refuses junk (exit 2)" "test \$? -eq 2"
"$LR" config set pr_tool svn --global 2>/dev/null; check "pr_tool refuses unknown tools (exit 2)" "test \$? -eq 2"

echo "== onboarding and the PR tool"
O="$("$LR" onboard)"; check "onboard prints the brief with state and settings" "echo \"\$O\" | grep -q '^STATE' && echo \"\$O\" | grep -q 'autocompact_window *300k (global)' && echo \"\$O\" | grep -q 'timer: .*NOT installed'"
check "onboard reports the autocompact mismatch with Claude Code" "echo \"\$O\" | grep -q 'longrun expects 300k: ask the user to type ./autocompact 300k'"
D="$(cd "$WT" && "$LR" digest --source startup)"; check "digest suggests onboarding until it is done" "echo \"\$D\" | grep -q 'First time here: .longrun onboard'"
"$LR" onboard done >/dev/null; D="$(cd "$WT" && "$LR" digest --source startup)"; check "onboard done records the date and silences the hint" "grep -q onboarded_at '$CLAUDE_CONFIG_DIR/longrun/config.json' && ! echo \"\$D\" | grep -q 'First time here'"
GIT="$T/gitrepo"; mkdir -p "$GIT/.git"; ARC="$T/arcrepo/sub"; mkdir -p "$ARC" "$T/arcrepo/.arc"
( cd "$GIT" && "$LR" watch add --no-test --then "gh one" -- pr-merged 42 >/dev/null 2>&1 ); ( cd "$ARC" && "$LR" watch add --no-test --then "arc one" -- pr-status 77 discarded >/dev/null 2>&1 )
check "pr-merged registered in a git repo picks gh, in an Arcadia checkout picks arc, discarded == closed" "python3 -c \"import json,glob,sys; w={json.load(open(f))['then']: json.load(open(f)) for f in glob.glob('$CLAUDE_CONFIG_DIR/longrun/watch/w*.json')}; sys.exit(0 if w['gh one']['check']['tool']=='gh' and w['arc one']['check']['tool']=='arc' and w['arc one']['check']['desc']=='PR 77 status == closed' else 1)\""
"$LR" config set pr_tool arc --global >/dev/null; ( cd "$GIT" && "$LR" watch add --no-test --then "forced" -- pr-merged 43 >/dev/null 2>&1 ); check "pr_tool in the config overrides the folder" "python3 -c \"import json,glob,sys; w={json.load(open(f))['then']: json.load(open(f)) for f in glob.glob('$CLAUDE_CONFIG_DIR/longrun/watch/w*.json')}; sys.exit(0 if w['forced']['check']['tool']=='arc' else 1)\""
"$LR" config unset pr_tool --global >/dev/null

echo "== the platform layer: which timer, which dialog, which metadata directory"
PY_IMPORT="import importlib.util,sys; sp=importlib.util.spec_from_loader('lr',importlib.machinery.SourceFileLoader('lr','$LR')); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m)"
lrpy(){ python3 -c "import importlib.machinery,importlib.util; $PY_IMPORT
$1"; }
check "cron_spec turns seconds into a crontab schedule (and never goes below a minute)" \
  "test \"\$(lrpy 'print(m.cron_spec(300), m.cron_spec(30), m.cron_spec(7200), sep=\"|\")')\" = '*/5 * * * *|*/1 * * * *|0 */2 * * *'"
check "cron_strip removes our two lines and leaves the rest of the crontab alone" \
  "test \"\$(lrpy 'print(m.cron_strip(\"@reboot foo\\n\" + m.CRON_MARK + \"\\n*/5 * * * * old\\n0 3 * * * backup\"))')\" = \"['@reboot foo', '0 3 * * * backup']\""
check "the systemd units name the script, the interval and a log, and escape % for systemd" \
  "lrpy 'sv,tm=m.systemd_unit_texts(600); print(sv+tm)' | grep -q 'Type=oneshot' && lrpy 'sv,tm=m.systemd_unit_texts(600); print(sv+tm)' | grep -q 'OnUnitActiveSec=600' && lrpy 'sv,tm=m.systemd_unit_texts(600); print(sv+tm)' | grep -q 'WantedBy=timers.target' && ! lrpy 'sv,tm=m.systemd_unit_texts(600); print(sv+tm)' | grep -q '[^%]%[a-zA-Z]'"
check "watch_timer in the config pins the scheduler on any OS" \
  "$LR config set watch_timer cron --global >/dev/null && $LR watch status | grep -q 'cron job' && $LR config set watch_timer none --global >/dev/null && $LR watch status | grep -q 'no scheduler'"
LONGRUN_NO_TIMER= "$LR" watch install >/tmp/lr-ti 2>&1; check "watch install with watch_timer=none explains what to do instead (exit 1)" "test \$? -eq 1 && grep -q 'longrun watch run' /tmp/lr-ti"
"$LR" config set watch_timer sysvinit --global 2>/dev/null; check "watch_timer refuses an unknown scheduler (exit 2)" "test \$? -eq 2"
"$LR" config unset watch_timer --global >/dev/null
check "auto picks launchd on macOS and systemd or cron on Linux" \
  "case \"\$(lrpy 'print(m.timer_kind())')\" in launchd) test \"\$(uname)\" = Darwin ;; systemd|cron|none) test \"\$(uname)\" = Linux ;; *) false ;; esac"
check "the desktop metadata dir follows the OS (Library on macOS, XDG on Linux)" \
  "test \"\$(LONGRUN_DESKTOP_DIR= lrpy 'print(m.desktop_dir())')\" = \"\$(test \"\$(uname)\" = Darwin && echo \"\$HOME/Library/Application Support/Claude/claude-code-sessions\" || echo \"\$HOME/.config/Claude/claude-code-sessions\")\""
check "the dialog program is chosen by OS: osascript on macOS, zenity/kdialog on a Linux desktop, none headless" \
  "test \"\$(DISPLAY= WAYLAND_DISPLAY= lrpy 'print(m.dialog_tool() or \"-\")')\" = \"\$(test \"\$(uname)\" = Darwin && echo osascript || echo -)\""
check "a machine with no dialog says why (headless, or nothing installed)" \
  "DISPLAY= WAYLAND_DISPLAY= lrpy 'print(m.dialog_missing_reason())' | grep -qE 'osascript|DISPLAY|zenity'"
check "with no dialog program the ask fails with a reason instead of hanging" \
  "LONGRUN_NO_UI= lrpy 'm.dialog_tool=lambda: \"\"; d=m.dialog_show(\"q?\", [\"a\",\"b\"]); print(d[\"state\"], d[\"error\"])' | grep -q '^failed .'"

echo "== notifications (terminal-notifier over osascript: macOS files an osascript notification and draws nothing)"
HAVE(){ echo "m.shutil.which=lambda p, *a, **k: '/usr/bin/'+p if p in ($1) else None"; }
check "auto prefers terminal-notifier whenever it is installed" \
  "test \"\$(lrpy \"\$(HAVE \"'terminal-notifier','osascript','notify-send'\")
print(m.notifier_kind())\")\" = terminal-notifier"
check "without it auto falls back to the OS default: osascript on macOS, notify-send on a Linux desktop" \
  "test \"\$(DISPLAY=:0 lrpy \"\$(HAVE \"'osascript','notify-send'\")
print(m.notifier_kind())\")\" = \"\$(test \"\$(uname)\" = Darwin && echo osascript || echo notify-send)\""
check "a headless box with nothing installed resolves to none, not to a command that will fail" \
  "test \"\$(DISPLAY= WAYLAND_DISPLAY= lrpy \"\$(HAVE '')
print(m.notifier_kind())\")\" = none"
check "the notifier config key pins the program and refuses an unknown one (exit 2)" \
  "$LR config set notifier osascript --global >/dev/null && test \"\$(lrpy 'print(m.notifier_kind())')\" = osascript && $LR config set notifier growl --global 2>/dev/null; test \$? -eq 2"
"$LR" config set notifier none --global >/dev/null
LONGRUN_NO_UI= "$LR" notify --test >/tmp/lr-nt 2>&1; check "notify --test with notifier=none exits 1 and names the config key, not a missing binary" \
  "test \$? -eq 1 && grep -q 'set to none' /tmp/lr-nt"
"$LR" config unset notifier --global >/dev/null
check "each notifier gets its own argv, and only terminal-notifier is asked for a sound" \
  "lrpy 'print(m.notify_cmd(\"terminal-notifier\",\"T\",\"X\"))' | grep -q -- '-sound' && lrpy 'print(m.notify_cmd(\"osascript\",\"T\",\"X\"))' | grep -q 'display notification' && lrpy 'print(m.notify_cmd(\"notify-send\",\"T\",\"X\"))' | grep -q -- '-a.*longrun'"
"$LR" notify "must never reach a screen from a test" >/tmp/lr-nu 2>&1; check "LONGRUN_NO_UI sends nothing and says that is why (exit 1)" \
  "test \$? -eq 1 && grep -q 'LONGRUN_NO_UI' /tmp/lr-nu"
check "notify_user reports the program it used, so a caller can log how it notified" \
  "test \"\$(LONGRUN_NO_UI= lrpy \"\$(HAVE \"'terminal-notifier','true'\")
m.notify_cmd=lambda k,t,x,link='': ['true']
print(m.notify_user('T','X'))\")\" = terminal-notifier"
check "a click target is built only from a real app session id (local_<uuid>), never from a CLI id" \
  "lrpy 'print(m.session_deep_link(\"local_e5afcd96-5166-44c7-80ab-eddda0ea171b\"))' | grep -q '^claude://code/continue?session=local_e5afcd96-5166-44c7-80ab-eddda0ea171b&source=desktop_action\$' && test \"\$(lrpy 'print([m.session_deep_link(x) for x in (\"\", \"4b21e5e6-0f9b-4be9-a4ff-6f78f4261890\", \"local_a b\")])')\" = \"['', '', '']\""
check "a missing notifier is never an error: notify_user returns a string for every kind and raises nothing" \
  "test \"\$(LONGRUN_NO_UI= lrpy \"
m.shutil.which=lambda p, *a, **k: None
print([m.notify_user('T','X') for _ in range(1)] == [''], m.notifier_kind())\")\" = \"True none\""
check "notify_turn_end is off by default, and refuses anything but off/unfocused/always (exit 2)" \
  "test \"\$(lrpy 'print(m.DEFAULTS[\"notify_turn_end\"])')\" = off && $LR config set notify_turn_end sometimes --global 2>/dev/null; test \$? -eq 2"
check "unfocused notifies only while the Claude app is not the one in front" \
  "test \"\$(lrpy \"
m.frontmost_bundle=lambda: 'com.anthropic.claudefordesktop'
s=type('S',(),{'cfg':{'notify_turn_end':'unfocused'}})()
print(m.should_notify_turn_end(s))
m.frontmost_bundle=lambda: 'ru.yandex.desktop.yandex-browser'
print(m.should_notify_turn_end(s))\")\" = \"\$(printf 'False\\nTrue')\""
check "always ignores the front app, off never fires, and an unknown value is treated as off" \
  "test \"\$(lrpy \"
m.frontmost_bundle=lambda: 'com.anthropic.claudefordesktop'
print([m.should_notify_turn_end(type('S',(),{'cfg':{'notify_turn_end':v}})()) for v in ('always','off','','nonsense')])\")\" = '[True, False, False, False]'"
check "the front app is read without Automation permission (lsappinfo), and never crashes when it cannot be told" \
  "lrpy 'import inspect; print(inspect.getsource(m.frontmost_bundle))' | grep -q 'lsappinfo' && ! lrpy 'import inspect; print(inspect.getsource(m.frontmost_bundle))' | grep -q 'osascript' && lrpy 'm.IS_MAC=False; print(repr(m.frontmost_bundle()))' | grep -q \"^''\$\""
check "only terminal-notifier carries the click target; the other two drop it instead of failing" \
  "lrpy 'print(m.notify_cmd(\"terminal-notifier\",\"T\",\"X\",\"claude://x\"))' | grep -q -- \"-open', 'claude://x\" && ! lrpy 'print(m.notify_cmd(\"osascript\",\"T\",\"X\",\"claude://x\"))' | grep -q 'claude://x' && ! lrpy 'print(m.notify_cmd(\"notify-send\",\"T\",\"X\",\"claude://x\"))' | grep -q 'claude://x'"
echo "== important sessions (the turn end the user must not miss)"
IMP="$T/flagged"; mkdir -p "$IMP"; ( cd "$IMP" && "$LR" init >/dev/null )
IMPSID=aaaaaaaa-2222-4333-8444-555555555555
IMPJ="\"session_id\":\"$IMPSID\",\"transcript_path\":\"/x.jsonl\",\"cwd\":\"$IMP\""
IMPSTOP(){ hook Stop "{$IMPJ,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false,\"last_assistant_message\":\"ready for you\"}" >/dev/null; }
cd "$IMP"; export LONGRUN_SESSION=$IMPSID
hook SessionStart "{$IMPJ,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" >/dev/null
IMPD="$("$LR" where | sed -n 's/^sessions: //p')/aaaaaaaa"
check "a session is not important by default, and says which setting turn ends follow instead" \
  "$LR important | grep -q 'not important - turn ends follow notify_turn_end (off)'"
"$LR" important next >/dev/null; check "important next arms exactly one turn end" "grep -q '\"left\": 1' '$IMPD/meta.json' && $LR important | grep -q 'important (1 turn left)'"
check "the flag is in the digest head, so it survives a compaction" "$LR digest --source compact | head -1 | grep -q 'important (1 turn left): every turn end here raises'"
check "status carries it as a session flag" "$LR status --all | grep -q 'important (1 turn left)'"
IMPSTOP; check "one turn end spends the counter and clears the flag" "! grep -q '\"important\"' '$IMPD/meta.json' && $LR important | grep -q 'not important'"
check "the journal records that the turn end was notified (here: that this box has no notifier)" "tail -1 '$IMPD/journal.md' | grep -q 'turn-end notification.*important, the last one'"
"$LR" important 3 >/dev/null; IMPSTOP; check "important N counts down one turn end at a time" "$LR important | grep -q 'important (2 turns left)'"
"$LR" important on >/dev/null; IMPSTOP; IMPSTOP; check "important on outlives any number of turn ends" "$LR important | grep -q ': important - it raises'"
check "another session can be flagged by name, and is listed as important from anywhere in the project" \
  "$LR important next --to $IMPSID | grep -q 'important (1 turn left)'"
"$LR" important off >/dev/null; IMPSTOP; check "important off is the only thing that drops it" "$LR important | grep -q 'not important' && ! grep -q '\"important\"' '$IMPD/meta.json'"
"$LR" important sometimes >/dev/null 2>&1; check "an unknown argument is refused (exit 2), not silently taken as on" "test \$? -eq 2"
check "the flag beats both gates: notify_turn_end off and the Claude app in front" \
  "test \"\$(lrpy \"
m.frontmost_bundle=lambda: 'com.anthropic.claudefordesktop'
s=type('S',(),dict(cfg=dict(notify_turn_end='off')))()
print(m.should_notify_turn_end(s), m.consume_important(dict(important=dict(mode='always'))) != '')\")\" = 'False True'"
check "consume_important spends a counted flag and never goes below zero" \
  "test \"\$(lrpy \"
mm=dict(important=dict(mode='count', left=2))
print([bool(m.consume_important(mm)) for _ in range(3)], 'important' in mm)\")\" = '[True, True, False] False'"
cd "$HUB"; export LONGRUN_SESSION=$SID

echo; echo "PASS=$PASS FAIL=$FAIL  (tmp: $T)"; test $FAIL -eq 0
