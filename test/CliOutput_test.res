open TestSupport

let json = JSON.parseOrThrow

let fixtureHome = async (context, rows) => {
  let home = await fixture(context, "resume-cli-")
  let project = NodePath.joinMany([home, ".claude", "projects", "fixture"])
  await mkdir(project)
  let rec writeRows = async index =>
    switch rows->Array.get(index) {
    | Some(row) => {
        await writeJsonl(NodePath.join(project, Int.toString(index) ++ ".jsonl"), [row])
        await writeRows(index + 1)
      }
    | None => ()
    }
  await writeRows(0)
  home
}

let run = (home, args) =>
  runSync(
    execPath,
    Array.concat(
      [
        "--import",
        NodePath.joinMany([root(), "lib", "es6", "test", "fixtures", "ClipboardUnavailable.mjs"]),
        NodePath.joinMany([root(), "dist", "resume.mjs"]),
      ],
      args,
    ),
    {env: environment(~home), encoding: "utf8", timeout: 10000},
  )

test("copy prints a recoverable command when the clipboard is unavailable", async context => {
  let home = await fixtureHome(
    context,
    [
      json(`{"type":"user","sessionId":"fixture","cwd":"/fixture with spaces","message":{"content":"Fixture"}}`),
    ],
  )
  let result = run(home, ["--copy", "fixture"])
  equal(result.status, 0)
  equal(result.stdout->String.trim, "cd '/fixture with spaces' && claude --resume fixture")
  ok(result.stderr->String.includes("clipboard unavailable"))
  equal(result.stderr->String.includes(" at "), false)
})

test("copy rejects ambiguous prefixes rather than choosing the newest", async context => {
  let home = await fixtureHome(
    context,
    [
      json(`{"type":"user","sessionId":"abc-one","message":{"content":"Fixture"}}`),
      json(`{"type":"user","sessionId":"abc-two","message":{"content":"Fixture"}}`),
    ],
  )
  let result = run(home, ["--copy", "abc"])
  equal(result.status, 2)
  equal(result.stdout, "")
  ok(result.stderr->String.includes("claude:abc-one"))
  ok(result.stderr->String.includes("claude:abc-two"))
})

test("TSV escapes delimiters and literal backslashes in every field", async context => {
  let home = await fixtureHome(
    context,
    [
      json(`{"type":"user","sessionId":"id\\tpart","cwd":"/fixture\\nwith\\ttabs\\\\literal","message":{"content":"Fixture"}}`),
    ],
  )
  let result = run(home, [])
  equal(result.status, 0)
  let lines = result.stdout->String.trimEnd->String.split("\n")
  equal(lines->Array.length, 1)
  equal(lines->Array.get(0)->Option.getOr("")->String.split("\t")->Array.length, 4)
  ok(result.stdout->String.includes("id\\tpart"))
  ok(result.stdout->String.includes("fixture\\nwith\\ttabs\\\\literal"))
})
