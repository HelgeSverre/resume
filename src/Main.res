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

let findSession = (sessions, id) => {
  switch sessions->Array.find(session => session.id == id) {
  | Some(session) => Some(session)
  | None => sessions->Array.find(session => session.id->String.startsWith(id))
  }
}

let loadSessions = async () =>
  SessionList.mergeAndSort(
    await Adapters.collectSessionsFromHome(env->Dict.get("HOME")->Option.getOr(homedir())),
  )

let printTsv = sessions =>
  sessions
  ->Array.slice(~start=0, ~end=50)
  ->Array.forEach(session => {
    Console.log(
      `${session.tool->Session.toolName}\t${session.id}\t${session.title}\t${Session.copyCommand(
          session,
        )}`,
    )
  })

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
    switch findSession(sessions, id) {
    | Some(session) =>
      let command = Session.copyCommand(session)
      await copyToClipboard(command)
      Console.log(command)
    | None =>
      Console.error(`No session found matching ${id}`)
      exit(1)
    }
  | Parsed(Pick) =>
    let sessions = await loadSessions()
    if !(stdin->isTTY) || !(stdout->isTTY) {
      printTsv(sessions)
    } else {
      await Tui.runPicker(~copyToClipboard, sessions)
    }
  }
}

main()->ignore
