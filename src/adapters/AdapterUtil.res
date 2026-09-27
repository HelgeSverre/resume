// Adapter utilities - shared helpers for filesystem scanning and JSONL parsing

open NodeFs

@val external promiseAll: array<promise<'a>> => promise<array<'a>> = "Promise.all"

// Keep file reads bounded: a large history can otherwise load thousands of
// multi-megabyte session files into memory at once.
let mapBounded = async (items: array<'a>, fn: 'a => promise<'b>): array<'b> => {
  let results = []
  let size = 8
  let offset = ref(0)
  while offset.contents < items->Array.length {
    let endIndex = min(offset.contents + size, items->Array.length)
    let chunk = items->Array.slice(~start=offset.contents, ~end=endIndex)
    let values = await promiseAll(chunk->Array.map(fn))
    values->Array.forEach(value => results->Array.push(value))
    offset.contents = endIndex
  }
  results
}

let all = async promises => await promiseAll(promises)

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

let collectCachedSessions = async (~root, ~matches, ~namespace, ~parse, cache) => {
  let files = await walkFiles(root, matches)
  let skipped = ref(0)
  let sessions = await mapBounded(files, async path => {
    try {
      Some(
        await Cache.cachedValue(
          cache,
          ~namespace,
          path,
          ~encode=Session.encode,
          ~decode=Session.decode,
          parse,
        ),
      )
    } catch {
    | _ => {
        skipped.contents = skipped.contents + 1
        None
      }
    }
  })
  if skipped.contents > 0 {
    Console.error(
      `Warning: skipped ${Int.toString(skipped.contents)} unreadable ${namespace} files`,
    )
  }
  sessions->Array.filterMap(session => session)
}

let splitLines = text => text->String.split("\n")

let readJsonl = async path => {
  let rows = []
  let lines = splitLines(await readFile(path, "utf8"))
  lines->Array.forEach(line => {
    if line->String.trim != "" {
      try {
        rows->Array.push(JSON.parseOrThrow(line))
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
