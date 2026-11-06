// One active CLI scan. Closing the picker aborts pending reads before handing
// the terminal to an agent; a later scan gets a fresh signal.
type controller
type signal
@new external create: unit => controller = "AbortController"
@get external signal: controller => signal = "signal"
@get external aborted: signal => bool = "aborted"
@send external abort: controller => unit = "abort"
@new external abortError: (string, string) => exn = "DOMException"
let current = ref(create())
let start = () => current.contents = create()
let getSignal = () => current.contents->signal
let cancelled = () => getSignal()->aborted
let cancel = () => current.contents->abort
let ensureActive = () => {
  if cancelled() {
    throw(abortError("Session scan cancelled", "AbortError"))
  }
}
