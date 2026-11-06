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
external readFileUnbounded: (
  string,
  {"encoding": string, "signal": ScanControl.signal},
) => promise<string> = "readFile"

@module("node:fs/promises")
external readdirWithFileTypes: (string, {"withFileTypes": bool}) => promise<array<dirent>> =
  "readdir"

@module("node:fs/promises")
external stat: string => promise<stats> = "stat"

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

@module("node:fs/promises")
external rename: (string, string) => promise<unit> = "rename"
@module("node:fs/promises")
external unlink: string => promise<unit> = "unlink"

// One shared leaf-I/O budget across adapters, including nested OpenCode tasks.
// Reserve a queued slot before waking its waiter so a new caller cannot barge.
type gate = {mutable active: int, waiters: array<unit => unit>}
let readGate = {active: 0, waiters: []}
@send external shift: array<'a> => option<'a> = "shift"
let acquire = () => {
  if readGate.active >= 8 {
    Promise.make((resolve, _reject) => readGate.waiters->Array.push(resolve))
  } else {
    readGate.active = readGate.active + 1
    Promise.resolve()
  }
}
let release = () =>
  switch readGate.waiters->shift {
  | Some(next) => next()
  | None => readGate.active = readGate.active - 1
  }
let withReadSlot = async task => {
  await acquire()
  try {
    ScanControl.ensureActive()
    let result = await task()
    release()
    result
  } catch {
  | error =>
    release()
    throw(error)
  }
}

let readFile = (path, encoding) =>
  withReadSlot(() =>
    readFileUnbounded(path, {"encoding": encoding, "signal": ScanControl.getSignal()})
  )

type stream
@module("node:fs")
external createReadStream: (
  string,
  {"encoding": string, "highWaterMark": int, "signal": ScanControl.signal},
) => stream = "createReadStream"

// A total file can exceed V8's string limit. Only a bounded record is retained;
// exceptionally large individual records are skipped without losing the rest.
type iterator
type step = {done: bool, value: option<string>}
// Access to the symbol-named iterator is a narrow host boundary.
let iterate: stream => iterator = %raw(`stream => stream[Symbol.asyncIterator]()`)
@send external next: iterator => promise<step> = "next"
@send external destroy: stream => unit = "destroy"
@send external indexOfFrom: (string, string, int) => int = "indexOf"
type clock
@module("node:perf_hooks") external performance: clock = "performance"
@send external now: clock => float = "now"
@val external scheduleYield: (unit => unit) => unit = "setImmediate"
let yieldToInput = () => Promise.make((resolve, _reject) => scheduleYield(resolve))

let consumeLines = async (stream, onLine) => {
  let maximum = 64 * 1024 * 1024
  let tail = ref("")
  let dropping = ref(false)
  let skipped = ref(0)
  let first = ref(true)
  let yielded = ref(performance->now)
  let deliver = value => {
    let value = if first.contents && value->String.startsWith("\u{FEFF}") {
      value->String.slice(~start=1)
    } else {
      value
    }
    first.contents = false
    onLine(
      value->String.endsWith("\r")
        ? value->String.slice(~start=0, ~end=value->String.length - 1)
        : value,
    )
  }
  try {
    let iterator = iterate(stream)
    let continuing = ref(true)
    while continuing.contents {
      let step = await iterator->next
      if step.done {
        continuing.contents = false
      } else {
        switch step.value {
        | Some(chunk) =>
          let start = ref(0)
          let endIndex = ref(indexOfFrom(chunk, "\n", 0))
          while endIndex.contents >= 0 {
            let part = chunk->String.slice(~start=start.contents, ~end=endIndex.contents)
            if !dropping.contents && tail.contents->String.length + part->String.length <= maximum {
              deliver(tail.contents ++ part)
            } else if !dropping.contents {
              skipped.contents = skipped.contents + 1
            }
            tail.contents = ""
            dropping.contents = false
            start.contents = endIndex.contents + 1
            endIndex.contents = indexOfFrom(chunk, "\n", start.contents)
          }
          let rest = chunk->String.slice(~start=start.contents)
          if !dropping.contents {
            if tail.contents->String.length + rest->String.length <= maximum {
              tail.contents = tail.contents ++ rest
            } else {
              skipped.contents = skipped.contents + 1
              tail.contents = ""
              dropping.contents = true
            }
          }
          if performance->now -. yielded.contents >= 8.0 {
            await yieldToInput()
            yielded.contents = performance->now
          }
        | None => ()
        }
      }
    }
    if !dropping.contents && tail.contents != "" {
      deliver(tail.contents)
    }
  } catch {
  | error =>
    stream->destroy
    throw(error)
  }
  stream->destroy
  skipped.contents
}

let forEachLine = (path, visit) =>
  withReadSlot(async () => {
    let skipped = await consumeLines(
      createReadStream(
        path,
        {"encoding": "utf8", "highWaterMark": 65536, "signal": ScanControl.getSignal()},
      ),
      visit,
    )
    if skipped > 0 {
      Diagnostics.warn("Warning: skipped " ++ Int.toString(skipped) ++ " oversized JSONL records")
    }
  })

// Cache persistence must finish atomically even when interactive reads abort.
@module("node:fs/promises")
external readPersistentFile: (string, string) => promise<string> = "readFile"
