// Node's built-in SQLite reader. Keep every connection read-only and short-lived.
type database
type statement

@module("node:sqlite") @new
external openReadOnly: (string, {"readOnly": bool}) => database = "DatabaseSync"

@send external prepare: (database, string) => statement = "prepare"
@send external all: statement => array<JSON.t> = "all"
@send external close: database => unit = "close"

let query = (path, sql) => {
  let db = openReadOnly(path, {"readOnly": true})
  let rows = try {
    db->prepare(sql)->all
  } catch {
  | _ => {
      Console.error(`Warning: could not read SQLite sessions from ${path}`)
      []
    }
  }
  db->close
  rows
}
