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

    let files = await AdapterUtil.walkFiles(convDir, path => path->String.endsWith(".pb"))
    let sessions = []

    let _ = await AdapterUtil.all(
      files->Array.map(async path => {
        let id = NodePath.basename(path, ".pb")
        let metaPath = NodePath.joinMany([root, "brain", id, "task.md.metadata.json"])
        let metaJson = if await NodeFs.exists(metaPath) {
          await Cache.readJson(metaPath)
        } else {
          None
        }

        let meta = metaJson->Option.flatMap(JSON.Decode.object)->Option.getOr(Dict.make())
        let summary =
          meta->Dict.get("summary")->Option.flatMap(JSON.Decode.string)->Option.getOr("")

        let updatedAt =
          meta
          ->Dict.get("updatedAt")
          ->Option.flatMap(val =>
            switch val {
            | JSON.String(s) => Some(JsonUtil.toMs(Some(JSON.Encode.string(s))))
            | JSON.Number(n) => Some(n)
            | _ => None
            }
          )
          ->Option.getOr(0.0)

        sessions->Array.push({
          Session.id,
          tool: Antigravity,
          title: JsonUtil.compact(Some(summary), ~fallback=id),
          messageCount: 0,
          updatedAtMs: Math.max(updatedAt, await AdapterUtil.fileMtimeMs(path)),
          cwd: cwdById->Dict.get(id),
          path,
          preview: summary,
        })
      }),
    )

    sessions
  }
}
