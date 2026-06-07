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
      switch sessionJson->Option.flatMap(JSON.Decode.object) {
      | Some(sessionObj) =>
        switch sessionObj->Dict.get("id")->Option.flatMap(JSON.Decode.string) {
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

          let sessionUpdated =
            sessionObj
            ->Dict.get("time")
            ->Option.flatMap(JSON.Decode.object)
            ->Option.flatMap(obj => obj->Dict.get("updated"))
            ->Option.flatMap(JSON.Decode.float)
            ->Option.getOr(0.0)

          let state = {index: 0, messageCount: 0, updatedAtMs: sessionUpdated, preview: ""}

          while state.index < messageFiles->Array.length {
            let messagePath = messageFiles->Array.get(state.index)->Option.getOr("")
            state.index = state.index + 1

            let messageJson = await Cache.readJson(messagePath)
            switch messageJson->Option.flatMap(JSON.Decode.object) {
            | Some(messageObj) =>
              let role =
                messageObj->Dict.get("role")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
              if role == "user" || role == "assistant" {
                state.messageCount = state.messageCount + 1

                let timeObj =
                  messageObj
                  ->Dict.get("time")
                  ->Option.flatMap(JSON.Decode.object)
                  ->Option.getOr(Dict.make())
                let completed =
                  timeObj
                  ->Dict.get("completed")
                  ->Option.flatMap(JSON.Decode.float)
                  ->Option.getOr(0.0)
                let created =
                  timeObj->Dict.get("created")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.0)
                state.updatedAtMs = Math.max(Math.max(state.updatedAtMs, completed), created)

                let summaryTitle =
                  messageObj
                  ->Dict.get("summary")
                  ->Option.flatMap(JSON.Decode.object)
                  ->Option.flatMap(obj => obj->Dict.get("title"))
                  ->Option.flatMap(JSON.Decode.string)
                  ->Option.getOr("")
                if summaryTitle != "" {
                  state.preview = summaryTitle
                }
              }
            | None => ()
            }
          }

          let title =
            sessionObj->Dict.get("title")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
          let directory = sessionObj->Dict.get("directory")->Option.flatMap(JSON.Decode.string)

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
