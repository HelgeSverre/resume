// Terminal-safe, cell-aware text used only for rendering. Session data remains
// raw so that copied resume commands retain the original path and identifier.

// ANSI string controls must be removed as whole sequences before removing
// remaining C0/C1 controls. Otherwise an OSC payload could be left behind as
// misleading visible text after its ESC introducer is stripped.
let safe = value =>
  value
  ->String.replaceRegExp(/\x1b\][\s\S]*?(?:\x07|\x1b\\|$)/g, "")
  ->String.replaceRegExp(/\x1b[PX^_][\s\S]*?(?:\x1b\\|$)/g, "")
  ->String.replaceRegExp(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "")
  ->String.replaceRegExp(/\x1b[ -\/]*[@-~]/g, "")
  ->String.replaceRegExp(/\x9d[\s\S]*?(?:\x07|\x9c|$)/g, "")
  ->String.replaceRegExp(/\x90[\s\S]*?(?:\x9c|$)/g, "")
  ->String.replaceRegExp(/\x9b[0-?]*[ -\/]*[@-~]/g, "")
  ->String.replaceRegExp(/[\x00-\x1f\x7f-\x9f]/g, " ")

let clean = value => value->safe->String.replaceRegExp(/\s+/gu, " ")->String.trim

// Segmenting by grapheme keeps surrogate pairs, combining marks and ZWJ emoji
// sequences intact when a narrow terminal forces truncation.
let graphemes: string => array<string> = %raw(`(() => {
  const segmenter = new Intl.Segmenter(undefined, {granularity: "grapheme"})
  return value => Array.from(segmenter.segment(String(value)), item => item.segment)
})()`)

@module("string-width")
external stringWidth: string => int = "default"

let graphemeWidth = grapheme => stringWidth(grapheme)

let width = text => text->safe->stringWidth

let take = (text, limit) => {
  let out = []
  let used = ref(0)
  let stopped = ref(false)
  text
  ->clean
  ->graphemes
  ->Array.forEach(part => {
    let partWidth = graphemeWidth(part)
    if !stopped.contents && used.contents + partWidth <= limit {
      out->Array.push(part)
      used.contents = used.contents + partWidth
    } else {
      stopped.contents = true
    }
  })
  out->Array.join("")
}

let takeTail = (text, limit) => {
  let out = []
  let used = ref(0)
  let stopped = ref(false)
  text
  ->clean
  ->graphemes
  ->Array.toReversed
  ->Array.forEach(part => {
    let partWidth = graphemeWidth(part)
    if !stopped.contents && used.contents + partWidth <= limit {
      out->Array.push(part)
      used.contents = used.contents + partWidth
    } else {
      stopped.contents = true
    }
  })
  out->Array.toReversed->Array.join("")
}

let spaces = count => count > 0 ? " "->String.repeat(count) : ""

let truncate = (text, limit) => {
  let value = text->clean
  if limit <= 0 {
    ""
  } else if width(value) <= limit {
    value ++ spaces(limit - width(value))
  } else if limit == 1 {
    "…"
  } else {
    let shortened = take(value, limit - 1) ++ "…"
    shortened ++ spaces(limit - width(shortened))
  }
}

let clip = (text, limit) => {
  let value = text->clean
  if limit <= 0 {
    ""
  } else if width(value) <= limit {
    value
  } else if limit == 1 {
    "…"
  } else {
    take(value, limit - 1) ++ "…"
  }
}

let clipTail = (text, limit) => {
  let value = text->clean
  if limit <= 0 {
    ""
  } else if width(value) <= limit {
    value
  } else if limit == 1 {
    "…"
  } else {
    "…" ++ takeTail(value, limit - 1)
  }
}

let chunks = (text, limit) => {
  if limit <= 0 {
    []
  } else {
    let out = []
    let current = ref("")
    let used = ref(0)
    text
    ->clean
    ->graphemes
    ->Array.forEach(part => {
      let partWidth = graphemeWidth(part)
      if partWidth > limit {
        if current.contents != "" {
          out->Array.push(current.contents)
        }
        out->Array.push("…")
        current.contents = ""
        used.contents = 0
      } else if used.contents + partWidth > limit && current.contents != "" {
        out->Array.push(current.contents)
        current.contents = part
        used.contents = partWidth
      } else if partWidth <= limit {
        current.contents = current.contents ++ part
        used.contents = used.contents + partWidth
      }
    })
    if current.contents != "" {
      out->Array.push(current.contents)
    }
    out
  }
}

let wrap = (text, limit, maxLines) => {
  let words = text->clean->String.split(" ")->Array.filter(word => word != "")
  let lines = []
  let line = ref("")
  words->Array.forEach(word => {
    let parts = width(word) > limit ? chunks(word, limit) : [word]
    parts->Array.forEach(part => {
      if lines->Array.length < maxLines {
        let next = line.contents == "" ? part : line.contents ++ " " ++ part
        if width(next) > limit && line.contents != "" {
          lines->Array.push(line.contents)
          line.contents = part
        } else {
          line.contents = next
        }
      }
    })
  })
  if line.contents != "" && lines->Array.length < maxLines {
    lines->Array.push(line.contents)
  }
  lines
}
