// Typed process boundary shared by developer scripts and subprocess fixtures.
type options = {
  cwd?: string,
  env?: dict<string>,
  encoding?: string,
  timeout?: int,
  input?: string,
  maxBuffer?: int,
  stdio?: array<string>,
}
type result = {status: int, stdout: string, stderr: string}
type rawResult
@module("cross-spawn") external sync: (string, array<string>, options) => rawResult = "sync"
let normalize: rawResult => result = %raw(`result => ({
  status: typeof result.status === "number" ? result.status : 1,
  stdout: result.stdout == null ? "" : String(result.stdout),
  stderr: result.stderr == null ? String(result.error?.message || "") : String(result.stderr)
})`)
let runSync = (command, args, options) => normalize(sync(command, args, options))

type child
type stream
@module("cross-spawn") external spawn: (string, array<string>, options) => child = "spawn"
@get external stdout: child => stream = "stdout"
@get external stderr: child => stream = "stderr"
@send external on: ('emitter, string, 'a => unit) => unit = "on"
@send external asString: 'buffer => string = "toString"
@new external failure: string => exn = "Error"
let runCapture = (command, args, ~cwd=?, ~env=?) =>
  Promise.make((resolve, reject) => {
    let output = ref("")
    let errors = ref("")
    let child = spawn(command, args, {?cwd, ?env, stdio: ["ignore", "pipe", "pipe"]})
    child->stdout->on("data", chunk => output.contents = output.contents ++ asString(chunk))
    child->stderr->on("data", chunk => errors.contents = errors.contents ++ asString(chunk))
    child->on("error", reject)
    child->on("close", code => {
      if code == 0 {
        resolve({status: code, stdout: output.contents, stderr: errors.contents})
      } else {
        reject(failure("Subprocess failed: " ++ errors.contents))
      }
    })
  })
