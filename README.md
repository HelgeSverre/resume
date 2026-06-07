# `--resume`

Search and resume local coding-agent sessions across many tools — after a crash, a closed terminal, or a context switch.

![resume in action — searching, expanding the preview, cycling the agent filter, toggling timestamps, and copying a cd-restoring resume command](demo/resume.gif)

`resume` scans the session histories that your coding agents leave on disk, normalizes them into one searchable list, and prints a `cd`-restoring command you can run to jump straight back into the right conversation in the right directory.

## Usage

```sh
resume
```

Type to search by tool, title, cwd, session id, or preview text.

| Key              | Action                                                       |
| ---------------- | ------------------------------------------------------------ |
| type             | Filter by tool, title, cwd, id, or preview                   |
| `↑` / `↓`        | Move selection                                               |
| `PageUp/Down`    | Jump 10 rows                                                 |
| `Tab`            | Expand / collapse the preview panel                          |
| `Ctrl+A`         | Cycle the agent filter (all → one tool → …)                  |
| `Ctrl+T`         | Toggle an exact `yyyy-mm-dd hh:mm:ss` column                 |
| `Backspace`      | Delete a search character                                    |
| `Ctrl+U`         | Clear the search                                             |
| `Enter`          | Copy the resume command to the clipboard, print it, and exit |
| `Esc` / `Ctrl+C` | Quit without printing                                        |

Pressing `Enter` copies the command to your clipboard and prints a cwd-restoring command such as:

```sh
cd /path/to/project && claude --resume SESSION_ID
```

To run it directly, evaluate the output:

```sh
eval "$(resume)"
```

## Supported tools

`resume` reads each tool's local session files (no network access) and knows how to build the right resume command for each:

| Tool        | Scanned location                                                                  | Resume command                     |
| ----------- | --------------------------------------------------------------------------------- | ---------------------------------- |
| Claude Code | `~/.claude/projects`                                                              | `claude --resume <id>`             |
| Codex       | `~/.codex/sessions`, `~/.codex/archived_sessions`, `~/.codex/session_index.jsonl` | `codex resume <id>`                |
| Amp         | `~/.local/share/amp/threads`                                                      | `amp threads continue <id>`        |
| OpenCode    | `~/.local/share/opencode/storage`                                                 | `opencode --session <id>`          |
| Junie       | `~/.junie/sessions`                                                               | `junie --resume --session-id <id>` |
| Pi          | `~/.pi/agent/sessions`                                                            | `pi --session <id>`                |
| Kimi        | `~/.kimi-code/session_index.jsonl`, `~/.kimi-code/sessions`                       | `kimi --session <id>`              |
| Copilot     | `~/.copilot/session-state`                                                        | `copilot --resume <id>`            |
| Antigravity | `~/.gemini/antigravity-cli/conversations`, `~/.gemini/antigravity-cli/brain`      | `agy --conversation <id>`          |

When a session records its working directory, the printed command is prefixed with `cd <cwd> &&` so you land back in the project. Parsed sessions are cached in `~/.cache/resume/sessions-cache-v2.json`, keyed by file size and mtime, so repeat runs are fast.

## Other commands

```sh
resume --json        # print normalized sessions as JSON
resume --copy <id>   # copy the resume command for an exact or prefix session id to the clipboard
resume --help        # show usage and keybindings
```

When stdout is not a TTY (e.g. piped), `resume` prints up to 50 sessions as tab-separated `tool<TAB>id<TAB>title<TAB>command` rows instead of opening the picker.

## Build

```sh
npm install   # also runs `npm run dist` via the prepare script
npm link      # exposes the `resume` binary (dist/resume.mjs)
```

## Development

```sh
npm run build         # compile ReScript (src/*.res -> lib/)
npm test              # build, then run the ReScript test suite
npm run dist          # build + bundle to a single dist/resume.mjs
npm run format        # format the ReScript sources with `rescript format`
```

The application is written entirely in ReScript (`src/*.res`):

- `src/Session.res`, `src/SessionList.res` — the session model, resume-command builder, search, and JSON codecs.
- `src/adapters/*.res` — one module per tool, plus shared `AdapterUtil`/`Codec` helpers; registered in `src/Adapters.res`.
- `src/Cache.res` — the stat-keyed parsed-session cache, with explicit per-adapter encode/decode codecs.
- `src/Tui.res` — a pure core (`update`, `view`, `keyOfEvent`) wrapped by a thin effectful picker shell, so layout and key handling are unit-tested without a TTY.
- `src/node/*.res` — thin typed bindings to Node's `fs`, `path`, `process`, `readline`, and `url`.
- `src/Main.res` — the CLI entry point.

ReScript compiles to `lib/`, and [esbuild](https://esbuild.github.io/) bundles `lib/es6/src/Main.mjs` into the single executable `dist/resume.mjs` (with `clipboardy` kept external). ReScript files are formatted with `rescript format`.

## Demo GIF

`demo/resume.gif` is recorded with [VHS](https://github.com/charmbracelet/vhs). It runs against a throwaway tree of synthetic sessions (one per supported tool) so the recording never shows real history. To regenerate it:

```sh
vhs demo/resume.tape   # writes demo/resume.gif
```

`demo/resume.tape` builds the fixtures first (`demo/make-fixtures.mjs`, into the gitignored `demo/home/`) and points `HOME` at them. The picker treats every printable character as filter input — toggles are bound to `Ctrl`-modified keys (`Ctrl+T` time, `Ctrl+A` agent cycle, `Ctrl+U` clear) and `Tab` expands the preview — so the demo's search terms can contain any letter.
