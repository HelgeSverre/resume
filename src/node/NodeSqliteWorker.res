// Separate entry point: copied beside the CLI bundle by the build.
type database
type statement
type port
type response = {rows: array<JSON.t>, failed: bool}
@module("node:sqlite") @new
external openReadOnly: (string, {"readOnly": bool}) => database = "DatabaseSync"
@send external prepare: (database, string) => statement = "prepare"
@send external all: statement => array<JSON.t> = "all"
@send external close: database => unit = "close"
@module("node:worker_threads")
external workerData: {"path": string, "sql": string} = "workerData"
@module("node:worker_threads")
external parentPort: port = "parentPort"
@send external postMessage: (port, response) => unit = "postMessage"

let failed = ref(false)
let rows = try {
  let db = openReadOnly(workerData["path"], {"readOnly": true})
  let rows = try {
    db->prepare(workerData["sql"])->all
  } catch {
  | _ => {
      failed.contents = true
      []
    }
  }
  db->close
  rows
} catch {
| _ => {
    failed.contents = true
    []
  }
}
parentPort->postMessage({rows, failed: failed.contents})
