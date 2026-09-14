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
NOTIFY="ask"
TIMER=1
for a in "$@"; do
  case "$a" in
    --uninstall) MODE="uninstall" ;;
    --purge) MODE="purge" ;;
    --notify) NOTIFY=1 ;;
    --no-notify) NOTIFY=0 ;;
    --no-timer) TIMER=0 ;;
    -h|--help) echo "usage: install.sh [--uninstall | --purge] [--notify | --no-notify] [--no-timer]
  --notify     set up desktop notifications without asking
  --no-notify  do not set them up (on macOS that skips installing terminal-notifier)
  --no-timer   do not install the 5-minute timer (watches then wait until 'longrun watch install')
  --purge      also removes ~/.claude/longrun data and the skill dir

Without either notify flag the installer asks, and skips the step when nothing can answer.

Run it from a checkout, or without one:
  curl -fsSL https://raw.githubusercontent.com/krllx/longrun/main/install.sh | bash
The sources then come from the same repository as a tarball (LONGRUN_REPO, LONGRUN_REF override it)."; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

# 0. sources. Piped through a shell there is no checkout around us, so fetch one; uninstalling needs no sources.
if [ "$MODE" = "install" ] && [ ! -f "$HERE/skill/longrun/SKILL.md" ]; then
  REPO="${LONGRUN_REPO:-krllx/longrun}"
  REF="${LONGRUN_REF:-main}"
  command -v curl >/dev/null || { echo "curl is required to fetch the sources (or clone the repo and run ./install.sh)" >&2; exit 1; }
  command -v tar >/dev/null || { echo "tar is required to fetch the sources (or clone the repo and run ./install.sh)" >&2; exit 1; }
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "source: $REPO@$REF (no checkout here, fetching the tarball)"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xzf - -C "$TMP" \
    || { echo "download failed: https://codeload.github.com/$REPO/tar.gz/$REF" >&2; exit 1; }
  HERE="$(echo "$TMP"/*)"
  [ -f "$HERE/skill/longrun/SKILL.md" ] || { echo "the tarball has no skill/longrun/SKILL.md" >&2; exit 1; }
fi
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
  # 1b. desktop notifications. Asked for, not assumed: they install software on macOS and ask the system for
  # a permission, and longrun never depends on them - a halt, a budget stop and a fired watch reach the
  # session through its socket or inbox either way. Neither OS can draw one unaided: macOS has no working
  # built-in route at all (an osascript notification is posted on behalf of Script Editor, which holds no
  # permission, so it is filed and never drawn, silently), and Linux needs libnotify.
  if [ "$NOTIFY" = "ask" ]; then
    echo ""
    echo "Desktop notifications. A halt, a session that finished its turn and a watch that came true reach"
    echo "the session either way; a notification is how you see one while looking at another window."
    if [ "$(uname)" = "Darwin" ]; then
      echo "On macOS this installs terminal-notifier through Homebrew and asks the system once for permission."
    else
      echo "On Linux this only uses notify-send (libnotify), which most desktops already have."
    fi
    # the script itself may be arriving on stdin (curl | bash), so the answer is read from the terminal;
    # opening it is the test - /dev/tty exists and looks readable even where there is no controlling one
    if { exec 3</dev/tty; } 2>/dev/null; then
      printf "Set them up now? [Y/n] "
      ANS=""
      if read -r ANS <&3; then         # Enter means yes; end of input is not an answer, so it means no
        case "$ANS" in [Nn]*) NOTIFY=0 ;; *) NOTIFY=1 ;; esac
      else
        NOTIFY=0
        printf "\n(no answer read from the terminal)"
      fi
      exec 3<&-
      echo ""
    else
      NOTIFY=0
      echo "Nothing here can answer (no terminal), so: skipped. 'longrun notify setup' turns them on later."
      echo ""
    fi
  fi
  if [ "$NOTIFY" = "0" ]; then
    echo "notify: skipped - 'longrun notify setup' (macOS) or a libnotify package (Linux) turns them on later"
  elif [ "$(uname)" = "Darwin" ]; then
    if ! command -v terminal-notifier >/dev/null 2>&1; then
      if command -v brew >/dev/null 2>&1; then
        echo "notify: installing terminal-notifier (Homebrew) - macOS cannot draw a notification without it"
        brew install terminal-notifier >/dev/null 2>&1 || echo "notify: brew install failed; run it by hand, then re-run this installer"
      else
        echo "notify: skipped - Homebrew is what installs terminal-notifier, and macOS draws no notification"
        echo "        without it. Install Homebrew from https://brew.sh, then run this installer again (or"
        echo "        just 'longrun notify setup'). Everything else works as it is."
      fi
    fi
    if command -v terminal-notifier >/dev/null 2>&1; then
      # the icon and the sender name of a macOS banner come only from the bundle that posted it, so we post
      # from our own copy; building it ends with a test notification, which is also what grants the permission
      echo "notify: setting up the sender bundle. macOS may ask once whether to allow notifications from"
      echo "        \"longrun\" - allow it, and a test notification appears when it works."
      "$BIN_DIR/longrun" notify setup 2>&1 | sed "s/^/        /"
    fi
  elif command -v notify-send >/dev/null 2>&1; then
    echo "notify: notify-send found; check it with 'longrun notify --test'"
  else
    echo "notify: no notify-send (libnotify) - halts, budget stops and fired watches still reach the sessions"
    echo "        themselves; 'apt install libnotify-bin' (or 'dnf install libnotify') to also see them on screen."
  fi
  # 1c. the timer that runs the tick every 5 minutes: the watches this machine is waiting on, and the watcher
  # that looks at the other sessions. Installed here so nothing has to be remembered; `--no-timer` skips it,
  # and the first `longrun watch add` installs it anyway.
  if [ "$TIMER" = "0" ]; then
    echo "timer:  skipped (--no-timer); 'longrun watch install' whenever you want it"
  elif TIMER_OUT="$("$BIN_DIR/longrun" watch install 2>&1)"; then
    echo "timer:  $(printf '%s' "$TIMER_OUT" | head -n1)"
  else
    printf '%s\n' "$TIMER_OUT" | sed 's/^/timer:  /'
    echo "timer:  not installed - everything else works; watches will not be checked until it is"
  fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "PATH:   $BIN_DIR is not on your PATH - add it (e.g. 'export PATH=\"\$HOME/.local/bin:\$PATH\"' in"
       echo "        ~/.zshrc or ~/.bashrc), otherwise the 'longrun' command below is not found. The hooks are"
       echo "        unaffected: they call the script by its absolute path." ;;
  esac
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
  # the timer goes first: it runs the script we are about to delete
  if [ -x "$BIN_DIR/longrun" ]; then
    "$BIN_DIR/longrun" watch uninstall >/dev/null 2>&1 && echo "timer:  removed" || true
  fi
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
if [ "$MODE" = "install" ]; then
  echo "next:   cd <the folder you open in Claude Code> && longrun init   (then say \"set up longrun\" in a session)"
fi
echo "done. Already-running sessions pick the hooks up without a restart (verified on 2.1.260), but their"
echo "SessionStart digest only appears at the next SessionStart: after a compaction, /clear, resume, or in a new session."
echo "To see it right away in a running session, type /longrun."
