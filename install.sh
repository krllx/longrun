#!/bin/bash
# Idempotent install for the selected clients. The no-flag Claude Code interface stays compatible.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
ZCODE_DIR="${LONGRUN_ZCODE_DIR:-$HOME/.zcode}"
CODEX_SKILLS="${LONGRUN_CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
BIN_DIR="${LONGRUN_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${LONGRUN_HOME:-$CLAUDE_DIR/longrun}"
MODE=install
CLIENTS=claude
NOTIFY=ask
TIMER=1
for a in "$@"; do
  case "$a" in
    --claude) CLIENTS=claude ;;
    --codex) CLIENTS=codex ;;
    --zcode) CLIENTS=zcode ;;
    --both) CLIENTS="claude codex" ;;
    --all) CLIENTS="claude codex zcode" ;;
    --uninstall) MODE=uninstall ;;
    --purge) MODE=purge ;;
    --notify) NOTIFY=1 ;;
    --no-notify) NOTIFY=0 ;;
    --no-timer) TIMER=0 ;;
    -h|--help) cat <<'HELP'
usage: install.sh [--claude | --codex | --zcode | --both | --all] [--uninstall | --purge]
                  [--notify | --no-notify] [--no-timer]
  --claude     Claude Code (default, existing install command unchanged)
  --codex      Codex: ~/.agents/skills/longrun and $CODEX_HOME/hooks.json
  --zcode      ZCode: ~/.zcode/skills/longrun and ~/.zcode/cli/config.json
  --both       Claude Code and Codex (existing meaning unchanged)
  --all        all three clients; notes and watches are shared
  --no-timer   skip the five-minute background timer
  --purge      also remove shared global data; refuses while another client remains

Without a notify flag, asks about desktop notifications (skips when non-interactive).
CLAUDE_CONFIG_DIR, CODEX_HOME, LONGRUN_CODEX_SKILLS_DIR, LONGRUN_ZCODE_DIR and LONGRUN_BIN_DIR override paths.
LONGRUN_HOME relocates shared data (default: ~/.claude/longrun, including on Codex).

From a checkout: ./install.sh --codex
Without one: curl -fsSL https://krllx.github.io/longrun/install.sh | bash -s -- --codex
LONGRUN_REPO and LONGRUN_REF override the source repository/ref.
HELP
      exit 0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

if [ "$MODE" = install ] && [ ! -f "$HERE/skill/longrun/SKILL.md" ]; then
  REPO="${LONGRUN_REPO:-krllx/longrun}"
  REF="${LONGRUN_REF:-main}"
  command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
  command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }
  SOURCE_TMP="$(mktemp -d)"
  trap 'rm -rf "$SOURCE_TMP"' EXIT
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xzf - -C "$SOURCE_TMP"
  HERE="$(echo "$SOURCE_TMP"/*)"
  [ -f "$HERE/skill/longrun/SKILL.md" ] || { echo "tarball has no longrun skill" >&2; exit 1; }
fi

# Client paths are also used to keep a surviving installation's CLI and timer.
client_dest() {
  case "$1" in
    claude) printf '%s' "$CLAUDE_DIR/skills/longrun" ;;
    codex) printf '%s' "$CODEX_SKILLS/longrun" ;;
    zcode) printf '%s' "$ZCODE_DIR/skills/longrun" ;;
  esac
}
client_settings() {
  case "$1" in
    claude) printf '%s' "$CLAUDE_DIR/settings.json" ;;
    codex) printf '%s' "$CODEX_DIR/hooks.json" ;;
    zcode) printf '%s' "$ZCODE_DIR/cli/config.json" ;;
  esac
}
# Refuse a data purge before modifying any installation.
if [ "$MODE" = purge ]; then
  for OTHER in claude codex zcode; do
    case " $CLIENTS " in *" $OTHER "*) continue ;; esac
    if [ -f "$(client_dest "$OTHER")/SKILL.md" ]; then
      echo "shared data is still used by another client; use --uninstall or --all --purge" >&2
      exit 2
    fi
  done
