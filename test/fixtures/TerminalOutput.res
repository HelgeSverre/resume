// Model a terminal stdout with redirected stdin: Main must take its TSV path.
@set external setTTY: ('stream, bool) => unit = "isTTY"
NodeProcess.stdin->setTTY(false)
NodeProcess.stdout->setTTY(true)
