let collectGemini = async home => {
  let root = NodePath.joinMany([home, ".gemini"])
  let projectMap = Dict.make()
  switch await Cache.readJson(NodePath.join(root, "projects.json")) {
  | Some(json) =>
    switch json
    ->JSON.Decode.object
    ->Option.flatMap(obj => obj->Dict.get("projects"))
    ->Option.flatMap(JSON.Decode.object) {
    | Some(projects) =>
      projects->Dict.forEachWithKey((slugJson, cwd) =>
        switch slugJson->JSON.Decode.string {
        | Some(slug) => projectMap->Dict.set(slug, cwd)
        | None => ()
        }
      )
    | None => ()
    }
  | None => ()
  }

  let files = await AdapterUtil.walkFiles(NodePath.join(root, "tmp"), path =>
    NodePath.basename(path, "")->String.startsWith("session-") &&
    (path->String.endsWith(".json") || path->String.endsWith(".jsonl")) &&
    NodePath.basename(NodePath.dirname(path), "") == "chats"
  )
  let groups = await AdapterUtil.mapBounded(files, async path => {
    let rows = if path->String.endsWith(".jsonl") {
      await AdapterUtil.readJsonl(path)
    } else {
      switch await Cache.readJson(path) {
      | Some(json) => [json]
      | None => []
      }
    }
    switch rows->Array.get(0) {
    | None => None
    | Some(header) =>
      switch JsonUtil.stringAt(header, ["sessionId"]) {
      | None => None
      | Some(id) =>
        let messages =
          rows
          ->Array.toReversed
          ->Array.findMap(row =>
            JsonUtil.decode(
              row,
              JsonUtil.at(["$set", "messages"], JsonUtil.Decode.array(JsonUtil.Decode.id)),
            )
          )
          ->Option.orElse(
            JsonUtil.decode(
              header,
              JsonUtil.at(["messages"], JsonUtil.Decode.array(JsonUtil.Decode.id)),
            ),
          )
          ->Option.getOr([])
        let isMessage = row =>
          switch JsonUtil.stringAt(row, ["type"]) {
          | Some("user") | Some("gemini") => true
          | _ => false
          }
        let firstUser =
          messages
          ->Array.findMap(row =>
            JsonUtil.stringAt(row, ["type"]) == Some("user")
              ? Some(JsonUtil.textAt(row, ["content"]))
              : None
          )
          ->Option.getOr("")
        let preview =
          messages
          ->Array.toReversed
          ->Array.findMap(row => {
            let text = JsonUtil.textAt(row, ["content"])
            isMessage(row) && text != "" ? Some(text) : None
          })
          ->Option.getOr("")
        let folder = NodePath.basename(NodePath.dirname(NodePath.dirname(path)), "")
        let updatedAt =
          rows
          ->Array.toReversed
          ->Array.findMap(row => {
            let timestamp = JsonUtil.msAt(row, ["$set", "lastUpdated"])
            timestamp > 0.0 ? Some(timestamp) : None
          })
          ->Option.getOr(JsonUtil.msAt(header, ["lastUpdated"]))
        let summary = JsonUtil.stringAt(header, ["summary"])->Option.getOr("")
        Some({
          Session.id,
          tool: Gemini,
          title: JsonUtil.compact(Some(summary == "" ? firstUser : summary), ~fallback=id),
          messageCount: messages->Array.filter(isMessage)->Array.length,
          updatedAtMs: Math.max(updatedAt, await AdapterUtil.fileMtimeMs(path)),
          cwd: projectMap->Dict.get(folder),
          path,
          preview: JsonUtil.compact(Some(preview), ~fallback=""),
        })
      }
    }
  })
  groups->Array.filterMap(group => group)
}
