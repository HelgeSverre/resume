@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a) => unit = "deepEqual"

test("no arguments opens the picker", () => {
  deepEqual(Cli.parse([]), Parsed(Pick))
})

test("recognizes --help and -h regardless of position", () => {
  deepEqual(Cli.parse(["--help"]), Parsed(Help))
  deepEqual(Cli.parse(["-h"]), Parsed(Help))
  deepEqual(Cli.parse(["--json", "-h"]), Parsed(Help))
})

test("parses --json", () => {
  deepEqual(Cli.parse(["--json"]), Parsed(Json))
})

test("parses --copy with an id", () => {
  deepEqual(Cli.parse(["--copy", "abc-123"]), Parsed(Copy("abc-123")))
})

test("rejects --copy without a value", () => {
  deepEqual(Cli.parse(["--copy"]), Invalid("Missing session id after --copy"))
})

test("rejects --copy followed by another flag", () => {
  deepEqual(Cli.parse(["--copy", "--json"]), Invalid("Missing session id after --copy"))
})

test("rejects --copy with an empty value", () => {
  deepEqual(Cli.parse(["--copy", ""]), Invalid("Missing session id after --copy"))
})

test("rejects unknown options", () => {
  deepEqual(Cli.parse(["--nope"]), Invalid("Unknown option: --nope"))
})

test("json takes precedence over copy", () => {
  deepEqual(Cli.parse(["--copy", "abc", "--json"]), Parsed(Json))
})

test("ignores stray positional arguments", () => {
  deepEqual(Cli.parse(["stray"]), Parsed(Pick))
})
