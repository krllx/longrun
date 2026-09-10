#!/bin/bash
# dumps hook stdin + env to a file named by event
ev="$1"; f="/tmp/longrun-hooktest/out2/${ev}.$(date +%s%N).json"
{ echo "{\"_env\":{\"CLAUDE_PROJECT_DIR\":\"$CLAUDE_PROJECT_DIR\",\"CLAUDE_SESSION_ID\":\"$CLAUDE_SESSION_ID\",\"CLAUDE_ENV_FILE\":\"$CLAUDE_ENV_FILE\",\"CLAUDE_CODE_REMOTE\":\"$CLAUDE_CODE_REMOTE\",\"CLAUDE_PLUGIN_ROOT\":\"$CLAUDE_PLUGIN_ROOT\",\"CLAUDE_CODE_ENTRYPOINT\":\"$CLAUDE_CODE_ENTRYPOINT\",\"PWD\":\"$PWD\"},\"_stdin\":"; cat; echo "}"; } > "$f"
if [ "$ev" = "SessionStart" ]; then echo "LONGRUN-SESSIONSTART-MARKER-42"; fi
if [ "$ev" = "UserPromptSubmit" ]; then echo "LONGRUN-UPS-MARKER-43"; fi
exit 0
