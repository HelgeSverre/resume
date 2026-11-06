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
  JsonUtil.object([
    ("id", JsonUtil.string(p.id)),
    ("messageCount", JsonUtil.int(p.messageCount)),
    ("updatedAtMs", JsonUtil.float(p.updatedAtMs)),
    ("cwd", JsonUtil.nullableString(p.cwd)),
    ("path", JsonUtil.string(p.path)),
    ("preview", JsonUtil.string(p.preview)),
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

let rolloutId = path =>
  NodePath.basename(path, ".jsonl")->String.replaceRegExp(/^.*-([0-9a-f]{8}-[0-9a-f-]{27})$/i, "$1")

let parseCodexFile = async path => {
  let id = ref(None)
  let cwd = ref(None)
  let messageCount = ref(0)
  let updatedAtMs = ref(0.0)
  let preview = ref("")

  await JsonLines.forEach(path, json => {
    let timestamp = JsonUtil.msAt(json, ["timestamp"])
    if timestamp > 0.0 {
      updatedAtMs.contents = timestamp
    }
    switch JsonUtil.stringAt(json, ["type"]) {
    | Some("session_meta") if id.contents == None =>
      id.contents = JsonUtil.stringAt(json, ["payload", "id"])
      cwd.contents = JsonUtil.stringAt(json, ["payload", "cwd"])
    | Some("response_item") =>
      switch JsonUtil.stringAt(json, ["payload", "role"]) {
      | Some("user") | Some("assistant") =>
        messageCount.contents = messageCount.contents + 1
        preview.contents = JsonUtil.textAt(json, ["payload", "content"])->JsonUtil.preview
      | _ => ()
      }
    | _ => ()
    }
  })

  {
    id: id.contents->Option.getOr(rolloutId(path)),
    messageCount: messageCount.contents,
    updatedAtMs: updatedAtMs.contents,
    cwd: cwd.contents,
    path,
    preview: preview.contents,
  }
}

let collectCodex = async (home, cache) => {
  let codexDir = NodePath.join(home, ".codex")
  let indexPath = NodePath.join(codexDir, "session_index.jsonl")
  let index = Dict.make()

  if await NodeFs.exists(indexPath) {
    let rows = await AdapterUtil.readIndex(indexPath)
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

  let byId: Dict.t<Session.t> = Dict.make()
  let parsedTimes: Dict.t<float> = Dict.make()

  let _ = await AdapterUtil.mapBounded(sessionFiles, async path => {
    try {
      let parsed = await Cache.cachedValue(
        cache,
        ~namespace="codex-file-v2",
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

      let candidate = {
        Session.id: parsed.id,
        tool: Codex,
        title,
        messageCount: parsed.messageCount,
        updatedAtMs,
        cwd: parsed.cwd,
        path: parsed.path,
        preview: parsed.preview,
      }
      // Index timestamps apply to both copies; compare their own transcript
      // timestamps so an index rename cannot mask a newer active rollout.
      switch parsedTimes->Dict.get(parsed.id) {
      | Some(existing) if existing >= parsed.updatedAtMs => ()
      | _ =>
        parsedTimes->Dict.set(parsed.id, parsed.updatedAtMs)
        byId->Dict.set(parsed.id, candidate)
      }
    } catch {
    | _ => Diagnostics.warn("Warning: skipped an unreadable Codex session")
    }
  })

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
