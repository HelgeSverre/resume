open NodeProcess
open Session

// Raw keypress event as delivered by node:readline.
type keyEvent = {
  ctrl?: bool,
  meta?: bool,
  name?: string,
  sequence?: string,
}

// A decoded key action; the pure layer never sees raw readline events.
type key =
  | Up
  | Down
  | PageUp
  | PageDown
  | Wheel(int)
  | Enter
  | Execute
  | Escape
  | ClearQuery
  | ToggleTimestamp
  | ToggleExpand
  | CycleAgent
  | Backspace
  | Insert(string)
  | Ignore

// Result of applying a key to the picker state.
type outcome =
  | Continue
  | Submit(Session.t)
  | RunSession(Session.t)
  | Exit

// The effectful caller owns what happens after the terminal is restored.
type action =
  | Cancel
  | Copy(Session.t)
  | Run(Session.t)

type metrics = {
  width: int,
  height: int,
  nowMs: float,
}

type pickerState = {
  mutable sessions: array<Session.t>,
  version: string,
  // Distinct tools present in `sessions`, in canonical order; used by ctrl+a.
  mutable tools: array<Session.tool>,
  mutable query: string,
  mutable selected: int,
  mutable offset: int,
  mutable notice: string,
  mutable showExactTime: bool,
  mutable expanded: bool,
  // None = show every agent; Some(tool) = filter to a single agent (ctrl+a).
  mutable agentFilter: option<Session.tool>,
}

// Computed screen layout for a given terminal height and expand state.
type layout = {
  rowsHeight: int,
  previewLines: int,
  detailsHeight: int,
  showLegend: bool,
}

type box<'a> = {mutable value: 'a}

let esc = "\x1b["

type timer
@val external schedule: (unit => unit, int) => timer = "setTimeout"
@val external cancel: timer => unit = "clearTimeout"

let intMax = (a, b) =>
  if a > b {
    a
  } else {
    b
  }
let intMin = (a, b) =>
  if a < b {
    a
  } else {
    b
  }

let defaultColorEnabled = () => {
  stdout->isTTY && env->Dict.get("NO_COLOR") == None && env->Dict.get("TERM") != Some("dumb")
}

// The picker can render to stderr when stdout is captured by command
// substitution. The lifecycle owner selects the target stream before entering
// the alternate screen and restores this process-global setting on cleanup.
let colorEnabled = ref(defaultColorEnabled())
let useColor = () => colorEnabled.contents
let setColorOutput = output => {
  let previous = colorEnabled.contents
  colorEnabled.contents =
    output->isTTY && env->Dict.get("NO_COLOR") == None && env->Dict.get("TERM") != Some("dumb")
  previous
}
let restoreColorOutput = previous => colorEnabled.contents = previous

let enterAltScreen = output => {
  // Switch to the alternate screen, hide the cursor, clear it once and home the
  // cursor. Subsequent frames overwrite in place to avoid flicker.
  output->write(
    esc ++
    "?1049h" ++
    esc ++
    "?25l" ++
    esc ++
    "?1000h" ++
    esc ++
    "?1006h" ++
    esc ++
    "2J" ++
    esc ++ "H",
  )
}

let leaveAltScreen = output => {
  output->write(esc ++ "?1006l" ++ esc ++ "?1000l" ++ esc ++ "?25h" ++ esc ++ "?1049l")
}

let inverse = text => {
  esc ++ "7m" ++ text ++ esc ++ "27m"
}

let dim = text => {
  if useColor() {
    esc ++ "2m" ++ text ++ esc ++ "22m"
  } else {
    text
  }
}

let color = (code, text) => {
  if useColor() {
    esc ++ "38;5;" ++ Int.toString(code) ++ "m" ++ text ++ esc ++ "39m"
  } else {
    text
  }
}

