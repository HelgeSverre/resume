open TestSupport

let createV2Database = (
  ~id="shared",
  ~title="Database title",
  ~cwd="/database",
  ~updated=100,
  home,
) => {
  let path = NodePath.joinMany([home, ".local", "share", "opencode", "opencode.db"])
  mkdir(NodePath.dirname(path))->Promise.then(_ => {
    sqlite(
      path,
      "CREATE TABLE session_v2 (id TEXT, title TEXT, directory TEXT, time_updated INTEGER); " ++
      "CREATE TABLE session_message (id TEXT, session_id TEXT, type TEXT); " ++
      `INSERT INTO session_v2 VALUES ('${id}', '${title}', '${cwd}', ${Int.toString(updated)}); ` ++
      `INSERT INTO session_message VALUES ('message-1', '${id}', 'user');`,
    )
    Promise.resolve(path)
  })
}

test("OpenCode keeps file metadata when v2 wins an equal timestamp", async context => {
  let home = await fixture(context, "resume-opencode-")
  let id = "ses_shared"
  let root = NodePath.joinMany([home, ".local", "share", "opencode", "storage"])
  await writeJson(
    NodePath.joinMany([root, "session", "project", id ++ ".json"]),
    JSON.parseOrThrow(
      `{"id":"${id}","title":"File title","directory":"/file","time":{"updated":100}}`,
    ),
  )
  await writeJson(
    NodePath.joinMany([root, "message", id, "message.json"]),
    JSON.parseOrThrow(`{"role":"assistant","time":{"created":100},"summary":{"title":"File preview"}}`),
  )
  let databasePath = await createV2Database(~id, ~title="", ~cwd="", ~updated=100, home)

  let sessions = await OpenCode.collectOpenCode(home, await Cache.loadCache(home))
  equal(sessions->Array.length, 1)
  switch sessions->Array.get(0) {
  | Some(session) => {
      equal(session.id, id)
      equal(session.tool, Session.OpenCode)
      equal(session.title, "File title")
      equal(session.messageCount, 1)
      equal(session.updatedAtMs, 100.0)
      equal(session.cwd, Some("/file"))
      equal(session.path, databasePath)
      equal(session.preview, "File preview")
    }
  | None => throw(failure("expected merged OpenCode session"))
  }
})

test("OpenCode database discovery works when Node uses input-type", async context => {
  let home = await fixture(context, "resume-opencode-input-type-")
  let _ = await createV2Database(~id="ses_v2", ~updated=100, home)
  let harnessUrl = NodeUrl.fileUrl(
    NodePath.joinMany([root(), "lib", "es6", "test", "fixtures", "OpenCodeInputHarness.mjs"]),
  )
  let script = "await import(" ++ JSON.stringify(JSON.Encode.string(harnessUrl)) ++ ");"
  let result = runSync(
    execPath,
    ["--input-type=module", "--eval", script],
    {encoding: "utf8", timeout: 20000, env: environment(~home)},
  )
  equal(result.status, 0)
  equal(result.stdout->String.trim, `["ses_v2"]`)
})
