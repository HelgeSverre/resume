type message = {count: int, updated: float, preview: string}
let encodeMessage = message =>
  JsonUtil.object([
    ("count", JsonUtil.int(message.count)),
    ("updated", JsonUtil.float(message.updated)),
    ("preview", JsonUtil.string(message.preview)),
  ])
let messageDecoder = JsonUtil.Decode.object(field => {
  count: field.required("count", JsonUtil.Decode.float)->Float.toInt,
  updated: field.required("updated", JsonUtil.Decode.float),
  preview: field.required("preview", JsonUtil.Decode.string),
})
let decodeMessage = json => JsonUtil.decode(json, messageDecoder)
let parseMessage = async path => {
  let json = await Cache.readJson(path)
  switch json {
  | Some(json) =>
    let role = JsonUtil.stringAt(json, ["role"])->Option.getOr("")
    let count = role == "user" || role == "assistant" ? 1 : 0
    {
      count,
      updated: count == 0
        ? 0.0
        : Math.max(
            JsonUtil.floatAt(json, ["time", "completed"])->Option.getOr(0.0),
            JsonUtil.floatAt(json, ["time", "created"])->Option.getOr(0.0),
          ),
      preview: count == 0 ? "" : JsonUtil.stringAt(json, ["summary", "title"])->Option.getOr(""),
    }
  | None => {count: 0, updated: 0.0, preview: ""}
  }
}

// An upgraded OpenCode installation can retain the same session in JSON, v1
// SQLite, and v2 SQLite. The newer (or, on a tie, later-loaded) record is the
// authoritative resume target, but SQLite does not expose the file-store
// preview. Keep useful display metadata from the other record instead of
// replacing it with an empty value.
let hasTitle = session => session.Session.title != "" && session.title != session.id

let mergeSession = (existing: Session.t, incoming: Session.t) => {
  let (primary, fallback) = if incoming.updatedAtMs >= existing.updatedAtMs {
    (incoming, existing)
  } else {
    (existing, incoming)
  }
  {
    ...primary,
    title: hasTitle(primary) ? primary.title : hasTitle(fallback) ? fallback.title : primary.title,
    cwd: switch primary.cwd {
    | Some(cwd) if cwd->String.trim != "" => Some(cwd)
    | _ => fallback.cwd
    },
    preview: primary.preview != "" ? primary.preview : fallback.preview,
  }
}

let mergeSessions = sessions => {
  let byId: Dict.t<Session.t> = Dict.make()
  sessions->Array.forEach(session => {
    switch byId->Dict.get(session.Session.id) {
    | Some(existing) => byId->Dict.set(session.Session.id, mergeSession(existing, session))
    | None => byId->Dict.set(session.Session.id, session)
    }
  })
  byId->Dict.valuesToArray->SessionList.mergeAndSort
}

let collectOpenCode = async (home, cache) => {
  let root = NodePath.joinMany([home, ".local", "share", "opencode", "storage"])
  let sessionFiles = await AdapterUtil.walkFiles(NodePath.join(root, "session"), path =>
    NodePath.basename(path, "")->String.startsWith("ses_") && path->String.endsWith(".json")
  )
  let groups = await AdapterUtil.mapBounded(sessionFiles, async path => {
    try {
      switch await Cache.readJson(path) {
      | Some(json) =>
        switch JsonUtil.stringAt(json, ["id"]) {
        | Some(id) =>
          let messageDir = NodePath.joinMany([root, "message", id])
          let files = await AdapterUtil.walkFiles(messageDir, path =>
            path->String.endsWith(".json")
          )
          let messages = await AdapterUtil.mapBounded(files, async path => {
            try {
              await Cache.cachedValue(
                cache,
                ~namespace="opencode-message-v1",
                path,
                ~encode=encodeMessage,
                ~decode=decodeMessage,
                parseMessage,
              )
            } catch {
            | _ => {count: 0, updated: 0.0, preview: ""}
            }
          })
          let latest =
            messages->Array.reduce({count: 0, updated: 0.0, preview: ""}, (latest, message) =>
              message.preview != "" && message.updated >= latest.updated ? message : latest
            )
          Some({
            Session.id,
            tool: OpenCode,
            title: JsonUtil.compact(
              JsonUtil.stringAt(json, ["title"]),
              ~fallback=JsonUtil.compact(Some(latest.preview), ~fallback=id),
            ),
            messageCount: messages->Array.reduce(0, (total, message) => total + message.count),
            updatedAtMs: messages->Array.reduce(
              JsonUtil.floatAt(json, ["time", "updated"])->Option.getOr(0.0),
              (updated, message) => Math.max(updated, message.updated),
            ),
            cwd: JsonUtil.stringAt(json, ["directory"]),
            path,
            preview: latest.preview,
          })
        | None => None
        }
      | None => None
      }
    } catch {
    | _ => None
    }
  })
  let sessions = groups->Array.filterMap(session => session)
  let dbPath = NodePath.joinMany([home, ".local", "share", "opencode", "opencode.db"])
  if await NodeFs.exists(dbPath) {
    let tables = await NodeSqlite.query(
      dbPath,
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )
    let hasTable = name => tables->Array.some(row => JsonUtil.stringAt(row, ["name"]) == Some(name))
    // Old JSON, v1 SQLite, and v2 SQLite may coexist after an upgrade.
    // Load v2 last so equal-timestamp copies prefer its current metadata.
    for version in 1 to 2 {
      let table = version == 2 ? "session_v2" : "session"
      let messages = version == 2 ? "session_message" : "message"
      if hasTable(table) {
        let counts = if hasTable(messages) {
          "LEFT JOIN (SELECT session_id, COUNT(*) AS count FROM " ++
          messages ++
          (version == 2
            ? " WHERE type IN ('user', 'assistant')"
            : "") ++ " GROUP BY session_id) m ON m.session_id = s.id"
        } else {
          ""
        }
        let rows = await NodeSqlite.query(
          dbPath,
          "SELECT s.id, s.title, s.directory, s.time_updated AS updated, " ++
          (hasTable(messages) ? "COALESCE(m.count, 0)" : "0") ++
          " AS messageCount FROM " ++
          table ++
          " s " ++
          counts,
        )
        rows->Array.forEach(row => {
          switch JsonUtil.stringAt(row, ["id"]) {
          | Some(id) =>
            sessions->Array.push({
              Session.id,
              tool: OpenCode,
              title: JsonUtil.compact(JsonUtil.stringAt(row, ["title"]), ~fallback=id),
              messageCount: JsonUtil.floatAt(row, ["messageCount"])->Option.mapOr(0, Float.toInt),
              updatedAtMs: JsonUtil.floatAt(row, ["updated"])->Option.getOr(0.0),
              cwd: JsonUtil.stringAt(row, ["directory"]),
              path: dbPath,
              preview: "",
            })
          | None => ()
          }
        })
      }
    }
  }
  mergeSessions(sessions)
}
