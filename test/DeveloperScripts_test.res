open TestSupport
let script = name => NodePath.joinMany([root(), "lib", "es6", "scripts", name ++ ".mjs"])

test("ReScript benchmark keeps null first-result metrics and adapter detail", async context => {
  let home = await fixture(context, "resume-bench-empty-")
  let result = runSync(
    execPath,
    [script("Benchmark"), root(), root(), "2"],
    {
      env: environment(~home, ~extra=[("RESUME_BENCH_COLD", "1")]),
      encoding: "utf8",
      timeout: 20000,
    },
  )
  equal(result.status, 0)
  let report = JSON.parseOrThrow(result.stdout)
  let revisions =
    JsonUtil.decode(
      report,
      JsonUtil.at(["results"], JsonUtil.Decode.array(JsonUtil.Decode.id)),
    )->Option.getOr([])
  equal(revisions->Array.length, 2)
  revisions->Array.forEach(revision => {
    equal(JsonUtil.floatAt(revision, ["sessions"]), Some(0.))
    equal(
      JsonUtil.decode(revision, JsonUtil.at(["warmMedian", "firstResultMs"], JsonUtil.Decode.id)),
      Some(JSON.Null),
    )
    let adapters =
      JsonUtil.decode(
        revision,
        JsonUtil.at(["firstRun", "adapters"], JsonUtil.Decode.array(JsonUtil.Decode.id)),
      )->Option.getOr([])
    equal(adapters->Array.length, Adapters.registry->Array.length)
  })
})

test("developer scripts expose help without creating a snapshot", async _context => {
  [
    script("Benchmark"),
    script("SnapshotHistory"),
    NodePath.joinMany([root(), "lib", "es6", "demo", "MakeFixtures.mjs"]),
  ]->Array.forEach(file => {
    let result = runSync(execPath, [file, "--help"], {encoding: "utf8", timeout: 10000})
    equal(result.status, 0)
    ok(result.stdout->String.includes("Usage:"))
  })
})

testWithOptions(
  "snapshot refuses an existing destination without removing its contents",
  {"skip": platform != "darwin"},
  async context => {
    let home = await fixture(context, "resume-snapshot-existing-")
    let sentinel = NodePath.join(home, "keep")
    await writeFile(sentinel, "keep")
    let result = runSync(
      execPath,
      [script("SnapshotHistory"), home],
      {env: environment(~home), encoding: "utf8", timeout: 10000},
    )
    notEqual(result.status, 0)
    equal(await readFile(sentinel), "keep")
  },
)
