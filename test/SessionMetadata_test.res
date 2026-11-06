open TestSupport

test("Codex resumed sessions show the current turn directory", async context => {
  let home = await fixture(context, "resume-codex-cwd-")
  let path = NodePath.join(home, "rollout.jsonl")
  await writeFile(
    path,
    "{\"type\":\"session_meta\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"payload\":{\"id\":\"resumed\",\"cwd\":\"/old-project\"}}\n" ++ "{\"type\":\"turn_context\",\"timestamp\":\"2026-11-06T12:00:00Z\",\"payload\":{\"cwd\":\"/current-project\"}}\n",
  )
  equal((await Codex.parseCodexFile(path)).cwd, Some("/current-project"))
})

test("Codex updated time cannot move backwards with out-of-order records", async context => {
  let home = await fixture(context, "resume-codex-updated-")
  let path = NodePath.join(home, "rollout.jsonl")
  await writeFile(
    path,
    "{\"type\":\"session_meta\",\"timestamp\":\"2026-11-06T12:00:00Z\",\"payload\":{\"id\":\"resumed\"}}\n" ++ "{\"type\":\"response_item\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"payload\":{\"role\":\"assistant\",\"content\":\"delayed record\"}}\n",
  )
  equal(
    (await Codex.parseCodexFile(path)).updatedAtMs,
    JsonUtil.msFromString("2026-11-06T12:00:00Z"),
  )
})

test("Codex refreshes cached metadata from the previous parser", async context => {
  let home = await fixture(context, "resume-codex-metadata-cache-")
  let directory = NodePath.joinMany([home, ".codex", "sessions"])
  await mkdir(directory)
  let path = NodePath.join(directory, "rollout.jsonl")
  await writeFile(
    path,
    "{\"type\":\"session_meta\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"payload\":{\"id\":\"resumed\",\"cwd\":\"/old-project\"}}\n" ++ "{\"type\":\"turn_context\",\"timestamp\":\"2026-11-06T12:00:00Z\",\"payload\":{\"cwd\":\"/current-project\"}}\n",
  )
  let cache = await Cache.loadCache(home)
  let _ = await Cache.cachedValue(
    cache,
    ~namespace="codex-file-v2",
    path,
    ~encode=Codex.encodeParsed,
    ~decode=Codex.decodeParsed,
    async _ => {
      Codex.id: "resumed",
      cwd: Some("/old-project"),
      messageCount: 0,
      updatedAtMs: 0.,
      preview: "",
      path,
    },
  )
  let sessions = await Codex.collectCodex(home, cache)
  equal(sessions->Array.length, 1)
  let session = sessions[0]->Option.getOrThrow
  equal(session.cwd, Some("/current-project"))
})

test(
  "Codex ignores empty turn directories without losing the latest valid folder",
  async context => {
    let home = await fixture(context, "resume-codex-empty-cwd-")
    let path = NodePath.join(home, "rollout.jsonl")
    await writeFile(
      path,
      "{\"type\":\"session_meta\",\"payload\":{\"id\":\"resumed\",\"cwd\":\"/old-project\"}}\n" ++
      "{\"type\":\"turn_context\",\"payload\":{\"cwd\":\"/current-project\"}}\n" ++
      "{\"type\":\"turn_context\",\"payload\":{\"cwd\":\"   \"}}\n" ++ "{\"type\":\"turn_context\",\"payload\":{}}\n",
    )
    equal((await Codex.parseCodexFile(path)).cwd, Some("/current-project"))
  },
)
