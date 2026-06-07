@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

@module("node:assert/strict")
external deepEqual: ('a, 'a) => unit = "deepEqual"

let baseSession = {
  Session.id: "abc-123",
  tool: Claude,
  title: "Implement parser",
  messageCount: 7,
  updatedAtMs: 1770000000000.,
  cwd: Some("/Users/helge/code/demo"),
  path: "/tmp/session.jsonl",
  preview: "last useful message",
}

test("builds a cwd-restoring command for Claude sessions", () => {
  let command = Session.copyCommand(baseSession)
  equal(command, "cd /Users/helge/code/demo && claude --resume abc-123")
})

test("shell-quotes cwd paths containing single quotes", () => {
  let session = {...baseSession, cwd: Some("/tmp/that's fine")}
  equal(Session.copyCommand(session), "cd '/tmp/that'\\''s fine' && claude --resume abc-123")
})

test("shell-quotes cwd paths containing shell metacharacters", () => {
  let session = {...baseSession, cwd: Some("/tmp/demo$branch")}
  equal(Session.copyCommand(session), "cd '/tmp/demo$branch' && claude --resume abc-123")
})

test("uses the correct resume command for each supported tool", () => {
  equal(
    Session.copyCommand({...baseSession, tool: Codex}),
    "cd /Users/helge/code/demo && codex resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Junie}),
    "cd /Users/helge/code/demo && junie --resume --session-id abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Pi}),
    "cd /Users/helge/code/demo && pi --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Amp}),
    "cd /Users/helge/code/demo && amp threads continue abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: OpenCode}),
    "cd /Users/helge/code/demo && opencode --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Kimi}),
    "cd /Users/helge/code/demo && kimi --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Copilot}),
    "cd /Users/helge/code/demo && copilot --resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Antigravity}),
    "cd /Users/helge/code/demo && agy --conversation abc-123",
  )
})

test("filters sessions by title, tool, cwd, id, and preview text", () => {
  equal(Session.matchesQuery(baseSession, "claude parser"), true)
  equal(Session.matchesQuery(baseSession, "demo useful"), true)
  equal(Session.matchesQuery(baseSession, "junie"), false)
})

test("formats relative time from milliseconds", () => {
  equal(Session.timeAgo(~nowMs=1770003600000., ~thenMs=1770000000000.), "1h ago")
  equal(Session.timeAgo(~nowMs=1770000005000., ~thenMs=1770000000000.), "5s ago")
})

test("formats exact local timestamps without timezone noise", () => {
  equal(Session.exactTimestamp(1770000000000.), "2026-02-02 03:40:00")
})

test("encodes the tool as its lowercase cli name", () => {
  equal(
    Session.encode(baseSession)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("tool"))
    ->Option.flatMap(JSON.Decode.string),
    Some("claude"),
  )
})

test("round-trips a session through encode/decode", () => {
  deepEqual(Session.decode(Session.encode(baseSession)), Some(baseSession))
})

test("round-trips a session with no cwd", () => {
  let session = {...baseSession, cwd: None}
  deepEqual(Session.decode(Session.encode(session)), Some(session))
})

test("decode rejects json missing required fields", () => {
  equal(Session.decode(JSON.parseOrThrow(`{"title":"x"}`)), None)
  equal(Session.decode(JSON.parseOrThrow(`{"id":"x","tool":"nope"}`)), None)
})

test("toolFromName is the inverse of toolName for every tool", () => {
  [
    Session.Claude,
    Codex,
    Junie,
    Pi,
    Amp,
    OpenCode,
    Kimi,
    Copilot,
    Antigravity,
  ]->Array.forEach(tool => {
    equal(Session.toolFromName(Session.toolName(tool)), Some(tool))
  })
})
