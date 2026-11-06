open TestSupport

let json = JSON.parseOrThrow

test("Pool skips ACP summaries without a nonempty sessionId", async context => {
  let home = await fixture(context, "resume-pool-validation-")
  let directory = NodePath.joinMany([
    home,
    "Library",
    "Application Support",
    "poolside",
    "acp",
    "fixture",
  ])
  let valid = NodePath.join(directory, "valid.json")
  let missing = NodePath.join(directory, "missing.json")
  let empty = NodePath.join(directory, "empty.json")
  await writeJson(valid, json(`{"sessionId":"real-id","title":"Valid"}`))
  await writeJson(missing, json(`{"title":"No ID"}`))
  await writeJson(empty, json(`{"sessionId":"  ","title":"Empty ID"}`))

  await rejects(() => Pool.parsePoolFile(missing))
  await rejects(() => Pool.parsePoolFile(empty))

  let sessions = await Pool.collectPool(home, await Cache.loadCache(home))
  deepEqual(sessions->Array.map(session => session.id), ["real-id"])
})
