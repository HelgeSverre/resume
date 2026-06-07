// Small JSON codec helpers used by cache value encoders/decoders.

let object = pairs => JSON.Encode.object(Dict.fromArray(pairs))

let string = JSON.Encode.string

let int = i => JSON.Encode.float(Int.toFloat(i))

let float = JSON.Encode.float

let nullableString = value =>
  switch value {
  | Some(s) => JSON.Encode.string(s)
  | None => JSON.Encode.null
  }

let asObject = (json, decode) => json->JSON.Decode.object->Option.flatMap(decode)

let getString = (obj, key) => obj->Dict.get(key)->Option.flatMap(JSON.Decode.string)

let getFloat = (obj, key) => obj->Dict.get(key)->Option.flatMap(JSON.Decode.float)

let getInt = (obj, key) => getFloat(obj, key)->Option.map(Float.toInt)
