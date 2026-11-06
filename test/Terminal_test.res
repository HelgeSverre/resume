// Node has no portable PTY API, so this test retains the small Python stdlib
// bridge. The CLI fixture and all assertions are ReScript.
open TestSupport

@send external indexOf: (string, string) => int = "indexOf"

let json = JSON.parseOrThrow
let boolAt = (value, path) =>
  JsonUtil.decode(value, JsonUtil.at(path, JsonUtil.Decode.bool))->Option.getOr(false)
let stringsAt = (value, path) =>
  JsonUtil.decode(
    value,
    JsonUtil.at(path, JsonUtil.Decode.array(JsonUtil.Decode.string)),
  )->Option.getOr([])

let ptySupported =
  (platform == "darwin" || platform == "linux") &&
    runSync("uv", ["--version"], {encoding: "utf8"}).status == 0

let count = async path =>
  if await NodeFs.exists(path) {
    await readFile(path)
  } else {
    ""
  }

let execute = async (context, key, ~exitCode=0, ~copy=false) => {
  let home = await fixture(context, "resume-terminal-")
  let project = NodePath.join(home, "project with spaces")
  await mkdir(project)
  let source = NodePath.joinMany([home, ".claude", "projects", "fixture"])
  await writeJsonl(
    NodePath.join(source, "session.jsonl"),
    [
      json(
        `{"type":"user","sessionId":"fixture","cwd":"${project}","message":{"content":"Fixture Resume"}}`,
      ),
    ],
  )

  let bin = NodePath.join(home, "bin")
  await mkdir(bin)
  let agent = NodePath.join(bin, "claude")
  let agentModule = NodePath.joinMany([
    root(),
    "lib",
    "es6",
    "test",
    "fixtures",
    "AgentFixture.mjs",
  ])
  // The fake executable only starts Node and forwards argv. AgentFixture.res
  // owns the observable child behavior.
  await writeFile(
    agent,
    "#!/bin/sh\nexec " ++
    Session.shellQuote(execPath) ++
    " " ++
    Session.shellQuote(agentModule) ++ " \"$@\"\n",
  )
  await chmod(agent, 493)

  let captured = NodePath.join(home, "captured")
  let runCount = NodePath.join(home, "count")
  let existingPath = NodeProcess.env->Dict.get("PATH")->Option.getOr("")
  let response = runSync(
    "uv",
    [
      "run",
      "--no-project",
      "python",
      NodePath.joinMany([root(), "test", "fixtures", "pty_driver.py"]),
    ],
    {
      input: JSON.stringifyAny({
        "args": [
          execPath,
          "--import",
          NodePath.joinMany([root(), "lib", "es6", "test", "fixtures", "ClipboardUnavailable.mjs"]),
          NodePath.joinMany([root(), "dist", "resume.mjs"]),
        ],
        "env": environment(
          ~home,
          ~extra=[
            ("TERM", "xterm-256color"),
            ("PATH", bin ++ ":" ++ existingPath),
            ("RUN_COUNT", runCount),
            ("FIXTURE_EXIT_CODE", Int.toString(exitCode)),
          ],
        ),
        "captured": captured,
        "key": key,
      })->Option.getOr("{}"),
      encoding: "utf8",
      timeout: 20000,
    },
  )
  equal(response.status, 0)
  let result = JSON.parseOrThrow(response.stdout)
  ok(boolAt(result, ["sent"]))
  let childStatus = JsonUtil.floatAt(result, ["status"])->Option.mapOr(-1, Float.toInt)
  let output = JsonUtil.stringAt(result, ["output"])->Option.getOr("")
  let printed = await readFile(captured)

  if copy {
    equal(childStatus, 0)
    ok(printed->String.endsWith("claude --resume fixture\n"))
    equal(await count(runCount), "")
  } else {
    equal(childStatus, exitCode)
    equal(printed, "")
    equal(await count(runCount), "x")
    let marker = output->indexOf("LAUNCH_FIXTURE:")
    ok(marker > output->indexOf("\x1b[?1049l"))
    let record =
      output
      ->String.slice(~start=marker + "LAUNCH_FIXTURE:"->String.length)
      ->String.split("\n")
      ->Array.get(0)
      ->Option.getOr("")
      ->String.trim
      ->JSON.parseOrThrow
    deepEqual(stringsAt(record, ["args"]), ["--resume", "fixture"])
    equal(JsonUtil.stringAt(record, ["cwd"]), Some(await realpath(project)))
    equal(boolAt(record, ["inputTTY"]), true)
    equal(boolAt(record, ["outputTTY"]), true)
    equal(boolAt(record, ["errorTTY"]), true)
    equal(boolAt(record, ["raw"]), false)
  }
}

testWithOptions(
  "Alt+Enter launches once after cleanup with captured stdout empty",
  {"skip": !ptySupported},
  context => execute(context, "\x1b\r"),
)

testWithOptions("Ctrl+R launches and propagates child failure", {"skip": !ptySupported}, context =>
  execute(context, "\x12", ~exitCode=23)
)

testWithOptions(
  "plain Enter prints one command and never launches",
  {"skip": !ptySupported},
  context => execute(context, "\r", ~copy=true),
)
