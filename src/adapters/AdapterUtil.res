// Adapter utilities - shared helpers for filesystem scanning and JSONL parsing

open NodeFs

@val external promiseAll: array<promise<'a>> => promise<array<'a>> = "Promise.all"

// Keep file reads bounded: a large history can otherwise load thousands of
// multi-megabyte session files into memory at once.
let mapBounded = (items, read) =>
  AsyncPool.map(~shouldContinue=() => !ScanControl.cancelled(), items, read)

let all = async promises => await promiseAll(promises)

let walkFiles = async (root, predicate) => {
  let rootExists = await exists(root)
  if !rootExists {
    []
  } else {
    let out = []
    let stack = [root]
    while stack->Array.length > 0 && !ScanControl.cancelled() {
      switch stack->Array.pop {
      | Some(dir) =>
        let entries = try {
          await readdirWithFileTypes(dir, {"withFileTypes": true})
        } catch {
        | _ =>
          Diagnostics.warn("Warning: skipped an unreadable session directory")
          []
        }
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

// All per-file/index collectors use this boundary so a single bad input
// cannot discard the rest of that tool's sessions.
let collectSome = async (~label, items, read) => {
  let skipped = ref(0)
  let sessions = await mapBounded(items, async item => {
    try {await read(item)} catch {
    | _ =>
      skipped.contents = skipped.contents + 1
      None
    }
  })
  if skipped.contents > 0 {
    Diagnostics.warn(
      "Warning: skipped " ++ Int.toString(skipped.contents) ++ " unreadable " ++ label ++ " files",
    )
  }
  sessions->Array.filterMap(session => session)
}

let collectCachedSessions = async (~root, ~matches, ~namespace, ~parse, cache) => {
  let files = await walkFiles(root, matches)
  await collectSome(~label=namespace, files, async path => Some(
    await Cache.cachedValue(
      cache,
      ~namespace,
      path,
      ~encode=Session.encode,
      ~decode=Session.decode,
      parse,
    ),
  ))
}

let splitLines = text => text->String.split("\n")

let readJsonl = JsonLines.read
let readIndex = async path =>
  try {await readJsonl(path)} catch {
  | _ =>
    Diagnostics.warn("Warning: could not read session index")
    []
  }

let firstParsedLine = (lines, predicate) => {
  lines->Array.findMap(line => {
    if predicate(line) {
      try {
        Some(JSON.parseOrThrow(line))
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
        Some(JSON.parseOrThrow(line))
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
      switch JSON.parseOrThrow(line) {
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
