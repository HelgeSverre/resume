open TestSupport

@module("node:timers/promises")
external immediate: unit => promise<unit> = "setImmediate"

type interval
@module("node:timers")
external every: (unit => unit, int) => interval = "setInterval"
@module("node:timers")
external stopEvery: interval => unit = "clearInterval"

@send external contains: (string, string) => bool = "includes"

let json = JSON.parseOrThrow
let ids = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
let slots = [
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
]

test("cache save failure preserves collected sessions", async context => {
  let home = await fixture(context, "resume-regression-")
  await writeJsonl(
    NodePath.joinMany([home, ".claude", "projects", "test", "session.jsonl"]),
    [json(`{"type":"user","sessionId":"test","message":{"content":"hello"}}`)],
  )
  await writeFile(NodePath.join(home, ".cache"), "not a directory")
  equal((await Adapters.collectSessionsFromHome(home))->Array.length, 1)
})

test("Claude uses the latest title and prompt records", async context => {
  let home = await fixture(context, "resume-regression-")
  let file = NodePath.join(home, "session.jsonl")
  await writeJsonl(
    file,
    [json(`{"type":"ai-title","aiTitle":"Old"}`), json(`{"type":"ai-title","aiTitle":"New"}`)],
  )
  equal((await Claude.parseClaudeFile(file)).title, "New")
  await writeJsonl(
    file,
    [
      json(`{"type":"last-prompt","lastPrompt":"Old"}`),
      json(`{"type":"last-prompt","lastPrompt":"New"}`),
    ],
  )
  equal((await Claude.parseClaudeFile(file)).title, "New")
})

test("Codex keeps the newest duplicate across active and archived files", async context => {
  let home = await fixture(context, "resume-regression-")
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "sessions", "session.jsonl"]),
    [
      json(`{"type":"session_meta","payload":{"id":"duplicate","cwd":"/fixture"}}`),
      json(`{"type":"response_item","timestamp":"2026-11-06T12:00:00Z","payload":{"role":"user","content":"hello"}}`),
    ],
  )
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "archived_sessions", "session.jsonl"]),
    [
      json(`{"type":"session_meta","payload":{"id":"duplicate","cwd":"/fixture"}}`),
      json(`{"type":"response_item","timestamp":"2026-01-01T12:00:00Z","payload":{"role":"user","content":"hello"}}`),
    ],
  )
  let sessions = await Codex.collectCodex(home, await Cache.loadCache(home))
  equal(sessions->Array.length, 1)
  equal(sessions->Array.get(0)->Option.map(session => session.updatedAtMs), Some(1793966400000.0))
})

test("the worker pool fills an idle slot without waiting for its first task", async _context => {
  let release: ref<option<unit => unit>> = ref(None)
  let gate = Promise.make((resolve, _reject) => release.contents = Some(resolve))
  let started = []
  let active = ref(0)
  let peak = ref(0)
  let pending = AdapterUtil.mapBounded(ids, async index => {
    started->Array.push(index)
    active.contents = active.contents + 1
    peak.contents = max(peak.contents, active.contents)
    if index == 0 {
      await gate
    } else {
      await immediate()
    }
    active.contents = active.contents - 1
    index
  })
  await immediate()
  await immediate()
  ok(started->Array.some(index => index == 8))
  switch release.contents {
  | Some(resolve) => resolve()
  | None => throw(failure("pool did not start"))
  }
  deepEqual(await pending, ids)
  equal(peak.contents, 8)
})

testSync("progressive loading preserves selection and updates available tools", _context => {
  let selected = {
    Session.id: "selected",
    tool: Claude,
    title: "Selected",
    messageCount: 1,
    updatedAtMs: 10.0,
    cwd: None,
    path: "/fixture",
    preview: "",
  }
  let state = {
    Tui.sessions: [selected],
    version: "test",
    tools: [Claude],
    query: "",
    selected: 0,
    offset: 0,
    notice: "",
    showExactTime: false,
    expanded: false,
    agentFilter: None,
  }
  let newer = {...selected, id: "newer", tool: Codex, updatedAtMs: 20.0}
  Tui.receiveSessions(state, [newer], ~visible=[selected])
  equal(state.selected, 1)
  equal(
    state.sessions->Array.get(state.selected)->Option.map(session => session.id),
    Some("selected"),
  )
  deepEqual(state.tools, [Claude, Codex])
})

