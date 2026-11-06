// Shared typed host bindings and fixture lifecycle for the test suite.
type context
@module("node:test") external test: (string, context => promise<unit>) => unit = "test"
@module("node:test") external testSync: (string, context => unit) => unit = "test"
@module("node:test")
external testWithOptions: (string, {"skip": bool}, context => promise<unit>) => unit = "test"
@send external after: (context, unit => promise<unit>) => unit = "after"
@module("node:assert/strict") external equal: ('a, 'a) => unit = "equal"
@module("node:assert/strict") external notEqual: ('a, 'a) => unit = "notEqual"
@module("node:assert/strict") external deepEqual: ('a, 'a) => unit = "deepEqual"
@module("node:assert/strict") external ok: bool => unit = "ok"
@new external failure: string => exn = "Error"
@module("node:process") external execPath: string = "execPath"
@module("node:process") external platform: string = "platform"
@module("node:process") external root: unit => string = "cwd"
@module("node:fs/promises")
external remove: (string, {"recursive": bool, "force": bool}) => promise<unit> = "rm"
@module("node:fs/promises") external realpath: string => promise<string> = "realpath"
@module("node:fs/promises") external readdir: string => promise<array<string>> = "readdir"
@module("node:fs/promises") external chmod: (string, int) => promise<unit> = "chmod"
@module("node:fs/promises") external utimes: (string, float, float) => promise<unit> = "utimes"
@module("node:fs") external openSync: (string, string) => int = "openSync"
@module("node:fs") external closeSync: int => unit = "closeSync"
let mkdir = path => NodeFs.mkdirWithRecursive(path, {"recursive": true})
let readFile = path => NodeFs.readPersistentFile(path, "utf8")
let writeFile = (path, text) => NodeFs.writeFile(path, text)
let fixture = async (context, prefix) => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), prefix))
  context->after(() => remove(home, {"recursive": true, "force": true}))
  home
}
let writeJson = async (path, value) => {
  await mkdir(NodePath.dirname(path))
  await writeFile(path, JSON.stringify(value))
}
let writeJsonl = async (path, rows) => {
  await mkdir(NodePath.dirname(path))
  await writeFile(path, rows->Array.map(row => JSON.stringify(row))->Array.join("\n") ++ "\n")
}
let environment = (~home, ~extra=[]) => {
  let env = NodeProcess.env->Dict.toArray->Dict.fromArray
  env->Dict.set("HOME", home)
  extra->Array.forEach(((key, value)) => env->Dict.set(key, value))
  env
}
let runSync = NodeChildProcess.runSync
let runCapture = NodeChildProcess.runCapture
let rejects = async operation => {
  let failed = ref(false)
  try {
    let _ = await operation()
  } catch {
  | _ => failed.contents = true
  }
  equal(failed.contents, true)
}
type database
@module("node:sqlite") @new external openDatabase: string => database = "DatabaseSync"
@send external execSql: (database, string) => unit = "exec"
@send external closeDatabase: database => unit = "close"
let sqlite = (path, sql) => {
  let db = openDatabase(path)
  try {db->execSql(sql)} catch {
  | error =>
    db->closeDatabase
    throw(error)
  }
  db->closeDatabase
}

let openWrite = path => openSync(path, "w")
let closeFd = closeSync
