open TestSupport

let encode = JSON.Encode.string
let decode = JSON.Decode.string

let populate = async (cache, namespace, file, value) => {
  let _ = await Cache.cachedValue(cache, ~namespace, file, ~encode, ~decode, async _ => value)
}

let entryKeys = async path => {
  let content = await readFile(path)
  switch JSON.parseOrThrow(content)->JSON.Decode.object {
  | Some(cache) =>
    switch cache->Dict.get("entries")->Option.flatMap(JSON.Decode.object) {
    | Some(entries) => entries->Dict.keysToArray
    | None => []
    }
  | None => []
  }
}

let pathIsMissing = async path => {
  try {
    let _ = await NodeFs.stat(path)
    false
  } catch {
  | _ => true
  }
}

test("concurrent cache saves preserve distinct fresh entries", async context => {
  let home = await fixture(context, "resume-cache-concurrency-")
  let first = NodePath.join(home, "first")
  let second = NodePath.join(home, "second")
  await writeFile(first, "first")
  await writeFile(second, "second")

  let left = await Cache.loadCache(home)
  let right = await Cache.loadCache(home)
  let _ = await Promise.all([
    populate(left, "adapter-a", first, "left"),
    populate(right, "adapter-b", second, "right"),
  ])
  let _ = await Promise.all([Cache.saveCache(left), Cache.saveCache(right)])

  let keys = await entryKeys(left.path)
  equal(keys->Array.length, 2)
  ok(keys->Array.includes("adapter-a\x00" ++ first))
  ok(keys->Array.includes("adapter-b\x00" ++ second))
  ok(await pathIsMissing(left.path ++ ".lock"))
})

test("an all-hit scan prunes entries for deleted session files", async context => {
  let home = await fixture(context, "resume-cache-concurrency-")
  let current = NodePath.join(home, "current")
  let deleted = NodePath.join(home, "deleted")
  await writeFile(current, "current")
  await writeFile(deleted, "deleted")

  let cache = await Cache.loadCache(home)
  await populate(cache, "adapter", current, "current")
  await populate(cache, "adapter", deleted, "deleted")
  await Cache.saveCache(cache)
  await remove(deleted, {"recursive": false, "force": false})

  let reloaded = await Cache.loadCache(home)
  await populate(reloaded, "adapter", current, "must be a cache hit")
  await Cache.saveCache(reloaded)

  deepEqual(await entryKeys(reloaded.path), ["adapter\x00" ++ current])
})

test("a stale lock from a dead process is reclaimed", async context => {
  let home = await fixture(context, "resume-cache-concurrency-")
  let file = NodePath.join(home, "session")
  await writeFile(file, "session")
  let cache = await Cache.loadCache(home)
  await populate(cache, "adapter", file, "session")

  let lock = cache.path ++ ".lock"
  await mkdir(lock)
  await writeFile(NodePath.join(lock, "owner"), "999999999:stale")
  await Cache.saveCache(cache)

  ok(await pathIsMissing(lock))
  let saved = JSON.parseOrThrow(await readFile(cache.path))
  let version = saved->JSON.Decode.object->Option.flatMap(cache => cache->Dict.get("version"))
  equal(version->Option.flatMap(JSON.Decode.string), Some("2"))
})

test("a fresh incomplete lock is not reclaimed", async context => {
  let home = await fixture(context, "resume-cache-concurrency-")
  let lock = NodePath.join(home, "fresh.lock")
  await mkdir(lock)

  let acquired = await Cache.acquireLock(~path=lock, ~attempt=100)
  equal(acquired, None)
  ok(!(await pathIsMissing(lock)))
})
