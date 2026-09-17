#!/bin/bash
# Goal-level scenarios: one per thing longrun exists for. Synthetic, no API calls, nothing outside a temp dir.
#   S1 a new session orients itself in the project      S5 a resume in the desktop app keeps the session's own state
#   S2 own notes survive compaction and stay own          S6 /clear continues the same session
#   S3 shared changes reach running sessions on their turn S7 a fork inherits the parent's own notes
#   S4 two sessions in one directory stay apart           S8 work is handed to the session that has the context
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LR="$HERE/../skill/longrun/scripts/longrun"
T="$(mktemp -d /tmp/longrun-scen.XXXXXX)"
export CLAUDE_CONFIG_DIR="$T/claude" HOME="$T/home" LONGRUN_NO_TIMER=1
export LONGRUN_DESKTOP_DIR="$T/home/desktop-sessions"
export LONGRUN_NO_UI=1                     # never a real dialog or notification from a test
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/projects/-proj" "$CLAUDE_CONFIG_DIR/sessions"
unset LONGRUN_DIR LONGRUN_SESSION LONGRUN_SCOPE LONGRUN_TRANSCRIPT CLAUDE_ENV_FILE
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
A=aaaaaaaa-0000-4000-8000-000000000001; B=bbbbbbbb-0000-4000-8000-000000000002; C=cccccccc-0000-4000-8000-000000000003
start(){ # start SID CWD SOURCE -> digest
  printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$2" "$3" | "$LR" hook SessionStart
}
turn(){ # turn SID CWD -> what the hook injects before the model sees the prompt
  printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"go"}' "$1" "$2" | "$LR" hook UserPromptSubmit
}
stop(){ printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s"}' "$1" "$2" "$3" | "$LR" hook Stop; }
end(){ printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionEnd","reason":"%s"}' "$1" "$2" "$3" | "$LR" hook SessionEnd; }
as(){ LONGRUN_SESSION="$1" "$LR" "${@:2}"; }   # a CLI call made from inside session $1's Bash

HQ="$T/lottery-dev"; WT_E="$T/arcadia-wt/EDAINAPP-1375-screen"; WT_C="$T/arcadia-wt/EDAINAPP-1376-payment-cycle"
mkdir -p "$HQ" "$WT_E" "$WT_C"
( cd "$HQ" && "$LR" init >/dev/null ); ( cd "$WT_E" && "$LR" link "$HQ" >/dev/null ); ( cd "$WT_C" && "$LR" link "$HQ" >/dev/null )
SESS="$(cd "$HQ" && "$LR" where | sed -n 's/^sessions: //p')"

echo "== S1: a new session orients itself in the project (shared picture + who is doing what)"
cd "$WT_E"; start $A "$WT_E" startup >/dev/null
as $A add --shared -t pin "PR E = 15526210, branch EDAINAPP-1375-screen, opened 2026-09-04" >/dev/null
as $A add --shared -t decision "STQ v2 over v1 for payment callbacks: v1 needs a TPS ticket per env" >/dev/null
as $A add --own -t dead "own: LC client path gives 400 whatever the body; bdui-catalog testing lacks the screen" >/dev/null
as $A stale n1 "PR E is merged, the branch is gone" >/dev/null   # any write the session journals
stop $A "$WT_E" "PR E opened, waiting for reviewers"
D="$(cd "$WT_C" && start $B "$WT_C" startup)"
check "S1.1 the new session in another worktree sees the project's shared notes (PR map, decisions)" "echo \"\$D\" | grep -q 'PR E = 15526210' && echo \"\$D\" | grep -q 'STQ v2 over v1'"
check "S1.2 shared entries name their author session" "echo \"\$D\" | grep -q 'pin (EDAINAPP-1375-screen): PR E'"
check "S1.3 it sees which other sessions exist and what each did last" "echo \"\$D\" | grep -q 'SESSIONS of project lottery-dev' && echo \"\$D\" | grep -q 'PR E opened, waiting for reviewers' && echo \"\$D\" | grep -q '1 own notes'"
check "S1.4 it does NOT get the other session's own notes pushed into its context" "! echo \"\$D\" | grep -q 'LC client path'"
check "S1.5 its own notes start empty" "echo \"\$D\" | grep -q 'OWN notes (this session) 0 entries'"
check "S1.6 but it can pull a detail from another session's own notes on demand" "(cd '$WT_C' && as $B recall 'LC client path' --no-transcript) | grep -q 'sessions/aaaaaaaa/notes.md'"

echo "== S2: own notes survive compaction and stay own"
cd "$WT_E"
printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"PreCompact","trigger":"auto"}' $A "$WT_E" | "$LR" hook PreCompact
printf '{"session_id":"%s","transcript_path":"/x.jsonl","cwd":"%s","hook_event_name":"PostCompact","trigger":"auto","compact_summary":"summary text"}' $A "$WT_E" | "$LR" hook PostCompact
DA="$(start $A "$WT_E" compact)"
check "S2.1 after compaction the session gets its own notes and its journal back" "echo \"\$DA\" | grep -q 's1\] .* dead: own: LC client path' && echo \"\$DA\" | grep -q 'SESSION journal tail' && echo \"\$DA\" | grep -q 'stale n1'"
check "S2.2 and the shared picture" "echo \"\$DA\" | grep -q 'PR E = 15526210'"
check "S2.3 the compaction summary is archived under the project, named by the session" "ls '$HQ/.longrun/archive/compact/' | grep -q '^aaaaaaaa-'"
DB="$(cd "$WT_C" && start $B "$WT_C" compact)"
check "S2.4 another session's compaction digest still excludes A's own notes" "! echo \"\$DB\" | grep -q 'LC client path' && echo \"\$DB\" | grep -q 'OWN notes (this session) 0 entries'"

echo "== S3: shared changes reach running sessions on their next turn; own writes are not echoed back"
cd "$WT_C"; turn $B "$WT_C" >/dev/null   # B's baseline turn
( cd "$WT_E" && as $A add --shared -t fact "arc trunk lags Arcanum merges: wait for the commit, not the PR status" >/dev/null )
TB="$(turn $B "$WT_C")"
check "S3.1 B's next turn shows the entry A just added, as a delta, not the whole file" "echo \"\$TB\" | grep -q 'SHARED notes of project lottery-dev changed' && echo \"\$TB\" | grep -q '+ - \[n3\] .*arc trunk lags' && ! echo \"\$TB\" | grep -q 'PR E = 15526210'"
TB2="$(turn $B "$WT_C")"; check "S3.2 nothing changed -> nothing injected" "test -z \"\$TB2\""
as $B add --shared -t pin "PR C = 15473925, branch EDAINAPP-1376-payment-cycle" >/dev/null
TB3="$(turn $B "$WT_C")"; check "S3.3 B's own shared write is not reported back to B" "test -z \"\$TB3\""
TA="$(cd "$WT_E" && turn $A "$WT_E")"; check "S3.4 ...but A hears about it on A's next turn" "echo \"\$TA\" | grep -q '+ - \[n4\] .*PR C = 15473925'"
( cd "$WT_E" && as $A replace n1 "PR E = 15526210, branch EDAINAPP-1375-screen, merged r21056999 2026-09-08" >/dev/null && as $A rm n2 >/dev/null )
TB4="$(turn $B "$WT_C")"; check "S3.5 a rewrite shows as ~ and a removal as removed" "echo \"\$TB4\" | grep -q '~ - \[n1\] .*merged r21056999' && echo \"\$TB4\" | grep -q 'removed: n2'"
# More changed at once than one turn's slice can carry: the rest must come on the following turns.
# Clipping the text and marking everything seen - what this used to do - hid them from B for good.
python3 - "$HQ/.longrun/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["shared_delta_max_bytes"]=260; json.dump(d,open(p,"w"))
PY
for i in 1 2 3; do ( cd "$WT_E" && as $A add --shared -t fact "burst entry $i: a line long enough that three of them do not fit one turn's delta slice" >/dev/null ); done
TB5="$(turn $B "$WT_C")"; TB6="$(turn $B "$WT_C")"; TB7="$(turn $B "$WT_C")"; TB8="$(turn $B "$WT_C")"
check "S3.6 a delta over its slice shows the oldest first and says how many are still coming" "echo \"\$TB5\" | grep -q 'burst entry 1' && ! echo \"\$TB5\" | grep -q 'burst entry 2' && echo \"\$TB5\" | grep -q 'more on your next turn'"
check "S3.7 the rest arrive on the next turns instead of being lost" "echo \"\$TB6\" | grep -q 'burst entry 2' && echo \"\$TB7\" | grep -q 'burst entry 3' && test -z \"\$TB8\""
python3 - "$HQ/.longrun/config.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("shared_delta_max_bytes",None); json.dump(d,open(p,"w"))
PY

echo "== S4: two sessions started in the same directory keep separate own notes"
cd "$HQ"; start $C "$HQ" startup >/dev/null
CC=dddddddd-0000-4000-8000-000000000004; start $CC "$HQ" startup >/dev/null
as $C add --own -t ctx "C's framing: only the testing checklist" >/dev/null; as $CC add --own -t ctx "CC's framing: the RFC for billing" >/dev/null
check "S4.1 each has its own notes file" "grep -q \"C's framing\" '$SESS/cccccccc/notes.md' && grep -q \"CC's framing\" '$SESS/dddddddd/notes.md' && ! grep -q \"CC's\" '$SESS/cccccccc/notes.md'"
check "S4.2 and the shared file is one" "as $C notes --shared | grep -q 'PR C = 15473925' && as $CC notes --shared | grep -q 'PR C = 15473925'"
S4="$(as $C status)"; check "S4.3 status lists both by key with their own-note counts" "echo \"\$S4\" | grep 'cccccccc' | grep -q 'notes=1' && echo \"\$S4\" | grep 'dddddddd' | grep -q 'notes=1'"

echo "== S5: the desktop app resumes a session under a NEW CLI id: notes and journal continue"
DSK="$LONGRUN_DESKTOP_DIR/x/y"; mkdir -p "$DSK"
A2=aaaa000a-0000-4000-8000-00000000000a
printf '{"sessionId":"local_desk-A","cliSessionId":"%s","priorCliSessionIds":["%s"],"cwd":"%s","title":"PR E: Шторка лотереи","isArchived":false,"lastActivityAt":1788779365881}' $A2 $A "$WT_E" > "$DSK/local_desk-A.json"
cd "$WT_E"; D5="$(start $A2 "$WT_E" startup)"
check "S5.1 the new CLI id continues the old session dir (priorCliSessionIds)" "grep -q '\"skey\": \"aaaaaaaa\"' '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/$A2.json' && ! test -d '$SESS/aaaa000a'"
check "S5.2 its digest carries the old own notes and journal, labelled as continued" "echo \"\$D5\" | grep -q 'continued from an earlier CLI id' && echo \"\$D5\" | grep -q 'LC client path' && echo \"\$D5\" | grep -q 'stale n1'"
check "S5.3 the digest head names the session as the sidebar does" "echo \"\$D5\" | grep -q 'session=PR E: Шторка лотереи \[aaaaaaaa\]'"
# the app may write its metadata only after SessionStart: then the chain is picked up on the first turn
A3=aaaa000b-0000-4000-8000-00000000000b
D5b="$(start $A3 "$WT_E" startup)"; check "S5.4 before the app wrote its metadata the new id looks fresh" "echo \"\$D5b\" | grep -q 'OWN notes (this session) 0 entries' && test -d '$SESS/aaaa000b'"
printf '{"sessionId":"local_desk-A","cliSessionId":"%s","priorCliSessionIds":["%s","%s"],"cwd":"%s","title":"PR E: Шторка лотереи","isArchived":false,"lastActivityAt":1788779365881}' $A3 $A $A2 "$WT_E" > "$DSK/local_desk-A.json"
T5="$(turn $A3 "$WT_E")"
check "S5.5 the first turn after the app caught up rebinds and shows the own notes once" "echo \"\$T5\" | grep -q 'continued from CLI id' && echo \"\$T5\" | grep -q 'LC client path' && grep -q '\"skey\": \"aaaaaaaa\"' '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/$A3.json' && ! test -d '$SESS/aaaa000b'"
T5b="$(turn $A3 "$WT_E")"; check "S5.6 ...and only once" "! echo \"\$T5b\" | grep -q 'LC client path'"

echo "== S6: /clear ends one CLI id and starts another in the same process: the session continues"
end $C "$HQ" clear
C2=cccccccc-0000-4000-8000-00000000000c
D6="$(cd "$HQ" && start $C2 "$HQ" clear)"
check "S6.1 SessionStart(clear) right after SessionEnd(clear) in the same cwd continues that session" "grep -q '\"skey\": \"cccccccc\"' '$CLAUDE_CONFIG_DIR/longrun/sessions/_index/$C2.json' && echo \"\$D6\" | grep -q \"C's framing\""

echo "== S7: a fork inherits the parent's own notes"
F=ffffffff-0000-4000-8000-00000000000f
printf '{"sessionId":"local_desk-F","cliSessionId":"%s","forkedFromSessionId":"local_desk-A","cwd":"%s","title":"PR E: Шторка (fork)","isArchived":false,"lastActivityAt":1788779365999}' $F "$WT_E" > "$DSK/local_desk-F.json"
D7="$(cd "$WT_E" && start $F "$WT_E" fork)"
check "S7.1 the fork starts with a copy of the parent's own notes, in its own dir" "echo \"\$D7\" | grep -q 'LC client path' && test -f '$SESS/ffffffff/notes.md' && grep -q 'LC client path' '$SESS/ffffffff/notes.md'"
as $F add --own -t fact "fork-only fact" >/dev/null
check "S7.2 from then on the two diverge" "! grep -q 'fork-only' '$SESS/aaaaaaaa/notes.md'"

echo "== S8: work is handed to the session that has the context for it"
( cd "$WT_E" && as $A3 send "PR C" "B merged: rebase C onto trunk, drop the F cherry-picks" >/dev/null 2>&1 ) || ( cd "$WT_E" && as $A3 send bbbbbbbb "B merged: rebase C onto trunk, drop the F cherry-picks" >/dev/null 2>&1 )
T8="$(cd "$WT_C" && turn $B "$WT_C")"
check "S8.1 a message to a stopped session arrives as its next turn, with the sender named" "echo \"\$T8\" | grep -q 'rebase C onto trunk' && echo \"\$T8\" | grep -q 'MESSAGE to bbbbbbbb from .*\[aaaa000b\]'"
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
printf '{"pid":%d,"sessionId":"%s","cwd":"%s","name":"lottery-dev-c","messagingSocketPath":"%s","kind":"interactive"}\n' $PEER $C2 "$HQ" "$T/peer.sock" > "$CLAUDE_CONFIG_DIR/sessions/$PEER.json"
( cd "$WT_E" && as $A3 send lottery-dev-c "please run the L0 checklist, you have the testing context" >/dev/null 2>&1 ); wait $PEER
check "S8.2 a running session gets it on its socket right away, as a user turn" "python3 -c \"import json;d=json.loads(open('$T/peer.out').read().splitlines()[0]);assert d['type']=='user' and 'L0 checklist' in d['message']['content']\""
rm -f "$CLAUDE_CONFIG_DIR/sessions/$PEER.json"
( cd "$WT_E" && as $A3 watch add --to "PR E: Шторка лотереи" --no-test --then "flag is up: run the tests" -- file "$T/flag" >/dev/null 2>&1 )
touch "$T/flag"; "$LR" watch run --force >/dev/null
T8b="$(cd "$WT_E" && turn $A3 "$WT_E")"
check "S8.3 a watch registered by name fires into that session with the --then text" "echo \"\$T8b\" | grep -q 'CONDITION MET' && echo \"\$T8b\" | grep -q 'flag is up: run the tests'"

echo "== S9: the picture of the other sessions stays live, and windows the user closed in the app go away"
cd "$HQ"
N=99999999-0000-4000-8000-00000000000e
turn $C "$HQ" >/dev/null   # C's baseline: it has just been told who exists
start $N "$HQ" startup >/dev/null
stop $N "$HQ" "picked up the payments retry, reading the STQ config"
T9="$(turn $C "$HQ")"
check "S9.1 a session opened after C started shows up on C's next turn, with what it is doing" "echo \"\$T9\" | grep -q 'SESSIONS of project lottery-dev changed' && echo \"\$T9\" | grep -q '+ .*99999999' && echo \"\$T9\" | grep -q 'payments retry'"
T9b="$(turn $C "$HQ")"; check "S9.2 nothing changed -> nothing injected" "! echo \"\$T9b\" | grep -q 'SESSIONS of project lottery-dev changed'"
stop $N "$HQ" "STQ v2 queue created, PR opened"
end $N "$HQ" other
T9c="$(turn $C "$HQ")"
check "S9.3 a new last reply and the session ending both reach C" "echo \"\$T9c\" | grep -q '~ .*99999999' && echo \"\$T9c\" | grep -q 'STQ v2 queue created'"
# the user archives that window in the app: gc only reaps a directory after a week, but the row must go now
printf '{"sessionId":"local_desk-N","cliSessionId":"%s","cwd":"%s","title":"payments retry","isArchived":false,"lastActivityAt":1788779365999}' $N "$HQ" > "$DSK/local_desk-N.json"
turn $N "$HQ" >/dev/null   # the hook learns the app id for this session
turn $C "$HQ" >/dev/null   # and C takes the current picture as its baseline
python3 - "$DSK/local_desk-N.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["isArchived"]=True; json.dump(d,open(p,"w"))
PY
T9d="$(turn $C "$HQ")"
check "S9.4 a window archived in the app disappears from the delta and from the block" "echo \"\$T9d\" | grep -q -- '- gone: 99999999' && ! (cd '$HQ' && as $C digest | grep -q '99999999')"
check "S9.5 ...but longrun status --all still shows it, and says why it was hidden" "(cd '$HQ' && as $C status | grep -qv '99999999') && (cd '$HQ' && as $C status --all | grep '99999999' | grep -q 'archived in the app')"

echo; echo "PASS=$PASS FAIL=$FAIL  (tmp: $T)"; test $FAIL -eq 0
