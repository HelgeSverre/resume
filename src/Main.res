open NodeProcess
open Session

type clipboard
@module("clipboardy")
external clipboard: clipboard = "default"
@send external writeClipboard: (clipboard, string) => promise<unit> = "write"

let help = () => {
  Console.log(`resume

Usage:
  resume              Open searchable session picker
  resume --json       Print normalized sessions as JSON
  resume --copy <id>  Copy the resume command for a matching session id

Keys:
  type search text    Filter by tool, title, cwd, id, or preview
  up/down             Move selection
  t                   Toggle exact timestamp column
  enter               Print resume command and exit
  esc or ctrl-c       Exit
`)
}

let findSession = (sessions, id) => {
  switch sessions->Array.find(session => session.id == id) {
  | Some(session) => Some(session)
  | None => sessions->Array.find(session => session.id->String.startsWith(id))
  }
}

let main = async () => {
  let args = argv->Array.slice(~start=2, ~end=argv->Array.length)
  if args->Array.includes("--help") || args->Array.includes("-h") {
    help()
  } else {
    let sessions = SessionList.mergeAndSort(
      await Adapters.collectSessionsFromHome(env->Dict.get("HOME")->Option.getOr(homedir())),
    )

    if args->Array.includes("--json") {
      Console.log(JSON.stringify(JSON.Encode.array(sessions->Array.map(Session.encode))))
    } else {
      let copyIndex = args->Array.findIndex(arg => arg == "--copy")
      if copyIndex >= 0 {
        let id = args->Array.get(copyIndex + 1)->Option.getOr("")
        if id == "" {
          Console.error("Missing session id after --copy")
          exit(2)
        } else {
          switch findSession(sessions, id) {
          | Some(session) =>
            let command = Session.copyCommand(session)
            await clipboard->writeClipboard(command)
            Console.log(command)
          | None =>
            Console.error(`No session found matching ${id}`)
            exit(1)
          }
        }
      } else if !(stdin->isTTY) || !(stdout->isTTY) {
        sessions
        ->Array.slice(~start=0, ~end=50)
        ->Array.forEach(session => {
          Console.log(
            `${session.tool->Session.toolName}\t${session.id}\t${session.title}\t${Session.copyCommand(
                session,
              )}`,
          )
        })
      } else {
        await Tui.runPicker(sessions)
      }
    }
  }
}

main()->ignore