// Subtle palette for branding and the bottom legend (256-color codes).
let brandPrimary = 67 // muted blue
let brandVersion = 74 // brighter blue
let legendKeyColor = 117 // cyan
let legendTextColor = 245 // light grey
let placeholderColor = 240 // faint grey

let toolColor = (tool, text) => {
  let code = switch tool {
  | Claude => 173
  | Codex => 71
  | Junie => 109
  | Pi => 180
  | Amp => 209
  | OpenCode => 66
  | Kimi => 176
  | Copilot => 147
  | Antigravity => 80
  | Gemini => 81
  | Vibe => 214
  | Kilo => 141
  | Hermes => 220
  | Pool => 141
  | Devin => 111
  }
  color(code, text)
}

let truncate = (value: option<string>, width) => {
  value->Option.getOr("")->Display.truncate(width)
}

// Clip plain text to a maximum width without padding (used for full-width lines
// that are cleared to end-of-line by the renderer, so trailing pad is wasteful).
let clip = (text, width) => text->Display.clip(width)

// Clip keeping the tail visible (used for the search query so the most recently
// typed characters stay on screen).
let clipTail = (text, width) => text->Display.clipTail(width)

let wrap = (text, width, maxLines) => Display.wrap(text, width, maxLines)

// Render the details box for a session. `width` is the box's outer width;
// `previewLines` is the number of wrapped preview rows (0 = a minimal box with
// no preview, for short terminals).
let renderDetailsLines = (session: Session.t, width, ~previewLines=2) => {
  let innerWidth = intMax(2, width - 2)
  let textWidth = innerWidth - 2
  let command = Session.copyCommand(session)
  let border = "─"->String.repeat(innerWidth)
  let bar = dim("│")
  let boxed = content => bar ++ " " ++ content ++ " " ++ bar

  let toolLabel = Session.toolName(session.tool)
  let head = truncate(Some(toolLabel ++ " " ++ session.id), textWidth)
  let labelLen = intMin(toolLabel->String.length, head->String.length)
  let headLine =
    toolColor(session.tool, head->String.slice(~start=0, ~end=labelLen)) ++
    dim(head->String.slice(~start=labelLen, ~end=head->String.length))

  let commandLabel = "Command "
  let commandLine = if textWidth <= commandLabel->Display.width {
    dim(truncate(Some(commandLabel), textWidth))
  } else {
    dim(commandLabel) ++
    color(71, truncate(Some(command), intMax(0, textWidth - commandLabel->Display.width)))
  }

  let pathLabel = "Path "
  let pathLine = if textWidth <= pathLabel->Display.width {
    dim(truncate(Some(pathLabel), textWidth))
  } else {
    dim(pathLabel) ++
    color(110, truncate(Some(session.path), intMax(0, textWidth - pathLabel->Display.width)))
  }

  let out = [dim("┌" ++ border ++ "┐"), boxed(headLine), boxed(commandLine), boxed(pathLine)]

  if previewLines > 0 {
    out->Array.push(boxed(" "->String.repeat(textWidth)))
    let preview = wrap(session.preview, textWidth, previewLines)
    while preview->Array.length < previewLines {
      preview->Array.push("")
    }
    preview->Array.forEach(line => out->Array.push(boxed(truncate(Some(line), textWidth))))
  }

  out->Array.push(dim("└" ++ border ++ "┘"))
  out
}

let selectedCommandOutput = (session: Session.t) => {
  Session.copyCommand(session)
}

let cwdLabel = cwd => {
  switch cwd {
  | Some(cwd) =>
    let home = env->Dict.get("HOME")->Option.getOr("")
    if home != "" && cwd->String.startsWith(home) {
      "~" ++ cwd->String.slice(~start=home->String.length)
    } else {
      cwd
    }
  | None => ""
  }
}

let distinctTools = sessions =>
  Adapters.registry
  ->Array.map(adapter => adapter.tool)
  ->Array.filter(tool => sessions->Array.some(s => s.Session.tool == tool))

