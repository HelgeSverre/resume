let collectAntigravity = async home => {
  let root = NodePath.joinMany([home, ".gemini", "antigravity-cli"])
  let convDir = NodePath.join(root, "conversations")

  let convDirExists = await NodeFs.exists(convDir)
  if !convDirExists {
    []
  } else {
    let cwdPath = NodePath.joinMany([root, "cache", "last_conversations.json"])
    let cwdMapJson = if await NodeFs.exists(cwdPath) {
      await Cache.readJson(cwdPath)
    } else {
      None
    }

    let cwdById = Dict.make()
    switch cwdMapJson->Option.flatMap(JSON.Decode.object) {
    | Some(cwdMap) =>
      cwdMap->Dict.forEachWithKey((idJson, cwd) => {
        switch idJson->JSON.Decode.string {
        | Some(id) => cwdById->Dict.set(id, cwd)
        | None => ()
        }
      })
    | None => ()
    }

    let summaries = Dict.make()
    let summariesPath = NodePath.join(root, "conversation_summaries.db")
    if await NodeFs.exists(summariesPath) {
      NodeSqlite.query(
        summariesPath,
        "SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris " ++ "FROM conversation_summaries",
      )->Array.forEach(row =>
        switch JsonUtil.stringAt(row, ["conversation_id"]) {
        | Some(id) => summaries->Dict.set(id, row)
        | None => ()
        }
      )
    }

    let files = await AdapterUtil.walkFiles(convDir, path =>
      path->String.endsWith(".pb") || path->String.endsWith(".db")
    )
    let sessions = []

    let _ = await AdapterUtil.mapBounded(files, async path => {
      let id = if path->String.endsWith(".db") {
        NodePath.basename(path, ".db")
      } else {
        NodePath.basename(path, ".pb")
      }
      let metaPath = NodePath.joinMany([root, "brain", id, "task.md.metadata.json"])
      let metaJson = if await NodeFs.exists(metaPath) {
        await Cache.readJson(metaPath)
      } else {
        None
      }

      let summary =
        metaJson->Option.flatMap(j => JsonUtil.stringAt(j, ["summary"]))->Option.getOr("")
      let updatedAt = metaJson->Option.mapOr(0.0, j => JsonUtil.msAt(j, ["updatedAt"]))
      let indexed = summaries->Dict.get(id)
      let indexedTitle =
        indexed->Option.flatMap(row => JsonUtil.stringAt(row, ["title"]))->Option.getOr("")
      let indexedPreview =
        indexed->Option.flatMap(row => JsonUtil.stringAt(row, ["preview"]))->Option.getOr("")
      let workspaceUris =
        indexed
        ->Option.flatMap(row => JsonUtil.stringAt(row, ["workspace_uris"]))
        ->Option.flatMap(text =>
          try {
            JSON.parseOrThrow(text)->JSON.Decode.array
          } catch {
          | _ => None
          }
        )
      let indexedCwd =
        workspaceUris
        ->Option.flatMap(uris => uris->Array.get(0))
        ->Option.flatMap(JSON.Decode.string)
        ->Option.flatMap(uri => JsonUtil.cwdFromFileUri(Some(uri)))

      let countedSteps = if path->String.endsWith(".db") {
        NodeSqlite.query(path, "SELECT COUNT(*) AS count FROM steps")
        ->Array.get(0)
        ->Option.flatMap(row => JsonUtil.floatAt(row, ["count"]))
        ->Option.mapOr(0, Float.toInt)
      } else {
        0
      }
      let indexedSteps =
        indexed
        ->Option.flatMap(row => JsonUtil.floatAt(row, ["step_count"]))
        ->Option.mapOr(0, Float.toInt)

      sessions->Array.push({
        Session.id,
        tool: Antigravity,
        title: JsonUtil.compact(Some(indexedTitle == "" ? summary : indexedTitle), ~fallback=id),
        messageCount: countedSteps > indexedSteps ? countedSteps : indexedSteps,
        updatedAtMs: Math.max(
          Math.max(
            updatedAt,
            indexed->Option.mapOr(0.0, row => JsonUtil.msAt(row, ["last_modified_time"])),
          ),
          await AdapterUtil.fileMtimeMs(path),
        ),
        cwd: cwdById->Dict.get(id)->Option.orElse(indexedCwd),
        path,
        preview: indexedPreview == "" ? summary : indexedPreview,
      })
    })

    sessions
  }
}
