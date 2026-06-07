@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

@module("node:assert/strict")
external deepEqual: ('a, 'a) => unit = "deepEqual"

let stripAnsi = text => {
  text->String.replaceRegExp(/\\x1b\\[[0-9;]*m/g, "")
}

// Fully strip every escape sequence (colors, inverse, cursor moves, erases) so
// that String.length reflects the visible column width. Built from the real ESC
// character because ReScript regex literals escape backslashes differently.
let ansiRe = RegExp.fromString(String.fromCharCode(27) ++ "\\[[0-9;?]*[a-zA-Z]", ~flags="g")
let stripAll = text => text->String.replaceRegExp(ansiRe, "")

let baseSession = {
  Session.id: "abc",
  tool: Claude,
  title: "Title",
  messageCount: 1,
  updatedAtMs: 0.,
  cwd: Some("/repo"),
  path: "/tmp/session.jsonl",
  preview: "last message preview",
}

test("renders details in a separated box with a blank line before preview", () => {
  let lines = Tui.renderDetailsLines(baseSession, 80)->Array.map(stripAnsi)

  equal(lines->Array.get(0)->Option.getOr("")->String.startsWith("┌"), true)
  equal(lines->Array.get(Array.length(lines) - 1)->Option.getOr("")->String.startsWith("└"), true)
  equal(
    lines->Array.some(line => line->String.includes("Command cd /repo && claude --resume abc")),
    true,
  )
  equal(lines->Array.get(4)->Option.getOr("")->String.match(/^│ +│$/) != None, true)
  equal(lines->Array.get(5)->Option.getOr("")->String.includes("last message preview"), true)
})

test("always reserves two preview lines in the details box", () => {
  let emptySession = {...baseSession, preview: ""}
  let lines = Tui.renderDetailsLines(emptySession, 80)->Array.map(stripAnsi)

  equal(Array.length(lines), 8)
  equal(lines->Array.get(5)->Option.getOr("")->String.match(/^│ +│$/) != None, true)
  equal(lines->Array.get(6)->Option.getOr("")->String.match(/^│ +│$/) != None, true)
})

test("wrap never returns more lines than maxLines", () => {
  let text = "one two three four five six seven eight nine ten eleven twelve"
  equal(Tui.wrap(text, 10, 2)->Array.length <= 2, true)
  equal(Tui.wrap(text, 10, 5)->Array.length <= 5, true)
})

test("renderDetailsLines clamps to two preview lines by default", () => {
  let longSession = {
    ...baseSession,
    preview: "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
  }
  let lines = Tui.renderDetailsLines(longSession, 80)->Array.map(stripAnsi)
  equal(Array.length(lines), 8) // 6 chrome + 2 preview lines
})

test("renderDetailsLines shows more preview lines when expanded", () => {
  let longSession = {
    ...baseSession,
    preview: "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
  }
  let lines = Tui.renderDetailsLines(longSession, 80, ~previewLines=6)->Array.map(stripAnsi)
  equal(Array.length(lines), 12) // 6 chrome + 6 preview lines
})

test("selected conversation output is the plain resume command", () => {
  let output = Tui.selectedCommandOutput(baseSession)
  equal(output, "cd /repo && claude --resume abc")
})

let claudeSession = {...baseSession, id: "c1", tool: Claude, title: "Refactor parser module"}
let codexSession = {...baseSession, id: "x1", tool: Codex, title: "Wire up billing endpoint"}
let ampSession = {...baseSession, id: "a1", tool: Amp, title: "Investigate flaky test"}

let mkState = sessions => {
  Tui.sessions,
  tools: Tui.distinctTools(sessions),
  query: "",
  selected: 0,
  offset: 0,
  notice: "",
  showExactTime: false,
  expanded: false,
  agentFilter: None,
}

test("keyOfEvent treats a bare 't' as searchable text, ctrl+t as toggle", () => {
  deepEqual(Tui.keyOfEvent("t", {}), Tui.Insert("t"))
  equal(Tui.keyOfEvent("", {ctrl: true, name: "t"}), Tui.ToggleTimestamp)
  equal(Tui.keyOfEvent("", {name: "escape"}), Tui.Escape)
  equal(Tui.keyOfEvent("", {ctrl: true, name: "c"}), Tui.Escape)
})

test("keyOfEvent maps tab to ToggleExpand", () => {
  equal(Tui.keyOfEvent("\t", {name: "tab"}), Tui.ToggleExpand)
})

test("keyOfEvent maps ctrl+a to CycleAgent", () => {
  equal(Tui.keyOfEvent("", {ctrl: true, name: "a"}), Tui.CycleAgent)
  // a bare 'a' is still searchable text
  deepEqual(Tui.keyOfEvent("a", {}), Tui.Insert("a"))
})

test("CycleAgent cycles all → each present agent → back to all", () => {
  let visible = [claudeSession, codexSession, ampSession]
  let state = mkState(visible)
  equal(state.agentFilter, None) // all
  // tools are derived in canonical order: Claude, Codex, Amp
  let _ = Tui.update(state, Tui.CycleAgent, ~visible, ~rowsHeight=10)
  equal(state.agentFilter, Some(Session.Claude))
  let _ = Tui.update(state, Tui.CycleAgent, ~visible, ~rowsHeight=10)
  equal(state.agentFilter, Some(Session.Codex))
  let _ = Tui.update(state, Tui.CycleAgent, ~visible, ~rowsHeight=10)
  equal(state.agentFilter, Some(Session.Amp))
  let _ = Tui.update(state, Tui.CycleAgent, ~visible, ~rowsHeight=10)
  equal(state.agentFilter, None) // wrapped back to all
})

test("an active agent filter restricts the visible rows", () => {
  let state = mkState([claudeSession, codexSession, ampSession])
  state.agentFilter = Some(Session.Codex)
  let lines = Tui.view(state, ~metrics={width: 120, height: 40, nowMs: 0.})->Array.map(stripAll)
  equal(lines->Array.some(line => line->String.includes("Wire up billing endpoint")), true)
  equal(lines->Array.some(line => line->String.includes("Refactor parser module")), false)
})

test("update ToggleExpand flips the expanded flag", () => {
  let state = mkState([claudeSession])
  equal(state.expanded, false)
  let _ = Tui.update(state, Tui.ToggleExpand, ~visible=[claudeSession], ~rowsHeight=10)
  equal(state.expanded, true)
  let _ = Tui.update(state, Tui.ToggleExpand, ~visible=[claudeSession], ~rowsHeight=10)
  equal(state.expanded, false)
})

test("update Down/Up moves the selection within bounds", () => {
  let visible = [claudeSession, codexSession, ampSession]
  let state = mkState(visible)
  let _ = Tui.update(state, Tui.Down, ~visible, ~rowsHeight=10)
  equal(state.selected, 1)
  let _ = Tui.update(state, Tui.Down, ~visible, ~rowsHeight=10)
  let _ = Tui.update(state, Tui.Down, ~visible, ~rowsHeight=10)
  equal(state.selected, 2) // clamped at last index
  let _ = Tui.update(state, Tui.Up, ~visible, ~rowsHeight=10)
  equal(state.selected, 1)
})

test("update Enter submits the selected session", () => {
  let visible = [claudeSession, codexSession, ampSession]
  let state = mkState(visible)
  state.selected = 1
  switch Tui.update(state, Tui.Enter, ~visible, ~rowsHeight=10) {
  | Tui.Submit(session) => equal(session.id, "x1")
  | _ => equal("not submit", "submit")
  }
})

test("update Escape exits", () => {
  let visible = [claudeSession]
  let state = mkState(visible)
  switch Tui.update(state, Tui.Escape, ~visible, ~rowsHeight=10) {
  | Tui.Exit => equal(true, true)
  | _ => equal("not exit", "exit")
  }
})

test("update Insert sets query and resets selection to top", () => {
  let visible = [claudeSession, codexSession]
  let state = mkState(visible)
  state.selected = 1
  let _ = Tui.update(state, Tui.Insert("codex"), ~visible, ~rowsHeight=10)
  equal(state.query, "codex")
  equal(state.selected, 0)
})

test("view filters rows by the query and only shows matches", () => {
  let state = mkState([claudeSession, codexSession, ampSession])
  state.query = "codex"
  let lines = Tui.view(state, ~metrics={width: 120, height: 40, nowMs: 0.})->Array.map(stripAnsi)
  equal(lines->Array.some(line => line->String.includes("Wire up billing endpoint")), true)
  equal(lines->Array.some(line => line->String.includes("Refactor parser module")), false)
})

test("view shows an empty-state message when nothing matches", () => {
  let state = mkState([claudeSession])
  state.query = "zzzznomatch"
  let lines = Tui.view(state, ~metrics={width: 120, height: 40, nowMs: 0.})->Array.map(stripAnsi)
  equal(lines->Array.some(line => line->String.includes("No sessions match your search.")), true)
})

test("view pads the row region so the details box stays pinned above the footer", () => {
  let state = mkState([claudeSession])
  let lines = Tui.view(state, ~metrics={width: 120, height: 40, nowMs: 0.})->Array.map(stripAll)
  // The legend is the final line; a blank spacer sits above it; the box bottom
  // border is the line above that.
  let n = Array.length(lines)
  equal(lines->Array.get(n - 1)->Option.getOr("")->String.includes("resume"), true) // legend
  equal(lines->Array.get(n - 2)->Option.getOr("")->String.trim, "") // spacer
  equal(lines->Array.get(n - 3)->Option.getOr("")->String.startsWith("└"), true) // box bottom
  // Layout is deterministic for a fixed height regardless of result count.
  let manyState = mkState([claudeSession, codexSession, ampSession])
  let manyLines = Tui.view(manyState, ~metrics={width: 120, height: 40, nowMs: 0.})
  equal(Array.length(lines), Array.length(manyLines))
})

test("expanded view keeps the same total height but shows more preview lines", () => {
  let collapsed = mkState([claudeSession])
  let expanded = mkState([claudeSession])
  expanded.expanded = true
  let collapsedLines = Tui.view(collapsed, ~metrics={width: 120, height: 40, nowMs: 0.})
  let expandedLines = Tui.view(expanded, ~metrics={width: 120, height: 40, nowMs: 0.})
  // The bottom box grows while the row region shrinks, so total height stays put.
  equal(Array.length(collapsedLines), Array.length(expandedLines))
  let collapsedBox =
    collapsedLines->Array.filter(line => line->stripAnsi->String.startsWith("│"))->Array.length
  let expandedBox =
    expandedLines->Array.filter(line => line->stripAnsi->String.startsWith("│"))->Array.length
  equal(expandedBox > collapsedBox, true)
})

test("no rendered line ever exceeds the terminal width", () => {
  let state = mkState([claudeSession, codexSession, ampSession])
  let widths = [20, 30, 40, 50, 60, 80, 100, 120, 200]
  widths->Array.forEach(w => {
    [false, true]->Array.forEach(
      expanded => {
        state.expanded = expanded
        let lines = Tui.view(state, ~metrics={width: w, height: 30, nowMs: 0.})->Array.map(stripAll)
        lines->Array.forEach(line => equal(line->String.length <= w, true))
      },
    )
  })
})

test("the whole view always fits within the terminal height", () => {
  let state = mkState([claudeSession, codexSession, ampSession])
  let heights = [6, 8, 10, 12, 16, 20, 24, 40, 60]
  heights->Array.forEach(h => {
    [false, true]->Array.forEach(
      expanded => {
        state.expanded = expanded
        let lines = Tui.view(state, ~metrics={width: 100, height: h, nowMs: 0.})
        equal(Array.length(lines) <= h, true)
      },
    )
  })
})

test("narrow terminals drop optional columns instead of overflowing", () => {
  // Wide: the CWD column is present.
  let wide = Tui.tableColumns(~width=120, ~showExactTime=false)
  equal(wide.cwdW > 0, true)
  // Narrow: CWD is dropped so the row still fits.
  let narrow = Tui.tableColumns(~width=44, ~showExactTime=false)
  equal(narrow.cwdW, 0)
  equal(narrow.titleW >= 12, true)
})

test("preview newlines and runs of whitespace are collapsed, not rendered raw", () => {
  let messy = {...baseSession, preview: "line one\n\nline two\t\tindented   spaced"}
  let lines = Tui.renderDetailsLines(messy, 80, ~previewLines=2)->Array.map(stripAll)
  // No box content line should contain a raw newline or tab.
  lines->Array.forEach(line => {
    equal(line->String.includes("\n"), false)
    equal(line->String.includes("\t"), false)
  })
  // The text is preserved (just normalized to single spaces).
  equal(lines->Array.some(line => line->String.includes("line one line two")), true)
})

test("short terminals omit the details box", () => {
  let state = mkState([claudeSession])
  let layout = Tui.layoutFor(~height=10, ~expanded=false)
  equal(layout.detailsHeight, 0)
  let lines = Tui.view(state, ~metrics={width: 100, height: 10, nowMs: 0.})->Array.map(stripAnsi)
  equal(lines->Array.some(line => line->String.startsWith("┌")), false)
})
