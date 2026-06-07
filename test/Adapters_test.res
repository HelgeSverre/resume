@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:test")
external testAsync: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

let assertEqual = (actual, expected, label) => {
  if actual != expected {
    Console.error("FAIL: " ++ label)
    Console.error("  expected: " ++ JSON.stringifyAny(expected)->Option.getOr("?"))
    Console.error("  actual:   " ++ JSON.stringifyAny(actual)->Option.getOr("?"))
  }
  equal(actual, expected)
}

let writeJsonl = async (path, rows) => {
  let content = rows->Array.map(row => JSON.stringify(row))->Array.join("\n") ++ "\n"
  await NodeFs.writeFile(path, content)
}

testAsync("collects normalized sessions from supported local agent stores", async () => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-fixtures-"))

  // Codex
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".codex", "sessions", "2026", "05", "30"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "session_index.jsonl"]),
    [
      JSON.parseOrThrow(`{"id":"codex-1","thread_name":"Codex title","updated_at":"2026-05-30T05:00:00.000Z"}`),
    ],
  )
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "sessions", "2026", "05", "30", "rollout-codex-1.jsonl"]),
    [
      JSON.parseOrThrow(`{"timestamp":"2026-05-30T04:59:00.000Z","type":"session_meta","payload":{"id":"codex-1","cwd":"/repo/codex"}}`),
      JSON.parseOrThrow(`{"timestamp":"2026-05-30T05:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"codex preview"}]}}`),
    ],
  )

  // Claude
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".claude", "projects", "-repo-claude"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([home, ".claude", "projects", "-repo-claude", "claude-1.jsonl"]),
    [
      JSON.parseOrThrow(`{"type":"ai-title","sessionId":"claude-1","aiTitle":"Claude title"}`),
      JSON.parseOrThrow(`{"type":"user","sessionId":"claude-1","timestamp":"2026-05-30T04:00:00.000Z","cwd":"/repo/claude","message":{"role":"user","content":"claude preview"}}`),
      JSON.parseOrThrow(`{"type":"assistant","sessionId":"claude-1","timestamp":"2026-05-30T04:01:00.000Z","cwd":"/repo/claude","message":{"role":"assistant","content":[{"type":"text","text":"answer"}]}}`),
    ],
  )

  // Junie
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".junie", "sessions", "junie-1"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([home, ".junie", "sessions", "index.jsonl"]),
    [
      JSON.parseOrThrow(`{"sessionId":"junie-1","taskName":"Junie title","projectDir":"/repo/junie","createdAt":1770000000000,"updatedAt":1770000100000}`),
    ],
  )
  await writeJsonl(
    NodePath.joinMany([home, ".junie", "sessions", "junie-1", "events.jsonl"]),
    [
      JSON.parseOrThrow(`{"kind":"UserPromptEvent","prompt":"junie preview"}`),
      JSON.parseOrThrow(`{"kind":"TaskState","text":"working"}`),
    ],
  )

  // Pi
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".pi", "agent", "sessions", "--repo-pi--"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([
      home,
      ".pi",
      "agent",
      "sessions",
      "--repo-pi--",
      "2026-05-30T01-00-00-000Z_pi-1.jsonl",
    ]),
    [
      JSON.parseOrThrow(`{"type":"session","id":"pi-1","timestamp":"2026-05-30T01:00:00.000Z","cwd":"/repo/pi"}`),
      JSON.parseOrThrow(`{"type":"message","id":"m1","timestamp":"2026-05-30T01:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"pi preview"}]}}`),
    ],
  )

  // Amp
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".local", "share", "amp", "threads"]),
    {"recursive": true},
  )
  await NodeFs.writeFile(
    NodePath.joinMany([home, ".local", "share", "amp", "threads", "T-amp-1.json"]),
    `{"id":"T-amp-1","title":"Amp title","created":1770000200000,"env":{"initial":{"trees":[{"uri":"file:///repo/amp"}]}},"messages":[{"role":"user","meta":{"sentAt":1770000201000},"content":[{"type":"text","text":"amp preview"}]}]}`,
  )

  // OpenCode
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".local", "share", "opencode", "storage", "session", "project-1"]),
    {"recursive": true},
  )
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([
      home,
      ".local",
      "share",
      "opencode",
      "storage",
      "message",
      "ses_opencode_1",
    ]),
    {"recursive": true},
  )
  await NodeFs.writeFile(
    NodePath.joinMany([
      home,
      ".local",
      "share",
      "opencode",
      "storage",
      "session",
      "project-1",
      "ses_opencode_1.json",
    ]),
    `{"id":"ses_opencode_1","directory":"/repo/opencode","title":"OpenCode title","time":{"updated":1770000300000}}`,
  )
  await NodeFs.writeFile(
    NodePath.joinMany([
      home,
      ".local",
      "share",
      "opencode",
      "storage",
      "message",
      "ses_opencode_1",
      "msg_1.json",
    ]),
    `{"id":"msg_1","sessionID":"ses_opencode_1","role":"user","time":{"created":1770000301000},"summary":{"title":"opencode preview"}}`,
  )

  // Kimi
  let kimiDir = NodePath.joinMany([home, ".kimi-code", "sessions", "wd_kimi-1"])
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([kimiDir, "agents", "main"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([home, ".kimi-code", "session_index.jsonl"]),
    [
      JSON.parseOrThrow(
        `{"sessionId":"ses_kimi-1","sessionDir":"${kimiDir}","workDir":"/repo/kimi"}`,
      ),
    ],
  )
  await NodeFs.writeFile(
    NodePath.join(kimiDir, "state.json"),
    `{"title":"Kimi title","createdAt":"2026-05-30T02:00:00.000Z","updatedAt":"2026-05-30T02:05:00.000Z","lastPrompt":"kimi preview"}`,
  )
  await writeJsonl(
    NodePath.joinMany([kimiDir, "agents", "main", "wire.jsonl"]),
    [
      JSON.parseOrThrow(`{"type":"metadata","protocol_version":"1.2"}`),
      JSON.parseOrThrow(`{"type":"context.append_message","message":{"role":"user","content":[{"type":"text","text":"kimi preview"}]}}`),
      JSON.parseOrThrow(`{"type":"context.append_message","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}`),
    ],
  )

  // Copilot
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".copilot", "session-state", "copilot-1"]),
    {"recursive": true},
  )
  await writeJsonl(
    NodePath.joinMany([home, ".copilot", "session-state", "copilot-1", "events.jsonl"]),
    [
      JSON.parseOrThrow(`{"type":"session.start","data":{"sessionId":"copilot-1","context":{"cwd":"/repo/copilot"}},"timestamp":"2026-05-30T03:00:00.000Z"}`),
      JSON.parseOrThrow(`{"type":"user.message","data":{"content":"copilot title"},"timestamp":"2026-05-30T03:01:00.000Z"}`),
      JSON.parseOrThrow(`{"type":"assistant.message","data":{"content":"copilot preview"},"timestamp":"2026-05-30T03:02:00.000Z"}`),
    ],
  )

  // Antigravity
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "conversations"]),
    {"recursive": true},
  )
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "brain", "agy-1"]),
    {"recursive": true},
  )
  await NodeFs.mkdirWithRecursive(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "cache"]),
    {"recursive": true},
  )
  await NodeFs.writeFile(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "conversations", "agy-1.pb"]),
    "synthetic-protobuf-bytes",
  )
  await NodeFs.writeFile(
    NodePath.joinMany([
      home,
      ".gemini",
      "antigravity-cli",
      "brain",
      "agy-1",
      "task.md.metadata.json",
    ]),
    `{"artifactType":"ARTIFACT_TYPE_TASK","summary":"antigravity summary","updatedAt":"2026-05-30T06:00:00.000Z"}`,
  )
  await NodeFs.writeFile(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "cache", "last_conversations.json"]),
    `{"/repo/antigravity":"agy-1"}`,
  )

  let sessions = await Adapters.collectSessionsFromHome(home)

  let byTool = sessions->Array.reduce(Dict.make(), (dict, session) => {
    dict->Dict.set(session.tool->Session.toolToString, session)
    dict
  })

  assertEqual(sessions->Array.length, 9, "expected 9 sessions")

  let codex = byTool->Dict.get("Codex")
  assertEqual(codex->Option.map(s => s.title), Some("Codex title"), "Codex title")

  let claude = byTool->Dict.get("Claude")
  assertEqual(claude->Option.map(s => s.messageCount), Some(2), "Claude messageCount")

  let junie = byTool->Dict.get("Junie")
  assertEqual(junie->Option.map(s => s.preview), Some("junie preview"), "Junie preview")

  let pi = byTool->Dict.get("Pi")
  assertEqual(pi->Option.map(s => s.cwd), Some(Some("/repo/pi")), "Pi cwd")

  let amp = byTool->Dict.get("Amp")
  assertEqual(amp->Option.map(s => s.preview), Some("amp preview"), "Amp preview")

  let opencode = byTool->Dict.get("OpenCode")
  assertEqual(opencode->Option.map(s => s.cwd), Some(Some("/repo/opencode")), "OpenCode cwd")

  let kimi = byTool->Dict.get("Kimi")
  assertEqual(kimi->Option.map(s => s.title), Some("Kimi title"), "Kimi title")
  assertEqual(kimi->Option.map(s => s.preview), Some("kimi preview"), "Kimi preview")
  assertEqual(kimi->Option.map(s => s.cwd), Some(Some("/repo/kimi")), "Kimi cwd")
  assertEqual(kimi->Option.map(s => s.messageCount), Some(2), "Kimi messageCount")

  let copilot = byTool->Dict.get("Copilot")
  assertEqual(copilot->Option.map(s => s.title), Some("copilot title"), "Copilot title")
  assertEqual(copilot->Option.map(s => s.preview), Some("copilot preview"), "Copilot preview")
  assertEqual(copilot->Option.map(s => s.cwd), Some(Some("/repo/copilot")), "Copilot cwd")
  assertEqual(copilot->Option.map(s => s.messageCount), Some(2), "Copilot messageCount")

  let antigravity = byTool->Dict.get("Antigravity")
  assertEqual(
    antigravity->Option.map(s => s.title),
    Some("antigravity summary"),
    "Antigravity title",
  )
  assertEqual(
    antigravity->Option.map(s => s.cwd),
    Some(Some("/repo/antigravity")),
    "Antigravity cwd",
  )
  assertEqual(antigravity->Option.map(s => s.messageCount), Some(0), "Antigravity messageCount")
})

test("adapter registry names are unique", () => {
  let names = Adapters.registry->Array.map(a => a.name)
  let unique = names->Array.reduce(Dict.make(), (dict, name) => {
    dict->Dict.set(name, true)
    dict
  })
  equal(unique->Dict.keysToArray->Array.length, names->Array.length)
})
