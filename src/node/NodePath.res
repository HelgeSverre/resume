// Node.js path bindings

@module("node:path")
external join: (string, string) => string = "join"

@module("node:path")
external basename: (string, string) => string = "basename"

@module("node:path")
external dirname: string => string = "dirname"

let joinMany = (parts: array<string>) => {
  parts->Array.reduce("", (acc, part) => {
    if acc == "" {
      part
    } else {
      join(acc, part)
    }
  })
}

@module("node:path")
external sep: string = "sep"
let hasSegment = (path, segment) => path->String.split(sep)->Array.some(part => part == segment)
