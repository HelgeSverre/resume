let parseClaudeFile = async path => {
  let id = ref(None)
  let generatedTitle = ref(None)
  let promptTitle = ref(None)
  let customTitle = ref(None)
  let messageCount = ref(0)
  let updatedAtMs = ref(0.0)
  let preview = ref("")
  let firstCwd = ref(None)
  let lastMessageCwd = ref(None)

  await JsonLines.forEach(path, json => {
    let timestamp = JsonUtil.msAt(json, ["timestamp"])
    if timestamp > 0.0 {
      updatedAtMs.contents = timestamp
    }
    if id.contents == None {
      id.contents = JsonUtil.stringAt(json, ["sessionId"])
    }
    if firstCwd.contents == None {
      firstCwd.contents = JsonUtil.stringAt(json, ["cwd"])
    }
    switch JsonUtil.stringAt(json, ["type"]) {
    | Some("custom-title") =>
      switch JsonUtil.stringAt(json, ["customTitle"])->Option.flatMap(JsonUtil.nonEmpty) {
      | Some(title) => customTitle.contents = Some(title)
      | None => ()
      }
    | Some("ai-title") =>
      generatedTitle.contents =
        JsonUtil.stringAt(json, ["aiTitle"])->Option.flatMap(JsonUtil.nonEmpty)
    | Some("last-prompt") =>
      promptTitle.contents =
        JsonUtil.stringAt(json, ["lastPrompt"])->Option.flatMap(JsonUtil.nonEmpty)
    | Some("user") | Some("assistant") =>
      let isMeta =
        json
        ->JSON.Decode.object
        ->Option.flatMap(obj => obj->Dict.get("isMeta"))
        ->Option.flatMap(JSON.Decode.bool)
        ->Option.getOr(false)
      if !isMeta {
        messageCount.contents = messageCount.contents + 1
        preview.contents = JsonUtil.textAt(json, ["message", "content"])->JsonUtil.preview
        lastMessageCwd.contents = JsonUtil.stringAt(json, ["cwd"])
      }
    | _ => ()
    }
  })

  let id = id.contents->Option.getOr(NodePath.basename(path, ".jsonl"))
  let title =
    customTitle.contents
    ->Option.orElse(generatedTitle.contents)
    ->Option.orElse(promptTitle.contents)
    ->Option.getOr("")

  {
    Session.id,
    tool: Claude,
    title: JsonUtil.compact(Some(title == "" ? preview.contents : title), ~fallback=id),
    messageCount: messageCount.contents,
    updatedAtMs: updatedAtMs.contents,
    cwd: lastMessageCwd.contents->Option.orElse(firstCwd.contents),
    path,
    preview: preview.contents,
  }
}

let collectClaude = async (home, cache) => {
  await AdapterUtil.collectCachedSessions(
    ~root=NodePath.joinMany([home, ".claude", "projects"]),
    ~matches=path => path->String.endsWith(".jsonl") && !NodePath.hasSegment(path, "subagents"),
    ~namespace="claude-session-v3",
    ~parse=parseClaudeFile,
    cache,
  )
}
