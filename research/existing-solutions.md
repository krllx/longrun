# Existing solutions (checked 2026-09-04)

Full report produced during research; URLs verified unless marked [unverified].

## Vendor-native
- **OpenAI Codex CLI 0.153.0 (2026-09-03), experimental context management** - https://github.com/openai/codex/releases/tag/rust-v0.153.0 , PR #39827, #27488, #29743. Token-budget context, `new_context` tool (fresh window, no summary), `history.*` and `notes.*` tools (`list_files_by_prefix/read_file/search_contents/append_to_file/write_file`) served by the Codex backend. Model-driven writes, no hooks, no pruning documented, ChatGPT plans only.
- **Codex Memories** (`~/.codex/memories/`) - https://github.com/openai/codex/blob/main/codex-rs/memories/README.md . Background two-phase extraction + consolidation sub-agent, SQLite, `max_unused_days`, global lock. Long-term preferences, not task state.
- **Claude Code auto memory** - https://code.claude.com/docs/en/memory . `MEMORY.md` 200 lines / 25 KB, per git root, re-injected after compaction; no pruning policy, no multi-session coordination, scoped to preferences.
- **Claude Code hook substrate** - https://code.claude.com/docs/en/hooks , https://code.claude.com/docs/en/context-window#what-survives-compaction . Issue https://github.com/anthropics/claude-code/issues/43733 (closed, not planned): no guaranteed model turn before compaction.
- **Anthropic API memory tool / context editing / engineering posts** - https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool , https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents , https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents (claude-progress.txt + feature list). Fully model-dependent.
- **Managed Agents memory stores** - https://platform.claude.com/docs/en/managed-agents/memory . Cloud only, versioned files, sha256 preconditions.
- **Agent teams / cross-session messaging** - https://code.claude.com/docs/en/agent-teams , https://code.claude.com/docs/en/cross-session-messaging . Tasks + messages, no shared notes.

## Community, hook-based
- **who96/claude-code-context-handoff** - PreCompact + SessionEnd(clear) write a handoff extracted from the transcript, SessionStart(compact|clear) restores. Fixed windows, cross-restore risk between parallel sessions in one dir.
- **u-ichi/compact-plus** - PreCompact transcript backup + LLM-generated state file, SessionStart(compact) recovery, UserPromptSubmit fallback. State in $TMPDIR, no size cap.
- **mikeadolan transcript-to-SQLite stack**, **yuvalsuede/memory-mcp**, **mem0** - every message stored, re-injected on PostCompact; no pruning, admits compaction still lossy.
- **thedotmack/claude-mem** - background worker, SQLite+Chroma, LLM-compressed observations; no cap, no multi-session story.
- **parcadei/Continuous-Claude-v3** - ledgers/handoffs in markdown + PostgreSQL, daemon, file claims; heavy.

## Trackers / state files
- **Beads** (steveyegge) - Dolt-backed issue graph, `bd prime` on SessionStart, memory decay; a tracker, not a scratchpad.
- **cc-sessions**, **get-shit-done STATE.md**, **Cline Memory Bank**, **Serena memories**, **ConPort** - prompt/command driven, no hooks, no caps.
- **Ralph Wiggum loop**, **continuous-claude**, **claude-checkpoint-system** - loop runners, state in files/git only.

## Gaps this project fills
Mechanical size cap on curated notes; defined forgetting rules at every level; writes that happen on PreCompact/PostCompact/PostToolUseFailure without the model; re-injection on every SessionStart source including clear/fork; shared ledger/inbox with file locks for parallel sessions; heartbeat for an HQ session.
