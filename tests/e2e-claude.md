# Live end-to-end check (costs money: ~0.2$ on haiku)

Run from a scratch directory after `./install.sh` (or point `--settings` at a file with the longrun hooks):

```bash
E=/tmp/longrun-e2e; mkdir -p $E/proj && cd $E/proj && git init -q . && longrun init
longrun add --shared -t dead "go test ./... with -race hangs on this box: the pgx pool test deadlocks; run without -race"
longrun add --shared -t decision "Use /v4/retrieve for personal: v3 returns 403 V3 API is forbidden"
SID=$(uuidgen | tr A-Z a-z)
claude -p "Which test approach is a dead end and why? Then record with Bash: longrun add -t fact \"make lint must run before commits\"" \
  --session-id $SID --model haiku --max-turns 4 --permission-mode dontAsk --allowedTools "Bash(longrun:*)" < /dev/null
claude -p "/compact keep the test-running decision" --resume $SID --model haiku < /dev/null
ls .longrun/archive/compact/          # the summary, verbatim
claude -p "From context only: which personal API version was decided and why? Then run: longrun recall forbidden" \
  --resume $SID --model haiku --max-turns 3 --permission-mode dontAsk --allowedTools "Bash(longrun:*)" < /dev/null
grep -o '"hookName":"SessionStart:compact"' ~/.claude/projects/*/$SID.jsonl | head -1   # digest re-injected after compaction
```

Notes written from the shell before the session exists must be `--shared` (own notes need a session). Observed on 2026-09-04 (Claude Code 2.1.238, haiku): the first answer came from the injected notes, `n3` was written by the model, the compaction summary (2882 chars) landed in `archive/compact/`, the post-compaction answer was correct and `recall` printed the note plus transcript hits.
