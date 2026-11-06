let selected = {
  Session.id: "selected",
  tool: Claude,
  title: "Selected",
  messageCount: 1,
  updatedAtMs: 1.,
  cwd: Some("/fixture"),
  path: "/fixture/session.jsonl",
  preview: "",
}

TestSupport.testSync("modified Enter mappings request execution before plain Enter", _context => {
  TestSupport.equal(Tui.keyOfEvent("", {meta: true, name: "return"}), Tui.Execute)
  TestSupport.equal(Tui.keyOfEvent("", {ctrl: true, name: "r"}), Tui.Execute)
  for modifier in 2 to 8 {
    TestSupport.equal(
      Tui.keyOfEvent("", {sequence: `\x1b[13;${Int.toString(modifier)}u`}),
      Tui.Execute,
    )
  }
  TestSupport.equal(Tui.keyOfEvent("", {name: "return"}), Tui.Enter)
})

TestSupport.test("Alt+Enter restores the terminal before returning a Run action", async context => {
  let patch = PickerSupport.patchStdinRawMode()
  context->TestSupport.after(() => {
    PickerSupport.restoreStdinRawMode(patch)
    Promise.resolve()
  })
  let screen = PickerSupport.makeOutput()
  let loader = PickerSupport.makeLoader()
  let before = PickerSupport.signalListenerCount()
  let picker = Tui.runPicker(~version="test", ~output=screen, ~loadSessions=callback =>
    loader->PickerSupport.load(callback)
  )
  loader->PickerSupport.receive([selected])
  PickerSupport.emitKeypress("", {meta: true, name: "return"})
  let action = await picker
  loader->PickerSupport.finish([])

  switch action {
  | Tui.Run(session) => TestSupport.equal(session.id, selected.id)
  | _ => TestSupport.ok(false)
  }
  TestSupport.deepEqual(patch->PickerSupport.rawModeCalls, [true, false])
  TestSupport.equal(PickerSupport.signalListenerCount(), before)
  let last =
    screen
    ->PickerSupport.writes
    ->Array.get(screen->PickerSupport.writes->Array.length - 1)
    ->Option.getOr("")
  TestSupport.ok(last->String.includes("\x1b[?1049l"))
})

TestSupport.test(
  "an empty completed scan restores the terminal and returns Cancel",
  async context => {
    let patch = PickerSupport.patchStdinRawMode()
    context->TestSupport.after(() => {
      PickerSupport.restoreStdinRawMode(patch)
      Promise.resolve()
    })
    let screen = PickerSupport.makeOutput()
    let action = await Tui.runPicker(~version="test", ~output=screen, ~loadSessions=_ =>
      Promise.resolve([])
    )
    TestSupport.equal(action, Tui.Cancel)
    TestSupport.deepEqual(patch->PickerSupport.rawModeCalls, [true, false])
    TestSupport.ok(
      screen
      ->PickerSupport.writes
      ->Array.some(write => write->String.includes("No resumable sessions found.")),
    )
  },
)
