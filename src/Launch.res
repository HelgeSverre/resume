// Launch a selected session without re-parsing its shell-display command. The
// display form is for a human shell; this module always receives argv directly.
// `cross-spawn` keeps command shims and shebang-based CLIs working on Windows
// while retaining Node's spawn(command, args, options) API.

type t = Session.launchSpec

type outcome =
  | Exited(int)
  | Signaled(string)
  | Failed(string)

type child

type options = {"cwd": string, "stdio": array<int>, "shell": bool, "windowsHide": bool}

@module("cross-spawn")
external spawn: (string, array<string>, options) => child = "spawn"

@send
external onceError: (child, string, 'a => unit) => child = "once"

@send external kill: (child, string) => bool = "kill"

// While an attached child owns the terminal, Ctrl+C is delivered to the whole
// foreground group. The parent must consume its copy rather than exiting and
// leaving a still-running coding agent behind. Explicit termination signals are
// forwarded so a targeted `kill resume-pid` still stops the child.
@val @scope("process")
external onSignal: (string, unit => unit) => unit = "on"

@val @scope("process")
external removeSignal: (string, unit => unit) => unit = "removeListener"

// Node emits literal null for either half of a `close` status. Normalize it at
// the FFI boundary; ReScript options are represented as undefined.
let onClose: (child, (option<int>, option<string>) => unit) => unit = %raw(`
  (child, callback) => child.once("close", (code, signal) =>
    callback(typeof code === "number" ? code : undefined,
      typeof signal === "string" ? signal : undefined))
`)

@get external errorMessage: 'a => string = "message"

@module("node:process")
external processCwd: unit => string = "cwd"

let plan = Session.launchSpec

let exitCode = outcome =>
  switch outcome {
  | Exited(code) => code
  // Match conventional shell reporting for common POSIX signals. Windows does
  // not report POSIX signals here, so it keeps the generic non-zero fallback.
  | Signaled("SIGHUP") => 129
  | Signaled("SIGINT") => 130
  | Signaled("SIGQUIT") => 131
  | Signaled("SIGKILL") => 137
  | Signaled("SIGTERM") => 143
  | Signaled(_) | Failed(_) => 1
  }

// `inputFd` and `outputFd` are selected by Main. Passing the terminal output
// FD for both child stdout/stderr keeps command-substitution stdout clean.
let run = (plan: t, ~inputFd, ~outputFd) =>
  Promise.make((resolve, _reject) => {
    let settled = ref(false)
    let removeHandlers: ref<unit => unit> = ref(() => ())
    let finish = outcome => {
      if !settled.contents {
        settled.contents = true
        removeHandlers.contents()
        resolve(outcome)
      }
    }

    try {
      let child = spawn(
        plan.executable,
        plan.args,
        {
          "cwd": plan.cwd->Option.getOr(processCwd()),
          "stdio": [inputFd, outputFd, outputFd],
          "shell": false,
          "windowsHide": false,
        },
      )
      let ignoreInterrupt = () => ()
      let forwardTermination = () => {
        let _ = child->kill("SIGTERM")
      }
      // Forwarding SIGHUP gives the agent a chance to persist or clean up when
      // its launching terminal disappears; the parent still waits for close.
      let forwardHangup = () => {
        let _ = child->kill("SIGHUP")
      }
      let remove = () => {
        removeSignal("SIGINT", ignoreInterrupt)
        removeSignal("SIGTERM", forwardTermination)
        removeSignal("SIGHUP", forwardHangup)
      }
      removeHandlers.contents = remove
      onSignal("SIGINT", ignoreInterrupt)
      onSignal("SIGTERM", forwardTermination)
      onSignal("SIGHUP", forwardHangup)
      let _ = child->onceError("error", error => finish(Failed(error->errorMessage)))
      onClose(child, (code, signal) =>
        switch (code, signal) {
        | (Some(code), _) => finish(Exited(code))
        | (None, Some(signal)) => finish(Signaled(signal))
        | (None, None) => finish(Failed("Launcher closed without an exit status"))
        }
      )
    } catch {
    | error => finish(Failed(error->errorMessage))
    }
  })
