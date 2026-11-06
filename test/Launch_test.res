open TestSupport

let session = (id, ~tool=Session.Claude) => {
  Session.id,
  tool,
  title: id,
  messageCount: 0,
  updatedAtMs: 0.,
  cwd: None,
  path: "/fixture",
  preview: "",
}

let fixtureModule = name =>
  NodePath.joinMany([root(), "lib", "es6", "test", "fixtures", name ++ ".mjs"])

let testHarness = async (~signal, ~exitCode) => {
  let result = await runCapture(
    execPath,
    [
      fixtureModule("LaunchSignalHarness"),
      fixtureModule("LaunchAgent"),
      signal,
      Int.toString(exitCode),
    ],
  )
  result.stdout
}

testSync("selection requires one unambiguous exact or prefix match", _context => {
  let old = session("abc-old")
  let newest = session("abc-new")
  let unique = session("unique")
  let rows = [old, newest, unique]
  deepEqual(Selection.find(rows, "unique"), Selection.Found(unique))
  deepEqual(Selection.find(rows, "abc"), Selection.Ambiguous([old, newest]))
  equal(Selection.find(rows, "missing"), Selection.Missing)
})

testSync("selection accepts tool-qualified IDs without splitting ID colons", _context => {
  let codex = session("rollout:abc", ~tool=Session.Codex)
  let claude = session("rollout:abc", ~tool=Session.Claude)
  deepEqual(Selection.find([claude, codex], "codex:rollout:abc"), Selection.Found(codex))
  deepEqual(Selection.find([claude, codex], "rollout:abc"), Selection.Ambiguous([claude, codex]))
})

test("launch passes argv unchanged and sets the child working directory", async context => {
  let cwd = await fixture(context, "resume-launch-")
  let output = NodePath.join(cwd, "output.json")
  let outputFd = openWrite(output)
  let outcome = await Launch.run(
    {
      executable: execPath,
      args: [fixtureModule("LaunchArguments"), "semicolon;not-a-shell-command", "$(not-a-command)"],
      cwd: Some(cwd),
    },
    ~inputFd=0,
    ~outputFd,
  )
  closeFd(outputFd)
  deepEqual(outcome, Launch.Exited(0))
  let output = await readFile(output)
  equal(JsonUtil.stringAt(JSON.parseOrThrow(output), ["cwd"]), Some(await realpath(cwd)))
  ok(output->String.includes(`"args":["semicolon;not-a-shell-command","$(not-a-command)"]`))
})

test("launch reports a missing executable rather than throwing", async _context => {
  let outcome = await Launch.run(
    {executable: "resume-definitely-not-installed", args: [], cwd: None},
    ~inputFd=0,
    ~outputFd=1,
  )
  switch outcome {
  | Launch.Failed(message) => ok(message->String.length > 0)
  | _ => ok(false)
  }
  equal(Launch.exitCode(outcome), 1)
})

testWithOptions(
  "launch maps signal outcomes to a conventional exit status",
  {"skip": platform == "win32"},
  async _context => {
    let outcome = await Launch.run(
      {
        executable: execPath,
        args: [fixtureModule("LaunchOutcome"), "signal", "SIGTERM"],
        cwd: None,
      },
      ~inputFd=0,
      ~outputFd=1,
    )
    deepEqual(outcome, Launch.Signaled("SIGTERM"))
    equal(Launch.exitCode(outcome), 143)
  },
)

test("launch preserves a child nonzero exit code", async _context => {
  let outcome = await Launch.run(
    {executable: execPath, args: [fixtureModule("LaunchOutcome"), "exit", "23"], cwd: None},
    ~inputFd=0,
    ~outputFd=1,
  )
  deepEqual(outcome, Launch.Exited(23))
  equal(Launch.exitCode(outcome), 23)
})

test(
  "SIGINT does not terminate the launcher while its foreground child continues",
  async _context => {
    let output = await testHarness(~signal="SIGINT", ~exitCode=0)
    ok(output->String.includes(`"TAG":"Exited","_0":99`))
    ok(output->String.includes(`"restored":true`))
  },
)

testWithOptions(
  "SIGTERM is forwarded and temporary handlers are removed",
  {"skip": platform == "win32"},
  async _context => {
    let output = await testHarness(~signal="SIGTERM", ~exitCode=42)
    ok(output->String.includes(`"TAG":"Exited","_0":42`))
    ok(output->String.includes(`"restored":true`))
  },
)

testWithOptions(
  "SIGHUP is forwarded and temporary handlers are removed",
  {"skip": platform == "win32"},
  async _context => {
    let output = await testHarness(~signal="SIGHUP", ~exitCode=43)
    ok(output->String.includes(`"TAG":"Exited","_0":43`))
    ok(output->String.includes(`"restored":true`))
  },
)
