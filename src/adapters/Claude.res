let parseClaudeFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let id = switch AdapterUtil.firstParsedLine(lines, line => line->String.includes("\"sessionId\""))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("sessionId"))
  ->Option.flatMap(JSON.Decode.string) {
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
  let previewText = switch previewRow
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("message"))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("content")) {
  | Some(content) => JsonUtil.textFromContent(content)
  | None => ""
  }

  let cwd = switch previewRow
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("cwd"))
  ->Option.flatMap(JSON.Decode.string) {
  | Some(cwd) => Some(cwd)
  | None =>
    AdapterUtil.firstParsedLine(lines, line => line->String.includes("\"cwd\""))
    ->Option.flatMap(JSON.Decode.object)
    ->Option.flatMap(obj => obj->Dict.get("cwd"))
    ->Option.flatMap(JSON.Decode.string)
  }

  let title = switch titleRow->Option.flatMap(JSON.Decode.object) {
  | Some(obj) =>
    switch obj->Dict.get("aiTitle")->Option.flatMap(JSON.Decode.string) {
    | Some(t) => t
    | None => obj->Dict.get("lastPrompt")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
    }
  | None => ""
  }

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
  let files =
    (
      await AdapterUtil.walkFiles(NodePath.joinMany([home, ".claude", "projects"]), path =>
        path->String.endsWith(".jsonl")
      )
    )->Array.filter(path => !(path->String.includes("/subagents/")))

  await AdapterUtil.all(
    files->Array.map(async path => {
      await Cache.cachedValue(
        cache,
        ~namespace="claude-session-v1",
        path,
        ~encode=Session.encode,
        ~decode=Session.decode,
        parseClaudeFile,
      )
    }),
  )
}
