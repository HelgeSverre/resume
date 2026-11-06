// Compare two already-built revisions without loading session contents into the
// report. Dynamic loading is deliberately confined to this boundary: the two
// revisions can have different generated module paths, while the collection and
// aggregation logic below remains ordinary ReScript.

type runtime
type runtimeCache
type runtimeAdapter
type delayMonitor
type resourceUsage
type clock

@get external adapterTool: runtimeAdapter => Session.tool = "tool"
@get external registry: runtime => array<runtimeAdapter> = "registry"
@send external loadCache: (runtime, string) => promise<runtimeCache> = "loadCache"
@send external saveCache: (runtime, runtimeCache) => promise<unit> = "saveCache"
@send
external collectOne: (runtime, string, runtimeCache, runtimeAdapter) => promise<array<Session.t>> =
  "collectOne"
@send external mergeAndSort: (runtime, array<Session.t>) => array<Session.t> = "mergeAndSort"

// This is the only dynamic-import boundary. `root` identifies the independently
// built revision; all returned functions have the typed surface above.
let loadRuntime: string => promise<runtime> = %raw(`async root => {
  const path = await import("node:path");
  const url = await import("node:url");
  const load = name => import(url.pathToFileURL(path.resolve(root, "lib", "es6", "src", name + ".mjs")).href);
  const [adapters, cache, sessions] = await Promise.all([load("Adapters"), load("Cache"), load("SessionList")]);
  return {...adapters, ...cache, ...sessions};
}`)

@module("node:path") external resolvePath: string => string = "resolve"
@module("node:fs/promises") external copyFile: (string, string) => promise<unit> = "copyFile"
@module("node:fs/promises")
external remove: (string, {"recursive": bool, "force": bool}) => promise<unit> = "rm"
@module("node:perf_hooks")
external monitorEventLoopDelay: {"resolution": int} => delayMonitor = "monitorEventLoopDelay"
@module("node:perf_hooks") external performance: clock = "performance"
@send external clockNow: clock => float = "now"
@send external enable: delayMonitor => unit = "enable"
@send external disable: delayMonitor => unit = "disable"
@get external maxDelay: delayMonitor => float = "max"
@module("node:process") external resourceUsage: unit => resourceUsage = "resourceUsage"
@get external maxRss: resourceUsage => float = "maxRSS"
@module("node:process") external execPath: string = "execPath"
@send external sortInPlace: (array<float>, (float, float) => int) => array<float> = "sort"

let moduleUrl: string = %raw(`import.meta.url`)
let scriptPath = NodeUrl.fileURLToPath(moduleUrl)

type adapterMetric = {tool: Session.tool, count: int, ms: float}

type sample = {
  firstResultMs: option<float>,
  scanMs: float,
  totalMs: float,
  sessions: int,
  eventLoopMaxMs: float,
  peakRssMiB: float,
  // Keep the child report's adapter detail intact when the parent re-emits its
  // samples.  The parent only aggregates top-level timing fields.
  adapters: JSON.t,
}

type medians = {
  firstResultMs: option<float>,
  scanMs: option<float>,
  totalMs: option<float>,
  eventLoopMaxMs: option<float>,
  peakRssMiB: option<float>,
}

let floatJson = value => JSON.Encode.float(value)
let intJson = value => JSON.Encode.float(Int.toFloat(value))
let nullableFloatJson = value => value->Option.mapOr(JSON.Encode.null, floatJson)

let encodeAdapter = (metric: adapterMetric) =>
  JsonUtil.object([
    // ReScript emits ordinary variant constructors as their constructor names.
    // Keep the historical benchmark wire value (`Pool`), rather than the
    // user-facing display name (`Poolside`).
    (
      "tool",
      JsonUtil.string(
        switch metric.tool {
        | Pool => "Pool"
        | tool => Session.toolToString(tool)
        },
      ),
    ),
    ("count", intJson(metric.count)),
    ("ms", floatJson(metric.ms)),
  ])

let encodeSample = (sample: sample) =>
  JsonUtil.object([
    ("firstResultMs", nullableFloatJson(sample.firstResultMs)),
    ("scanMs", floatJson(sample.scanMs)),
    ("totalMs", floatJson(sample.totalMs)),
    ("sessions", intJson(sample.sessions)),
    ("eventLoopMaxMs", floatJson(sample.eventLoopMaxMs)),
    ("peakRssMiB", floatJson(sample.peakRssMiB)),
    ("adapters", sample.adapters),
  ])

