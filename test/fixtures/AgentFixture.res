// Executed by the tiny fake `claude` shim used by the PTY test. The shim only
// imports this compiled module; the child behavior itself remains typed code.
@module("node:fs")
external appendFileSync: (string, string) => unit = "appendFileSync"

@module("node:process")
external argv: array<string> = "argv"
@module("node:process")
external env: dict<string> = "env"
@module("node:process")
external cwd: unit => string = "cwd"
@module("node:process")
external stdin: 'stream = "stdin"
@module("node:process")
external stdout: 'stream = "stdout"
@module("node:process")
external stderr: 'stream = "stderr"
@module("node:process")
external exit: int => unit = "exit"

@get external isTTY: 'stream => bool = "isTTY"
@get external isRaw: 'stream => option<bool> = "isRaw"

let exitCode =
  env
  ->Dict.get("FIXTURE_EXIT_CODE")
  ->Option.flatMap(value => Int.fromString(value))
  ->Option.getOr(0)

switch env->Dict.get("RUN_COUNT") {
| Some(path) => appendFileSync(path, "x")
| None => ()
}

let record = {
  "args": argv->Array.slice(~start=2, ~end=argv->Array.length),
  "cwd": cwd(),
  "inputTTY": stdin->isTTY,
  "outputTTY": stdout->isTTY,
  "errorTTY": stderr->isTTY,
  "raw": stdin->isRaw->Option.getOr(false),
}
Console.log("LAUNCH_FIXTURE:" ++ JSON.stringifyAny(record)->Option.getOr("{}"))
exit(exitCode)
