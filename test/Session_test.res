@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

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
