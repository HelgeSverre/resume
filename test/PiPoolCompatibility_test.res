type context
@module("node:test")
external testAsync: (string, context => promise<unit>) => unit = "test"
@send external after: (context, unit => promise<unit>) => unit = "after"
@module("node:fs/promises")
external remove: (string, {"recursive": bool, "force": bool}) => promise<unit> = "rm"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

let mkdir = path => NodeFs.mkdirWithRecursive(path, {"recursive": true})

testAsync("Pi honors saved names and custom session directories", async context => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-pi-"))
  context->after(() => remove(home, {"recursive": true, "force": true}))
  let root = NodePath.join(home, "custom-sessions")
  await mkdir(root)
  await NodeFs.writeFile(
    NodePath.join(root, "session.jsonl"),
    `{"type":"session","version":3,"id":"pi-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/repo/pi"}\n{"type":"message","id":"one","parentId":null,"timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":"first prompt"}}\n{"type":"session_info","id":"two","parentId":"one","timestamp":"2026-01-01T00:00:02.000Z","name":"Named Pi session"}\n`,
  )
  let session = await Pi.parsePiFile(NodePath.join(root, "session.jsonl"))
  equal(session.title, "Named Pi session")
  equal(Pi.sessionRoot(~home, ~sessionDir=root), root)
  equal(Pi.sessionRoot(~home, ~agentDir="/custom/pi-agent"), "/custom/pi-agent/sessions")
})

testAsync("Pool ACP summaries normalize resumable sessions", async context => {
  let home = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-pool-"))
  context->after(() => remove(home, {"recursive": true, "force": true}))
  let root = NodePath.joinMany([
    home,
    "Library",
    "Application Support",
    "poolside",
    "acp",
    "--repo--",
  ])
  await mkdir(root)
  await NodeFs.writeFile(
    NodePath.join(root, "pool-1.json"),
    `{"sessionId":"pool-1","poolSessionId":"remote-1","cwd":"/repo/pool","title":"Pool title","updatedAt":"2026-01-01T00:00:00.000Z"}`,
  )
  let cache = await Cache.loadCache(home)
  let sessions = await Pool.collectPool(home, cache)
  equal(sessions->Array.length, 1)
  equal(sessions->Array.get(0)->Option.map(session => session.id), Some("pool-1"))
  equal(sessions->Array.get(0)->Option.map(session => session.title), Some("Pool title"))
  equal(sessions->Array.get(0)->Option.map(session => session.cwd), Some(Some("/repo/pool")))
  equal(sessions->Array.get(0)->Option.map(session => session.updatedAtMs), Some(1767225600000.0))
})
