open NodeProcess

let sessionRoot = (~home, ~sessionDir=?, ~agentDir=?) =>
  switch sessionDir {
  | Some(dir) => dir
  | None =>
    switch agentDir {
    | Some(dir) => NodePath.join(dir, "sessions")
    | None => NodePath.joinMany([home, ".pi", "agent", "sessions"])
    }
  }

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

  let savedName =
    AdapterUtil.lastParsedLine(lines, line =>
      JsonUtil.hasJsonField(line, "type", "session_info")
    )->Option.flatMap(j => JsonUtil.stringAt(j, ["name"]))

  let headerTs = headerRow->Option.mapOr(0.0, j => JsonUtil.msAt(j, ["timestamp"]))

  {
    Session.id,
    tool: Pi,
    title: JsonUtil.compact(savedName->Option.orElse(Some(previewText)), ~fallback=id),
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: Math.max(headerTs, AdapterUtil.lastTimestampFromLines(lines)),
    cwd: headerRow->Option.flatMap(j => JsonUtil.stringAt(j, ["cwd"])),
    path,
    preview: previewText,
  }
}

let collectPi = async (home, cache) => {
  await AdapterUtil.collectCachedSessions(
    ~root=sessionRoot(
      ~home,
      ~sessionDir=?env->Dict.get("PI_CODING_AGENT_SESSION_DIR"),
      ~agentDir=?env->Dict.get("PI_CODING_AGENT_DIR"),
    ),
    ~matches=path => path->String.endsWith(".jsonl"),
    ~namespace="pi-session-v3",
    ~parse=parsePiFile,
    cache,
  )
}
