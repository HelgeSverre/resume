// Node.js readline bindings

@module("node:readline")
external emitKeypressEvents: 'stream => unit = "emitKeypressEvents"

@send external setRawMode: ('stream, bool) => unit = "setRawMode"
@send external resume: 'stream => unit = "resume"
@send external pause: 'stream => unit = "pause"
@send external removeListener: ('stream, string, 'a) => unit = "removeListener"
@send external on: ('stream, string, 'a) => unit = "on"
