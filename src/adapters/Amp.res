// Amp threads are a single JSON object per file, so parse it whole rather than
// scanning text lines for fields.
let parseAmpFile = async path => {
  let content = await NodeFs.readFile(path, "utf8")
  let root = switch JSON.parseOrThrow(content) {
  | json => json->JSON.Decode.object
  | exception _ => None
  }

  switch root {
  | None => None
  | Some(obj) =>
    let id = obj->Codec.getString("id")->Option.getOr("")
    if id == "" {
      None
    } else {
      let title = obj->Codec.getString("title")
      let created = obj->Codec.getFloat("created")->Option.getOr(0.0)

      let treeUri =
        obj
        ->Dict.get("env")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.flatMap(o => o->Dict.get("initial"))
        ->Option.flatMap(JSON.Decode.object)
        ->Option.flatMap(o => o->Dict.get("trees"))
        ->Option.flatMap(JSON.Decode.array)
        ->Option.flatMap(arr => arr->Array.get(0))
        ->Option.flatMap(JSON.Decode.object)
        ->Option.flatMap(o => o->Dict.get("uri"))
        ->Option.flatMap(JSON.Decode.string)

      let messages = obj->Dict.get("messages")->Option.flatMap(JSON.Decode.array)->Option.getOr([])

      let isUserOrAssistant = msg =>
        switch msg->JSON.Decode.object->Option.flatMap(o => o->Codec.getString("role")) {
        | Some("user") | Some("assistant") => true
        | _ => false
        }

      let previewText = switch messages
      ->Array.get(messages->Array.length - 1)
      ->Option.flatMap(JSON.Decode.object)
      ->Option.flatMap(o => o->Dict.get("content")) {
      | Some(content) => JsonUtil.textFromContent(content)
      | None => ""
      }

      let sentAt =
        messages
        ->Array.toReversed
        ->Array.findMap(msg =>
          msg
          ->JSON.Decode.object
          ->Option.flatMap(o => o->Dict.get("meta"))
          ->Option.flatMap(JSON.Decode.object)
          ->Option.flatMap(o => o->Dict.get("sentAt"))
          ->Option.flatMap(JSON.Decode.float)
        )
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
