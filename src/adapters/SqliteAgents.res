// Collectors for agents whose sessions live in a single SQLite database.

let collectKilo = async home => {
  let path = NodePath.joinMany([home, ".local", "share", "kilo", "kilo.db"])
  if !(await NodeFs.exists(path)) {
    []
  } else {
    NodeSqlite.query(
      path,
      "SELECT s.id, s.title, s.directory, s.time_updated AS updated, " ++
      "(SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS messageCount " ++ "FROM session s",
    )->Array.filterMap(row =>
      switch JsonUtil.stringAt(row, ["id"]) {
      | None => None
      | Some(id) =>
        Some({
          Session.id,
          tool: Kilo,
          title: JsonUtil.compact(JsonUtil.stringAt(row, ["title"]), ~fallback=id),
          messageCount: JsonUtil.floatAt(row, ["messageCount"])->Option.mapOr(0, Float.toInt),
          updatedAtMs: JsonUtil.floatAt(row, ["updated"])->Option.getOr(0.0),
          cwd: JsonUtil.stringAt(row, ["directory"]),
          path,
          preview: "",
        })
      }
    )
  }
}
let collectHermes = async home => {
  let path = NodePath.joinMany([home, ".hermes", "state.db"])
  if !(await NodeFs.exists(path)) {
    []
  } else {
    NodeSqlite.query(
      path,
      "SELECT id, title, display_name, cwd, message_count, " ++
      "COALESCE(last_activity_at, ended_at, started_at) AS updated, " ++
      "last_activity_description AS preview FROM sessions " ++ "WHERE source = 'cli' AND COALESCE(hidden, 0) = 0",
    )->Array.filterMap(row =>
      switch JsonUtil.stringAt(row, ["id"]) {
      | None => None
      | Some(id) =>
        let title =
          JsonUtil.stringAt(row, ["title"])->Option.orElse(JsonUtil.stringAt(row, ["display_name"]))
        Some({
          Session.id,
          tool: Hermes,
          title: JsonUtil.compact(title, ~fallback=id),
          messageCount: JsonUtil.floatAt(row, ["message_count"])->Option.mapOr(0, Float.toInt),
          updatedAtMs: JsonUtil.floatAt(row, ["updated"])->Option.getOr(0.0) *. 1000.0,
          cwd: JsonUtil.stringAt(row, ["cwd"]),
          path,
          preview: JsonUtil.compact(JsonUtil.stringAt(row, ["preview"]), ~fallback=""),
        })
      }
    )
  }
}
let collectDevin = async home => {
  let path = NodePath.joinMany([home, ".local", "share", "devin", "cli", "sessions.db"])
  if !(await NodeFs.exists(path)) {
    []
  } else {
    NodeSqlite.query(
      path,
      "SELECT s.id, s.title, s.working_directory, s.last_activity_at, s.created_at, " ++
      "(SELECT COUNT(*) FROM message_nodes m WHERE m.session_id = s.id) AS message_count " ++ "FROM sessions s WHERE COALESCE(s.hidden, 0) = 0",
    )->Array.filterMap(row =>
      switch JsonUtil.stringAt(row, ["id"]) {
      | None => None
      | Some(id) =>
        Some({
          Session.id,
          tool: Devin,
          title: JsonUtil.compact(JsonUtil.stringAt(row, ["title"]), ~fallback=id),
          messageCount: JsonUtil.floatAt(row, ["message_count"])->Option.mapOr(0, Float.toInt),
          updatedAtMs: JsonUtil.floatAt(row, ["last_activity_at"])
          ->Option.orElse(JsonUtil.floatAt(row, ["created_at"]))
          ->Option.getOr(0.0) *. 1000.0,
          cwd: JsonUtil.stringAt(row, ["working_directory"]),
          path,
          preview: "",
        })
      }
    )
  }
}
