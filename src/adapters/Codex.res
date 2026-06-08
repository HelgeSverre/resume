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

module D = JsonCombinators.Json.Decode

let parsedDecoder = D.object(field => {
  id: field.required("id", D.string),
  messageCount: field.optional("messageCount", D.float)->Option.mapOr(0, Float.toInt),
  updatedAtMs: field.optional("updatedAtMs", D.float)->Option.getOr(0.0),
  cwd: field.optional("cwd", D.option(D.string))->Option.getOr(None),
  path: field.optional("path", D.string)->Option.getOr(""),
  preview: field.optional("preview", D.string)->Option.getOr(""),
})

let decodeParsed = json => JsonUtil.decode(json, parsedDecoder)

let parseCodexFile = async path => {
  let lines = AdapterUtil.splitLines(await NodeFs.readFile(path, "utf8"))

  let metaRow = AdapterUtil.firstParsedLine(lines, line =>
    JsonUtil.hasJsonField(line, "type", "session_meta")
  )
  let id = switch metaRow->Option.flatMap(j => JsonUtil.stringAt(j, ["payload", "id"])) {
  | Some(id) => id
  | None => {
      let base = NodePath.basename(path, ".jsonl")
      base->String.replaceRegExp(/^rollout-[^-]+-/, "")->String.replaceRegExp(/\\.jsonl$/, "")
    }
  }

  let isMessageLine = line =>
    JsonUtil.hasJsonField(line, "type", "response_item") && AdapterUtil.isUserOrAssistantLine(line)

  let previewRow = AdapterUtil.lastParsedLine(lines, isMessageLine)
  let previewText = previewRow->Option.mapOr("", j => JsonUtil.textAt(j, ["payload", "content"]))

  {
    id,
    messageCount: AdapterUtil.countLines(lines, isMessageLine),
    updatedAtMs: AdapterUtil.lastTimestampFromLines(lines),
    cwd: metaRow->Option.flatMap(j => JsonUtil.stringAt(j, ["payload", "cwd"])),
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
      switch JsonUtil.stringAt(row, ["id"]) {
      | Some(id) =>
        index->Dict.set(
          id,
          {
            title: JsonUtil.stringAt(row, ["thread_name"])->Option.getOr(id),
            updatedAtMs: JsonUtil.msAt(row, ["updated_at"]),
          },
        )
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