let checkOpenCode = (~label, ~withV1, ~withV2) =>
  test(
    `OpenCode reads ${label} SQLite schemas and deduplicates migrated sessions`,
    async context => {
      let home = await fixture(context, "resume-regression-")
      let file = NodePath.joinMany([home, ".local", "share", "opencode", "opencode.db"])
      await mkdir(NodePath.dirname(file))
      if withV1 {
        sqlite(
          file,
          "CREATE TABLE session(id TEXT,title TEXT,directory TEXT,time_updated INTEGER);" ++
          "CREATE TABLE message(id TEXT,session_id TEXT);" ++
          "INSERT INTO session VALUES ('shared','v1','/v1',100);" ++ "INSERT INTO message VALUES ('old','shared');",
        )
      }
      if withV2 {
        sqlite(
          file,
          "CREATE TABLE session_v2(id TEXT,title TEXT,directory TEXT,time_updated INTEGER);" ++
          "CREATE TABLE session_message(id TEXT,session_id TEXT,type TEXT);" ++
          "INSERT INTO session_v2 VALUES ('shared','v2','/v2',200),('v2-only',NULL,'/v2',300);" ++ "INSERT INTO session_message VALUES ('u','shared','user'),('a','shared','assistant'),('s','shared','system');",
        )
      }
      let sessions = await OpenCode.collectOpenCode(home, await Cache.loadCache(home))
      equal(sessions->Array.length, withV1 && !withV2 ? 1 : 2)
      let shared = sessions->Array.find(session => session.id == "shared")
      equal(shared->Option.map(session => session.title), Some(withV1 && !withV2 ? "v1" : "v2"))
      equal(shared->Option.map(session => session.messageCount), Some(withV1 && !withV2 ? 1 : 2))
      equal(shared->Option.flatMap(session => session.cwd), Some(withV1 && !withV2 ? "/v1" : "/v2"))
    },
  )

checkOpenCode(~label="v1", ~withV1=true, ~withV2=false)
checkOpenCode(~label="v2", ~withV1=false, ~withV2=true)
checkOpenCode(~label="mixed", ~withV1=true, ~withV2=true)

test("a slow SQLite query leaves the main event loop responsive", async context => {
  let home = await fixture(context, "resume-regression-")
  let file = NodePath.join(home, "test.db")
  sqlite(file, "CREATE TABLE fixture (id INTEGER)")
  let ticks = ref(0)
  let timer = every(() => ticks.contents = ticks.contents + 1, 1)
  let rows = await NodeSqlite.query(
    file,
    "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<500000) SELECT SUM(x) AS total FROM n",
  )
  stopEvery(timer)
  equal(
    rows->Array.get(0)->Option.flatMap(row => JsonUtil.floatAt(row, ["total"])),
    Some(125000250000.0),
  )
  ok(ticks.contents > 0)
})

test("the picker renders before loading and ignores late results after Escape", async _context => {
  let output = PickerSupport.makeOutput()
  let patch = PickerSupport.patchStdinRawMode()
  let loader = PickerSupport.makeLoader()
  let before = PickerSupport.signalListenerCount()
  let picker = Tui.runPicker(~version="test", ~output, ~loadSessions=receive =>
    loader->PickerSupport.load(receive)
  )
  ok(output->PickerSupport.writes->Array.some(frame => frame->contains("Loading sessions")))
  PickerSupport.emitKeypress("", {name: "escape"})
  let action = await picker
  equal(action, Tui.Cancel)
  let frameCount = output->PickerSupport.writes->Array.length
  loader->PickerSupport.receive([])
  loader->PickerSupport.finish([])
  await immediate()
  equal(output->PickerSupport.writes->Array.length, frameCount)
  equal(PickerSupport.signalListenerCount(), before)
  patch->PickerSupport.restoreStdinRawMode
})

test("Codex prefers transcript time over a newer index timestamp", async context => {
  let home = await fixture(context, "resume-regression-")
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "session_index.jsonl"]),
    [json(`{"id":"duplicate","thread_name":"Renamed","updated_at":"2026-12-01T00:00:00Z"}`)],
  )
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "sessions", "current.jsonl"]),
    [
      json(`{"type":"session_meta","payload":{"id":"duplicate"}}`),
      json(`{"type":"response_item","timestamp":"2026-11-06T12:00:00Z","payload":{"role":"user","content":"2026-11-06"}}`),
    ],
  )
  await writeJsonl(
    NodePath.joinMany([home, ".codex", "archived_sessions", "old.jsonl"]),
    [
      json(`{"type":"session_meta","payload":{"id":"duplicate"}}`),
      json(`{"type":"response_item","timestamp":"2026-01-01T12:00:00Z","payload":{"role":"user","content":"2026-01-01"}}`),
    ],
  )
  let sessions = await Codex.collectCodex(home, await Cache.loadCache(home))
  equal(sessions->Array.length, 1)
  equal(sessions->Array.get(0)->Option.map(session => session.preview), Some("2026-11-06"))
})

