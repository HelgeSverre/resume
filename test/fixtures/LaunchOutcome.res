// Simple typed child outcomes for the direct exit/signal tests.

@module("node:process")
external argv: array<string> = "argv"

@module("node:process")
external pid: int = "pid"

@module("node:process")
external exit: int => unit = "exit"

@module("node:process")
external kill: (int, string) => bool = "kill"

let argument = (index, fallback) => argv->Array.get(index)->Option.getOr(fallback)

switch argument(2, "exit") {
| "signal" => {
    let _ = kill(pid, argument(3, "SIGTERM"))
  }
| _ => exit(argument(3, "0")->Int.fromString->Option.getOr(0))
}
