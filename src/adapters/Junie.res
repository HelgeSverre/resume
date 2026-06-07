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

  let preview = switch previewEvent->Option.flatMap(JSON.Decode.object) {
  | Some(obj) =>
    switch obj->Dict.get("presentablePrompt")->Option.flatMap(JSON.Decode.string) {
    | Some(t) => t
    | None =>
      switch obj->Dict.get("prompt")->Option.flatMap(JSON.Decode.string) {
      | Some(t) => t
      | None => obj->Dict.get("text")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
      }
    }
  | None => ""
  }

  let fallbackPreview = switch fallbackPreviewEvent->Option.flatMap(JSON.Decode.object) {
  | Some(obj) =>
    switch obj->Dict.get("text")->Option.flatMap(JSON.Decode.string) {
    | Some(t) => t
    | None => obj->Dict.get("details")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
    }
  | None => ""
  }

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
        switch JSON.Decode.object(row)
        ->Option.flatMap(obj => obj->Dict.get("sessionId"))
        ->Option.flatMap(JSON.Decode.string) {
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

          let rowObj = row->JSON.Decode.object->Option.getOr(Dict.make())
          let taskName =
            rowObj
            ->Dict.get("taskName")
            ->Option.flatMap(JSON.Decode.string)
            ->Option.getOr(sessionId)
          let updatedAt =
            rowObj
            ->Dict.get("updatedAt")
            ->Option.flatMap(val =>
              switch val {
              | JSON.String(s) => Some(JsonUtil.toMs(Some(JSON.Encode.string(s))))
              | JSON.Number(n) => Some(n)
              | _ => None
              }
            )
            ->Option.getOr(0.0)
          let projectDir = rowObj->Dict.get("projectDir")->Option.flatMap(JSON.Decode.string)

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
