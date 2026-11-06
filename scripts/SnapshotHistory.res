// macOS/APFS benchmark helper: immutable copy-on-write files, no history output.
// Refuses overwrites. SQLite read transactions prevent WAL resets during clones.

type database
type statement
@module("node:fs/promises")
external createPrivateDirectory: (string, {"mode": int}) => promise<unit> = "mkdir"
@module("node:fs/promises")
external createPrivateParents: (string, {"recursive": bool, "mode": int}) => promise<unit> = "mkdir"
@module("node:fs/promises")
external removeTree: (string, {"recursive": bool, "force": bool}) => promise<unit> = "rm"

@module("node:path")
external resolve: string => string = "resolve"

@module("node:process")
external platform: string = "platform"

@module("node:sqlite") @new
external openReadOnly: (string, {"readOnly": bool}) => database = "DatabaseSync"
@send external execute: (database, string) => unit = "exec"
@send external prepare: (database, string) => statement = "prepare"
@send external get: statement => unit = "get"
@send external close: database => unit = "close"

@new external error: string => exn = "Error"

// Async Node errors are wrapped by ReScript. This narrow FFI preserves the
// original distinction: only genuinely absent inputs are skipped.
let isMissingFsError: exn => bool = %raw(`error => {
  const raw = error?.RE_EXN_ID === "JsExn" ? error._1 : error;
  return raw?.code === "ENOENT";
}`)

let source = switch NodeProcess.env->Dict.get("HOME") {
| Some(home) if home != "" => home
| _ => NodeProcess.homedir()
}

let roots = [
  ".claude/projects",
  ".codex/sessions",
  ".codex/archived_sessions",
  ".codex/session_index.jsonl",
  ".local/share/amp/threads",
  ".local/share/opencode/storage",
  ".kimi-code/session_index.jsonl",
  ".kimi-code/sessions",
  ".copilot/session-state",
  ".junie/sessions",
  ".pi/agent/sessions",
  ".gemini/projects.json",
  ".gemini/tmp",
  ".gemini/antigravity-cli/conversations",
  ".gemini/antigravity-cli/brain",
  ".gemini/antigravity-cli/cache",
  ".vibe/logs/session",
  "Library/Application Support/poolside/acp",
]

let databases = [
  ".local/share/opencode/opencode.db",
  ".local/share/kilo/kilo.db",
  ".local/share/devin/cli/sessions.db",
  ".hermes/state.db",
  ".gemini/antigravity-cli/conversation_summaries.db",
]

let exec = NodeChildProcess.runCapture

let clone = async (file, target) => {
  let present = try {
    let _ = await NodeFs.access(file)
    true
  } catch {
  | error => isMissingFsError(error) ? false : throw(error)
  }

  // An absent root is deliberately skipped. Other access errors propagate,
  // rather than becoming a silent omission.
  if present {
    await createPrivateParents(NodePath.dirname(target), {"recursive": true, "mode": 448})
    let _ = await exec("/bin/cp", ["-cR", file, target])
  }
}

let cloneDatabase = async (relative, destination) => {
  let file = NodePath.join(source, relative)
  let target = NodePath.join(destination, relative)
  let present = try {
    let _ = await NodeFs.access(file)
    true
  } catch {
  | error => isMissingFsError(error) ? false : throw(error)
  }

  if present {
    let database = openReadOnly(file, {"readOnly": true})
    try {
      database->execute("BEGIN")
      let _ = database->prepare("SELECT COUNT(*) FROM sqlite_master")->get
      await clone(file, target)
      await clone(file ++ "-wal", target ++ "-wal")
      database->execute("ROLLBACK")
      database->close
    } catch {
    | error => {
        database->close
        throw(error)
      }
    }
  }
}

let rewriteKimiIndex = async destination => {
  let index = NodePath.joinMany([destination, ".kimi-code", "session_index.jsonl"])
  try {
    let rows =
      (await NodeFs.readPersistentFile(index, "utf8"))
      ->String.split("\n")
      ->Array.filter(line => line != "")
      ->Array.map(line =>
        try {
          let row = JSON.parseOrThrow(line)
          let rewritten = switch JSON.Decode.object(row) {
          | Some(object) =>
            switch object->Dict.get("sessionDir")->Option.flatMap(JSON.Decode.string) {
            | Some(sessionDir) if sessionDir->String.startsWith(source ++ NodePath.sep) =>
              object->Dict.set(
                "sessionDir",
                JSON.Encode.string(
                  destination ++ sessionDir->String.slice(~start=source->String.length),
                ),
              )
            | _ => ()
            }
            JSON.Object(object)->JSON.stringify
          | None => line
          }
          rewritten
        } catch {
        | _ => line
        }
      )
    await NodeFs.writeFile(index, rows->Array.join("\n") ++ "\n")
  } catch {
  | error => isMissingFsError(error) ? () : throw(error)
  }
}

let rec cloneRoots = async (destination, index) => {
  if index < roots->Array.length {
    switch roots->Array.get(index) {
    | Some(relative) => {
        await clone(NodePath.join(source, relative), NodePath.join(destination, relative))
        await cloneRoots(destination, index + 1)
      }
    | None => ()
    }
  }
}

let rec cloneDatabases = async (destination, index) => {
  if index < databases->Array.length {
    switch databases->Array.get(index) {
    | Some(relative) => {
        await cloneDatabase(relative, destination)
        await cloneDatabases(destination, index + 1)
      }
    | None => ()
    }
  }
}

let main = async () => {
  let first = NodeProcess.argv->Array.get(2)
  if first == Some("--help") || first == Some("-h") {
    Console.log("Usage: node lib/es6/scripts/SnapshotHistory.mjs NEW_DESTINATION (macOS/APFS)")
  } else {
    if platform != "darwin" {
      throw(error("This snapshot helper requires macOS copy-on-write cp -c support"))
    }

    let destination = switch NodeProcess.argv->Array.get(2) {
    | Some(value) if value != "" => resolve(value)
    | _ => throw(error("Usage: node lib/es6/scripts/SnapshotHistory.mjs NEW_DESTINATION"))
    }

    // This intentionally sits before the protected block. A pre-existing
    // destination must fail without risking cleanup of user-owned data.
    await createPrivateDirectory(destination, {"mode": 448})

    try {
      await cloneRoots(destination, 0)
      await cloneDatabases(destination, 0)
      await rewriteKimiIndex(destination)
      Console.log(destination)
    } catch {
    | error => {
        await removeTree(destination, {"recursive": true, "force": true})
        throw(error)
      }
    }
  }
}

await main()
