# Post-1.1.0 bug hunt

This pass checked adapter metadata, cache use, search input, terminal output,
launch handling, and release packaging. Six additional issues were reproduced
with synthetic inputs before fixes; no private conversation contents are used.

| Priority | Trigger | Observed failure | Correction |
| --- | --- | --- | --- |
| Medium | stdin is redirected while stdout is a terminal; a session field contains ANSI controls | The TSV fallback emits those controls to the terminal, bypassing the picker's sanitization | Sanitize terminal-bound TSV fields; keep redirected output unchanged |
| Medium | A Claude chat moves directories, then an assistant message omits `cwd` | The last directory becomes absent and the parser falls back to the original folder; resume launches there too | Retain the latest nonempty message directory |
| Medium | An older-timestamped Claude record follows newer activity | Updated time moves backwards | Take the maximum valid timestamp, as for Codex |
| Medium | A Vibe session appends messages without rewriting `meta.json` | The preview changes but the activity time remains old | Include the message log's modification time |
| Low | Backspace after emoji, a combining sequence, or a family emoji in search | One UTF-16 code unit is deleted, leaving a broken query | Delete one grapheme using the existing segmenter |
| Low | A long title has an emoji crossing the compact-title cutoff | The title ends in a lone surrogate | Share the existing surrogate-safe prefix operation between titles and previews |

The affected cached adapters advance their namespaces so stale metadata and
truncated titles are reparsed on upgrade. This causes one fresh parse for those
adapters, not a change to source session files.

Regression coverage is in `FollowupHunt_test.res` and `CliOutput_test.res`.
The six initial reproductions failed before the fixes and pass afterward;
an additional case checks the Claude cache upgrade. Full validation covers
143 tests, including the packaged SQLite worker and PTY handoff checks.
