#!/bin/bash
# longrun installer: idempotent, backs up settings, never touches other hooks. `install.sh --uninstall` reverses it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
DEST="$SKILLS_DIR/longrun"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUPS="$CLAUDE_DIR/backups"
BIN_DIR="${LONGRUN_BIN_DIR:-$HOME/.local/bin}"
MODE="install"
for a in "$@"; do
  case "$a" in
    --uninstall) MODE="uninstall" ;;
    --purge) MODE="purge" ;;
    -h|--help) echo "usage: install.sh [--uninstall | --purge]   (purge also removes ~/.claude/longrun data and the skill dir)"; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
mkdir -p "$BACKUPS" "$SKILLS_DIR" "$BIN_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUPS/settings.json.$STAMP.longrun.bak"
  echo "backup: $BACKUPS/settings.json.$STAMP.longrun.bak"
fi

if [ "$MODE" = "install" ]; then
  # 1. skill files (copy, not symlink: the skill must keep working if this checkout moves)
  mkdir -p "$DEST/scripts"
  cp "$HERE/skill/longrun/SKILL.md" "$DEST/SKILL.md"
  cp "$HERE/skill/longrun/hooks.json" "$DEST/hooks.json"
  cp "$HERE/skill/longrun/scripts/longrun" "$DEST/scripts/longrun"
  chmod +x "$DEST/scripts/longrun"
  ln -sfn "$DEST/scripts/longrun" "$BIN_DIR/longrun"
  echo "skill:  $DEST"
  echo "cli:    $BIN_DIR/longrun -> $DEST/scripts/longrun"
  # 1a. the MCP server behind the `ask` / `notify` tools, user scope: every session of every project gets it.
  # Re-added on every install so the command follows BIN_DIR; only new sessions see a (re)registered server.
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove --scope user longrun >/dev/null 2>&1 || true
    if claude mcp add --scope user longrun -- "$BIN_DIR/longrun" mcp >/dev/null 2>&1; then
      echo "mcp:    server 'longrun' (tools ask, notify) registered in user scope; sessions started from now on get it"
    else
      echo "mcp:    registration failed; run by hand: claude mcp add --scope user longrun -- $BIN_DIR/longrun mcp"
    fi
  else
    echo "mcp:    'claude' is not on PATH; register the server by hand: claude mcp add --scope user longrun -- $BIN_DIR/longrun mcp"
  fi
fi

# 2. merge/remove hook entries in settings.json (identified by the script path)
python3 - "$SETTINGS" "$DEST/scripts/longrun" "$HERE/skill/longrun/hooks.json" "$MODE" <<'PY'
import json, os, sys
settings_path, bin_path, hooks_path, mode = sys.argv[1:5]
try:
    settings = json.load(open(settings_path))
except FileNotFoundError:
    settings = {}
except ValueError as e:
    sys.exit("settings.json is not valid JSON (%s); fix it first, nothing was changed" % e)
hooks = settings.setdefault("hooks", {})
def is_ours(entry):
    return any("/skills/longrun/scripts/longrun" in (h.get("command") or "") for h in entry.get("hooks", []))
removed = 0
for ev in list(hooks):
    before = len(hooks[ev])
    hooks[ev] = [e for e in hooks[ev] if not is_ours(e)]
    removed += before - len(hooks[ev])
    if not hooks[ev]:
        del hooks[ev]
added = 0
if mode == "install":
    spec = json.load(open(hooks_path))["hooks"]
    for ev, entries in spec.items():
        for e in entries:
            e = json.loads(json.dumps(e).replace("LONGRUN_BIN", bin_path))
            hooks.setdefault(ev, []).append(e)
            added += 1
    perms = settings.setdefault("permissions", {}).setdefault("allow", [])
    for rule in ("Bash(longrun:*)", "Bash(%s:*)" % bin_path):
        if rule not in perms:
            perms.append(rule)
else:
    perms = settings.get("permissions", {}).get("allow", [])
    ours = lambda p: p == "Bash(longrun:*)" or "/skills/longrun/scripts/longrun" in p  # only the two rules we add
    settings.setdefault("permissions", {})["allow"] = [p for p in perms if not ours(p)]
if not settings.get("hooks"):
    settings.pop("hooks", None)
tmp = settings_path + ".tmp"
json.dump(settings, open(tmp, "w"), indent=2, ensure_ascii=False)
os.replace(tmp, settings_path)
print("hooks:  removed %d old longrun entries, added %d" % (removed, added))
PY

if [ "$MODE" != "install" ]; then
  command -v claude >/dev/null 2>&1 && claude mcp remove --scope user longrun >/dev/null 2>&1 && echo "mcp:    server 'longrun' unregistered"
  rm -f "$BIN_DIR/longrun"
  rm -rf "$DEST"
  echo "removed $DEST and $BIN_DIR/longrun"
  if [ "$MODE" = "purge" ]; then
    rm -rf "$CLAUDE_DIR/longrun"
    echo "removed $CLAUDE_DIR/longrun (registry, external project dirs). Project-local .longrun/ dirs are left alone."
  else
    echo "data kept: $CLAUDE_DIR/longrun and any project .longrun/ dirs (use --purge to delete the global part)"
  fi
fi
echo "done. Already-running sessions pick the hooks up without a restart (verified on 2.1.260), but their"
echo "SessionStart digest only appears at the next SessionStart: after a compaction, /clear, resume, or in a new session."
echo "To see it right away in a running session, type /longrun."
