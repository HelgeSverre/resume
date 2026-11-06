// Poolside's ACP client keeps one resumable-session summary per JSON file.
// The file does not include the full transcript, but it has the ID accepted by
// `pool --resume`, the working directory, title, and last-update timestamp.

@new external invalidSummary: string => exn = "Error"

let parsePoolFile = async path => {
  let json = JSON.parseOrThrow(await NodeFs.readFile(path, "utf8"))

  switch JsonUtil.stringAt(json, ["sessionId"])->Option.map(String.trim) {
  | Some(id) if id != "" => {
      Session.id,
      tool: Pool,
      title: JsonUtil.compact(JsonUtil.stringAt(json, ["title"]), ~fallback=id),
      messageCount: 0,
      updatedAtMs: JsonUtil.msAt(json, ["updatedAt"]),
      cwd: JsonUtil.stringAt(json, ["cwd"]),
      path,
      preview: "",
    }
  | _ => throw(invalidSummary("Pool ACP summary is missing sessionId"))
  }
}

let collectPool = async (home, cache) =>
  await AdapterUtil.collectCachedSessions(
    ~root=NodePath.joinMany([home, "Library", "Application Support", "poolside", "acp"]),
    ~matches=path => path->String.endsWith(".json"),
    // v1 accepted a filename fallback for a missing id. Refresh those entries
    // so malformed summaries no longer produce non-resumable commands.
    ~namespace="pool-acp-v2",
    ~parse=parsePoolFile,
    cache,
  )
