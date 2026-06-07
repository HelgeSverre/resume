type tool = Claude | Codex | Junie | Pi | Amp | OpenCode | Kimi | Copilot | Antigravity

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

let toolToString = tool =>
  switch tool {
  | Claude => "Claude"
  | Codex => "Codex"
  | Junie => "Junie"
  | Pi => "Pi"
  | Amp => "Amp"
  | OpenCode => "OpenCode"
  | Kimi => "Kimi"
  | Copilot => "Copilot"
  | Antigravity => "Antigravity"
  }

let toolName = tool =>
  switch tool {
  | Claude => "claude"
  | Codex => "codex"
  | Junie => "junie"
  | Pi => "pi"
  | Amp => "amp"
  | OpenCode => "opencode"
  | Kimi => "kimi"
  | Copilot => "copilot"
  | Antigravity => "antigravity"
  }

let toolFromName = name =>
  switch name {
  | "claude" => Some(Claude)
  | "codex" => Some(Codex)
  | "junie" => Some(Junie)
  | "pi" => Some(Pi)
  | "amp" => Some(Amp)
  | "opencode" => Some(OpenCode)
  | "kimi" => Some(Kimi)
  | "copilot" => Some(Copilot)
  | "antigravity" => Some(Antigravity)
  | _ => None
  }

let resumeCommand = session =>
  switch session.tool {
  | Claude => "claude --resume " ++ session.id
  | Codex => "codex resume " ++ session.id
  | Junie => "junie --resume --session-id " ++ session.id
  | Pi => "pi --session " ++ session.id
  | Amp => "amp threads continue " ++ session.id
  | OpenCode => "opencode --session " ++ session.id
  | Kimi => "kimi --session " ++ session.id
  | Copilot => "copilot --resume " ++ session.id
  | Antigravity => "agy --conversation " ++ session.id
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

let encodeTool = tool => JSON.Encode.string(toolName(tool))

let decodeTool = json => json->JSON.Decode.string->Option.flatMap(toolFromName)

let encode = (session: t): JSON.t =>
  JSON.Encode.object(
    Dict.fromArray([
      ("id", JSON.Encode.string(session.id)),
      ("tool", encodeTool(session.tool)),
      ("title", JSON.Encode.string(session.title)),
      ("messageCount", JSON.Encode.float(Int.toFloat(session.messageCount))),
      ("updatedAtMs", JSON.Encode.float(session.updatedAtMs)),
      (
        "cwd",
        switch session.cwd {
        | Some(cwd) => JSON.Encode.string(cwd)
        | None => JSON.Encode.null
        },
      ),
      ("path", JSON.Encode.string(session.path)),
      ("preview", JSON.Encode.string(session.preview)),
    ]),
  )

let decode = (json: JSON.t): option<t> =>
  switch JSON.Decode.object(json) {
  | Some(obj) =>
    switch (
      obj->Dict.get("id")->Option.flatMap(JSON.Decode.string),
      obj->Dict.get("tool")->Option.flatMap(decodeTool),
    ) {
    | (Some(id), Some(tool)) =>
      Some({
        id,
        tool,
        title: obj->Dict.get("title")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        messageCount: obj
        ->Dict.get("messageCount")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.getOr(0.0)
        ->Float.toInt,
        updatedAtMs: obj
        ->Dict.get("updatedAtMs")
        ->Option.flatMap(JSON.Decode.float)
        ->Option.getOr(0.0),
        cwd: obj->Dict.get("cwd")->Option.flatMap(JSON.Decode.string),
        path: obj->Dict.get("path")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
        preview: obj->Dict.get("preview")->Option.flatMap(JSON.Decode.string)->Option.getOr(""),
      })
    | _ => None
    }
  | None => None
  }

let encodeOption = value =>
  switch value {
  | Some(session) => encode(session)
  | None => JSON.Encode.null
  }

let decodeOption = json =>
  if json == JSON.Null {
    Some(None)
  } else {
    decode(json)->Option.map(session => Some(session))
  }
