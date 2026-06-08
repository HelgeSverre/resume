let parseCopilotFile = async path => {
  let id = NodePath.basename(NodePath.dirname(path), "")
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let startRow = AdapterUtil.firstParsedLine(lines, line =>
    JsonUtil.hasJsonField(line, "type", "session.start")
  )
  let cwd = startRow->Option.flatMap(j => JsonUtil.stringAt(j, ["data", "context", "cwd"]))

  let isUser = line => JsonUtil.hasJsonField(line, "type", "user.message")
  let isMessage = line => isUser(line) || JsonUtil.hasJsonField(line, "type", "assistant.message")

  let firstUser = AdapterUtil.firstParsedLine(lines, isUser)
  let lastMessage = AdapterUtil.lastParsedLine(lines, isMessage)

  let titleText = firstUser->Option.mapOr("", j => JsonUtil.textAt(j, ["data", "content"]))
  let previewText = lastMessage->Option.mapOr("", j => JsonUtil.textAt(j, ["data", "content"]))

  let title = JsonUtil.compact(Some(titleText), ~fallback="")
  let preview = JsonUtil.compact(Some(previewText), ~fallback="")

  {
    Session.id,
    tool: Copilot,
    title: title == "" ? preview : title,
    messageCount: AdapterUtil.countLines(lines, isMessage),
    updatedAtMs: AdapterUtil.lastTimestampFromLines(lines),
    cwd,
    path,
    preview,
  }
}

let collectCopilot = async (home, cache) => {
  let files = await AdapterUtil.walkFiles(
    NodePath.joinMany([home, ".copilot", "session-state"]),
    path => NodePath.basename(path, "") == "events.jsonl",
  )

  await AdapterUtil.all(
    files->Array.map(async path => {
      await Cache.cachedValue(
        cache,
        ~namespace="copilot-session-v1",
        path,
        ~encode=Session.encode,
        ~decode=Session.decode,
        parseCopilotFile,
      )
    }),
  )
}
