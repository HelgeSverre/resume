type loopState = {
  mutable index: int,
  mutable messageCount: int,
  mutable updatedAtMs: float,
  mutable preview: string,
}

let collectOpenCode = async home => {
  let root = NodePath.joinMany([home, ".local", "share", "opencode", "storage"])
  let sessionFiles = await AdapterUtil.walkFiles(NodePath.join(root, "session"), path =>
    NodePath.basename(path, "")->String.startsWith("ses_") && path->String.endsWith(".json")
  )

  let sessions = []

  let _ = await AdapterUtil.all(
    sessionFiles->Array.map(async path => {
      let sessionJson = await Cache.readJson(path)
      switch sessionJson {
      | Some(json) =>
        switch JsonUtil.stringAt(json, ["id"]) {
        | Some(id) =>
          let messageDir = NodePath.joinMany([root, "message", id])
          let messageFiles = if await NodeFs.exists(messageDir) {
            await AdapterUtil.walkFiles(messageDir, messagePath =>
              NodePath.basename(messagePath, "")->String.startsWith("msg_") &&
                messagePath->String.endsWith(".json")
            )
          } else {
            []
          }

          let sessionUpdated = JsonUtil.floatAt(json, ["time", "updated"])->Option.getOr(0.0)

          let state = {index: 0, messageCount: 0, updatedAtMs: sessionUpdated, preview: ""}

          while state.index < messageFiles->Array.length {
            let messagePath = messageFiles->Array.get(state.index)->Option.getOr("")
            state.index = state.index + 1

            let messageJson = await Cache.readJson(messagePath)
            switch messageJson {
            | Some(mjson) =>
              let role = JsonUtil.stringAt(mjson, ["role"])->Option.getOr("")
              if role == "user" || role == "assistant" {
                state.messageCount = state.messageCount + 1

                let completed = JsonUtil.floatAt(mjson, ["time", "completed"])->Option.getOr(0.0)
                let created = JsonUtil.floatAt(mjson, ["time", "created"])->Option.getOr(0.0)
                state.updatedAtMs = Math.max(Math.max(state.updatedAtMs, completed), created)

                let summaryTitle =
                  JsonUtil.stringAt(mjson, ["summary", "title"])->Option.getOr("")
                if summaryTitle != "" {
                  state.preview = summaryTitle
                }
              }
            | None => ()
            }
          }

          let title = JsonUtil.stringAt(json, ["title"])->Option.getOr("")
          let directory = JsonUtil.stringAt(json, ["directory"])

          sessions->Array.push({
            Session.id,
            tool: OpenCode,
            title: JsonUtil.compact(Some(title == "" ? state.preview : title), ~fallback=id),
            messageCount: state.messageCount,
            updatedAtMs: state.updatedAtMs,
            cwd: directory,
            path,
            preview: state.preview,
          })
        | None => ()
        }
      | None => ()
      }
    }),
  )

  sessions
}
