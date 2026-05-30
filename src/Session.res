type tool = Claude | Codex | Junie | Pi | Amp | OpenCode

type t = {
  id: string,
  tool: tool,
  title: string,
  messageCount: int,
  updatedAtMs: float,
  cwd: option<string>,
  path: string,
  preview: string,
}

@send external replaceAll: (string, string, string) => string = "replaceAll"
@send external toLowerCase: string => string = "toLowerCase"
@send external includes: (string, string) => bool = "includes"
@send external split: (string, string) => array<string> = "split"
@send external trim: string => string = "trim"
@new external makeDate: float => 'date = "Date"
@send external getFullYear: 'date => int = "getFullYear"
@send external getMonth: 'date => int = "getMonth"
@send external getDate: 'date => int = "getDate"
@send external getHours: 'date => int = "getHours"
@send external getMinutes: 'date => int = "getMinutes"
@send external getSeconds: 'date => int = "getSeconds"

let isSafeShellWord: string => bool = %raw(`value => /^[A-Za-z0-9_./:-]+$/.test(value)`)

let toolName = tool =>
  switch tool {
  | Claude => "claude"
  | Codex => "codex"
  | Junie => "junie"
  | Pi => "pi"
  | Amp => "amp"
  | OpenCode => "opencode"
  }

let resumeCommand = session =>
  switch session.tool {
  | Claude => "claude --resume " ++ session.id
  | Codex => "codex resume " ++ session.id
  | Junie => "junie --resume --session-id " ++ session.id
  | Pi => "pi --session " ++ session.id
  | Amp => "amp threads continue " ++ session.id
  | OpenCode => "opencode --session " ++ session.id
  }

let shellQuote = value => {
  let safe = replaceAll(value, "'", "'\\''")
  switch isSafeShellWord(value) {
  | true => value
  | false => "'" ++ safe ++ "'"
  }
}

let copyCommand = session =>
  switch session.cwd {
  | Some(cwd) => "cd " ++ shellQuote(cwd) ++ " && " ++ resumeCommand(session)
  | None => resumeCommand(session)
  }

let searchableText = session =>
  [
    toolName(session.tool),
    session.id,
    session.title,
    switch session.cwd {
    | Some(cwd) => cwd
    | None => ""
    },
    session.preview,
  ]
  ->Array.join(" ")
  ->toLowerCase

let matchesQuery = (session, query) => {
  let haystack = searchableText(session)
  query
  ->toLowerCase
  ->trim
  ->split(" ")
  ->Array.filter(token => token != "")
  ->Array.every(token => includes(haystack, token))
}

let timeAgo = (~nowMs, ~thenMs) => {
  let rawSeconds = Float.toInt((nowMs -. thenMs) /. 1000.)
  let seconds = if rawSeconds < 0 {
    0
  } else {
    rawSeconds
  }

  if seconds < 60 {
    Int.toString(seconds) ++ "s ago"
  } else if seconds < 3600 {
    Int.toString(seconds / 60) ++ "m ago"
  } else if seconds < 86400 {
    Int.toString(seconds / 3600) ++ "h ago"
  } else {
    Int.toString(seconds / 86400) ++ "d ago"
  }
}

let pad2 = value =>
  if value < 10 {
    "0" ++ Int.toString(value)
  } else {
    Int.toString(value)
  }

let exactTimestamp = timestampMs => {
  let date = makeDate(timestampMs)
  Int.toString(getFullYear(date)) ++
  "-" ++
  pad2(getMonth(date) + 1) ++
  "-" ++
  pad2(getDate(date)) ++
  " " ++
  pad2(getHours(date)) ++
  ":" ++
  pad2(getMinutes(date)) ++
  ":" ++
  pad2(getSeconds(date))
}
