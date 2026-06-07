// Node.js process bindings

@module("node:process")
external argv: array<string> = "argv"
@module("node:process")
external env: dict<string> = "env"
@module("node:process")
external stdin: 'stream = "stdin"
@module("node:process")
external stdout: 'stream = "stdout"
@module("node:process")
external exit: int => unit = "exit"

@get external isTTY: 'stream => bool = "isTTY"
@get external columns: 'stream => int = "columns"
@get external rows: 'stream => int = "rows"
@send external write: ('stream, string) => unit = "write"

// `on` is an EventEmitter method on the global process object; it is not a named
// export of "node:process", so bind it off the global rather than the module.
@val @scope("process")
external on: (string, 'a => unit) => unit = "on"

// Re-export types for use in other modules
@module("node:os")
external homedir: unit => string = "homedir"
@module("node:os")
external tmpdir: unit => string = "tmpdir"
