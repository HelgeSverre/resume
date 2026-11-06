// Keep signal injection outside the Node test process: the harness can safely
// receive SIGINT/SIGTERM/SIGHUP while it verifies Launch's temporary handlers.

@module("node:process")
external argv: array<string> = "argv"

@module("node:process")
external execPath: string = "execPath"

@val @scope("process")
external listenerCount: string => int = "listenerCount"

let argument = (index, fallback) => argv->Array.get(index)->Option.getOr(fallback)
let names = ["SIGINT", "SIGTERM", "SIGHUP"]
let counts = () => names->Array.map(name => (name, listenerCount(name)))

let run = async () => {
  let fixture = argument(2, "")
  let signal = argument(3, "SIGTERM")
  let childExitCode = argument(4, "42")
  let before = counts()
  let outcome = await Launch.run(
    {
      executable: execPath,
      args: [fixture, signal, childExitCode],
      cwd: None,
    },
    ~inputFd=0,
    ~outputFd=1,
  )
  let after = counts()
  let restored = JSON.stringifyAny(before) == JSON.stringifyAny(after)
  let record = {
    "outcome": outcome,
    "before": before,
    "after": after,
    "restored": restored,
  }
  Console.log(JSON.stringifyAny(record)->Option.getOr("{}"))
}

run()->ignore
