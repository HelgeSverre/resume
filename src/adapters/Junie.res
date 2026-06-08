type parsed = {
  messageCount: int,
  preview: string,
}

let encodeParsed = (p: parsed): JSON.t =>
  Codec.object([("messageCount", Codec.int(p.messageCount)), ("preview", Codec.string(p.preview))])

let decodeParsed = json =>
  json->Codec.asObject(obj => Some({
    messageCount: obj->Codec.getInt("messageCount")->Option.getOr(0),
    preview: obj->Codec.getString("preview")->Option.getOr(""),
  }))

let parseJunieEvents = async eventsPath => {
  let lines = if await NodeFs.exists(eventsPath) {
    AdapterUtil.splitLines(await NodeFs.readFile(eventsPath, "utf8"))
  } else {
    []
  }

  let isUserPrompt = line => JsonUtil.hasJsonField(line, "kind", "UserPromptEvent")
  let isTaskState = line => JsonUtil.hasJsonField(line, "kind", "TaskState")

  let previewEvent = AdapterUtil.lastParsedLine(lines, isUserPrompt)
  let fallbackPreviewEvent = if previewEvent == None {
    AdapterUtil.lastParsedLine(lines, isTaskState)
  } else {
    None
  }

  let preview =
    previewEvent
    ->Option.flatMap(j =>
      JsonUtil.stringAt(j, ["presentablePrompt"])
      ->Option.orElse(JsonUtil.stringAt(j, ["prompt"]))
      ->Option.orElse(JsonUtil.stringAt(j, ["text"]))
    )
    ->Option.getOr("")

  let fallbackPreview =
    fallbackPreviewEvent
    ->Option.flatMap(j =>
      JsonUtil.stringAt(j, ["text"])->Option.orElse(JsonUtil.stringAt(j, ["details"]))
    )
    ->Option.getOr("")

  {
    messageCount: AdapterUtil.countLines(lines, line => isUserPrompt(line) || isTaskState(line)),
    preview: if preview != "" {
      preview
    } else {
      fallbackPreview
    },
  }
}

let collectJunie = async (home, cache) => {
  let sessionsDir = NodePath.joinMany([home, ".junie", "sessions"])
  let indexPath = NodePath.join(sessionsDir, "index.jsonl")

  let indexExists = await NodeFs.exists(indexPath)
  if !indexExists {
    []
  } else {
    let sessions = []
    let rows = await AdapterUtil.readJsonl(indexPath)

    let _ = await AdapterUtil.all(
      rows->Array.map(async row => {
        switch JsonUtil.stringAt(row, ["sessionId"]) {
        | Some(sessionId) =>
          let eventsPath = NodePath.joinMany([sessionsDir, sessionId, "events.jsonl"])
          let parsed = if await NodeFs.exists(eventsPath) {
            await Cache.cachedValue(
              cache,
              ~namespace="junie-events-v1",
              eventsPath,
              ~encode=encodeParsed,
              ~decode=decodeParsed,
              parseJunieEvents,
            )
          } else {
            {messageCount: 0, preview: ""}
          }

          let taskName = JsonUtil.stringAt(row, ["taskName"])->Option.getOr(sessionId)
          let updatedAt = JsonUtil.msAt(row, ["updatedAt"])
          let projectDir = JsonUtil.stringAt(row, ["projectDir"])

          sessions->Array.push({
            Session.id: sessionId,
            tool: Junie,
            title: JsonUtil.compact(Some(taskName), ~fallback=sessionId),
            messageCount: parsed.messageCount,
            updatedAtMs: updatedAt,
            cwd: projectDir,
            path: eventsPath,
            preview: parsed.preview,
          })
        | None => ()
        }
      }),
    )

    sessions
  }
}
