let parsePiFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let headerRow = AdapterUtil.firstParsedLine(lines, line =>
    JsonUtil.hasJsonField(line, "type", "session")
  )

  let id = switch headerRow->Option.flatMap(j => JsonUtil.stringAt(j, ["id"])) {
  | Some(id) => id
  | None => {
      let base = NodePath.basename(path, ".jsonl")
      base
      ->String.split("_")
      ->Array.get(base->String.split("_")->Array.length - 1)
      ->Option.getOr(base)
    }
  }

  let isMessageLine = line =>
    JsonUtil.hasJsonField(line, "type", "message") && AdapterUtil.isUserOrAssistantLine(line)

  let previewRow = AdapterUtil.lastParsedLine(lines, isMessageLine)
  let previewText = previewRow->Option.mapOr("", j => JsonUtil.textAt(j, ["message", "content"]))

  let headerTs = headerRow->Option.mapOr(0.0, j => JsonUtil.msAt(j, ["timestamp"]))

  {
    Session.id,
    tool: Pi,
    title: JsonUtil.compact(Some(previewText), ~fallback=id),
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: Math.max(headerTs, AdapterUtil.lastTimestampFromLines(lines)),
    cwd: headerRow->Option.flatMap(j => JsonUtil.stringAt(j, ["cwd"])),
    path,
    preview: previewText,
  }
}

let collectPi = async (home, cache) => {
  let files = await AdapterUtil.walkFiles(
    NodePath.joinMany([home, ".pi", "agent", "sessions"]),
    path => path->String.endsWith(".jsonl"),
  )

  await AdapterUtil.all(
    files->Array.map(async path => {
      await Cache.cachedValue(
        cache,
        ~namespace="pi-session-v1",
        path,
        ~encode=Session.encode,
        ~decode=Session.decode,
        parsePiFile,
      )
    }),
  )
}