test("concurrent atomic cache saves leave valid JSON and no temporary files", async context => {
  let home = await fixture(context, "resume-regression-")
  let file = NodePath.join(home, "data")
  await writeFile(file, "hello")
  let cache = await Cache.loadCache(home)
  let _ = await Cache.cachedValue(
    cache,
    ~namespace="test",
    file,
    ~encode=JSON.Encode.string,
    ~decode=JSON.Decode.string,
    async _ => "value",
  )
  let _ = await Promise.all([Cache.saveCache(cache), Cache.saveCache(cache)])
  let saved = JSON.parseOrThrow(await readFile(cache.path))
  equal(JsonUtil.stringAt(saved, ["version"]), Some("2"))
  deepEqual(await readdir(NodePath.dirname(cache.path)), ["sessions-cache-v2.json"])
})

test("OpenCode legacy JSON previews use message time and refresh cached files", async context => {
  let home = await fixture(context, "resume-regression-")
  let root = NodePath.joinMany([home, ".local", "share", "opencode", "storage"])
  await writeJson(
    NodePath.joinMany([root, "session", "project", "ses_test.json"]),
    json(`{"id":"ses_test","title":"","directory":"/fixture","time":{"updated":1}}`),
  )
  let first = NodePath.joinMany([root, "message", "ses_test", "msg_a.json"])
  let second = NodePath.joinMany([root, "message", "ses_test", "msg_z.json"])
  await writeJson(
    first,
    json(`{"role":"assistant","time":{"created":200},"summary":{"title":"Latest"}}`),
  )
  await writeJson(
    second,
    json(`{"role":"user","time":{"created":100},"summary":{"title":"Older"}}`),
  )
  let cache = await Cache.loadCache(home)
  let initialSessions = await OpenCode.collectOpenCode(home, cache)
  equal(initialSessions->Array.get(0)->Option.map(session => session.preview), Some("Latest"))
  equal(initialSessions->Array.get(0)->Option.map(session => session.title), Some("Latest"))
  await writeJson(
    second,
    json(`{"role":"user","time":{"created":300},"summary":{"title":"Latest after update"}}`),
  )
  let updatedSessions = await OpenCode.collectOpenCode(home, cache)
  equal(
    updatedSessions->Array.get(0)->Option.map(session => session.preview),
    Some("Latest after update"),
  )
  equal(updatedSessions->Array.get(0)->Option.map(session => session.messageCount), Some(2))
})

test("shared read slots release after errors and cap concurrent tasks", async _context => {
  let active = ref(0)
  let peak = ref(0)
  let tasks = slots->Array.map(async index =>
    try {
      Some(
        await NodeFs.withReadSlot(
          async () => {
            active.contents = active.contents + 1
            peak.contents = max(peak.contents, active.contents)
            await immediate()
            active.contents = active.contents - 1
            if index == 4 {
              throw(failure("fixture"))
            }
            index
          },
        ),
      )
    } catch {
    | _ => None
    }
  )
  let results = await Promise.all(tasks)
  equal(peak.contents, 8)
  equal(results->Array.filterMap(value => value)->Array.length, 31)
  equal(await NodeFs.withReadSlot(async () => 42), 42)
})

testSync("JSON classification accepts valid whitespace and escapes dynamic patterns", _context => {
  equal(JsonUtil.hasJsonField(`{"type" :\t  "user.message"}`, "type", "user.message"), true)
  equal(JsonUtil.hasJsonField(`{"type":"userXmessage"}`, "type", "user.message"), false)
})

testSync("display truncation pads wide text and width-one wrapping stays visible", _context => {
  equal(Display.width(Display.truncate("漢漢漢漢", 6)), 6)
  deepEqual(Display.wrap("漢", 1, 2), ["…"])
})

test("cancelling discovery aborts active streams and does not leak read slots", async context => {
  let home = await fixture(context, "resume-regression-")
  let file = NodePath.join(home, "stream.jsonl")
  await writeFile(file, `{"type":"fixture"}\n`->String.repeat(20_000))
  ScanControl.start()
  let count = ref(0)
  await rejects(() =>
    NodeFs.forEachLine(
      file,
      _line => {
        count.contents = count.contents + 1
        if count.contents == 1 {
          ScanControl.cancel()
        }
      },
    )
  )
  ok(count.contents < 20_000)
  ScanControl.start()
  equal(await NodeFs.withReadSlot(async () => 7), 7)
})

testSync("preview clipping does not split a Unicode surrogate pair", _context => {
  let text = "a"->String.repeat(15999) ++ "😀"
  equal(JsonUtil.preview(text)->String.length, 15999)
})
