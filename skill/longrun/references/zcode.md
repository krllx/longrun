# ZCode adapter

This adapter targets **ZCode from Z.ai**. Install from a checkout with `./install.sh --zcode`, or without a checkout:

```bash
curl -fsSL https://krllx.github.io/longrun/install.sh | bash -s -- --zcode
```

`--both` continues to select Claude Code and Codex; `--all` selects all three clients. `LONGRUN_ZCODE_DIR` overrides `~/.zcode`. The skill lives at `~/.zcode/skills/longrun/SKILL.md`, and user hooks are merged into `~/.zcode/cli/config.json` under `hooks.events`. A skill imported as a symlink is moved to the backup directory before installing a separate copy, preserving the source client. Other settings, handlers and hook limits are preserved; an existing file is backed up before changes. A fresh hook configuration gets `hooks.enabled: true`; an explicit `false` is preserved. Review Settings -> Hooks and enable hooks if needed, then start a new session and invoke `$longrun`. ZCode snapshots hook configuration at session startup. Project-level hook configs are ignored by ZCode; this installer uses the user scope.

The installer also provides the common `~/.local/bin/longrun` CLI. ZCode commands use the explicit prefix injected by the hook: `env LONGRUN_CLIENT=zcode LONGRUN_SESSION=<this-session-id> LONGRUN_HOME=<shared-store> <absolute-longrun-path> <args>`. It is emitted on startup and every user prompt because the hook cannot export variables into the model's shell. Without an ID, shared commands work, but longrun does not borrow the freshest conversation's identity. No ZCode MCP CLI syntax is assumed: the installer does not register an MCP server for ZCode. The existing `scripts/longrun mcp` server may be configured separately; set `LONGRUN_CLIENT=zcode` and the same `LONGRUN_HOME`, and pass the hook's full `session_id` and absolute `cwd` to each `run` call.

All clients use the same project `.longrun/` and global store (the existing `~/.claude/longrun/`, or a common `LONGRUN_HOME`). Shared notes, loading policy, document pointers, recall, board, inbox and HALT use the existing implementation; own notes remain bound to each conversation. ZCode context output uses `hookSpecificOutput.additionalContext` JSON; plain stdout is not model-visible in ZCode.

Supported events are `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` and `Stop`. Inputs use ZCode's documented Claude-compatible snake_case fields. Shell and patch aliases are normalized; all successful tools are observed, including read-only calls. Failure hooks record failures and deliver queued context; interrupted calls clear their running marker without recording a failure. HALT denies a tool using `PreToolUse.permissionDecision: deny`; permission hooks record the waiting state and never automatically grant permission.

A `SessionStart(source=compact)` reloads resident shared notes and own notes. There are no documented `PreCompact`, `PostCompact`, `SessionEnd`, `Interrupt` or `PostToolBatch` events in this adapter. It does not take pre-compaction snapshots, archive compaction summaries, measure context usage or infer a compaction threshold. ZCode's `transcript_path` is temporary and disappears after the hook, so longrun neither stores it as a durable pointer nor falls back to Claude transcript discovery for ZCode recall.

Messages for ZCode arrive in the shared inbox and are delivered at the next hook or digest. They do not start a model turn. `send --resume` and watch `--wake` refuse ZCode targets before launching a process or registering a watch. Watches without `--wake` can queue their result for later delivery. Sidebar discovery, live sockets, shell-process inspection and notification jump links remain Claude-specific. Address ZCode by its session ID/prefix or a journal `title:`. `notify_turn_end=always` and the important-session flag work with an available notifier; `unfocused` is unsupported because no ZCode app bundle ID is assumed.

`--zcode --uninstall` removes only the ZCode skill and longrun hook handlers. It retains user hook settings, shared data and a CLI/timer needed by another installed client. Purging shared global data refuses while an unselected client is still installed; `--all --purge` removes all three integrations and global data, retaining project-local `.longrun/` directories. Optional manually registered ZCode MCP entries must be removed separately.

Contract tests run with `python3 tests/zcode.py`, without model calls, real UI or scheduler installation. Live ZCode behavior still requires an installed client smoke test.

Sources: [ZCode skills](https://zcode.z.ai/en/docs/skill), [ZCode hooks](https://zcode.z.ai/en/docs/hooks). Contracts checked on 2026-10-02.
