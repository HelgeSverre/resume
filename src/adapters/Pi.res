let parsePiFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let headerRow = AdapterUtil.firstParsedLine(lines, line =>
    JsonUtil.hasJsonField(line, "type", "session")
  )
  let header = switch headerRow->Option.flatMap(JSON.Decode.object) {
  | Some(obj) => obj
  | None => Dict.make()
  }

  let id = switch header->Dict.get("id")->Option.flatMap(JSON.Decode.string) {
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
  let previewText = switch previewRow
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("message"))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("content")) {
  | Some(content) => JsonUtil.textFromContent(content)
  | None => ""
  }

  let headerTs = switch header->Dict.get("timestamp") {
  | Some(JSON.String(s)) => JsonUtil.toMs(Some(JSON.Encode.string(s)))
  | Some(JSON.Number(n)) => n
  | _ => 0.0
  }

  {
    Session.id,
    tool: Pi,
    title: JsonUtil.compact(Some(previewText), ~fallback=id),
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: Math.max(headerTs, AdapterUtil.lastTimestampFromLines(lines)),
    cwd: header->Dict.get("cwd")->Option.flatMap(JSON.Decode.string),
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
