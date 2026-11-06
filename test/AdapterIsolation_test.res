open TestSupport

let json = JSON.parseOrThrow

test(
  "Amp gives untitled threads a conversational fallback and ignores trailing info",
  async context => {
    let home = await fixture(context, "resume-adapter-isolation-")
    let threads = NodePath.joinMany([home, ".local", "share", "amp", "threads"])
    await writeJson(
      NodePath.join(threads, "T-good.json"),
      json(`{"id":"T-good","messages":[{"role":"assistant","content":[{"text":"Useful answer"}]},{"role":"info","content":[{"text":"implementation detail"}]}]}`),
    )
    // A file with no thread id is a valid JSON document but not a valid Amp thread.
    await writeJson(NodePath.join(threads, "T-malformed.json"), json(`{"messages":[]}`))

    let sessions = await Amp.collectAmp(home, await Cache.loadCache(home))
    deepEqual(sessions->Array.map(session => session.id), ["T-good"])
    equal(sessions->Array.get(0)->Option.map(session => session.title), Some("Useful answer"))
    equal(sessions->Array.get(0)->Option.map(session => session.preview), Some("Useful answer"))
  },
)

test("Junie keeps valid sessions when another events path is unreadable", async context => {
  let home = await fixture(context, "resume-adapter-isolation-")
  let root = NodePath.joinMany([home, ".junie", "sessions"])
  await writeJsonl(
    NodePath.join(root, "index.jsonl"),
    [
      json(`{"sessionId":"good","taskName":"Good","updatedAt":1}`),
      json(`{"sessionId":"bad","taskName":"Bad","updatedAt":1}`),
    ],
  )
  await writeJson(
    NodePath.joinMany([root, "good", "events.jsonl"]),
    json(`{"kind":"UserPromptEvent","prompt":"hello"}`),
  )
  await mkdir(NodePath.joinMany([root, "bad", "events.jsonl"]))

  let sessions = await Junie.collectJunie(home, await Cache.loadCache(home))
  deepEqual(sessions->Array.map(session => session.id), ["good"])
})

test("Kimi keeps valid sessions when another wire path is unreadable", async context => {
  let home = await fixture(context, "resume-adapter-isolation-")
  let root = NodePath.join(home, ".kimi-code")
  let good = NodePath.joinMany([root, "sessions", "good"])
  let bad = NodePath.joinMany([root, "sessions", "bad"])
  await writeJsonl(
    NodePath.join(root, "session_index.jsonl"),
    [
      json(`{"sessionId":"good","sessionDir":"${good}","workDir":"/good"}`),
      json(`{"sessionId":"bad","sessionDir":"${bad}","workDir":"/bad"}`),
    ],
  )
  await writeJson(
    NodePath.joinMany([good, "agents", "main", "wire.jsonl"]),
    json(`{"type":"context.append_message"}`),
  )
  await mkdir(NodePath.joinMany([bad, "agents", "main", "wire.jsonl"]))

  let sessions = await Kimi.collectKimi(home, await Cache.loadCache(home))
  deepEqual(sessions->Array.map(session => session.id), ["good"])
})
