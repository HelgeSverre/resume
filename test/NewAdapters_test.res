@module("node:test")
external testAsync: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

type db
@module("node:sqlite") @new external createDb: string => db = "DatabaseSync"
@send external exec: (db, string) => unit = "exec"
@send external close: db => unit = "close"

let makeDb = (path, sql) => {
  let db = createDb(path)
  db->exec(sql)
  db->close
}

let mkdir = path => NodeFs.mkdirWithRecursive(path, {"recursive": true})

testAsync("new adapters normalize anonymized local session formats", async () => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-new-adapters-"))

  let geminiRoot = NodePath.joinMany([home, ".gemini", "tmp", "project-one", "chats"])
  await mkdir(geminiRoot)
  await NodeFs.writeFile(
    NodePath.joinMany([home, ".gemini", "projects.json"]),
    `{"projects":{"/repo/gemini":"project-one"}}`,
  )
  await NodeFs.writeFile(
    NodePath.join(geminiRoot, "session-one.json"),
    `{"sessionId":"gemini-json","lastUpdated":"2026-05-30T01:00:00Z","summary":"Gemini JSON","messages":[{"type":"user","content":"first prompt"},{"type":"gemini","content":"last answer"}]}`,
  )
  await NodeFs.writeFile(
    NodePath.join(geminiRoot, "session-two.jsonl"),
    `{"sessionId":"gemini-jsonl","lastUpdated":"2026-05-30T02:00:00Z","kind":"session"}\n{"$set":{"lastUpdated":"2026-05-30T02:01:00Z","messages":[{"type":"user","content":"second prompt"}]}}\n`,
  )

  let vibeRoot = NodePath.joinMany([home, ".vibe", "logs", "session", "session-one"])
  await mkdir(vibeRoot)
  await NodeFs.writeFile(
    NodePath.join(vibeRoot, "meta.json"),
    `{"session_id":"vibe-1","title":"Vibe title","end_time":"2026-05-30T03:00:00Z","environment":{"working_directory":"/repo/vibe"}}`,
  )
  await NodeFs.writeFile(
    NodePath.join(vibeRoot, "messages.jsonl"),
    `{"role":"user","content":"vibe prompt"}\n{"role":"assistant","content":"vibe answer"}\n`,
  )

  let agyRoot = NodePath.joinMany([home, ".gemini", "antigravity-cli", "conversations"])
  await mkdir(agyRoot)
  makeDb(
    NodePath.join(agyRoot, "agy-db.db"),
    "CREATE TABLE steps (idx INTEGER PRIMARY KEY); INSERT INTO steps VALUES (1);",
  )
  makeDb(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "conversation_summaries.db"]),
    "CREATE TABLE conversation_summaries (conversation_id TEXT, title TEXT, preview TEXT, step_count INTEGER, last_modified_time TEXT, workspace_uris TEXT); " ++ "INSERT INTO conversation_summaries VALUES ('agy-db','AGY title','AGY preview',1,'2026-05-30T04:00:00Z','[\"file:///repo/agy\"]');",
  )

  let kiloRoot = NodePath.joinMany([home, ".local", "share", "kilo"])
  await mkdir(kiloRoot)
  makeDb(
    NodePath.join(kiloRoot, "kilo.db"),
    "CREATE TABLE session (id TEXT, title TEXT, directory TEXT, time_updated INTEGER); " ++
    "CREATE TABLE message (session_id TEXT); " ++
    "INSERT INTO session VALUES ('kilo-1','Kilo title','/repo/kilo',1770000000000); " ++ "INSERT INTO message VALUES ('kilo-1');",
  )

  let openCodeRoot = NodePath.joinMany([home, ".local", "share", "opencode"])
  await mkdir(openCodeRoot)
  makeDb(
    NodePath.join(openCodeRoot, "opencode.db"),
    "CREATE TABLE session (id TEXT, title TEXT, directory TEXT, time_updated INTEGER); " ++
    "CREATE TABLE message (session_id TEXT); " ++
    "INSERT INTO session VALUES ('opencode-db-1','OpenCode DB title','/repo/opencode',1770000000000); " ++ "INSERT INTO message VALUES ('opencode-db-1');",
  )

  let hermesRoot = NodePath.join(home, ".hermes")
  await mkdir(hermesRoot)
  makeDb(
    NodePath.join(hermesRoot, "state.db"),
    "CREATE TABLE sessions (id TEXT, title TEXT, display_name TEXT, cwd TEXT, message_count INTEGER, " ++
    "last_activity_at REAL, ended_at REAL, started_at REAL, last_activity_description TEXT, " ++
    "source TEXT, hidden INTEGER); " ++ "INSERT INTO sessions VALUES ('hermes-1','Hermes title',NULL,'/repo/hermes',2,1770000000,NULL,NULL,'hermes preview','cli',0);",
  )

  let devinRoot = NodePath.joinMany([home, ".local", "share", "devin", "cli"])
  await mkdir(devinRoot)
  makeDb(
    NodePath.join(devinRoot, "sessions.db"),
    "CREATE TABLE sessions (id TEXT, title TEXT, working_directory TEXT, last_activity_at INTEGER, created_at INTEGER, hidden INTEGER); " ++
    "CREATE TABLE message_nodes (session_id TEXT); " ++
    "INSERT INTO sessions VALUES ('devin-1','Devin title','/repo/devin',1770000000,1769999000,0); " ++ "INSERT INTO message_nodes VALUES ('devin-1');",
  )

  let sessions = await Adapters.collectSessionsFromHome(home)
  equal(sessions->Array.length, 8)
  let get = id => sessions->Array.find(session => session.id == id)
  equal(get("gemini-json")->Option.map(s => s.cwd), Some(Some("/repo/gemini")))
  equal(get("gemini-jsonl")->Option.map(s => s.title), Some("second prompt"))
  equal(get("vibe-1")->Option.map(s => s.preview), Some("vibe answer"))
  equal(get("agy-db")->Option.map(s => s.messageCount), Some(1))
  equal(get("agy-db")->Option.map(s => s.title), Some("AGY title"))
  equal(get("agy-db")->Option.map(s => s.cwd), Some(Some("/repo/agy")))
  equal(get("kilo-1")->Option.map(s => s.messageCount), Some(1))
  equal(get("opencode-db-1")->Option.map(s => s.messageCount), Some(1))
  equal(get("hermes-1")->Option.map(s => s.updatedAtMs), Some(1770000000000.0))
  equal(get("devin-1")->Option.map(s => s.cwd), Some(Some("/repo/devin")))
  equal(get("devin-1")->Option.map(s => s.messageCount), Some(1))
})
