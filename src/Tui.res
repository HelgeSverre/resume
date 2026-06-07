open NodeProcess
open Session

// Raw keypress event as delivered by node:readline.
type keyEvent = {
  ctrl?: bool,
  meta?: bool,
  name?: string,
}

// A decoded key action; the pure layer never sees raw readline events.
type key =
  | Up
  | Down
  | PageUp
  | PageDown
  | Enter
  | Escape
  | ClearQuery
  | ToggleTimestamp
  | ToggleExpand
  | Backspace
  | Insert(string)
  | Ignore

// Result of applying a key to the picker state.
type outcome =
  | Continue
  | Submit(Session.t)
  | Exit

type metrics = {
  width: int,
  height: int,
  nowMs: float,
}

type pickerState = {
  mutable sessions: array<Session.t>,
  mutable query: string,
  mutable selected: int,
  mutable offset: int,
  mutable notice: string,
  mutable showExactTime: bool,
  mutable expanded: bool,
}

// Computed screen layout for a given terminal height and expand state.
type layout = {
  rowsHeight: int,
  previewLines: int,
  detailsHeight: int,
}

type box<'a> = {mutable value: 'a}

let esc = "\x1b["

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

let useColor = () => {
  stdout->isTTY && env->Dict.get("NO_COLOR") == None && env->Dict.get("TERM") != Some("dumb")
}

let enterAltScreen = () => {
  // Switch to the alternate screen, hide the cursor, clear it once and home the
  // cursor. Subsequent frames overwrite in place to avoid flicker.
  stdout->write(esc ++ "?1049h" ++ esc ++ "?25l" ++ esc ++ "2J" ++ esc ++ "H")
}

let leaveAltScreen = () => {
  stdout->write(esc ++ "?25h" ++ esc ++ "?1049l")
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
  }
  color(code, text)
}

let truncate = (value: option<string>, width) => {
  let text = switch value {
  | Some(v) => v->String.replaceRegExp(/\s+/g, " ")->String.trim
  | None => ""
  }
  if width <= 0 {
    ""
  } else if width == 1 {
    text == "" ? " " : "…"
  } else if text->String.length > width {
    text->String.slice(~start=0, ~end=width - 1) ++ "…"
  } else {
    text->String.padEnd(width, " ")
  }
}

// Clip plain text to a maximum width without padding (used for full-width lines
// that are cleared to end-of-line by the renderer, so trailing pad is wasteful).
let clip = (text, width) => {
  if width <= 0 {
    ""
  } else if text->String.length <= width {
    text
  } else if width == 1 {
    "…"
  } else {
    text->String.slice(~start=0, ~end=width - 1) ++ "…"
  }
}

// Clip keeping the tail visible (used for the search query so the most recently
// typed characters stay on screen).
let clipTail = (text, width) => {
  if width <= 0 {
    ""
  } else if text->String.length <= width {
    text
  } else if width == 1 {
    "…"
  } else {
    "…" ++ text->String.sliceToEnd(~start=text->String.length - (width - 1))
  }
}

let wrap = (text, width, maxLines) => {
  let words =
    text
    ->String.replaceRegExp(/\s+/g, " ")
    ->String.trim
    ->String.split(" ")
    ->Array.filter(word => word != "")

  let lines = []
  let line = {value: ""}

  words->Array.forEach(word => {
    if lines->Array.length >= maxLines {
      () // region already full; ignore remaining words
    } else {
      let next = if line.value == "" {
        word
      } else {
        line.value ++ " " ++ word
      }
      if next->String.length > width && line.value != "" {
        lines->Array.push(line.value)
        line.value = word
      } else {
        line.value = next
      }
    }
  })

  if line.value != "" && lines->Array.length < maxLines {
    lines->Array.push(line.value)
  }

  lines
}

// Render the details box for a session. `width` is the box's outer width;
// `previewLines` is the number of wrapped preview rows (0 = a minimal box with
// no preview, for short terminals).
let renderDetailsLines = (session: Session.t, width, ~previewLines=2) => {
  let innerWidth = intMax(8, width - 2)
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
  let commandLine =
    dim(commandLabel) ++
    color(71, truncate(Some(command), intMax(0, textWidth - commandLabel->String.length)))

  let pathLabel = "Path "
  let pathLine =
    dim(pathLabel) ++
    color(110, truncate(Some(session.path), intMax(0, textWidth - pathLabel->String.length)))

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
      "~" ++ cwd->String.sliceToEnd(~start=home->String.length)
    } else {
      cwd
    }
  | None => ""
  }
}

// Number of fixed "chrome" lines around the preview inside the details box when
// a preview is shown: top border, header, command, path, blank, bottom border.
let detailsChrome = 6
// A box with no preview: top border, header, command, path, bottom border.
let detailsMinimal = 5
let minRows = 3
let headerLines = 5

// Compute a screen layout that always fits within `height`. The details box is
// pinned to the bottom; the row region is padded to a fixed height so nothing
// floats as the result count changes. Preview is clamped to 2 lines unless the
// user expands it, and the box shrinks (or disappears) on short terminals.
//
// Invariant: headerLines + rowsHeight + (box ? 1 gap : 0) + detailsHeight <= height.
let layoutFor = (~height, ~expanded) => {
  let h = intMax(1, height)
  let gapLines = 1
  let safety = 1
  // Vertical budget shared by the row region, the gap line and the details box.
  let body = intMax(1, h - headerLines - gapLines - safety)

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
  {rowsHeight, previewLines, detailsHeight}
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

  if (ctrl && name == "c") || name == "escape" {
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
  | Backspace =>
    state.query = state.query->String.slice(~start=0, ~end=state.query->String.length - 1)
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
  | Insert(str) =>
    state.query = state.query ++ str
    resetToTop()
    Continue
  | Ignore => Continue
  }
}

