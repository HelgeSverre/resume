@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

@module("node:assert/strict")
external deepEqual: ('a, 'a) => unit = "deepEqual"

@new external makeDate: float => 'date = "Date"
@send external toLocaleString: ('date, string, {"hour12": bool}) => string = "toLocaleString"

let baseSession = {
  Session.id: "abc-123",
  tool: Claude,
  title: "Implement parser",
  messageCount: 7,
  updatedAtMs: 1770000000000.,
  cwd: Some("/example/project"),
  path: "/tmp/session.jsonl",
  preview: "last useful message",
}

test("builds a cwd-restoring command for Claude sessions", () => {
  let command = Session.copyCommand(baseSession)
  equal(command, "cd /example/project && claude --resume abc-123")
})

test("shell-quotes cwd paths containing single quotes", () => {
  let session = {...baseSession, cwd: Some("/tmp/that's fine")}
  equal(Session.copyCommand(session), "cd '/tmp/that'\\''s fine' && claude --resume abc-123")
})

test("shell-quotes cwd paths containing shell metacharacters", () => {
  let session = {...baseSession, cwd: Some("/tmp/demo$branch")}
  equal(Session.copyCommand(session), "cd '/tmp/demo$branch' && claude --resume abc-123")
})

test("shell-quotes session ids in resume commands", () => {
  let session = {...baseSession, cwd: None, id: "id; touch /tmp/unwanted"}
  equal(Session.copyCommand(session), "claude --resume 'id; touch /tmp/unwanted'")
})

test("shell-quotes Gemini session file paths", () => {
  let session = {...baseSession, tool: Gemini, cwd: None, path: "/tmp/a user's session.jsonl"}
  equal(Session.copyCommand(session), "gemini --session-file '/tmp/a user'\\''s session.jsonl'")
})

test("uses the correct resume command for each supported tool", () => {
  equal(
    Session.copyCommand({...baseSession, tool: Codex}),
    "cd /example/project && codex resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Junie}),
    "cd /example/project && junie --resume --session-id abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Pi}),
    "cd /example/project && pi --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Amp}),
    "cd /example/project && amp threads continue abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: OpenCode}),
    "cd /example/project && opencode --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Kimi}),
    "cd /example/project && kimi --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Copilot}),
    "cd /example/project && copilot --resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Antigravity}),
    "cd /example/project && agy --conversation abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Gemini}),
    "cd /example/project && gemini --session-file /tmp/session.jsonl",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Vibe}),
    "cd /example/project && vibe --resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Kilo}),
    "cd /example/project && kilo --session abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Hermes}),
    "cd /example/project && hermes --resume abc-123",
  )
  equal(
    Session.copyCommand({...baseSession, tool: Devin}),
    "cd /example/project && devin --resume abc-123",
  )
})

test("filters sessions by title, tool, cwd, id, and preview text", () => {
  equal(Session.matchesQuery(baseSession, "claude parser"), true)
  equal(Session.matchesQuery(baseSession, "project useful"), true)
  equal(Session.matchesQuery(baseSession, "junie"), false)
})

test("formats relative time from milliseconds", () => {
  equal(Session.timeAgo(~nowMs=1770003600000., ~thenMs=1770000000000.), "1h ago")
  equal(Session.timeAgo(~nowMs=1770000005000., ~thenMs=1770000000000.), "5s ago")
})

test("formats exact local timestamps without timezone noise", () => {
  let timestamp = 1770000000000.
  let expected = makeDate(timestamp)->toLocaleString("sv-SE", {"hour12": false})
  equal(Session.exactTimestamp(timestamp), expected)
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
    Gemini,
    Vibe,
    Kilo,
    Hermes,
    Devin,
  ]->Array.forEach(tool => {
    equal(Session.toolFromName(Session.toolName(tool)), Some(tool))
  })
})
