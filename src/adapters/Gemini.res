type message = {id: string, row: JSON.t}

type replay = {
  mutable sessionId: option<string>,
  mutable summary: string,
  mutable updatedAtMs: float,
  mutable messages: array<message>,
}

let messagesAt = (row, keys) =>
  JsonUtil.decode(row, JsonUtil.at(keys, JsonUtil.Decode.array(JsonUtil.Decode.id)))

let isMessage = row =>
  switch JsonUtil.stringAt(row, ["type"]) {
  | Some("user") | Some("gemini") => true
  | _ => false
  }

let addMessage = (state, row) =>
  switch JsonUtil.stringAt(row, ["id"]) {
  | Some(id) =>
    let next = {id, row}
    let index = state.messages->Array.findIndex(message => message.id == id)
    if index >= 0 {
      state.messages[index] = next
    } else {
      state.messages->Array.push(next)
    }
  | None => ()
  }

let replaceMessages = (state, rows) => {
  state.messages = []
  // Old snapshot files did not always give messages an id. They are already
  // a complete replacement array, so retain those records with a local slot
  // key; current append-only records continue to use their durable ids.
  rows->Array.forEachWithIndex((row, index) =>
    switch JsonUtil.stringAt(row, ["id"]) {
    | Some(_) => addMessage(state, row)
    | None => state.messages->Array.push({id: "snapshot-" ++ Int.toString(index), row})
    }
  )
}

let applyMetadata = (state, row) => {
  switch JsonUtil.stringAt(row, ["sessionId"]) {
  | Some(id) => state.sessionId = Some(id)
  | None => ()
  }
  switch JsonUtil.stringAt(row, ["summary"]) {
  | Some(summary) => state.summary = summary
  | None => ()
  }
  let updatedAt = JsonUtil.msAt(row, ["lastUpdated"])
  if updatedAt > 0.0 {
    state.updatedAtMs = updatedAt
  }
}

let applyRewind = (state, id) => {
  let index = state.messages->Array.findIndex(message => message.id == id)
  state.messages = if index >= 0 {
    state.messages->Array.slice(~start=0, ~end=index)
  } else {
    []
  }
}

// Gemini JSONL writes initial metadata, then appends raw message records and
// `$set` metadata updates. Replay the stream instead of reading one snapshot.
let replayRows = rows => {
  let state = {sessionId: None, summary: "", updatedAtMs: 0.0, messages: []}
  rows->Array.forEach(row => {
    switch JsonUtil.stringAt(row, ["$rewindTo"]) {
    | Some(id) => applyRewind(state, id)
    | None =>
      switch JsonUtil.decode(row, JsonUtil.at(["$set"], JsonUtil.Decode.id)) {
      | Some(updates) =>
        applyMetadata(state, updates)
        switch messagesAt(updates, ["messages"]) {
        | Some(messages) => replaceMessages(state, messages)
        | None => ()
        }
      | None =>
        applyMetadata(state, row)
        switch messagesAt(row, ["messages"]) {
        | Some(messages) => replaceMessages(state, messages)
        | None => ()
        }
        if JsonUtil.stringAt(row, ["id"]) != None && JsonUtil.stringAt(row, ["type"]) != None {
          addMessage(state, row)
        }
      }
    }
  })
  state
}

let collectGemini = async home => {
  let root = NodePath.joinMany([home, ".gemini"])
  let projectMap = Dict.make()
  switch await Cache.readJson(NodePath.join(root, "projects.json")) {
  | Some(json) =>
    switch json
    ->JSON.Decode.object
    ->Option.flatMap(obj => obj->Dict.get("projects"))
    ->Option.flatMap(JSON.Decode.object) {
    | Some(projects) =>
      projects->Dict.forEachWithKey((slugJson, cwd) =>
        switch slugJson->JSON.Decode.string {
        | Some(slug) => projectMap->Dict.set(slug, cwd)
        | None => ()
        }
      )
    | None => ()
    }
  | None => ()
  }

  let files = await AdapterUtil.walkFiles(NodePath.join(root, "tmp"), path =>
    NodePath.basename(path, "")->String.startsWith("session-") &&
    (path->String.endsWith(".json") || path->String.endsWith(".jsonl")) &&
    NodePath.basename(NodePath.dirname(path), "") == "chats"
  )
  let groups = await AdapterUtil.collectSome(~label="Gemini session", files, async path => {
    let rows = if path->String.endsWith(".jsonl") {
      await AdapterUtil.readJsonl(path)
    } else {
      switch await Cache.readJson(path) {
      | Some(json) => [json]
      | None => []
      }
    }
    let replay = replayRows(rows)
    switch replay.sessionId {
    | None => None
    | Some(id) =>
      let messages = replay.messages->Array.map(message => message.row)
      let firstUser =
        messages
        ->Array.findMap(row =>
          JsonUtil.stringAt(row, ["type"]) == Some("user")
            ? Some(JsonUtil.textAt(row, ["content"]))
            : None
        )
        ->Option.getOr("")
      let preview =
        messages
        ->Array.toReversed
        ->Array.findMap(row => {
          let text = JsonUtil.textAt(row, ["content"])
          isMessage(row) && text != "" ? Some(text) : None
        })
        ->Option.getOr("")
      let folder = NodePath.basename(NodePath.dirname(NodePath.dirname(path)), "")
      Some({
        Session.id,
        tool: Gemini,
        title: JsonUtil.compact(
          Some(replay.summary == "" ? firstUser : replay.summary),
          ~fallback=id,
        ),
        messageCount: messages->Array.filter(isMessage)->Array.length,
        // `lastUpdated` is the session's logical update time. File mtime can
        // change when a session is copied, restored, or indexed, so only use
        // it for legacy records that did not persist that metadata.
        updatedAtMs: replay.updatedAtMs > 0.0
          ? replay.updatedAtMs
          : await AdapterUtil.fileMtimeMs(path),
        cwd: projectMap->Dict.get(folder),
        path,
        preview: JsonUtil.compact(Some(preview), ~fallback=""),
      })
    }
  })
  groups
}