// The visible sessions for the current agent filter + search query.
let filteredFor = (state: pickerState) => {
  let base = switch state.agentFilter {
  | None => state.sessions
  | Some(tool) => state.sessions->Array.filter(s => s.Session.tool == tool)
  }
  if state.query == "" {
    base
  } else {
    base->Array.filter(session => Session.matchesQuery(session, state.query))
  }
}

// Number of fixed "chrome" lines around the preview inside the details box when
// a preview is shown: top border, header, command, path, blank, bottom border.
let detailsChrome = 6
// A box with no preview: top border, header, command, path, bottom border.
let detailsMinimal = 5
let minRows = 3
let headerLines = 5

// Footer = one blank spacer line + the legend line, pinned to the very bottom.
let footerLines = 2

// Compute a screen layout that always fits within `height`. The details box is
// pinned above the footer; the row region is padded to a fixed height so nothing
// floats as the result count changes. Preview is clamped to 2 lines unless the
// user expands it, and the box (then the legend) drop away on short terminals.
//
// Invariant: headerLines + rowsHeight + (box ? 1 gap + detailsHeight : 0)
//            + (legend ? footerLines : 0) <= height.
let layoutFor = (~height, ~expanded) => {
  let h = intMax(1, height)
  let gapLines = 1
  let safety = 1
  // Only show the legend when there's room for the header, the footer and at
  // least one row of results.
  let showLegend = h >= headerLines + footerLines + minRows
  let footer = showLegend ? footerLines : 0
  // Vertical budget shared by the row region, the gap line and the details box.
  let body = intMax(1, h - headerLines - footer - gapLines - safety)

  let desiredPreview = if expanded {
    16
  } else {
    2
  }
  // How many preview lines fit while still leaving `minRows` rows on screen.
  let maxPreview = body - minRows - detailsChrome
  let previewLines = intMax(0, intMin(desiredPreview, maxPreview))

  let detailsHeight = if previewLines > 0 {
    detailsChrome + previewLines
  } else if body >= minRows + detailsMinimal {
    detailsMinimal
  } else {
    0 // terminal too short for any box
  }
  let rowsHeight = intMax(1, body - detailsHeight)
  {rowsHeight, previewLines, detailsHeight, showLegend}
}

// Responsive table columns: always sum (with single-space gaps) to <= width.
// Optional columns (cwd, msgs, updated) are dropped as the terminal narrows.
// A width of 0 means the column is hidden.
type columns = {
  toolW: int,
  titleW: int,
  countW: int,
  updatedW: int,
  cwdW: int,
}

let tableColumns = (~width, ~showExactTime) => {
  let toolW = 10
  let countW = 5
  let updatedW = if showExactTime {
    19
  } else {
    8
  }
  let minTitle = 12
  let minCwd = 12

  // Flexible budget for title (+ cwd) given which optional columns are present.
  let flexibleFor = (~withCount, ~withCwd) => {
    let visibleCols = 3 + (withCount ? 1 : 0) + (withCwd ? 1 : 0) // tool, title, updated + opts
    let gaps = visibleCols - 1
    width - toolW - updatedW - (withCount ? countW : 0) - gaps
  }

  let full = flexibleFor(~withCount=true, ~withCwd=true)
  if full >= minTitle + minCwd {
    let cwdW = intMax(minCwd, intMin(36, full * 28 / 100))
    {toolW, titleW: full - cwdW, countW, updatedW, cwdW}
  } else {
    let noCwd = flexibleFor(~withCount=true, ~withCwd=false)
    if noCwd >= minTitle {
      {toolW, titleW: noCwd, countW, updatedW, cwdW: 0}
    } else {
      let noCount = flexibleFor(~withCount=false, ~withCwd=false)
      if noCount >= minTitle {
        {toolW, titleW: noCount, countW: 0, updatedW, cwdW: 0}
      } else if width > toolW + 1 + minTitle {
        {toolW, titleW: width - toolW - 1, countW: 0, updatedW: 0, cwdW: 0}
      } else {
        {toolW: 0, titleW: intMax(1, width), countW: 0, updatedW: 0, cwdW: 0}
      }
    }
  }
}

