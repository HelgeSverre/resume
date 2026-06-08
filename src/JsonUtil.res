// Typed JSON utilities for JSONL parsing.

// Cheap substring prefilter to avoid parsing every line; callers parse matches.
let hasJsonField = (line, key, value) => {
  line->String.includes(`"${key}":"${value}"`) || line->String.includes(`"${key}": "${value}"`)
}

// Declarative decoders (json-combinators), used to replace deep
// `Option.flatMap(JSON.Decode.object)->Dict.get(...)` chains.

module Decode = JsonCombinators.Json.Decode

// Run a decoder best-effort: any failure (missing key, wrong type) collapses to None.
let decode = (json, decoder) =>
  switch JsonCombinators.Json.decode(json, decoder) {
  | Ok(value) => Some(value)
  | Error(_) => None
  }

// A decoder that reaches through a chain of object keys to `leaf`.
let at = (keys, leaf) => keys->Array.reduceRight(leaf, (acc, key) => Decode.field(key, acc))

// Best-effort string at a nested object-key path, e.g. ["data", "context", "cwd"].
let stringAt = (json, keys) => decode(json, at(keys, Decode.string))

// Best-effort float at a nested object-key path.
let floatAt = (json, keys) => decode(json, at(keys, Decode.float))

// Conversion helpers

let msFromString = value => {
  let parsed = Date.fromString(value)->Date.getTime
  Float.isNaN(parsed) ? 0.0 : parsed
}

let toMs = value =>
  switch value->Option.flatMap(JSON.Decode.float) {
  | Some(n) => n
  | None => value->Option.flatMap(JSON.Decode.string)->Option.mapOr(0.0, msFromString)
  }

// Timestamps appear either as ISO date strings or as epoch-millisecond numbers.
let msDecoder = Decode.oneOf([Decode.map(Decode.string, msFromString), Decode.float])

// Best-effort millisecond timestamp at a nested object-key path (0.0 when absent).
let msAt = (json, keys) => decode(json, at(keys, msDecoder))->Option.getOr(0.0)

let textFromContent = content => {
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

// Best-effort: the message content at a nested path, flattened to display text.
let textAt = (json, keys) => decode(json, at(keys, Decode.id))->Option.mapOr("", textFromContent)

let compact = (text, ~fallback="Untitled session") => {
  let value = switch text {
  | Some(s) => s
  | None => ""
  }

  let value = value->String.replaceRegExp(/\s+/g, " ")
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
