type parsed = {
  id: string,
  messageCount: int,
  updatedAtMs: float,
  cwd: option<string>,
  path: string,
  preview: string,
}

type indexEntry = {
  title: string,
  updatedAtMs: float,
}

let encodeParsed = (p: parsed): JSON.t =>
  Codec.object([
    ("id", Codec.string(p.id)),
    ("messageCount", Codec.int(p.messageCount)),
    ("updatedAtMs", Codec.float(p.updatedAtMs)),
    ("cwd", Codec.nullableString(p.cwd)),
    ("path", Codec.string(p.path)),
    ("preview", Codec.string(p.preview)),
  ])

let decodeParsed = json =>
  json->Codec.asObject(obj =>
    switch obj->Codec.getString("id") {
    | Some(id) =>
      Some({
        id,
        messageCount: obj->Codec.getInt("messageCount")->Option.getOr(0),
        updatedAtMs: obj->Codec.getFloat("updatedAtMs")->Option.getOr(0.0),
        cwd: obj->Codec.getString("cwd"),
        path: obj->Codec.getString("path")->Option.getOr(""),
        preview: obj->Codec.getString("preview")->Option.getOr(""),
      })
    | None => None
    }
  )

let parseCodexFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let metaRow = AdapterUtil.firstParsedLine(lines, line =>
    JsonUtil.hasJsonField(line, "type", "session_meta")
  )
  let meta = switch metaRow
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("payload"))
  ->Option.flatMap(JSON.Decode.object) {
  | Some(obj) => obj
  | None => Dict.make()
  }

  let id = switch meta->Dict.get("id")->Option.flatMap(JSON.Decode.string) {
  | Some(id) => id
  | None => {
      let base = NodePath.basename(path, ".jsonl")
      base->String.replaceRegExp(/^rollout-[^-]+-/, "")->String.replaceRegExp(/\\.jsonl$/, "")
    }
  }

  let isMessageLine = line =>
    JsonUtil.hasJsonField(line, "type", "response_item") && AdapterUtil.isUserOrAssistantLine(line)

  let previewRow = AdapterUtil.lastParsedLine(lines, isMessageLine)
  let previewText = switch previewRow
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("payload"))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(obj => obj->Dict.get("content")) {
  | Some(content) => JsonUtil.textFromContent(content)
  | None => ""
  }

  {
    id,
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: AdapterUtil.lastTimestampFromLines(lines),
    cwd: meta->Dict.get("cwd")->Option.flatMap(JSON.Decode.string),
    path,
    preview: previewText,
  }
}

let collectCodex = async (home, cache) => {
  let codexDir = NodePath.join(home, ".codex")
  let indexPath = NodePath.join(codexDir, "session_index.jsonl")
  let index = Dict.make()

  if await NodeFs.exists(indexPath) {
    let rows = await AdapterUtil.readJsonl(indexPath)
    rows->Array.forEach(row => {
      switch JSON.Decode.object(row) {
      | Some(obj) =>
        switch obj->Dict.get("id")->Option.flatMap(JSON.Decode.string) {
        | Some(id) =>
          let title =
            obj->Dict.get("thread_name")->Option.flatMap(JSON.Decode.string)->Option.getOr(id)
          let updatedAt =
            obj->Dict.get("updated_at")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
          index->Dict.set(
            id,
            {
              title,
              updatedAtMs: JsonUtil.toMs(Some(JSON.Encode.string(updatedAt))),
            },
          )
        | None => ()
        }
      | None => ()
      }
    })
  }

  let sessionFiles = Array.concat(
    await AdapterUtil.walkFiles(NodePath.join(codexDir, "sessions"), path =>
      path->String.endsWith(".jsonl")
    ),
    await AdapterUtil.walkFiles(NodePath.join(codexDir, "archived_sessions"), path =>
      path->String.endsWith(".jsonl")
    ),
  )

  let byId = Dict.make()

  let _ = await AdapterUtil.all(
    sessionFiles->Array.map(async path => {
      let parsed = await Cache.cachedValue(
        cache,
        ~namespace="codex-file-v1",
        path,
        ~encode=encodeParsed,
        ~decode=decodeParsed,
        parseCodexFile,
      )
      let indexed = index->Dict.get(parsed.id)

      let title = switch indexed {
      | Some(entry) => entry.title
      | None => JsonUtil.compact(Some(parsed.preview), ~fallback=parsed.id)
      }

      let updatedAtMs = switch indexed {
      | Some(entry) => Math.max(parsed.updatedAtMs, entry.updatedAtMs)
      | None => parsed.updatedAtMs
      }

      byId->Dict.set(
        parsed.id,
        {
          Session.id: parsed.id,
          tool: Codex,
          title,
          messageCount: parsed.messageCount,
          updatedAtMs,
          cwd: parsed.cwd,
          path: parsed.path,
          preview: parsed.preview,
        },
      )
    }),
  )

  index
  ->Dict.keysToArray
  ->Array.forEach(id => {
    if byId->Dict.get(id) == None {
      let entry = index->Dict.get(id)->Option.getOr({title: id, updatedAtMs: 0.0})
      byId->Dict.set(
        id,
        {
          Session.id,
          tool: Codex,
          title: entry.title,
          messageCount: 0,
          updatedAtMs: entry.updatedAtMs,
          cwd: None,
          path: indexPath,
          preview: "",
        },
      )
    }
  })

  byId->Dict.valuesToArray
}
