// Prints exactly the values needed to demonstrate Launch uses argv and cwd,
// rather than feeding a display command to a shell.

@module("node:process")
external argv: array<string> = "argv"

@module("node:process")
external cwd: unit => string = "cwd"

let record = {
  "cwd": cwd(),
  "args": argv->Array.slice(~start=2, ~end=argv->Array.length),
}

Console.log(JSON.stringifyAny(record)->Option.getOr("{}"))
