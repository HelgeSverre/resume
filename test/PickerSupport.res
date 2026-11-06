// Typed fake terminal and deferred loader; only deleting an absent host method
// needs a JavaScript escape hatch. No test behavior is embedded in JavaScript.
type output = {
  isTTY: bool,
  columns: int,
  rows: int,
  writes: array<string>,
  write: string => unit,
  on: (string, unit => unit) => unit,
  removeListener: (string, unit => unit) => unit,
}
let makeOutput = () => {
  let writes = []
  {
    isTTY: true,
    columns: 100,
    rows: 30,
    writes,
    write: value => writes->Array.push(value),
    on: (_, _) => (),
    removeListener: (_, _) => (),
  }
}
let writes = output => output.writes

type rawModePatch = {original: option<bool => unit>, calls: array<bool>}
@get external rawSetter: 'stream => option<bool => unit> = "setRawMode"
@set external setRawSetter: ('stream, bool => unit) => unit = "setRawMode"
let deleteRawSetter: 'stream => unit = %raw(`stream => { delete stream.setRawMode }`)
let patchStdinRawMode = () => {
  let calls = []
  let original = NodeProcess.stdin->rawSetter
  NodeProcess.stdin->setRawSetter(value => calls->Array.push(value))
  {original, calls}
}
let rawModeCalls = patch => patch.calls
let restoreStdinRawMode = patch =>
  switch patch.original {
  | Some(original) => NodeProcess.stdin->setRawSetter(original)
  | None => deleteRawSetter(NodeProcess.stdin)
  }
@send external emit: ('stream, string, string, Tui.keyEvent) => unit = "emit"
let emitKeypress = (text, event) => NodeProcess.stdin->emit("keypress", text, event)
@val @scope("process") external listenerCount: string => int = "listenerCount"
let signalListenerCount = () => listenerCount("SIGINT")

type sessions = array<Session.t>
type loader = {
  receiver: ref<option<sessions => unit>>,
  resolver: ref<option<sessions => unit>>,
  pending: promise<sessions>,
}
let makeLoader = () => {
  let receiver = ref(None)
  let resolver = ref(None)
  let pending = Promise.make((resolve, _reject) => resolver.contents = Some(resolve))
  {receiver, resolver, pending}
}
let load = (loader, receive) => {
  loader.receiver.contents = Some(receive)
  loader.pending
}
let receive = (loader, value) =>
  switch loader.receiver.contents {
  | Some(callback) => callback(value)
  | None => ()
  }
let finish = (loader, value) =>
  switch loader.resolver.contents {
  | Some(resolve) => resolve(value)
  | None => ()
  }
