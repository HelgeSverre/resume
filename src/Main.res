open NodeProcess
open Session

type clipboard
@module("clipboardy")
external clipboard: clipboard = "default"
@send external writeClipboard: (clipboard, string) => promise<unit> = "write"

let copyToClipboard = command => clipboard->writeClipboard(command)

// `import.meta.url` points at this module; in the shipped bundle that is
// dist/resume.mjs, so package.json sits one directory up. Read it at runtime so
// the version stays a single source of truth (package.json).
let moduleUrl: string = %raw(`import.meta.url`)

let readVersion = async () => {
  try {
    let pkgPath = NodePath.join(
      NodePath.dirname(NodeUrl.fileURLToPath(moduleUrl)),
      "../package.json",
    )
    let content = await NodeFs.readFile(pkgPath, "utf8")
    JsonUtil.stringAt(JSON.parseOrThrow(content), ["version"])->Option.getOr("unknown")
  } catch {
  | _ => "unknown"
  }
}

let loadSessions = async () =>
  SessionList.mergeAndSort(
    await Adapters.collectSessionsFromHome(env->Dict.get("HOME")->Option.getOr(homedir())),
  )

let tsvField = value =>
  value
  ->String.replaceAll("\\", "\\\\")
  ->String.replaceAll("\t", "\\t")
  ->String.replaceAll("\r", "\\r")
  ->String.replaceAll("\n", "\\n")

let printTsv = sessions =>
  sessions
  ->Array.slice(~start=0, ~end=50)
  ->Array.forEach(session => {
    Console.log(
      [Session.toolName(session.tool), session.id, session.title, Session.copyCommand(session)]
      ->Array.map(value => tsvField(stdout->isTTY ? Display.safe(value) : value))
      ->Array.join("\t"),
    )
  })

let writeOutput = text => stdout->writeAsync(text)

let copyAndPrint = async session => {
  let command = Session.copyCommand(session)
  try {await copyToClipboard(command)} catch {
  | _ => Console.error("Warning: clipboard unavailable; printing the resume command")
  }
  await writeOutput((stdout->isTTY ? Display.safe(command) : command) ++ "\n")
}

let main = async () => {
  let args = argv->Array.slice(~start=2, ~end=argv->Array.length)
  switch Cli.parse(args) {
  | Invalid(message) =>
    Console.error(message)
    exit(2)
  | Parsed(Help) => Console.log(Cli.usage)
  | Parsed(Version) => Console.log(await readVersion())
  | Parsed(Json) =>
    let sessions = await loadSessions()
    Console.log(JSON.stringify(JSON.Encode.array(sessions->Array.map(Session.encode))))
  | Parsed(Copy(id)) =>
    let sessions = await loadSessions()
    switch Selection.find(sessions, id) {
    | Found(session) => await copyAndPrint(session)
    | Ambiguous(matches) =>
      Console.error("Ambiguous session id; use one of these tool-qualified IDs:")
      matches->Array.forEach(session =>
        Console.error(Display.clean(Session.toolName(session.tool) ++ ":" ++ session.id))
      )
      exit(2)
    | Missing =>
      Console.error("No session found matching " ++ Display.clean(id))
      exit(1)
    }
  | Parsed(Pick) =>
    if stdin->isTTY && (stdout->isTTY || stderr->isTTY) {
      let output = stdout->isTTY ? stdout : stderr
      let pendingScan = ref(None)
      let action = await Tui.runPicker(
        ~version=await readVersion(),
        ~output,
        ~loadSessions=onSessions => {
          let pending = Adapters.collectSessionsFromHome(
            ~onSessions,
            env->Dict.get("HOME")->Option.getOr(homedir()),
          )
          pendingScan.contents = Some(pending)
          pending
        },
      )
      ScanControl.cancel()
      await NodeSqlite.cancelAll()
      switch pendingScan.contents {
      | Some(pending) =>
        let _ = await pending->Promise.catch(_ => Promise.resolve([]))
      | None => ()
      }
      switch action {
      | Cancel => exit(0)
      | Copy(session) =>
        await copyAndPrint(session)
        exit(0)
      | Run(session) =>
        let outcome = await Launch.run(
          Launch.plan(session),
          ~inputFd=stdin->fd,
          ~outputFd=output->fd,
        )
        switch outcome {
        | Failed(message) => Console.error("Could not launch session: " ++ Display.clean(message))
        | _ => ()
        }
        exit(Launch.exitCode(outcome))
      }
    } else {
      printTsv(await loadSessions())
    }
  }
}

main()->ignore
