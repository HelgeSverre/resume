# Session-store compatibility notes

This document records the storage contracts `resume` relies on. It is a
maintenance aid, not a user-facing catalogue of every coding agent.

## Codex

The rollout's first `session_meta` identifies the session and its original
working directory. Resuming it in another project or worktree does not rewrite
that header. The adapter therefore uses the latest nonempty `turn_context`
`payload.cwd`, falling back to the header when there is no turn directory.
That directory also determines where the resume command launches.

Updated time is the maximum valid rollout timestamp or session-index update.
It describes recorded activity, including reasoning, tools, and bookkeeping;
it is not restricted to the last user message. An old session with an active
background task can therefore appear near the top of the picker. Taking the
maximum also prevents an out-of-order record from moving activity backwards.
The Codex parsed-file cache uses `codex-file-v3` so older cached directories and
timestamps are refreshed without requiring users to delete their cache.

## Pi

Pi 1.4.0 is installed on the reference machine. Its sessions are JSONL files
under `~/.pi/agent/sessions/`, grouped by encoded working directory. The first
row is a `session` header with an id, cwd, and ISO timestamp. Conversation rows
have `type: "message"` and contain the message role and content under
`message`. `pi --session <id>` accepts an id or a session path, so the current
adapter's `pi --session <id>` command is supported.

The current adapter correctly counts `user` and `assistant` entries because
its role prefilter searches the complete JSON row, including nested
`message.role`. It also accepts Pi's current version-3 files. Pi documents
automatic load-time migration from versions 1 and 2 to version 3, but `resume`
does not invoke that migration: it parses files directly. Version-1 and
version-2 raw files have not been verified with adapter fixtures and should not
be treated as supported merely because Pi itself can load them. It honors
`PI_CODING_AGENT_SESSION_DIR` first, then `PI_CODING_AGENT_DIR/sessions`,
matching Pi's documented storage overrides. A later `session_info` entry
carries the user-provided display name and takes precedence over the last
message as the picker title.

Sources: [Pi session format](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/session-format.md),
[Pi CLI session options](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md#session-management).

## OpenCode 1 and 2

OpenCode 2.1.2 is installed on the reference machine. Both the legacy `session`
table and the v2 `session_v2` table are present in its SQLite store. They are
different stores: v2 adds fields such as fork metadata and suspended time, and
the active CLI accepts `opencode --session <id>`.

The adapter queries both tables and merges the resulting JSON-store, v1, and
v2 records by session id. The newest timestamp wins; when timestamps tie,
the v2 record wins because it is loaded after the v1 table. JSON records under
`storage/session` remain a fallback, not a complete v2 index. V2 message rows
are stored in `session_message`; their `type` values include `user` and
`assistant`, so the displayed message count uses those two values. The scan
does not filter archived rows, preserving the legacy adapter's behavior of
listing every resumable session.

OpenCode's migration has changed during v2 development. Its maintainers state
that a v1-to-v2 import now exists, but reports show legacy sessions created
after the one-time migration can remain only in the legacy table. Scanning both
schema families is therefore required even on a v2 installation.

Sources: [OpenCode v1/v2 migration issue and maintainer update](https://github.com/anomalyco/opencode/issues/41217),
[OpenCode session CLI documentation](https://opencode.ai/docs/cli/).

## Poolside

Poolside's locally installed CLI is `pool` 1.0.16. `pool --resume <id>` resumes
a previous session by ID, according to the installed binary's help. On macOS,
`pool config` reports its data root as
`~/Library/Application Support/poolside`; resumable ACP summaries are JSON
files at `acp/<encoded-cwd>/<session-id>.json`. Each includes `sessionId`,
`cwd`, `title`, and `updatedAt`. The adapter uses `sessionId`: it is the
locally persisted identifier and `poolSessionId` is absent for some records.
The CLI help does not distinguish those two fields, so this mapping should be
regression-tested against a future Pool release.

The summary files do not include a conversation transcript, so Pool sessions
currently show no preview or message count. Full trajectories and logs are
separate and are intentionally not scanned: they contain substantially more
data and are not needed to resume a session. The adapter currently implements
only this macOS data root; it will find no Pool sessions on Linux or Windows
until their storage locations are verified.

Sources: installed `pool --help` and `pool config`; [Pool automated-mode documentation](https://docs.poolside.ai/cli/automated-mode.md).

## Discovery gaps

Every collector receives one home directory, resolved from `HOME` by the CLI.
That supports a relocated home but does not resolve every tool-specific storage
override.

| Tool or location | Current behavior | Gap |
| --- | --- | --- |
| Codex | Scans `$HOME/.codex`. | Codex documents `CODEX_HOME` as the state root; a non-default value is not discovered. |
| Claude Code | Scans `$HOME/.claude/projects`. | A `CLAUDE_CONFIG_DIR` relocation is not resolved, so its project sessions are missed. |
| Amp and OpenCode | Scan `$HOME/.local/share/...`. | The collectors do not consult `XDG_DATA_HOME`; installations relocated from the XDG default are missed. |
| Poolside | Scans macOS ACP summaries only. | Linux and Windows paths, transcript-derived preview, and message counts are unverified. |
| Pi | Supports its two session-directory environment overrides. | Raw pre-v3 files and custom per-project `sessionDir` settings are unverified. |

Sources: [Codex configuration source](https://github.com/openai/codex/blob/main/codex-rs/core/src/config/mod.rs),
[Pi session format](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/session-format.md).
