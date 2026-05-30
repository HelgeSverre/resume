# resume

Search and resume local coding-agent sessions across many tools — after a crash, a closed terminal, or a context switch.

`resume` scans the session histories that your coding agents leave on disk, normalizes them into one searchable list, and prints a `cd`-restoring command you can run to jump straight back into the right conversation in the right directory.

## Usage

```sh
resume
```

Type to search by tool, title, cwd, session id, or preview text.

| Key              | Action                                       |
| ---------------- | -------------------------------------------- |
| type             | Filter by tool, title, cwd, id, or preview   |
| `↑` / `↓`        | Move selection                               |
| `PageUp/Down`    | Jump 10 rows                                 |
| `t`              | Toggle an exact `yyyy-mm-dd hh:mm:ss` column |
| `Backspace`      | Delete a search character                    |
| `Ctrl+U`         | Clear the search                             |
| `Enter`          | Print the resume command and exit            |
| `Esc` / `Ctrl+C` | Quit without printing                        |

Pressing `Enter` prints a cwd-restoring command such as:

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

When a session records its working directory, the printed command is prefixed with `cd <cwd> &&` so you land back in the project. Parsed sessions are cached in `~/.cache/resume/sessions-cache-v1.json`, keyed by file size and mtime, so repeat runs are fast.

## Other commands

```sh
resume --json        # print normalized sessions as JSON
resume --copy <id>   # copy the resume command for an exact or prefix session id to the clipboard
resume --help        # show usage and keybindings
```

When stdout is not a TTY (e.g. piped), `resume` prints up to 50 sessions as tab-separated `tool<TAB>id<TAB>title<TAB>command` rows instead of opening the picker.

## Build

```sh
npm install
npm run build
npm link
```

## Development

```sh
npm run build         # compile ReScript (src/*.res -> lib/)
npm test              # build, then run ReScript and JS tests
npm run format        # format JS/.mjs sources with oxfmt
npm run format:check  # verify formatting in CI
```

The codebase is a mix of ReScript (`src/*.res`, pure logic such as session shaping and the resume-command builder) and hand-written JavaScript (`src/adapters.mjs`, `src/tui.mjs`, `bin/resume.js`, for filesystem scanning and the terminal UI). ReScript files are formatted with `rescript format`; the JavaScript is formatted with [oxfmt](https://www.npmjs.com/package/oxfmt).