// Keep the selected row in view by adjusting the scroll offset for a given
// visible-row region height. Mutates only the scroll/selection cursors.
let clampScroll = (state: pickerState, ~visibleLen, ~rowsHeight) => {
  let lastIndex = intMax(0, visibleLen - 1)
  state.selected = intMin(intMax(0, state.selected), lastIndex)
  if state.selected < state.offset {
    state.offset = state.selected
  }
  if state.selected >= state.offset + rowsHeight {
    state.offset = state.selected - rowsHeight + 1
  }
  state.offset = intMax(0, intMin(state.offset, lastIndex))
}

// Pure: translate a raw readline event into a key action.
let keyOfEvent = (str, event: keyEvent) => {
  let ctrl = event.ctrl->Option.getOr(false)
  let meta = event.meta->Option.getOr(false)
  let name = event.name->Option.getOr("")
  let sequence = event.sequence->Option.getOr(str)
  // readline decodes Alt+Enter as meta+return. It leaves CSI-u variants
  // undecoded, so accept only the explicit modified-Enter sequences; we do
  // not enable a terminal keyboard protocol just to receive them.
  let csiModifiedEnter =
    [
      esc ++ "13;2u",
      esc ++ "13;3u",
      esc ++ "13;4u",
      esc ++ "13;5u",
      esc ++ "13;6u",
      esc ++ "13;7u",
      esc ++ "13;8u",
    ]->Array.some(candidate => candidate == sequence)

  if (meta && (name == "return" || name == "enter")) || ctrl && name == "r" || csiModifiedEnter {
    Execute
  } else if (ctrl && name == "c") || name == "escape" {
    Escape
  } else if name == "return" || name == "enter" {
    Enter
  } else if name == "down" {
    Down
  } else if name == "up" {
    Up
  } else if name == "pagedown" {
    PageDown
  } else if name == "pageup" {
    PageUp
  } else if name == "backspace" {
    Backspace
  } else if ctrl && name == "u" {
    ClearQuery
  } else if ctrl && name == "t" {
    ToggleTimestamp
  } else if ctrl && name == "a" {
    CycleAgent
  } else if name == "tab" {
    ToggleExpand
  } else if str != "" && !ctrl && !meta && str >= " " {
    Insert(str)
  } else {
    Ignore
  }
}

// Pure-ish: apply a key to the picker state and report what should happen next.
// Mutates only the picker state; performs no IO.
let update = (state: pickerState, key, ~visible: array<Session.t>, ~rowsHeight) => {
  let lastIndex = intMax(0, visible->Array.length - 1)
  let scroll = () => {
    if state.selected < state.offset {
      state.offset = state.selected
    }
    if state.selected >= state.offset + rowsHeight {
      state.offset = state.selected - rowsHeight + 1
    }
  }
  let resetToTop = () => {
    state.selected = 0
    state.offset = 0
  }

  switch key {
  | Escape => Exit
  | Enter =>
    switch visible->Array.get(state.selected) {
    | Some(session) => Submit(session)
    | None => Continue
    }
  | Execute =>
    switch visible->Array.get(state.selected) {
    | Some(session) => RunSession(session)
    | None => Continue
    }
  | Down =>
    state.selected = intMin(state.selected + 1, lastIndex)
    scroll()
    Continue
  | Up =>
    state.selected = intMax(0, state.selected - 1)
    scroll()
    Continue
  | PageDown =>
    let step = intMax(1, rowsHeight - 1)
    state.selected = intMin(state.selected + step, lastIndex)
    scroll()
    Continue
  | PageUp =>
    let step = intMax(1, rowsHeight - 1)
    state.selected = intMax(0, state.selected - step)
    scroll()
    Continue
  | Wheel(delta) =>
    state.selected = intMin(intMax(0, state.selected + delta), lastIndex)
    scroll()
    Continue
  | Backspace =>
    let parts = Display.graphemes(state.query)
    let _ = parts->Array.pop
    state.query = parts->Array.join("")
    resetToTop()
    Continue
  | ClearQuery =>
    state.query = ""
    resetToTop()
    Continue
  | ToggleTimestamp =>
    state.showExactTime = !state.showExactTime
    Continue
  | ToggleExpand =>
    state.expanded = !state.expanded
    Continue
  | CycleAgent =>
    // Cycle: all → first agent → … → last agent → all.
    state.agentFilter = switch state.agentFilter {
    | None => state.tools->Array.get(0)
    | Some(current) =>
      let index = state.tools->Array.findIndex(tool => tool == current)
      state.tools->Array.get(index + 1)
    }
    resetToTop()
    Continue
  | Insert(str) =>
    state.query = state.query ++ str
    resetToTop()
    Continue
  | Ignore => Continue
  }
}

