open TestSupport

let picker = query => {
  Tui.sessions: [],
  version: "test",
  tools: [],
  query,
  selected: 0,
  offset: 0,
  notice: "",
  showExactTime: false,
  expanded: false,
  agentFilter: None,
}

test("search backspace removes one complete grapheme", async _ => {
  ["😀", "é", "👨‍👩‍👧‍👦"]->Array.forEach(character => {
    let state = picker("prefix" ++ character)
    let _ = Tui.update(state, Backspace, ~visible=[], ~rowsHeight=10)
    equal(state.query, "prefix")
  })
})

test("Claude retains the latest folder when subsequent messages omit cwd", async context => {
  let home = await fixture(context, "resume-claude-folder-")
  let path = NodePath.join(home, "session.jsonl")
  await writeFile(
    path,
    "{\"type\":\"user\",\"sessionId\":\"moved\",\"cwd\":\"/original\"}\n" ++
    "{\"type\":\"user\",\"sessionId\":\"moved\",\"cwd\":\"/current\"}\n" ++ "{\"type\":\"assistant\",\"sessionId\":\"moved\",\"message\":{\"content\":\"answer\"}}\n",
  )
  equal((await Claude.parseClaudeFile(path)).cwd, Some("/current"))
})

test("Claude activity time does not move backwards on delayed records", async context => {
  let home = await fixture(context, "resume-claude-time-")
  let path = NodePath.join(home, "session.jsonl")
  await writeFile(
    path,
    "{\"type\":\"user\",\"sessionId\":\"delayed\",\"timestamp\":\"2026-11-06T12:00:00Z\"}\n" ++ "{\"type\":\"assistant\",\"sessionId\":\"delayed\",\"timestamp\":\"2026-01-01T00:00:00Z\"}\n",
  )
  equal(
    (await Claude.parseClaudeFile(path)).updatedAtMs,
    JsonUtil.msFromString("2026-11-06T12:00:00Z"),
  )
})

test("Vibe activity advances when only the message log changes", async context => {
  let home = await fixture(context, "resume-vibe-activity-")
  let directory = NodePath.joinMany([home, ".vibe", "logs", "session", "active"])
  await mkdir(directory)
  let meta = NodePath.join(directory, "meta.json")
  let messages = NodePath.join(directory, "messages.jsonl")
  await writeFile(
    meta,
    "{\"session_id\":\"active\",\"environment\":{\"working_directory\":\"/project\"}}",
  )
  await writeFile(messages, "{\"role\":\"assistant\",\"content\":\"new answer\"}\n")
  await utimes(meta, 1767225600., 1767225600.)
  await utimes(messages, 1767312000., 1767312000.)
  let sessions = await Vibe.collectVibe(home)
  let session = sessions[0]->Option.getOrThrow
  equal(session.updatedAtMs, 1767312000000.)
})

test("title truncation preserves complete UTF-16 characters", async _ => {
  let prefix = "a"->String.repeat(136)
  let title = JsonUtil.compact(Some(prefix ++ "😀" ++ "b"->String.repeat(20)))
  equal(title, prefix ++ "...")
})

test(
  "Claude reparses cached metadata from before the folder and timestamp fixes",
  async context => {
    let home = await fixture(context, "resume-claude-cache-upgrade-")
    let directory = NodePath.joinMany([home, ".claude", "projects", "fixture"])
    await mkdir(directory)
    let path = NodePath.join(directory, "session.jsonl")
    await writeFile(path, "{\"type\":\"user\",\"sessionId\":\"moved\",\"cwd\":\"/current\"}\n")
    let correct = await Claude.parseClaudeFile(path)
    let cache = await Cache.loadCache(home)
    let _ = await Cache.cachedValue(
      cache,
      ~namespace="claude-session-v3",
      path,
      ~encode=Session.encode,
      ~decode=Session.decode,
      async _ => {...correct, cwd: Some("/original")},
    )
    let sessions = await Claude.collectClaude(home, cache)
    let session = sessions[0]->Option.getOrThrow
    equal(session.cwd, Some("/current"))
  },
)
