// Typed JSON utilities for JSONL parsing.

// Cheap substring prefilter to avoid parsing every line; callers parse matches.
let hasJsonField = (line, key, value) => {
  line->String.includes(`"${key}":"${value}"`) || line->String.includes(`"${key}": "${value}"`)
}

// Conversion helpers

let toMs = value => {
  switch value->Option.flatMap(JSON.Decode.float) {
  | Some(n) => n
  | None =>
    switch value->Option.flatMap(JSON.Decode.string) {
    | Some(s) => {
        let parsed = Date.fromString(s)->Date.getTime
        if Float.isNaN(parsed) {
          0.0
        } else {
          parsed
        }
      }
    | None => 0.0
    }
  }
}

let rec textFromContent = content => {
  switch content {
  | JSON.String(s) => s
  | JSON.Array(arr) =>
    arr
    ->Array.map(item => {
      switch item {
      | JSON.String(s) => s
      | JSON.Object(obj) =>
        switch obj->Dict.get("text")->Option.flatMap(JSON.Decode.string) {
        | Some(s) => s
        | None =>
          switch obj->Dict.get("content")->Option.flatMap(JSON.Decode.string) {
          | Some(s) => s
          | None => ""
          }
        }
      | _ => ""
      }
    })
    ->Array.filter(s => s != "")
    ->Array.join(" ")
    ->String.trim
  | _ => ""
  }
}

let compact = (text, ~fallback="Untitled session") => {
  let value = switch text {
  | Some(s) => s
  | None => ""
  }

  let value = value->String.replaceRegExp(/\\s+/g, " ")
  let value = value->String.trim

  if value->String.length == 0 {
    fallback
  } else if value->String.length > 140 {
    value->String.slice(~start=0, ~end=137) ++ "..."
  } else {
    value
  }
}

let cwdFromFileUri = uri => {
  switch uri {
  | Some(s) if s->String.startsWith("file://") =>
    try {
      Some(NodeUrl.fileURLToPath(s))
    } catch {
    | _ => None
    }
  | _ => None
  }
}
