open TestSupport

@val external schedule: (unit => unit, int) => unit = "setTimeout"

let wait = milliseconds =>
  Promise.make((resolve, _reject) => schedule(() => resolve(), milliseconds))

let encode = JSON.Encode.string
let decode = JSON.Decode.string

test("a cancelled SQLite query creates no late worker", async _context => {
  ScanControl.start()
  let before = NodeSqlite.activeWorkerCount()
  ScanControl.cancel()
  let rows = await NodeSqlite.query("/does-not-exist/resume.db", "SELECT 1")
  let after = NodeSqlite.activeWorkerCount()
  ScanControl.start()
  equal(rows->Array.length, 0)
  equal(after, before)
})

test("cancelling while the cache lock is held does not wait for retries", async context => {
  let home = await fixture(context, "resume-cancel-")
  let file = NodePath.join(home, "session.json")
  await writeFile(file, "fixture")

  ScanControl.start()
  let cache = await Cache.loadCache(home)
  let _ = await Cache.cachedValue(cache, ~namespace="cancel", file, ~encode, ~decode, async _ =>
    "value"
  )

  let lock = NodePath.joinMany([home, ".cache", "resume", "sessions-cache-v2.json.lock"])
  await mkdir(lock)
  await writeFile(NodePath.join(lock, "owner"), Int.toString(NodeProcess.pid) ++ ":test")

  let started = Date.now()
  let pending = Cache.saveCache(cache)
  await wait(10)
  ScanControl.cancel()
  await pending
  let elapsed = Date.now() -. started
  ScanControl.start()

  // The old 100-attempt lock loop waited about 2.5 seconds even after a
  // picker closed. The cancellation-aware loop should finish on its next
  // 25ms retry boundary, leaving a generous margin for loaded CI hosts.
  ok(elapsed < 500.)
  equal(await NodeFs.exists(cache.path), false)
})
