@module("node:test")
external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external equal: ('a, 'a) => unit = "equal"

@module("node:assert/strict")
external deepEqual: ('a, 'a) => unit = "deepEqual"

test("strips terminal controls without altering printable text", () => {
  equal(Display.clean("before\x1b[2Jafter"), "beforeafter")
  equal(Display.clean("before\x1b]52;c;clipboard\x07after"), "beforeafter")
  equal(Display.clean("before\x9b31mafter"), "beforeafter")
  equal(Display.clean("a\n\tb"), "a b")
})

test("measures terminal cells rather than UTF-16 code units", () => {
  equal(Display.width("漢字"), 4)
  equal(Display.width("😀"), 2)
  equal(Display.width("🇳🇴"), 2)
  equal(Display.width("1️⃣"), 2)
  equal(Display.width("e\u{0301}"), 1)
})

test("truncation preserves graphemes and fills exactly the requested cells", () => {
  let cjk = Display.truncate("漢字語", 5)
  equal(cjk, "漢字…")
  equal(Display.width(cjk), 5)

  let emoji = Display.truncate("😀😀😀", 5)
  equal(emoji, "😀😀…")
  equal(Display.width(emoji), 5)
  equal(emoji->String.includes("�"), false)
})

test("wrapping keeps wide and unbroken preview text within the cell limit", () => {
  let lines = Display.wrap("漢字語漢字語", 4, 4)
  deepEqual(lines, ["漢字", "語漢", "字語"])
  equal(lines->Array.every(line => Display.width(line) <= 4), true)
})