fi
mkdir -p "$BIN_DIR"
STAMP="$(date +%Y%m%d-%H%M%S).$$"

# Validate all selected config files before copying files or registering servers.
for CLIENT in $CLIENTS; do
  SETTINGS="$(client_settings "$CLIENT")"
  python3 - "$SETTINGS" "$CLIENT" <<'PY_VALIDATE'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    try:
        d = json.load(open(p))
        if not isinstance(d, dict) or not isinstance(d.get("hooks", {}), dict):
            raise ValueError("expected an object with a hooks object")
        hooks = d.get("hooks", {})
        if sys.argv[2] == "zcode":
            if "enabled" in hooks and not isinstance(hooks["enabled"], bool):
                raise ValueError("hooks.enabled must be a boolean")
            hooks = hooks.get("events", {})
            if not isinstance(hooks, dict):
                raise ValueError("hooks.events must be an object")
        for entries in hooks.values():
            if not isinstance(entries, list):
                raise ValueError("hook events must contain arrays")
            for entry in entries:
                if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list) or not all(isinstance(h, dict) for h in entry["hooks"]):
                    raise ValueError("hook entries must contain arrays of handler objects")
    except ValueError as e:
        sys.exit("%s is not valid hook configuration (%s); nothing was changed" % (p, e))
PY_VALIDATE
done

for CLIENT in $CLIENTS; do
  DEST="$(client_dest "$CLIENT")"
  SETTINGS="$(client_settings "$CLIENT")"
  case "$CLIENT" in
    claude) CONFIG_DIR="$CLAUDE_DIR"; ENTRY=SKILL.md; SPEC=hooks.json ;;
    codex) CONFIG_DIR="$CODEX_DIR"; ENTRY=SKILL.codex.md; SPEC=hooks.codex.json ;;
    zcode) CONFIG_DIR="$ZCODE_DIR"; ENTRY=SKILL.zcode.md; SPEC=hooks.zcode.json ;;
  esac
  mkdir -p "$CONFIG_DIR/backups"
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$CONFIG_DIR/backups/$(basename "$SETTINGS").$STAMP.longrun.bak"
  fi
  if [ "$MODE" = install ]; then
    # ZCode can import another client's skill as a symlink. Keep that link as a
    # backup and install independently instead of overwriting the source skill.
    if [ "$CLIENT" = zcode ] && [ -L "$DEST" ]; then
      mv "$DEST" "$CONFIG_DIR/backups/longrun.skill.$STAMP.symlink"
    fi
    mkdir -p "$DEST/scripts" "$DEST/references"
    cp "$HERE/skill/longrun/$ENTRY" "$DEST/SKILL.md"
    cp "$HERE/skill/longrun/$SPEC" "$DEST/hooks.json"
    cp "$HERE/skill/longrun/references/"*.md "$DEST/references/"
    cp "$HERE/skill/longrun/scripts/longrun" "$DEST/scripts/longrun"
    chmod +x "$DEST/scripts/longrun"
    ln -sfn "$DEST/scripts/longrun" "$BIN_DIR/longrun"
    echo "$CLIENT skill: $DEST"
  fi

  # Only our handlers are removed, even inside a group with another owner's hook.
  python3 - "$SETTINGS" "$DEST/scripts/longrun" "$HERE/skill/longrun/$SPEC" "$MODE" "$CLIENT" "$DATA_DIR" <<'PY_HOOKS'
import json, os, shlex, sys
settings_path, bin_path, spec_path, mode, client, data_path = sys.argv[1:]
settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
hook_config = settings.setdefault("hooks", {})
hooks = hook_config.setdefault("events", {}) if client == "zcode" else hook_config
def ours(h):
    try:
        return any(p.endswith("/longrun/scripts/longrun") for p in shlex.split(h.get("command") or ""))
    except ValueError:
        return False