// Top branding line: the installed package version, then the active agent filter
// and any transient notice.
let brandingLine = (state: pickerState, ~width) => {
  let version = ("v" ++ state.version)->Display.clean
  let notice = state.notice->Display.clean
  let agent = switch state.agentFilter {
  | None => dim("all agents")
  | Some(tool) => toolColor(tool, Session.toolName(tool))
  }
  let plain =
    "resume " ++
    version ++
    "  ·  agent: " ++
    switch state.agentFilter {
    | None => "all agents"
    | Some(tool) => Session.toolName(tool)
    } ++ (notice != "" ? "  " ++ notice : "")
  if plain->Display.width <= width {
    color(brandPrimary, "resume ") ++
    color(brandVersion, version) ++
    dim("  ·  agent: ") ++
    agent ++ (notice != "" ? "  " ++ dim(notice) : "")
  } else {
    clip(color(brandPrimary, "resume ") ++ color(brandVersion, version), width)
  }
}

// Search line: dim label, then either the query or a faint placeholder.
let searchLine = (~query, ~width) => {
  let label = "Search: "
  let labelWidth = label->Display.width
  if width <= labelWidth {
    dim(clip(label, width))
  } else {
    let avail = width - labelWidth
    if query == "" {
      dim(label) ++ color(placeholderColor, clip("write to filter", avail))
    } else {
      dim(label) ++ clipTail(query, avail)
    }
  }
}

// Bottom legend. Each item is a cyan key + a lighter-grey explainer, separated
// by faint bullets. Three width tiers (descriptive → terse → minimal) keep it on
// one line; below that it is clipped.
let legendKey = key => color(legendKeyColor, key)
let legendText = text => color(legendTextColor, text)

let legendItems = [
  ("enter", "resume session"),
  ("alt+enter/^r", "run now"),
  ("↑/↓", "move"),
  ("tab", "expand"),
  ("^a", "cycle agent"),
  ("^t", "time"),
  ("^u", "clear"),
  ("esc", "quit"),
]
let legendTerse = [
  ("enter", "resume"),
  ("alt+enter/^r", "run"),
  ("↑/↓", "move"),
  ("tab", "expand"),
  ("^a", "agent"),
  ("^t", "time"),
  ("^u", "clear"),
  ("esc", "quit"),
]
let legendMinimal = [
  ("↑/↓", "move"),
  ("enter", "resume"),
  ("alt+enter/^r", "run"),
  ("esc", "quit"),
]

