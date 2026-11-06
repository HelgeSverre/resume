open TestSupport

@send external repeat: (string, int) => string = "repeat"

let object = JsonUtil.object
let string = JsonUtil.string
let text = value => JSON.Encode.array([object([("type", string("text")), ("text", string(value))])])

test("Claude custom titles take precedence over generated titles", async context => {
  let directory = await fixture(context, "resume-claude-title-")
  let path = NodePath.join(directory, "session.jsonl")
  await writeJsonl(
    path,
    [
      object([
        ("type", string("user")),
        ("sessionId", string("claude-custom")),
        ("cwd", string("/fixture")),
        ("message", object([("content", text("prompt"))])),
      ]),
      object([("type", string("ai-title")), ("aiTitle", string("Generated title"))]),
      object([("type", string("custom-title")), ("customTitle", string("   "))]),
      object([("type", string("custom-title")), ("customTitle", string("Chosen title"))]),
      object([("type", string("assistant")), ("message", object([("content", text("response"))]))]),
    ],
  )
  let session = await Claude.parseClaudeFile(path)
  equal(session.id, "claude-custom")
  equal(session.title, "Chosen title")
  equal(session.messageCount, 2)
  equal(session.preview, "response")
})

test("Codex streams a large valid rollout and caps its preview", async context => {
  let directory = await fixture(context, "resume-codex-stream-")
  let path = NodePath.join(
    directory,
    "rollout-2026-11-03T13-41-34-01a1a16d-dfb2-73e3-b5d2-705da3ca4218.jsonl",
  )
  let huge = "x"->repeat(17000)
  await writeJsonl(
    path,
    [
      object([
        ("type", string("session_meta")),
        ("timestamp", string("2026-01-01T00:00:00Z")),
        ("payload", object([("id", string("codex-stream")), ("cwd", string("/fixture"))])),
      ]),
      object([
        ("type", string("response_item")),
        ("timestamp", string("2026-01-01T00:00:01Z")),
        ("payload", object([("role", string("user")), ("content", string("first"))])),
      ]),
      object([
        ("type", string("response_item")),
        ("timestamp", string("2026-01-01T00:00:02Z")),
        ("payload", object([("role", string("assistant")), ("content", string(huge))])),
      ]),
    ],
  )
  let session = await Codex.parseCodexFile(path)
  equal(session.id, "codex-stream")
  equal(session.cwd, Some("/fixture"))
  equal(session.messageCount, 2)
  equal(session.updatedAtMs, 1767225602000.0)
  equal(session.preview->String.length, 16000)
})

test("Codex extracts a current rollout UUID without metadata", async context => {
  let id = "01a1a16d-dfb2-73e3-b5d2-705da3ca4218"
  let directory = await fixture(context, "resume-codex-id-")
  let path = NodePath.join(directory, "rollout-2026-11-03T13-41-34-" ++ id ++ ".jsonl")
  await writeJsonl(
    path,
    [
      object([
        ("type", string("response_item")),
        ("timestamp", string("2026-01-01T00:00:00Z")),
        ("payload", object([("role", string("user")), ("content", string("prompt"))])),
      ]),
    ],
  )
  equal((await Codex.parseCodexFile(path)).id, id)
})

test("streaming parsers retain records after malformed JSONL", async context => {
  let directory = await fixture(context, "resume-stream-malformed-")
  let claude = NodePath.join(directory, "claude.jsonl")
  let codex = NodePath.join(
    directory,
    "rollout-2026-11-03T13-41-34-01a1a16d-dfb2-73e3-b5d2-705da3ca4218.jsonl",
  )
  await writeFile(
    claude,
    "{not json}\n{\"type\":\"user\",\"sessionId\":\"claude\",\"message\":{\"content\":\"works\"}}",
  )
  await writeFile(codex, "{not json}\n{\"type\":\"session_meta\",\"payload\":{\"id\":\"codex\"}}")
  equal((await Claude.parseClaudeFile(claude)).id, "claude")
  equal((await Codex.parseCodexFile(codex)).id, "codex")
})
