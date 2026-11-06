# Execute a selected session after closing the picker

Implemented: Enter copies/prints, Alt+Enter executes, and Ctrl+R provides a
broadly compatible fallback. Explicit CSI-u modified-Enter events are recognized
when a terminal already emits them; the picker does not require protocol
negotiation. The remainder explains the architecture and its portability limits.

## Keyboard behavior

| Binding | Action | Compatibility |
| --- | --- | --- |
| Enter | Existing copy + print | Existing behavior. |
| Alt+Enter | Close picker and launch selected session | Legacy terminals can encode this as ESC followed by CR; Node readline reports `meta: true` and `name: "return"`. Some terminal/OS shortcuts intercept it. |
| Ctrl+R | Same launch action | A distinct control byte understood by Node readline in raw mode; a practical fallback when Alt+Enter is unavailable. |
| Ctrl+Enter / Shift+Enter | No additional promise | Legacy terminal protocols commonly collapse these to ordinary CR, so the application cannot reliably distinguish them from Enter. |

A PassThrough + `readline.emitKeypressEvents` probe confirmed CR, ESC+CR and
Ctrl+R decoding. CSI-u encodings for modified Enter were not decoded into named
keys by Node readline. Supporting enhanced protocols would require explicit
parsing and capability negotiation; it should be an optional enhancement, not a
prerequisite for executing sessions.

On macOS, Option/Alt behavior depends on terminal configuration. Multiplexers
and terminal-level shortcuts can also intercept the combination. ESC immediately
followed by Enter is indistinguishable from legacy Alt+Enter, so the UI should
show the action clearly and retain the separate Ctrl+R fallback.

Sources: [kitty keyboard protocol, including legacy C0 encodings](https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
[Node readline keypress decoding](https://nodejs.org/api/readline.html#readlineemitkeypresseventsstream-interface),
[xterm control-sequence reference](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).

## Structured launch plans

`Session.launchSpec` produces executable, argv and optional
cwd, for example `codex`, `["resume", session.id]`, and `session.cwd`. The same
spec derives the human-readable shell-quoted command. Do not split or execute
the printed `cd ... && ...` string.

The picker returns Cancel, Copy(session), or Run(session), after restoring raw mode, mouse reporting, cursor and alternate
screen, removing listeners, and stopping scheduled draws. Main owns copying,
printing or launching. Run has a single-submission guard and does not depend on clipboard access.
Closing the viewer aborts the scan, terminates SQLite workers, and awaits cleanup
before launching, so background collectors do not compete with the agent.

`Launch.run` uses asynchronous `cross-spawn` with executable, args, cwd, explicit
terminal file descriptors and `shell: false`. This passes
paths and IDs as arguments, without shell interpretation or login-shell startup.
Keep the child attached to the terminal and wait for its close event. Report
missing executables after cleanup and preserve nonzero exit status. Test signal
behavior through a pseudo-terminal: parent and child normally share the foreground
process group, so blindly forwarding keyboard SIGINT can deliver it twice.
Explicitly exit after the child finishes if background discovery is still alive.

Sources: [Node child process spawn and stdio](https://nodejs.org/api/child_process.html#child_processspawncommand-args-options),
[Node signal behavior](https://nodejs.org/api/process.html#signal-events).

## Captured stdout and the existing eval workflow

`eval "$(resume)"` makes stdout a pipe. A launch action must emit no command on
that stream, and the launched agent must not inherit that pipe: otherwise agent
output could be captured and evaluated as shell input when it exits.

For Run, connect the child's stdin to the restored terminal input and connect its
stdout/stderr to the picker's selected terminal output. In the captured-stdout
case this is the parent's stderr terminal. Thus the child remains interactive,
the outer command substitution receives no text, and nothing executes twice.
For Copy, retain the current single shell-quoted command on stdout.

Launching a child with its cwd set starts the agent in the right project, but it
cannot change the calling shell's directory. After the agent exits, the shell
stays in its original directory. Enter through the existing eval workflow can
continue to provide parent-shell `cd` behavior. No terminal keystroke injection,
shell startup-file modification or user shell integration is required for Run.

## Portability and tests

Executable agent commands use the same launch plan across platforms.
`cross-spawn` handles Windows PATHEXT, shebangs and npm command shims; the app
does not construct or evaluate a shell command from session data. Native Windows
host testing was not available in this macOS session.

Source: [cross-spawn platform handling](https://github.com/moxystudio/node-cross-spawn#why).
`process.execve` is not a baseline solution: it is absent from the minimum Node
22.13 version supported by this package and is unavailable on Windows.

Sources: [Node Windows batch-file limitations](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows),
[Node execve availability](https://nodejs.org/api/process.html#processexecvefile-args-env).

Implemented tests cover: modifier precedence before plain Enter; ordinary Enter never
launches; Ctrl+R/Alt+Enter launch exactly once; special characters remain literal
argv; cwd is observed by a fixture child; terminal teardown precedes child output;
missing executable/nonzero exit/signal behavior; quitting during discovery;
no command or agent output reaches captured stdout in Run mode. Include a real
pseudo-terminal test alongside pure key-mapping and subprocess tests.
