// Typed JSON utilities for JSONL parsing.

// Cheap substring prefilter to avoid parsing every line; callers parse matches.
let fieldPatterns: Dict.t<RegExp.t> = Dict.make()
let hasJsonField = (line, key, value) => {
  let token = key ++ ":" ++ value
  let expression = switch fieldPatterns->Dict.get(token) {
  | Some(expression) => expression
  | None =>
    let escape: string => string = %raw(`value => Array.from(value, c =>
      [46,42,43,63,94,36,123,125,40,41,124,91,93,92].includes(c.codePointAt(0))
        ? String.fromCharCode(92) + c : c).join("")`)
    let expression = RegExp.fromString(
      "\"" ++ escape(key) ++ "\"\\s*:\\s*\"" ++ escape(value) ++ "\"",
    )
    fieldPatterns->Dict.set(token, expression)
    expression
  }
  RegExp.test(expression, line)
}

// Small value helpers shared by streamed adapters and metadata merging.
let parse = text =>
  try {Some(JSON.parseOrThrow(text))} catch {
  | _ => None
  }
let nonEmpty = value => value->String.trim == "" ? None : Some(value)
@send external codeUnitAt: (string, int) => int = "charCodeAt"
let prefix = (text, limit) => {
  if limit <= 0 {
    ""
  } else if text->String.length <= limit {
    text
  } else {
    // Do not leave half of an emoji/surrogate in a truncated title or preview.
    let last = codeUnitAt(text, limit - 1)
    text->String.slice(~start=0, ~end=last >= 0xd800 && last <= 0xdbff ? limit - 1 : limit)
  }
}
let preview = text => prefix(text, 16000)

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
    prefix(value, 137) ++ "..."
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

// Encoders and decoders for small cached adapter payloads.
let object = pairs => JSON.Encode.object(Dict.fromArray(pairs))
let string = JSON.Encode.string
let int = i => JSON.Encode.float(Int.toFloat(i))
let float = JSON.Encode.float
let nullableString = value => value->Option.mapOr(JSON.Encode.null, JSON.Encode.string)
let asObject = (json, decode) => json->JSON.Decode.object->Option.flatMap(decode)
let getString = (obj, key) => obj->Dict.get(key)->Option.flatMap(JSON.Decode.string)
let getInt = (obj, key) =>
  obj->Dict.get(key)->Option.flatMap(JSON.Decode.float)->Option.map(Float.toInt)
