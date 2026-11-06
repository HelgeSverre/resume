// Loaded with Node's `--import` flag by CLI integration fixtures. Keep the
// fault in ReScript so the fixture follows the same module/FFI boundaries as
// production clipboard handling.
type clipboard

@module("clipboardy")
external clipboard: clipboard = "default"

@set
external setWrite: (clipboard, string => promise<unit>) => unit = "write"

@new external fixtureError: string => exn = "Error"

let unavailable = async _ => throw(fixtureError("Fixture clipboard unavailable"))

clipboard->setWrite(unavailable)