let encodeMedians = (values: medians) =>
  JsonUtil.object([
    ("firstResultMs", nullableFloatJson(values.firstResultMs)),
    ("scanMs", nullableFloatJson(values.scanMs)),
    ("totalMs", nullableFloatJson(values.totalMs)),
    ("eventLoopMaxMs", nullableFloatJson(values.eventLoopMaxMs)),
    ("peakRssMiB", nullableFloatJson(values.peakRssMiB)),
  ])

let decodeSample = json => {
  let field = (name, fallback) => JsonUtil.floatAt(json, [name])->Option.getOr(fallback)
  switch JSON.Decode.object(json) {
  | Some(object) =>
    Some({
      firstResultMs: object->Dict.get("firstResultMs")->Option.flatMap(JSON.Decode.float),
      scanMs: field("scanMs", 0.0),
      totalMs: field("totalMs", 0.0),
      sessions: Float.toInt(field("sessions", 0.0)),
      eventLoopMaxMs: field("eventLoopMaxMs", 0.0),
      peakRssMiB: field("peakRssMiB", 0.0),
      adapters: object->Dict.get("adapters")->Option.getOr(JSON.Encode.array([])),
    })
  | None => None
  }
}

let runSample = async (~root, ~cacheHome) => {
  let runtime = await loadRuntime(root)
  let delay = monitorEventLoopDelay({"resolution": 10})
  delay->enable
  let started = performance->clockNow
  let cache = await runtime->loadCache(cacheHome)
  let firstResult = ref(None)
  let metrics = []
  let groups = await Promise.all(
    runtime
    ->registry
    ->Array.map(async adapter => {
      let adapterStarted = performance->clockNow
      let sessions = await runtime->collectOne(NodeProcess.homedir(), cache, adapter)
      if sessions->Array.length > 0 && firstResult.contents == None {
        firstResult.contents = Some(performance->clockNow -. started)
      }
      metrics->Array.push({
        tool: adapter->adapterTool,
        count: sessions->Array.length,
        ms: performance->clockNow -. adapterStarted,
      })
      sessions
    }),
  )
  let scanMs = performance->clockNow -. started
  let sessions = mergeAndSort(runtime, groups->Array.flat)
  await runtime->saveCache(cache)
  delay->disable
  {
    firstResultMs: firstResult.contents,
    scanMs,
    totalMs: performance->clockNow -. started,
    sessions: sessions->Array.length,
    eventLoopMaxMs: delay->maxDelay /. 1000000.0,
    peakRssMiB: resourceUsage()->maxRss /. 1024.0,
    adapters: JSON.Encode.array(metrics->Array.map(encodeAdapter)),
  }
}

let median = values => {
  let values = values->Array.filterMap(value => value)
  if values->Array.length == 0 {
    None
  } else {
    let _ = values->sortInPlace((left, right) => left < right ? -1 : left > right ? 1 : 0)
    values->Array.get(values->Array.length / 2)
  }
}

let summaryMedians = (samples: array<sample>): medians => {
  let warmed = samples->Array.slice(~start=1, ~end=samples->Array.length)
  {
    firstResultMs: median(warmed->Array.map((sample: sample) => sample.firstResultMs)),
    scanMs: median(warmed->Array.map((sample: sample) => Some(sample.scanMs))),
    totalMs: median(warmed->Array.map((sample: sample) => Some(sample.totalMs))),
    eventLoopMaxMs: median(warmed->Array.map((sample: sample) => Some(sample.eventLoopMaxMs))),
    peakRssMiB: median(warmed->Array.map((sample: sample) => Some(sample.peakRssMiB))),
  }
}

let parseSample = text => {
  try {decodeSample(JSON.parseOrThrow(text))} catch {
  | _ => None
  }
}

let collectChildSample = async (~root, ~cacheHome) => {
  let result = await NodeChildProcess.runCapture(
    execPath,
    [scriptPath, "--sample", root, cacheHome],
  )
  switch parseSample(result.stdout) {
  | Some(sample) => sample
  | None => failwith("Benchmark child returned invalid JSON: " ++ result.stderr)
  }
}

let setupCache = async (~temporary, ~index, ~cold) => {
  let home = NodePath.join(temporary, Int.toString(index))
  let destination = NodePath.joinMany([home, ".cache", "resume"])
  await NodeFs.mkdirWithRecursive(destination, {"recursive": true})
  if !cold {
    let source = NodePath.joinMany([
      NodeProcess.homedir(),
      ".cache",
      "resume",
      "sessions-cache-v2.json",
    ])
    if await NodeFs.exists(source) {
      await copyFile(source, NodePath.join(destination, "sessions-cache-v2.json"))
    }
  }
  home
}

