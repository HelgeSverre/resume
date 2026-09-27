let collectVibe = async home => {
  let root = NodePath.joinMany([home, ".vibe", "logs", "session"])
  let files = await AdapterUtil.walkFiles(root, path => NodePath.basename(path, "") == "meta.json")

  let groups = await AdapterUtil.mapBounded(files, async metaPath => {
    switch await Cache.readJson(metaPath) {
    | None => None
    | Some(meta) =>
      switch JsonUtil.stringAt(meta, ["session_id"]) {
      | None => None
      | Some(id) =>
        let messagesPath = NodePath.join(NodePath.dirname(metaPath), "messages.jsonl")
        let messages = if await NodeFs.exists(messagesPath) {
          await AdapterUtil.readJsonl(messagesPath)
        } else {
          []
        }
        let isMessage = row =>
          switch JsonUtil.stringAt(row, ["role"]) {
          | Some("user") | Some("assistant") => true
          | _ => false
          }
        let count = messages->Array.filter(isMessage)->Array.length
        let preview =
          messages
          ->Array.toReversed
          ->Array.findMap(row => {
            let text = JsonUtil.textAt(row, ["content"])
            isMessage(row) && text != "" ? Some(text) : None
          })
          ->Option.getOr("")
        let title = JsonUtil.stringAt(meta, ["title"])->Option.getOr("")
        Some({
          Session.id,
          tool: Vibe,
          title: JsonUtil.compact(Some(title == "" ? preview : title), ~fallback=id),
          messageCount: count,
          updatedAtMs: Math.max(
            JsonUtil.msAt(meta, ["end_time"]),
            await AdapterUtil.fileMtimeMs(metaPath),
          ),
          cwd: JsonUtil.stringAt(meta, ["environment", "working_directory"]),
          path: messagesPath,
          preview: JsonUtil.compact(Some(preview), ~fallback=""),
        })
      }
    }
  })
  groups->Array.filterMap(group => group)
}
