// Typed parsing of process arguments into a single command.
//
// The grammar is small on purpose; this module is the one place that knows the
// flags, so Main stays a thin dispatcher and the rules are unit-testable.

type command =
  | Help
  | Json
  | Copy(string)
  | Pick

type t =
  | Parsed(command)
  | Invalid(string) // message to print to stderr before exiting non-zero

let usage = `resume

Usage:
  resume              Open searchable session picker
  resume --json       Print normalized sessions as JSON
  resume --copy <id>  Copy the resume command for a matching session id
  resume --help       Show this help

Keys:
  type search text    Filter by tool, title, cwd, id, or preview
  up/down             Move selection
  tab                 Expand / collapse the preview panel
  ctrl-a              Cycle the agent filter (all -> one tool -> ...)
  ctrl-t              Toggle exact timestamp column
  ctrl-u              Clear the search
  enter               Copy resume command to clipboard, print it, and exit
  esc or ctrl-c       Exit
`

let isHelpFlag = arg => arg == "--help" || arg == "-h"

// Parse the arguments after `node script` (i.e. argv without the first two).
// Precedence matches the historical behaviour: help > json > copy > pick.
let parse = (args: array<string>): t =>
  if args->Array.some(isHelpFlag) {
    Parsed(Help)
  } else {
    let rec scan = (i, json, copy) =>
      switch args->Array.get(i) {
      | None =>
        if json {
          Parsed(Json)
        } else {
          switch copy {
          | Some(id) => Parsed(Copy(id))
          | None => Parsed(Pick)
          }
        }
      | Some("--json") => scan(i + 1, true, copy)
      | Some("--copy") =>
        switch args->Array.get(i + 1) {
        | Some(id) if id != "" && !(id->String.startsWith("-")) => scan(i + 2, json, Some(id))
        | _ => Invalid("Missing session id after --copy")
        }
      | Some(other) =>
        if other->String.startsWith("-") {
          Invalid(`Unknown option: ${other}`)
        } else {
          // Stray positional arguments are ignored, not rejected.
          scan(i + 1, json, copy)
        }
      }
    scan(0, false, None)
  }