removed = added = 0
for event in list(hooks):
    kept = []
    for entry in hooks[event]:
        remaining = [h for h in entry.get("hooks", []) if not ours(h)]
        removed += len(entry.get("hooks", [])) - len(remaining)
        if remaining:
            kept.append(dict(entry, hooks=remaining))
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
if mode == "install":
    if client == "zcode":
        # Respect an explicit user disable; only a fresh hook configuration is enabled.
        hook_config.setdefault("enabled", True)
    for event, entries in json.load(open(spec_path))["hooks"].items():
        for entry in entries:
            entry = json.loads(json.dumps(entry))
            for h in entry["hooks"]:
                h["command"] = "LONGRUN_HOME=%s %s" % (shlex.quote(data_path), h["command"].replace("LONGRUN_BIN", shlex.quote(bin_path)))
            hooks.setdefault(event, []).append(entry)
            added += 1
if client == "claude":
    perms = settings.setdefault("permissions", {}).setdefault("allow", [])
    if mode == "install":
        for rule in ("Bash(longrun:*)", "Bash(%s:*)" % bin_path):
            if rule not in perms:
                perms.append(rule)
    else:
        settings["permissions"]["allow"] = [p for p in perms if p != "Bash(longrun:*)" and "/skills/longrun/scripts/longrun" not in p]
if client == "zcode":
    if not hooks:
        hook_config.pop("events", None)
    if not hook_config:
        settings.pop("hooks", None)
else:
    if not hooks:
        settings.pop("hooks", None)
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path + ".tmp", "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
os.replace(settings_path + ".tmp", settings_path)
print("%s hooks: removed %d old handlers, added %d entries" % (client, removed, added))
PY_HOOKS

  if [ "$CLIENT" = zcode ]; then
    if [ "$MODE" = install ]; then
      echo 'ZCode: CLI protocol installed; optional MCP registration is documented in references/zcode.md.'
    fi
  elif command -v "$CLIENT" >/dev/null 2>&1; then
    if [ "$CLIENT" = claude ]; then
      claude mcp remove --scope user longrun >/dev/null 2>&1 || true
      if [ "$MODE" = install ]; then
        claude mcp add --scope user longrun --env "LONGRUN_HOME=$DATA_DIR" -- "$DEST/scripts/longrun" mcp >/dev/null 2>&1 ||
          echo "mcp: register manually: claude mcp add --scope user longrun --env 'LONGRUN_HOME=$DATA_DIR' -- '$DEST/scripts/longrun' mcp"
      fi
    else
      # `mcp add` replaces this named entry; other config.toml settings are preserved.
      if [ "$MODE" = install ]; then
        if [ -f "$CONFIG_DIR/config.toml" ]; then
          cp "$CONFIG_DIR/config.toml" "$CONFIG_DIR/backups/config.toml.$STAMP.longrun.bak"
        fi
        codex mcp add longrun --env LONGRUN_CLIENT=codex --env "LONGRUN_HOME=$DATA_DIR" -- "$DEST/scripts/longrun" mcp >/dev/null 2>&1 ||
          echo "mcp: register manually: codex mcp add longrun --env LONGRUN_CLIENT=codex --env 'LONGRUN_HOME=$DATA_DIR' -- '$DEST/scripts/longrun' mcp"
      else
        codex mcp remove longrun >/dev/null 2>&1 || true
      fi
    fi
  elif [ "$MODE" = install ]; then
    echo "mcp: '$CLIENT' is not on PATH; register longrun with '$CLIENT mcp add' later"
  fi
done

