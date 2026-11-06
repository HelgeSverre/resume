open TestSupport

let json = JSON.parseOrThrow

test("Gemini replays raw JSONL messages and later metadata updates", async context => {
  let home = await fixture(context, "resume-replay-")
  let file = NodePath.joinMany([
    home,
    ".gemini",
    "tmp",
    "project",
    "chats",
    "session-current.jsonl",
  ])
  await writeJsonl(
    file,
    [
      json(`{"sessionId":"current","projectHash":"project","summary":"old summary","lastUpdated":"2026-01-01T00:00:00Z"}`),
      json(`{"id":"user-1","type":"user","content":"first prompt"}`),
      json(`{"id":"assistant-1","type":"gemini","content":"first response"}`),
      json(`{"$set":{"summary":"new summary","lastUpdated":"2026-01-02T00:00:00Z"}}`),
      json(`{"id":"assistant-1","type":"gemini","content":"updated response"}`),
    ],
  )

  let session = (await Gemini.collectGemini(home))->Array.get(0)
  equal(session->Option.map(session => session.id), Some("current"))
  equal(session->Option.map(session => session.title), Some("new summary"))
  equal(session->Option.map(session => session.preview), Some("updated response"))
  equal(session->Option.map(session => session.messageCount), Some(2))
  equal(session->Option.map(session => session.updatedAtMs), Some(1767312000000.0))
})

test("Gemini applies rewinds before later raw records", async context => {
  let home = await fixture(context, "resume-replay-")
  let file = NodePath.joinMany([home, ".gemini", "tmp", "project", "chats", "session-rewind.jsonl"])
  await writeJsonl(
    file,
    [
      json(`{"sessionId":"rewind","projectHash":"project"}`),
      json(`{"id":"user-1","type":"user","content":"keep"}`),
      json(`{"id":"assistant-1","type":"gemini","content":"discard"}`),
      json(`{"id":"user-2","type":"user","content":"also discard"}`),
      json(`{"$rewindTo":"assistant-1"}`),
      json(`{"id":"assistant-2","type":"gemini","content":"replacement"}`),
    ],
  )

  let session = (await Gemini.collectGemini(home))->Array.get(0)
  equal(session->Option.map(session => session.messageCount), Some(2))
  equal(session->Option.map(session => session.title), Some("keep"))
  equal(session->Option.map(session => session.preview), Some("replacement"))
})

test("Antigravity ignores a database without its conversation steps table", async context => {
  let home = await fixture(context, "resume-replay-")
  let conversations = NodePath.joinMany([home, ".gemini", "antigravity-cli", "conversations"])
  await mkdir(conversations)
  sqlite(NodePath.join(conversations, "unrelated.db"), "CREATE TABLE unrelated (id TEXT)")
  sqlite(NodePath.join(conversations, "conversation.db"), "CREATE TABLE steps (idx INTEGER)")
  // The collector treats a protobuf as opaque; JSON bytes are sufficient for a fixture.
  await writeJson(NodePath.join(conversations, "opaque.pb"), json(`{"fixture":true}`))

  let sessions = await Antigravity.collectAntigravity(home)
  equal(sessions->Array.length, 2)
  ok(sessions->Array.some(session => session.id == "conversation"))
  ok(sessions->Array.some(session => session.id == "opaque"))
})
