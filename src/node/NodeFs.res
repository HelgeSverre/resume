// Node.js fs/promises bindings

// Type definitions for Node.js types
@scope("node:fs")
type dirent
@get external name: dirent => string = "name"
@send external isDirectory: dirent => bool = "isDirectory"
@send external isFile: dirent => bool = "isFile"

@scope("node:fs")
type stats
@get external mtimeMs: stats => float = "mtimeMs"
@get external size: stats => float = "size"

@module("node:fs/promises")
external readFile: (string, string) => promise<string> = "readFile"

@module("node:fs/promises")
external readdir: string => promise<array<string>> = "readdir"

@module("node:fs/promises")
external readdirWithFileTypes: (string, {"withFileTypes": bool}) => promise<array<dirent>> =
  "readdir"

@module("node:fs/promises")
external stat: string => promise<stats> = "stat"

@module("node:fs/promises")
external mkdir: string => promise<unit> = "mkdir"

@module("node:fs/promises")
external mkdirWithRecursive: (string, {"recursive": bool}) => promise<unit> = "mkdir"

@module("node:fs/promises")
external writeFile: (string, string) => promise<unit> = "writeFile"

@module("node:fs/promises")
external access: string => promise<unit> = "access"

@module("node:fs/promises")
external mkdtemp: string => promise<string> = "mkdtemp"

let exists = path => {
  access(path)
  ->Promise.then(_ => Promise.resolve(true))
  ->Promise.catch(_ => Promise.resolve(false))
}
