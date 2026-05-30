@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

let make = (~id, ~tool, ~title, ~updatedAtMs, ~preview="") => {
  Session.id,
  tool,
  title,
  messageCount: 1,
  updatedAtMs,
  cwd: Some("/repo"),
  path: "/tmp/" ++ id,
  preview,
}

let at = (items, index) =>
  switch items[index] {
  | Some(item) => item
  | None => throw(Failure("missing item"))
  }

test("merges duplicate tool/session ids by keeping the newest record", () => {
  let sessions = [
    make(~id="same", ~tool=Claude, ~title="old", ~updatedAtMs=10.),
    make(~id="same", ~tool=Claude, ~title="new", ~updatedAtMs=20.),
    make(~id="same", ~tool=Codex, ~title="other tool", ~updatedAtMs=30.),
  ]

  let merged = SessionList.mergeAndSort(sessions)

  equal(Array.length(merged), 2)
  equal(at(merged, 0).title, "other tool")
  equal(at(merged, 1).title, "new")
})

test("filters merged sessions by query", () => {
  let sessions = [
    make(~id="a", ~tool=Claude, ~title="billing migration", ~updatedAtMs=20.),
    make(~id="b", ~tool=Pi, ~title="music parser", ~updatedAtMs=10., ~preview="matrix notes"),
  ]

  let visible = SessionList.visible(~query="pi matrix", sessions)

  equal(Array.length(visible), 1)
  equal(at(visible, 0).id, "b")
})
