module D = JsonUtil.Decode

// Amp threads are a single JSON object per file, so parse it whole rather than
// scanning text lines for fields.
let parseAmpFile = async path => {
  let content = await NodeFs.readFile(path, "utf8")
  let root = switch JSON.parseOrThrow(content) {
  | json => Some(json)
  | exception _ => None
  }

  switch root {
  | None => None
  | Some(json) =>
    let id = JsonUtil.stringAt(json, ["id"])->Option.getOr("")
    if id == "" {
      None
    } else {
      let title = JsonUtil.stringAt(json, ["title"])
      let created = JsonUtil.msAt(json, ["created"])

      let treeUri =
        JsonUtil.decode(json, JsonUtil.at(["env", "initial", "trees"], D.array(D.id)))
        ->Option.flatMap(trees => trees->Array.get(0))
        ->Option.flatMap(tree => JsonUtil.stringAt(tree, ["uri"]))

      let messages =
        JsonUtil.decode(json, JsonUtil.at(["messages"], D.array(D.id)))->Option.getOr([])

      let isUserOrAssistant = msg =>
        switch JsonUtil.stringAt(msg, ["role"]) {
        | Some("user") | Some("assistant") => true
        | _ => false
        }

      let previewText =
        messages
        ->Array.get(messages->Array.length - 1)
        ->Option.mapOr("", msg => JsonUtil.textAt(msg, ["content"]))

      let sentAt =
        messages
        ->Array.toReversed
        ->Array.findMap(msg => JsonUtil.floatAt(msg, ["meta", "sentAt"]))
        ->Option.getOr(0.0)

      let preview = JsonUtil.compact(Some(previewText), ~fallback="")
      let titleText = JsonUtil.compact(title, ~fallback="")

      Some({
        Session.id,
        tool: Amp,
        title: titleText == "" ? preview : titleText,
        messageCount: messages->Array.filter(isUserOrAssistant)->Array.length,
        updatedAtMs: Math.max(Math.max(sentAt, created), await AdapterUtil.fileMtimeMs(path)),
        cwd: JsonUtil.cwdFromFileUri(treeUri),
        path,
        preview,
      })
    }
  }
}

let collectAmp = async (home, cache) => {
  let files = await AdapterUtil.walkFiles(
    NodePath.joinMany([home, ".local", "share", "amp", "threads"]),
    path => NodePath.basename(path, "")->String.startsWith("T-") && path->String.endsWith(".json"),
  )

  let sessions = []
  let _ = await AdapterUtil.all(
    files->Array.map(async path => {
      switch await Cache.cachedValue(
        cache,
        ~namespace="amp-thread-v1",
        path,
        ~encode=Session.encodeOption,
        ~decode=Session.decodeOption,
        parseAmpFile,
      ) {
      | Some(session) => sessions->Array.push(session)
      | None => ()
      }
    }),
  )
  sessions
}