// The status/help line, made responsive: shows the full hint when it fits, a
// short hint when it half-fits, otherwise just the (tail-clipped) query.
let statusLine = (~query, ~expanded, ~width) => {
  let prefix = "Search: " ++ query
  let tabHint = expanded ? "tab collapse" : "tab expand"
  let helpFull =
    "enter print · ↑/↓ move · " ++ tabHint ++ " · ctrl+t time · esc quit · ctrl+u clear"
  let helpShort = "↑/↓ move · enter print · esc quit"
  let sep = "  "
  let fits = help => prefix->String.length + sep->String.length + help->String.length <= width
  if fits(helpFull) {
    prefix ++ sep ++ dim(helpFull)
  } else if fits(helpShort) {
    prefix ++ sep ++ dim(helpShort)
  } else {
    clipTail(prefix, width)
  }
}

// Pure: render the whole picker to an array of lines (no IO, no mutation).
// Every returned line is guaranteed to fit within `metrics.width` so the
// terminal never soft-wraps and breaks the fixed layout.
let view = (state: pickerState, ~metrics) => {
  let width = intMax(1, metrics.width)
  let layout = layoutFor(~height=metrics.height, ~expanded=state.expanded)
  let rowsHeight = layout.rowsHeight
  let cols = tableColumns(~width, ~showExactTime=state.showExactTime)

  let visible = SessionList.visible(~query=state.query, state.sessions)
  let lastIndex = intMax(0, visible->Array.length - 1)
  let selected = intMin(intMax(0, state.selected), lastIndex)
  let offset = intMin(intMax(0, state.offset), lastIndex)
  let shown = visible->Array.slice(~start=offset, ~end=offset + rowsHeight)

  let out = []

  // Header.
  let titlePlain =
    "resume search coding-agent sessions" ++ (state.notice != "" ? " " ++ state.notice : "")
  out->Array.push(
    if titlePlain->String.length <= width {
      "resume " ++
      dim("search coding-agent sessions") ++ (state.notice != "" ? " " ++ state.notice : "")
    } else {
      clip("resume", width)
    },
  )
  out->Array.push(statusLine(~query=state.query, ~expanded=state.expanded, ~width))
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
  let renderedRows = if shown->Array.length == 0 {
    out->Array.push(dim(clip("No sessions match your search.", width)))
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

  // Details box, pinned to the bottom (omitted on very short terminals).
  if layout.detailsHeight > 0 {
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
  out
}

let runPicker = async sessions => {
  if sessions->Array.length == 0 {
    Console.log("No resumable sessions found.")
  } else {
    let state = {
      sessions,
      query: "",
      selected: 0,
      offset: 0,
      notice: "",
      showExactTime: false,
      expanded: false,
    }

    let input = stdin

    let restored = {value: false}
    let restore = () => {
      if !restored.value {
        restored.value = true
        leaveAltScreen()
      }
    }
    on("exit", restore)
    on("SIGINT", () => {
      restore()
      exit(130)
    })

    let render = () => {
      let metrics = {width: stdout->columns, height: stdout->rows, nowMs: Date.now()}
      let layout = layoutFor(~height=metrics.height, ~expanded=state.expanded)
      let visible = SessionList.visible(~query=state.query, state.sessions)
      clampScroll(state, ~visibleLen=visible->Array.length, ~rowsHeight=layout.rowsHeight)
      // Build the whole frame and write it in one call. Each line is cleared to
      // end-of-line and the area below is cleared, so we overwrite in place
      // instead of blanking the screen first (which causes flicker).
      let frame =
        esc ++
        "H" ++
        view(state, ~metrics)->Array.map(line => line ++ esc ++ "K")->Array.join("\n") ++
        esc ++ "0J"
      stdout->write(frame)
    }

    enterAltScreen()
    NodeReadline.emitKeypressEvents(input)
    NodeReadline.setRawMode(input, true)
    NodeReadline.resume(input)

    await Promise.make((resolve, _reject) => {
      let onResize = () => render()

      let rec cleanup = () => {
        input->NodeReadline.setRawMode(false)
        input->NodeReadline.removeListener("keypress", onKeypress)
        stdout->NodeReadline.removeListener("resize", onResize)
        restore()
        NodeReadline.pause(input)
        resolve()
      }

      and onKeypress = (str: string, event: keyEvent) => {
        let layout = layoutFor(~height=stdout->rows, ~expanded=state.expanded)
        let visible = SessionList.visible(~query=state.query, state.sessions)
        switch update(state, keyOfEvent(str, event), ~visible, ~rowsHeight=layout.rowsHeight) {
        | Exit => cleanup()
        | Submit(session) =>
          cleanup()
          Console.log(selectedCommandOutput(session))
        | Continue => render()
        }
      }

      input->NodeReadline.on("keypress", onKeypress)
      stdout->NodeReadline.on("resize", onResize)
      render()
    })
  }
}