let legendLine = (~width) => {
  let build = (items, ~sep) => {
    let plain = items->Array.map(((k, t)) => k ++ " " ++ t)->Array.join(sep)
    if plain->Display.width <= width {
      Some(
        items
        ->Array.map(((k, t)) => legendKey(k) ++ " " ++ legendText(t))
        ->Array.join(color(placeholderColor, sep)),
      )
    } else {
      None
    }
  }
  switch build(legendItems, ~sep="   ·   ") {
  | Some(line) => line
  | None =>
    switch build(legendTerse, ~sep="  ·  ") {
    | Some(line) => line
    | None =>
      switch build(legendMinimal, ~sep="  ·  ") {
      | Some(line) => line
      | None =>
        color(
          legendTextColor,
          clip(legendMinimal->Array.map(((k, t)) => k ++ " " ++ t)->Array.join("  ·  "), width),
        )
      }
    }
  }
}

// Pure: render the whole picker to an array of lines (no IO, no mutation).
// Every returned line is guaranteed to fit within `metrics.width` so the
// terminal never soft-wraps and breaks the fixed layout.
let viewWithVisible = (state: pickerState, ~metrics, visible) => {
  let width = intMax(1, metrics.width)
  let layout = layoutFor(~height=metrics.height, ~expanded=state.expanded)
  let rowsHeight = layout.rowsHeight
  let cols = tableColumns(~width, ~showExactTime=state.showExactTime)

  let lastIndex = intMax(0, visible->Array.length - 1)
  let selected = intMin(intMax(0, state.selected), lastIndex)
  let offset = intMin(intMax(0, state.offset), lastIndex)
  let shown = visible->Array.slice(~start=offset, ~end=offset + rowsHeight)

  let out = []

  // Header: branding + search.
  out->Array.push(brandingLine(state, ~width))
  out->Array.push(searchLine(~query=state.query, ~width))
  out->Array.push("")

  // Column header + separator.
  let updatedHeader = if state.showExactTime {
    "Timestamp"
  } else {
    "Updated"
  }
  let headerCells = []
  let widths = []
  let addHeader = (w, label) =>
    if w > 0 {
      headerCells->Array.push(truncate(Some(label), w))
      widths->Array.push(w)
    }
  addHeader(cols.toolW, "Tool")
  addHeader(cols.titleW, "Title")
  addHeader(cols.countW, "Msgs")
  addHeader(cols.updatedW, updatedHeader)
  addHeader(cols.cwdW, "CWD")
  out->Array.push(dim(headerCells->Array.join(" ")))
  let sepWidth = widths->Array.reduce(0, (a, b) => a + b) + intMax(0, widths->Array.length - 1)
  out->Array.push("─"->String.repeat(intMin(width, sepWidth)))

  // Rows.
  let emptyMessage = switch state.agentFilter {
  | Some(tool) => "No " ++ Session.toolName(tool) ++ " sessions match your search."
  | None => "No sessions match your search."
  }
  let renderedRows = if shown->Array.length == 0 {
    out->Array.push(dim(clip(emptyMessage, width)))
    1
  } else {
    shown->Array.forEachWithIndex((session, index) => {
      let absoluteIndex = offset + index
      let plainCells = []
      let styledCells = []
      let cell = (w, text, style) =>
        if w > 0 {
          let c = truncate(Some(text), w)
          plainCells->Array.push(c)
          styledCells->Array.push(style(c))
        }
      cell(cols.toolW, Session.toolName(session.tool), c => toolColor(session.tool, c))
      cell(cols.titleW, session.title, c => c)
      cell(cols.countW, session.messageCount->Int.toString, dim)
      cell(
        cols.updatedW,
        if state.showExactTime {
          Session.exactTimestamp(session.updatedAtMs)
        } else {
          Session.timeAgo(~nowMs=metrics.nowMs, ~thenMs=session.updatedAtMs)
        },
        dim,
      )
      cell(cols.cwdW, cwdLabel(session.cwd), c => color(110, c))

      if absoluteIndex == selected {
        out->Array.push(inverse(plainCells->Array.join(" ")))
      } else {
        out->Array.push(styledCells->Array.join(" "))
      }
    })
    shown->Array.length
  }

  // Pad the row region so the details box stays pinned to the bottom regardless
  // of how many results are shown.
  for _ in renderedRows + 1 to rowsHeight {
    out->Array.push("")
  }

  // Details box, pinned above the footer (omitted on very short terminals).
  if layout.detailsHeight > 0 && width >= 4 {
    out->Array.push("")
    switch visible->Array.get(selected) {
    | Some(session) =>
      let boxWidth = intMin(width, intMax(40, sepWidth))
      renderDetailsLines(
        session,
        boxWidth,
        ~previewLines=layout.previewLines,
      )->Array.forEach(line => out->Array.push(line))
    | None => ()
    }
  }

  // Footer: one blank spacer row, then the keybind legend pinned to the bottom.
  if layout.showLegend {
    out->Array.push("")
    out->Array.push(legendLine(~width))
  }
  out
}

