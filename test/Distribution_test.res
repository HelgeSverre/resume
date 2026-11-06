open TestSupport

test("distribution contains and uses the SQLite worker", async context => {
  let npm = platform == "win32" ? "npm.cmd" : "npm"
  let packed = runSync(
    npm,
    ["pack", "--dry-run", "--json", "--ignore-scripts"],
    {cwd: root(), encoding: "utf8", timeout: 20000},
  )
  equal(packed.status, 0)
  ok(packed.stdout->String.includes("dist/resume.mjs"))
  ok(packed.stdout->String.includes("dist/NodeSqliteWorker.mjs"))

  let home = await fixture(context, "resume-dist-")
  let databasePath = NodePath.joinMany([home, ".local", "share", "opencode", "opencode.db"])
  await mkdir(NodePath.dirname(databasePath))
  sqlite(
    databasePath,
    "CREATE TABLE session(id TEXT, title TEXT, directory TEXT, time_updated INTEGER); " ++
    "CREATE TABLE message(id TEXT, session_id TEXT); " ++
    "INSERT INTO session VALUES ('distribution-fixture', 'Distribution fixture', '/fixture', 1); " ++ "INSERT INTO message VALUES ('message-1', 'distribution-fixture');",
  )

  let result = runSync(
    execPath,
    [NodePath.joinMany([root(), "dist", "resume.mjs"]), "--json"],
    {
      cwd: root(),
      env: environment(~home),
      encoding: "utf8",
      timeout: 20000,
      maxBuffer: 1048576,
    },
  )
  equal(result.status, 0)
  let rows = JSON.parseOrThrow(result.stdout)->JSON.Decode.array->Option.getOr([])
  let session =
    rows->Array.find(row => JsonUtil.stringAt(row, ["id"]) == Some("distribution-fixture"))
  switch session {
  | Some(session) => {
      equal(JsonUtil.stringAt(session, ["tool"]), Some("opencode"))
      equal(JsonUtil.stringAt(session, ["title"]), Some("Distribution fixture"))
      equal(JsonUtil.floatAt(session, ["messageCount"]), Some(1.0))
      equal(JsonUtil.stringAt(session, ["cwd"]), Some("/fixture"))
    }
  | None => throw(failure("distribution fixture session was not returned"))
  }
})
