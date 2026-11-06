// A child coding-agent stand-in for the launch signal tests. It asks its
// parent (the signal harness) for a signal, then stays alive unless the
// launcher applies the expected policy.

@module("node:process")
external argv: array<string> = "argv"

@module("node:process")
external ppid: int = "ppid"

@module("node:process")
external exit: int => unit = "exit"

@module("node:process")
external kill: (int, string) => bool = "kill"

@val @scope("process")
external on: (string, unit => unit) => unit = "on"

@val
external schedule: (unit => unit, int) => unit = "setTimeout"

let argument = (index, fallback) => argv->Array.get(index)->Option.getOr(fallback)
let signal = argument(2, "SIGTERM")
let exitCode = argument(3, "42")->Int.fromString->Option.getOr(42)

on(signal, () => exit(exitCode))
schedule(() => {
  let _ = kill(ppid, signal)
}, 30)
// SIGINT must not be forwarded: it was already delivered to a foreground
// child. A normal exit therefore proves the launcher consumed its copy.
schedule(() => exit(99), 250)
