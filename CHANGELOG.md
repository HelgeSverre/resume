# Changelog

## 1.1.0-rc.1

- Open the picker immediately and load sessions progressively with bounded async I/O.
- Resume the selected session after closing the viewer with Alt+Enter or Ctrl+R.
- Support Poolside's `pool` CLI and improve Pi and OpenCode JSON/SQLite compatibility.
- Stream large Claude and Codex histories; fix Gemini replay and session titles.
- Isolate malformed adapter data, coordinate concurrent cache writers, and support cancellation.
- Sanitize terminal output and handle Unicode display widths and ambiguous session IDs.
- Move developer scripts and demo fixtures to ReScript.
- Publish tagged releases through GitHub Actions with npm trusted publishing.

Measured against a frozen local history snapshot: warm scan 729 ms → 504 ms,
warm peak RSS 1887 MiB → 319 MiB. See `docs/performance.md` for methodology,
sample limits, and cold scan results.
