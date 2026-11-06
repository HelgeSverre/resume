# `--resume`

[![npm version](https://img.shields.io/npm/v/@helgesverre/resume?logo=npm&color=cb3837)](https://www.npmjs.com/package/@helgesverre/resume)
[![npm downloads](https://img.shields.io/npm/dm/@helgesverre/resume?logo=npm&color=cb3837)](https://www.npmjs.com/package/@helgesverre/resume)
[![node](https://img.shields.io/node/v/@helgesverre/resume?logo=nodedotjs&color=339933)](https://www.npmjs.com/package/@helgesverre/resume)
[![license](https://img.shields.io/npm/l/@helgesverre/resume?color=blue)](LICENSE)

Search and resume local coding-agent sessions across many tools — after a crash, a closed terminal, or a context switch.

![resume in action — searching, expanding the preview, cycling the agent filter, toggling timestamps, and copying a cd-restoring resume command](demo/resume.gif)

`resume` opens its picker immediately, scans the session histories that your coding agents leave on disk in the background, normalizes them into one searchable list, and prints a `cd`-restoring command you can run to jump straight back into the right conversation in the right directory.

## Install

```sh
npm install -g @helgesverre/resume
```

Or run it without installing:

```sh
npx @helgesverre/resume
```

It ships with a bundled JavaScript executable for Node.js. Clipboard access uses [`clipboardy`](https://www.npmjs.com/package/clipboardy), and cross-platform process launching uses [`cross-spawn`](https://www.npmjs.com/package/cross-spawn). Node.js 22.13 or newer is required.

## Usage

```sh
resume
```

Type to search by tool, title, cwd, session id, or preview text.

| Key              | Action                                                       |
| ---------------- | ------------------------------------------------------------ |
| type             | Filter by tool, title, cwd, id, or preview                   |
| `↑` / `↓`        | Move selection                                               |
| mouse wheel      | Scroll the session list                                      |
| `PageUp/Down`    | Jump 10 rows                                                 |
| `Tab`            | Expand / collapse the preview panel                          |
| `Ctrl+A`         | Cycle the agent filter (all → one tool → …)                  |
| `Ctrl+T`         | Toggle an exact `yyyy-mm-dd hh:mm:ss` column                 |
| `Backspace`      | Delete a search character                                    |
| `Ctrl+U`         | Clear the search                                             |
| `Enter`          | Copy the resume command to the clipboard, print it, and exit |
| `Alt+Enter` / `Ctrl+R` | Close the picker and run the selected agent in its project directory |
| `Esc` / `Ctrl+C` | Quit without printing                                        |

Pressing `Enter` copies the command to your clipboard and prints a cwd-restoring command such as:

```sh
cd /path/to/project && claude --resume SESSION_ID
```

To run the selected session immediately, press **Alt+Enter** or **Ctrl+R**. The
picker restores the terminal before starting the agent. Ctrl+R is the fallback
when your terminal reserves Alt+Enter or Option is not configured to send Meta.
The child agent runs in the session's project directory; when it exits, your
shell remains in its original directory. Its exit status is preserved.

To have Enter's printed command also change your calling shell's directory,
evaluate the output:

```sh
eval "$(resume)"
```

## Supported tools

`resume` reads each tool's local session files (no network access) and knows how to build the right resume command for each:

| Tool         | Scanned location                                                                               | Resume command                     |
| ------------ | ---------------------------------------------------------------------------------------------- | ---------------------------------- |
| Claude Code  | `~/.claude/projects`                                                                           | `claude --resume <id>`             |
| Codex        | `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex/session_index.jsonl`              | `codex resume <id>`                |
| Amp          | `~/.local/share/amp/threads`                                                                   | `amp threads continue <id>`        |
| OpenCode     | `~/.local/share/opencode/storage`, `~/.local/share/opencode/opencode.db`                        | `opencode --session <id>`          |
| Junie        | `~/.junie/sessions`                                                                            | `junie --resume --session-id <id>` |
| Pi           | `~/.pi/agent/sessions`                                                                         | `pi --session <id>`                |
| Kimi         | `~/.kimi-code/session_index.jsonl`, `~/.kimi-code/sessions`                                    | `kimi --session <id>`              |
| Copilot      | `~/.copilot/session-state`                                                                     | `copilot --resume <id>`            |
| Antigravity  | `~/.gemini/antigravity-cli/conversations` (`.pb` and `.db`), `~/.gemini/antigravity-cli/brain` | `agy --conversation <id>`          |
| Gemini CLI   | `~/.gemini/tmp/*/chats`                                                                        | `gemini --session-file <path>`     |
| Mistral Vibe | `~/.vibe/logs/session`                                                                         | `vibe --resume <id>`               |
| Kilo         | `~/.local/share/kilo/kilo.db`                                                                  | `kilo --session <id>`              |
| Hermes       | `~/.hermes/state.db`                                                                           | `hermes --resume <id>`             |
| Poolside     | `~/Library/Application Support/poolside/acp` (macOS)                                           | `pool --resume <id>`               |
| Devin        | `~/.local/share/devin/cli/sessions.db`                                                         | `devin --resume <id>`              |

When a session records its working directory, the printed command is prefixed with `cd <cwd> &&` so you land back in the project. File-based adapters that use the shared cache store parsed sessions in `~/.cache/resume/sessions-cache-v2.json`, keyed by file size and mtime.

### Adding an adapter

Add a collector in `src/adapters/` that returns normalized `Session.t` values. For one session per file, `AdapterUtil.collectCachedSessions` handles file discovery, caching, and bounded reads. `NodeSqlite.query` reads SQLite stores in worker threads without changing them. Register the collector in `src/Adapters.res`; the registry also defines the order of tools in the picker filter. Add its `Session.tool` value, name, and resume command in `src/Session.res`, then add anonymized fixtures under `test/`. Run `npm test`, `npm run dist`, and a local scan to verify the format.

## Other commands

```sh
resume --json        # print normalized sessions as JSON
resume --copy <id>   # copy/print a uniquely matching id or prefix
resume --copy codex:<id> # qualify an id when multiple tools match
resume --help        # show usage and keybindings
resume --version     # print the version and exit
```

When stdin is a terminal, the picker uses stdout or, when stdout is captured,
stderr. This keeps `eval "$(resume)"` interactive and reserves its captured
output for the selected command. When stdin is not a terminal (or neither output
stream is a terminal), `resume` prints up to 50 sessions as tab-separated
`tool<TAB>id<TAB>title<TAB>command` rows. Use `resume </dev/null` to request this
listing from a terminal, or `resume --json` for structured output. TSV fields
escape backslashes, tabs, CR and LF so every record stays on one line.

Launch mode sends the agent's output directly to the terminal and emits no
command on captured stdout, so it is safe to use Alt+Enter/Ctrl+R inside the
`eval` workflow too. Clipboard failures still print the command with a warning.

## Build from source

```sh
npm install
npm run dist
npm link      # exposes the resume command
```

## Development

```sh
npm run build         # compile ReScript (src/*.res -> lib/)
npm test              # build, then run the ReScript test suite
npm run dist          # build + bundle dist/resume.mjs
npm run format        # format the ReScript sources with `rescript format`
npm run benchmark -- BEFORE_ROOT AFTER_ROOT 4
npm run snapshot-history -- NEW_DESTINATION  # macOS/APFS benchmark snapshot
npm run demo:fixtures -- demo/home
```

The application, tests, developer scripts, and demo generator are authored in ReScript. Generated JavaScript stays in `lib/` and `dist/`; the only Python source is the small optional native PTY test bridge. Keep new logic in ReScript and use narrow typed FFI for Node boundaries.

The modules are:

- `src/Session.res`, `src/SessionList.res` — the session model, resume-command builder, search, and JSON codecs.
- `src/adapters/*.res` — collectors grouped by data format where useful, plus the shared `AdapterUtil` helper; registered in `src/Adapters.res`.
- `src/JsonLines.res`, `src/AsyncPool.res` — streaming JSONL decoding and bounded task scheduling.
- `src/Display.res` — terminal-safe text, grapheme-aware clipping, wrapping, and cell widths.
- `src/Launch.res`, `src/Selection.res` — structured agent launch and unambiguous session lookup.
- `src/JsonUtil.res` — shared JSON decode helpers built on [`@glennsl/rescript-json-combinators`](https://github.com/glennsl/rescript-json-combinators), used by the adapters and the session codec.
- `src/Cache.res` — the stat-keyed parsed-session cache, with explicit per-adapter encode/decode codecs.
- `src/Tui.res` — a pure core (`update`, `view`, `keyOfEvent`) wrapped by a thin effectful picker shell, so layout and key handling are unit-tested without a TTY.
- `src/Cli.res` — typed parsing of argv into a single command, unit-tested without spawning the process.
- `src/node/*.res` — thin typed bindings to Node's `fs`, `path`, `process`, `readline`, `url`, and SQLite modules.
- `src/Main.res` — the CLI entry point that dispatches the parsed command.

OpenCode discovery supports legacy JSON storage, v1 SQLite (`session`), and
v2 SQLite (`session_v2` / `session_message`), including mixed upgraded stores.
Pi honors `PI_CODING_AGENT_SESSION_DIR` and `PI_CODING_AGENT_DIR` and displays
saved session names. Poolside currently supplies titles and working directories
from macOS ACP summaries; those files have no transcript preview or message count.
See [compatibility notes](docs/compatibility.md) for verified versions and remaining
storage-discovery gaps, and [performance results](docs/performance.md) for the
before/after measurements.

ReScript compiles to `lib/`, and [esbuild](https://esbuild.github.io/) bundles `lib/es6/src/Main.mjs` into `dist/resume.mjs` and the SQLite worker into `dist/NodeSqliteWorker.mjs` (with `clipboardy` and `cross-spawn` kept external). `npm pack` builds this distribution through `prepack`. Generated output and package-manager lockfiles are ignored in this repository. ReScript files are formatted with `rescript format`.

JSONL transcripts are streamed, so total file size does not need to fit in a
JavaScript string. Individual records over 64 million UTF-16 code units are
skipped with a warning, preserving the rest of the session. Displayed session
text is sanitized; original IDs and paths are preserved for clipboard/launch.
Closing the picker cancels outstanding reads and SQLite workers before handoff.

The test suite rebuilds the release bundle and exercises SQLite worker packaging.
On macOS/Linux, optional real-PTY tests run through `uv` and Python's standard
library when `uv` is available. Unit and distribution tests do not require it.

## Demo GIF

`demo/resume.gif` is recorded with [VHS](https://github.com/charmbracelet/vhs). It runs against a throwaway tree of synthetic sessions so the recording never shows real history. To regenerate it:

```sh
npm run dist
vhs demo/resume.tape   # writes demo/resume.gif
```

`demo/resume.tape` builds the fixtures first (`lib/es6/demo/MakeFixtures.mjs`, compiled from `demo/MakeFixtures.res`, into the gitignored `demo/home/`) and points `HOME` at them. The picker treats every printable character as filter input — toggles are bound to `Ctrl`-modified keys (`Ctrl+T` time, `Ctrl+A` agent cycle, `Ctrl+U` clear) and `Tab` expands the preview — so the demo's search terms can contain any letter.