if [ "$MODE" = install ]; then
  # 1b. desktop notifications. Asked for, not assumed: they install software on macOS and ask the system for
  # a permission, and longrun never depends on them - a halt and a fired watch reach the
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
      echo "Nothing here can answer (no terminal), so: skipped. 'brew install terminal-notifier' turns them on later."
      echo ""
    fi
  fi
  if [ "$NOTIFY" = "0" ]; then
    echo "notify: skipped - 'brew install terminal-notifier' (macOS) or a libnotify package (Linux) turns them on later"
  elif [ "$(uname)" = "Darwin" ]; then
    if ! command -v terminal-notifier >/dev/null 2>&1; then
      if command -v brew >/dev/null 2>&1; then
        echo "notify: installing terminal-notifier (Homebrew) - macOS cannot draw a notification without it"
        brew install terminal-notifier >/dev/null 2>&1 || echo "notify: brew install failed; run it by hand, then re-run this installer"
      else
        echo "notify: skipped - Homebrew is what installs terminal-notifier, and macOS draws no notification"
        echo "        without it. Install Homebrew from https://brew.sh, then run this installer again."
        echo "        Everything else works as it is."
      fi
    fi
    if command -v terminal-notifier >/dev/null 2>&1; then
      # its first send is what creates its entry in System Settings and asks for the permission
      echo "notify: terminal-notifier is here. macOS may ask once whether to allow its notifications - allow"
      echo "        it, then 'longrun notify --test' puts one on the screen."
    fi
  elif command -v notify-send >/dev/null 2>&1; then
    echo "notify: notify-send found; check it with 'longrun notify --test'"
  else
    echo "notify: no notify-send (libnotify) - halts and fired watches still reach the sessions"
    echo "        themselves; 'apt install libnotify-bin' (or 'dnf install libnotify') to also see them on screen."
  fi
  if [ "$TIMER" = 0 ]; then
    echo "timer: skipped (--no-timer)"
  elif TIMER_OUT="$("$BIN_DIR/longrun" watch install 2>&1)"; then
    echo "timer: $(printf '%s' "$TIMER_OUT" | head -n1)"
  else
    printf '%s\n' "$TIMER_OUT" | sed 's/^/timer: /'
  fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "PATH: add $BIN_DIR to PATH; hooks already use absolute paths" ;;
  esac
  echo "next: cd <project> && longrun init"
  case " $CLIENTS " in *" codex "*)
    echo 'Codex: open /hooks to review and trust the installed hooks, then invoke $longrun.'
    echo 'Restart Codex if the skill or MCP server is not visible. No hook trust or sandbox settings were changed.'
  ;; esac
  case " $CLIENTS " in *" claude "*)
    echo 'Claude Code: type /longrun to load the digest in an existing session.'
  ;; esac
  case " $CLIENTS " in *" zcode "*)
    echo 'ZCode: review Settings -> Hooks, enable hooks if previously disabled, then start a new session and invoke $longrun.'
    echo 'ZCode headless resume/wake and pre-compaction snapshots are unsupported.'
  ;; esac
else
  SURVIVOR=""
  for OTHER in claude codex zcode; do
    case " $CLIENTS " in *" $OTHER "*) continue ;; esac
    if [ -x "$(client_dest "$OTHER")/scripts/longrun" ]; then
      SURVIVOR="$(client_dest "$OTHER")/scripts/longrun"
      break
    fi
  done
  RESTART_TIMER=0
  if [ -x "$BIN_DIR/longrun" ]; then
    if ! "$BIN_DIR/longrun" watch status | head -n1 | grep -q 'NOT INSTALLED'; then
      RESTART_TIMER=1
    fi
    "$BIN_DIR/longrun" watch uninstall >/dev/null 2>&1 || true
  fi
  for CLIENT in $CLIENTS; do
    rm -rf "$(client_dest "$CLIENT")"
  done
  if [ -n "$SURVIVOR" ]; then
    ln -sfn "$SURVIVOR" "$BIN_DIR/longrun"
    if [ "$RESTART_TIMER" = 1 ]; then
      "$BIN_DIR/longrun" watch install >/dev/null 2>&1 || true
    fi
    echo "cli kept for the other client: $SURVIVOR"
  else
    rm -f "$BIN_DIR/longrun"
  fi
  if [ "$MODE" = purge ]; then
    rm -rf "$DATA_DIR"
    echo "removed shared data: $DATA_DIR (project .longrun/ directories are kept)"
  else
    echo "shared data kept: $DATA_DIR"
  fi
fi
echo done.
