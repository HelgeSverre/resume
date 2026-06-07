@module("node:test")
external testAsync: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

// A trivial string-valued codec for exercising the cache.
let encode = JSON.Encode.string
let decode = JSON.Decode.string

let setup = async () => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-cache-"))
  let file = NodePath.join(home, "data.txt")
  await NodeFs.writeFile(file, "hello")
  let cache = await Cache.loadCache(home)
  (home, file, cache)
}

testAsync("cache miss runs the loader and caches the encoded value", async () => {
  let (_home, file, cache) = await setup()
  let calls = ref(0)
  let load = async _ => {
    calls := calls.contents + 1
    "value-a"
  }
  let first = await Cache.cachedValue(cache, ~namespace="t", file, ~encode, ~decode, load)
  let second = await Cache.cachedValue(cache, ~namespace="t", file, ~encode, ~decode, load)
  equal(first, "value-a")
  equal(second, "value-a")
  equal(calls.contents, 1) // loader runs once; second call is an in-memory hit
})

testAsync("a different mtime/size invalidates the cached value", async () => {
  let (_home, file, cache) = await setup()
  let load = async _ => "first"
  let _ = await Cache.cachedValue(cache, ~namespace="t", file, ~encode, ~decode, load)

  await NodeFs.writeFile(file, "much longer content now")
  let reload = async _ => "second"
  let after = await Cache.cachedValue(cache, ~namespace="t", file, ~encode, ~decode, reload)
  equal(after, "second")
})

testAsync("a decode failure falls back to reloading", async () => {
  let (home, file, _cache) = await setup()
  // Prime an entry, then reload the cache so the value is raw JSON on disk.
  let cache = await Cache.loadCache(home)
  let _ = await Cache.cachedValue(cache, ~namespace="t", file, ~encode, ~decode, async _ => "x")
  await Cache.saveCache(cache)

  // Decode with an incompatible codec (expects a number) -> miss -> reload.
  let reloaded = await Cache.loadCache(home)
  let calls = ref(0)
  let load = async _ => {
    calls := calls.contents + 1
    7.0
  }
  let value = await Cache.cachedValue(
    reloaded,
    ~namespace="t",
    file,
    ~encode=JSON.Encode.float,
    ~decode=JSON.Decode.float,
    load,
  )
  equal(value, 7.0)
  equal(calls.contents, 1)
})