let printJson = json =>
  switch JSON.stringifyAny(json) {
  | Some(text) => Console.log(text)
  | None => Console.error("Could not encode benchmark report")
  }

let runComparison = async (~beforeRoot, ~afterRoot, ~runs) => {
  let temporary = await NodeFs.mkdtemp(NodePath.join(NodeProcess.tmpdir(), "resume-perf-"))
  try {
    let cold =
      NodeProcess.env->Dict.get("RESUME_BENCH_COLD")->Option.mapOr(false, value => value != "")
    let beforeCache = await setupCache(~temporary, ~index=0, ~cold)
    let afterCache = await setupCache(~temporary, ~index=1, ~cold)
    let before: array<sample> = []
    let after: array<sample> = []
    // Run serially so each revision has its own warmed cache.  Starting with a
    // different revision on every pass avoids a persistent first-run advantage.
    let rec collect = async run => {
      if run < runs {
        if run % 2 == 0 {
          before->Array.push(await collectChildSample(~root=beforeRoot, ~cacheHome=beforeCache))
          after->Array.push(await collectChildSample(~root=afterRoot, ~cacheHome=afterCache))
        } else {
          after->Array.push(await collectChildSample(~root=afterRoot, ~cacheHome=afterCache))
          before->Array.push(await collectChildSample(~root=beforeRoot, ~cacheHome=beforeCache))
        }
        await collect(run + 1)
      }
    }
    await collect(0)
    let encodeRevision = (name, samples) => {
      let empty = {
        firstResultMs: None,
        scanMs: 0.0,
        totalMs: 0.0,
        sessions: 0,
        eventLoopMaxMs: 0.0,
        peakRssMiB: 0.0,
        adapters: JSON.Encode.array([]),
      }
      let first = samples->Array.get(0)->Option.getOr(empty)
      let latest = samples->Array.get(samples->Array.length - 1)->Option.getOr(empty)
      JsonUtil.object([
        ("revision", JsonUtil.string(name)),
        ("sessions", intJson(latest.sessions)),
        ("firstRun", encodeSample(first)),
        ("warmMedian", encodeMedians(summaryMedians(samples))),
        ("samples", JSON.Encode.array(samples->Array.map(encodeSample))),
      ])
    }
    printJson(
      JsonUtil.object([
        ("runs", intJson(runs)),
        (
          "results",
          JSON.Encode.array([encodeRevision("before", before), encodeRevision("after", after)]),
        ),
      ]),
    )
    await remove(temporary, {"recursive": true, "force": true})
  } catch {
  | error =>
    await remove(temporary, {"recursive": true, "force": true})
    throw(error)
  }
}

let main = async () => {
  let args = NodeProcess.argv->Array.slice(~start=2, ~end=NodeProcess.argv->Array.length)
  if args->Array.get(0) == Some("--help") || args->Array.get(0) == Some("-h") {
    Console.log("Usage: node lib/es6/scripts/Benchmark.mjs BEFORE_ROOT AFTER_ROOT [RUNS >= 2]")
  } else if args->Array.length == 3 && args->Array.get(0) == Some("--sample") {
    let root = args->Array.get(1)->Option.getOr("")
    let cacheHome = args->Array.get(2)->Option.getOr("")
    printJson(encodeSample(await runSample(~root, ~cacheHome)))
  } else if args->Array.length >= 2 {
    let beforeRoot = args->Array.get(0)->Option.getOr("")
    let afterRoot = args->Array.get(1)->Option.getOr("")
    let parsedRuns = switch args->Array.get(2) {
    | None => Some(5)
    | Some(value) => RegExp.test(/^[0-9]+$/, value) ? Int.fromString(value) : None
    }
    if parsedRuns->Option.mapOr(true, runs => runs < 2) {
      Console.error("Usage: Benchmark BEFORE_ROOT AFTER_ROOT [RUNS >= 2]")
      NodeProcess.exit(2)
    } else {
      let runs = parsedRuns->Option.getOr(5)
      await runComparison(
        ~beforeRoot=resolvePath(beforeRoot),
        ~afterRoot=resolvePath(afterRoot),
        ~runs,
      )
    }
  } else {
    Console.error("Usage: Benchmark BEFORE_ROOT AFTER_ROOT [RUNS >= 2]")
    NodeProcess.exit(2)
  }
}

main()->ignore
