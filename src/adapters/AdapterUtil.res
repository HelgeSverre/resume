// Adapter utilities - shared helpers for filesystem scanning and JSONL parsing

open NodeFs

@val external all: array<promise<'a>> => promise<array<'a>> = "Promise.all"

let walkFiles = async (root, predicate) => {
  let rootExists = await exists(root)
  if !rootExists {
    []
  } else {
    let out = []
    let stack = [root]
    while stack->Array.length > 0 {
      switch stack->Array.pop {
      | Some(dir) =>
        let entries = await readdirWithFileTypes(dir, {"withFileTypes": true})
        entries->Array.forEach(entry => {
          let path = NodePath.join(dir, entry->name)
          if entry->isDirectory {
            stack->Array.push(path)
          } else if entry->isFile && predicate(path) {
            out->Array.push(path)
          }
        })
      | None => ()
      }
    }
    out
  }
}

let splitLines = text => text->String.split("\n")

let readJsonl = async path => {
  let rows = []
  let lines = splitLines(await readFile(path, "utf8"))
  lines->Array.forEach(line => {
    if line->String.trim != "" {
      try {
        rows->Array.push(JSON.parseExn(line))
      } catch {
      | _ => ()
      }
    }
  })
  rows
}

let firstParsedLine = (lines, predicate) => {
  lines->Array.findMap(line => {
    if predicate(line) {
      try {
        Some(JSON.parseExn(line))
      } catch {
      | _ => None
      }
    } else {
      None
    }
  })
}

let lastParsedLine = (lines, predicate) => {
  lines
  ->Array.toReversed
  ->Array.findMap(line => {
    if predicate(line) {
      try {
        Some(JSON.parseExn(line))
      } catch {
      | _ => None
      }
    } else {
      None
    }
  })
}

let countLines = (lines, predicate) => {
  lines->Array.filter(predicate)->Array.length
}

let isUserOrAssistantLine = line => {
  JsonUtil.hasJsonField(line, "role", "user") || JsonUtil.hasJsonField(line, "role", "assistant")
}

// Prefilter cheaply with a substring check, then parse only candidate lines.
let lastTimestampFromLines = lines =>
  lines
  ->Array.toReversed
  ->Array.findMap(line =>
    if line->String.includes("\"timestamp\"") {
      switch JSON.parseExn(line) {
      | json =>
        let ts = JsonUtil.toMs(
          json->JSON.Decode.object->Option.flatMap(obj => obj->Dict.get("timestamp")),
        )
        ts > 0.0 ? Some(ts) : None
      | exception _ => None
      }
    } else {
      None
    }
  )
  ->Option.getOr(0.0)

let fileMtimeMs = async path => {
  try {
    (await stat(path))->mtimeMs
  } catch {
  | _ => 0.0
  }
}
