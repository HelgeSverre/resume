type parsed = {
  messageCount: int,
}

let encodeParsed = (p: parsed): JSON.t =>
  Codec.object([("messageCount", Codec.int(p.messageCount))])

let decodeParsed = json =>
  json->Codec.asObject(obj => Some({
    messageCount: obj->Codec.getInt("messageCount")->Option.getOr(0),
  }))

let parseKimiWire = async wirePath => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(wirePath, "utf8"))
  {
    messageCount: AdapterUtil.countLines(lines, line =>
      JsonUtil.hasJsonField(line, "type", "context.append_message")
    ),
  }
}

let collectKimi = async (home, cache) => {
  let indexPath = NodePath.joinMany([home, ".kimi-code", "session_index.jsonl"])

  let indexExists = await NodeFs.exists(indexPath)
  if !indexExists {
    []
  } else {
    let sessions = []
    let rows = await AdapterUtil.readJsonl(indexPath)

    let _ = await AdapterUtil.all(
      rows->Array.map(async row => {
        let rowObj = row->JSON.Decode.object->Option.getOr(Dict.make())
        let sessionId = rowObj->Dict.get("sessionId")->Option.flatMap(JSON.Decode.string)
        let sessionDir = rowObj->Dict.get("sessionDir")->Option.flatMap(JSON.Decode.string)

        switch (sessionId, sessionDir) {
        | (Some(id), Some(dir)) =>
          let stateJson = await Cache.readJson(NodePath.join(dir, "state.json"))
          let state = stateJson->Option.flatMap(JSON.Decode.object)->Option.getOr(Dict.make())

          let wirePath = NodePath.joinMany([dir, "agents", "main", "wire.jsonl"])
          let parsed = if await NodeFs.exists(wirePath) {
            await Cache.cachedValue(
              cache,
              ~namespace="kimi-wire-v1",
              wirePath,
              ~encode=encodeParsed,
              ~decode=decodeParsed,
              parseKimiWire,
            )
          } else {
            {messageCount: 0}
          }

          let title = state->Dict.get("title")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
          let lastPrompt =
            state->Dict.get("lastPrompt")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
          let preview = JsonUtil.compact(Some(lastPrompt), ~fallback="")
          let updatedAt =
            state
            ->Dict.get("updatedAt")
            ->Option.flatMap(val =>
              switch val {
              | JSON.String(s) => Some(JsonUtil.toMs(Some(JSON.Encode.string(s))))
              | JSON.Number(n) => Some(n)
              | _ => None
              }
            )
            ->Option.getOr(0.0)
          let createdAt =
            state
            ->Dict.get("createdAt")
            ->Option.flatMap(val =>
              switch val {
              | JSON.String(s) => Some(JsonUtil.toMs(Some(JSON.Encode.string(s))))
              | JSON.Number(n) => Some(n)
              | _ => None
              }
            )
            ->Option.getOr(0.0)
          let workDir = rowObj->Dict.get("workDir")->Option.flatMap(JSON.Decode.string)

          sessions->Array.push({
            Session.id,
            tool: Kimi,
            title: JsonUtil.compact(Some(title == "" ? preview : title), ~fallback=id),
            messageCount: parsed.messageCount,
            updatedAtMs: Math.max(
              Math.max(updatedAt, createdAt),
              await AdapterUtil.fileMtimeMs(wirePath),
            ),
            cwd: workDir,
            path: wirePath,
            preview,
          })
        | _ => ()
        }
      }),
    )

    sessions
  }
}
