// During an interactive scan warnings belong in the status line, so background
// collectors cannot write over a partially rendered terminal frame.
let handler: ref<option<string => unit>> = ref(None)
let warn = message =>
  if !ScanControl.cancelled() {
    switch handler.contents {
    | Some(report) => report(message)
    | None => Console.error(message)
    }
  }
