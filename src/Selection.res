type result =
  | Found(Session.t)
  | Missing
  | Ambiguous(array<Session.t>)

@send external indexOf: (string, string) => int = "indexOf"
@send external slice: (string, int, int) => string = "slice"

type query = {filterTool: option<Session.tool>, id: string}

// A tool-qualified query uses the first colon, preserving colons that belong
// to the session id itself (for example `codex:rollout:abc`). An unknown prefix
// remains an ordinary id so existing IDs containing a colon stay searchable.
let parse = value => {
  let separator = value->indexOf(":")
  if separator <= 0 {
    {filterTool: None, id: value}
  } else {
    let toolName = value->slice(0, separator)
    switch Session.toolFromName(toolName) {
    | Some(tool) => {filterTool: Some(tool), id: value->slice(separator + 1, value->String.length)}
    | None => {filterTool: None, id: value}
    }
  }
}

let candidates = (sessions, query, matchesId) =>
  sessions->Array.filter((session: Session.t) => {
    let matchesTool = switch query.filterTool {
    | Some(tool) => session.tool == tool
    | None => true
    }
    matchesTool && matchesId(session.id, query.id)
  })

let resultFor = sessions =>
  switch sessions {
  | [session] => Found(session)
  | [] => Missing
  | many => Ambiguous(many)
  }

let find = (sessions, value) => {
  let query = parse(value)
  let exact = candidates(sessions, query, (id, expected) => id == expected)
  switch exact {
  | [session] => Found(session)
  | [] => resultFor(candidates(sessions, query, (id, prefix) => id->String.startsWith(prefix)))
  | many => Ambiguous(many)
  }
}
