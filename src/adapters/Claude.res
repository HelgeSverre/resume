let parseClaudeFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let id = switch AdapterUtil.firstParsedLine(lines, line =>
    line->String.includes("\"sessionId\"")
  )->Option.flatMap(j => JsonUtil.stringAt(j, ["sessionId"])) {
  | Some(id) => id
  | None => NodePath.basename(path, ".jsonl")
  }

  let titleRow =
    AdapterUtil.firstParsedLine(lines, line =>
      JsonUtil.hasJsonField(line, "type", "ai-title")
    )->Option.orElse(
      AdapterUtil.firstParsedLine(lines, line =>
        JsonUtil.hasJsonField(line, "type", "last-prompt")
      ),
    )

  let isMessageLine = line => {
    (JsonUtil.hasJsonField(line, "type", "user") ||
    JsonUtil.hasJsonField(line, "type", "assistant")) &&
    !(line->String.includes("\"isMeta\":true")) &&
    !(line->String.includes("\"isMeta\": true"))
  }

  let previewRow = AdapterUtil.lastParsedLine(lines, isMessageLine)
  let previewText = previewRow->Option.mapOr("", j => JsonUtil.textAt(j, ["message", "content"]))

  let cwd =
    previewRow
    ->Option.flatMap(j => JsonUtil.stringAt(j, ["cwd"]))
    ->Option.orElse(
      AdapterUtil.firstParsedLine(lines, line =>
        line->String.includes("\"cwd\"")
      )->Option.flatMap(j => JsonUtil.stringAt(j, ["cwd"])),
    )

  let title =
    titleRow
    ->Option.flatMap(j =>
      JsonUtil.stringAt(j, ["aiTitle"])->Option.orElse(JsonUtil.stringAt(j, ["lastPrompt"]))
    )
    ->Option.getOr("")

  {
    Session.id,
    tool: Claude,
    title: JsonUtil.compact(Some(title == "" ? previewText : title), ~fallback=id),
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: AdapterUtil.lastTimestampFromLines(lines),
    cwd,
    path,
    preview: previewText,
  }
}

let collectClaude = async (home, cache) => {
  await AdapterUtil.collectCachedSessions(
    ~root=NodePath.joinMany([home, ".claude", "projects"]),
    ~matches=path => path->String.endsWith(".jsonl") && !(path->String.includes("/subagents/")),
    ~namespace="claude-session-v1",
    ~parse=parseClaudeFile,
    cache,
  )
}