let view = (state: pickerState, ~metrics) => viewWithVisible(state, ~metrics, filteredFor(state))

// Readline splits SGR mouse reports into individual keypresses. Parse the
// report body after its ESC[< prefix, ignoring buttons and release events.
let wheelDelta = report => {
  if !(report->String.endsWith("M")) {
    None
  } else {
    switch report->String.split(";")->Array.get(0)->Option.flatMap(s => Int.fromString(s)) {
    | Some(button) if button >= 64 && button < 96 && button - button / 4 * 4 < 2 =>
      Some(button / 2 * 2 == button ? -3 : 3)
    | _ => None
    }
  }
}

// Keep the highlighted conversation stable as newer groups reorder the list.
let receiveSessions = (state: pickerState, sessions, ~visible) => {
  let selected = visible->Array.get(state.selected)->Option.map(SessionList.key)
  state.sessions = SessionList.mergeAndSort(Array.concat(state.sessions, sessions))
  state.tools = distinctTools(state.sessions)
  switch selected {
  | Some(key) =>
    let index = filteredFor(state)->Array.findIndex(session => SessionList.key(session) == key)
    state.selected = intMax(0, index)
  | None => ()
  }
}

// The caller receives an action only after the terminal has been restored.
let runPicker = async (~version, ~output=stdout, ~loadSessions) => {
  let stdout = output
  let previousColorOutput = setColorOutput(output)
  let closed = ref(false)
  let submitting = ref(false)
  let warningCount = ref(0)
  let previousWarningHandler = Diagnostics.handler.contents
  let state = {
    sessions: [],
    version,
    tools: [],
    query: "",
    selected: 0,
    offset: 0,
    notice: "Loading sessions…",
    showExactTime: false,
    expanded: false,
    agentFilter: None,
  }
  let visible = {value: filteredFor(state)}

  let input = stdin
  let mouseReport = {value: None}
  let renderTimer = {value: None}

  let restored = {value: false}
  let restore = () => {
    if !restored.value {
      restored.value = true
      leaveAltScreen(output)
    }
  }
  on("exit", restore)
  let onInterrupt = () => {
    restore()
    exit(130)
  }
  on("SIGINT", onInterrupt)

  let render = () => {
    switch renderTimer.value {
    | Some(timer) =>
      cancel(timer)
      renderTimer.value = None
    | None => ()
    }
    let metrics = {width: stdout->columns, height: stdout->rows, nowMs: Date.now()}
    let layout = layoutFor(~height=metrics.height, ~expanded=state.expanded)
    clampScroll(state, ~visibleLen=visible.value->Array.length, ~rowsHeight=layout.rowsHeight)
    // Build the whole frame and write it in one call. Each line is cleared to
    // end-of-line and the area below is cleared, so we overwrite in place
    // instead of blanking the screen first (which causes flicker).
    let frame =
      esc ++
      "H" ++
      viewWithVisible(state, ~metrics, visible.value)
      ->Array.map(line => line ++ esc ++ "K")
      ->Array.join("\n") ++
      esc ++ "0J"
    stdout->write(frame)
  }

  let renderSoon = () =>
    switch renderTimer.value {
    | Some(_) => ()
    | None => renderTimer.value = Some(schedule(() => {
          renderTimer.value = None
          render()
        }, 16))
    }

  Diagnostics.handler.contents = Some(
    message => {
      warningCount.contents = warningCount.contents + 1
      if !closed.contents {
        state.notice = JsonUtil.compact(Some(message), ~fallback="Warning")
        renderSoon()
      }
    },
  )
  enterAltScreen(output)
  NodeReadline.emitKeypressEvents(input)
  NodeReadline.setRawMode(input, true)
  NodeReadline.resume(input)

  await Promise.make((resolve, _reject) => {
    let onResize = () => render()

    let rec cleanup = action => {
      if !closed.contents {
        closed.contents = true
        Diagnostics.handler.contents = previousWarningHandler
        restoreColorOutput(previousColorOutput)
        switch renderTimer.value {
        | Some(timer) => cancel(timer)
        | None => ()
        }
        input->NodeReadline.setRawMode(false)
        input->NodeReadline.removeListener("keypress", onKeypress)
        stdout->NodeReadline.removeListener("resize", onResize)
        restore()
        NodeProcess.removeListener("exit", restore)
        NodeProcess.removeListener("SIGINT", onInterrupt)
        NodeReadline.pause(input)
        resolve(action)
      }
    }

    and onKeypress = (str: string, event: keyEvent) => {
      let sequence = event.sequence->Option.getOr(str)
      if sequence == esc ++ "<" {
        mouseReport.value = Some("")
      } else {
        switch mouseReport.value {
        | Some(report) =>
          let next = report ++ sequence
          if next->String.endsWith("M") || next->String.endsWith("m") || next->String.length > 64 {
            mouseReport.value = None
            switch wheelDelta(next) {
            | Some(delta) =>
              let rowsHeight = layoutFor(~height=stdout->rows, ~expanded=state.expanded).rowsHeight
              let _ = update(state, Wheel(delta), ~visible=visible.value, ~rowsHeight)
              renderSoon()
            | None => ()
            }
          } else {
            mouseReport.value = Some(next)
          }
        | None => handleKeypress(str, event)
        }
      }
    }

    and handleKeypress = (str: string, event: keyEvent) => {
      if !submitting.contents {
        let layout = layoutFor(~height=stdout->rows, ~expanded=state.expanded)
        let priorQuery = state.query
        let priorFilter = state.agentFilter
        switch update(
          state,
          keyOfEvent(str, event),
          ~visible=visible.value,
          ~rowsHeight=layout.rowsHeight,
        ) {
        | Exit => cleanup(Cancel)
        | Submit(session) =>
          submitting.contents = true
          cleanup(Copy(session))
        | RunSession(session) =>
          submitting.contents = true
          cleanup(Run(session))
        | Continue =>
          if priorQuery != state.query || priorFilter != state.agentFilter {
            visible.value = filteredFor(state)
          }
          render()
        }
      }
    }
    input->NodeReadline.on("keypress", onKeypress)
    stdout->NodeReadline.on("resize", onResize)
    render()
    let receive = sessions => {
      if !closed.contents {
        receiveSessions(state, sessions, ~visible=visible.value)
        visible.value = filteredFor(state)
        renderSoon()
      }
    }
    loadSessions(receive)
    ->Promise.then(_ => {
      if !closed.contents {
        if state.sessions->Array.length == 0 {
          cleanup(Cancel)
          output->write("No resumable sessions found.\n")
        } else {
          state.notice =
            Int.toString(state.sessions->Array.length) ++
            " sessions · ready" ++ (
              warningCount.contents > 0
                ? " · " ++ Int.toString(warningCount.contents) ++ " warnings"
                : ""
            )
          renderSoon()
        }
      }
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      if !closed.contents {
        state.notice = "Session loading failed"
        renderSoon()
      }
      Promise.resolve()
    })
    ->ignore
  })
}
