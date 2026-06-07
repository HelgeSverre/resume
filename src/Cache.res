// Sessions cache: stat-keyed (mtime + size) JSON cache of parsed session data.

open NodeFs
open NodePath

type entry = {
  mtimeMs: float,
  size: float,
  value: JSON.t,
}

type t = {
  path: string,
  mutable entries: Dict.t<entry>,
  mutable used: array<string>,
  mutable changed: bool,
}

let readText = async path => {
  try {
    Some(await NodeFs.readFile(path, "utf8"))
  } catch {
  | _ => None
  }
}

let loadCache = async home => {
  let path = joinMany([home, ".cache", "resume", "sessions-cache-v2.json"])

  let entries = Dict.make()

  if await exists(path) {
    switch await readText(path) {
    | Some(content) =>
      try {
        let data = JSON.parseOrThrow(content)
        switch JSON.Decode.object(data) {
        | Some(obj) =>
          switch obj->Dict.get("version")->Option.flatMap(JSON.Decode.string) {
          | Some("2") =>
            switch obj->Dict.get("entries")->Option.flatMap(JSON.Decode.object) {
            | Some(entriesObj) =>
              entriesObj->Dict.forEachWithKey((entryJson, key) => {
                switch JSON.Decode.object(entryJson) {
                | Some(entryObj) =>
                  let mtimeMs = entryObj->Dict.get("mtimeMs")->Option.flatMap(JSON.Decode.float)
                  let size = entryObj->Dict.get("size")->Option.flatMap(JSON.Decode.float)
                  let value = entryObj->Dict.get("value")
                  switch (mtimeMs, size, value) {
                  | (Some(mtimeMs), Some(size), Some(value)) =>
                    let entry = {
                      mtimeMs,
                      size,
                      value,
                    }
                    entries->Dict.set(key, entry)
                  | _ => ()
                  }
                | _ => ()
                }
              })
            | _ => ()
            }
          | _ => ()
          }
        | _ => ()
        }
      } catch {
      | _ => ()
      }
    | None => ()
    }
  }

  {
    path,
    entries,
    used: [],
    changed: false,
  }
}

let saveCache = async cache => {
  if !cache.changed {
    ()
  } else {
    let filteredEntries = Dict.make()
    cache.used->Array.forEach(path => {
      switch cache.entries->Dict.get(path) {
      | Some(entry) => filteredEntries->Dict.set(path, entry)
      | None => ()
      }
    })

    let dir = dirname(cache.path)
    await mkdirWithRecursive(dir, {"recursive": true})

    let cacheData = {
      "version": "2",
      "entries": filteredEntries,
    }

    switch JSON.stringifyAny(cacheData) {
    | Some(json) => await writeFile(cache.path, json)
    | None => ()
    }
  }
}

let cachedValue = async (cache: t, ~namespace, path, ~encode, ~decode, load) => {
  let info = await stat(path)
  let key = namespace ++ "\x00" ++ path

  let refresh = async () => {
    let value = await load(path)
    cache.entries->Dict.set(
      key,
      {
        mtimeMs: info->mtimeMs,
        size: info->size,
        value: encode(value),
      },
    )
    cache.changed = true
    cache.used = cache.used->Array.concat([key])
    value
  }

  switch cache.entries->Dict.get(key) {
  | Some(entry) if entry.mtimeMs == info->mtimeMs && entry.size == info->size =>
    cache.used = cache.used->Array.concat([key])
    switch decode(entry.value) {
    | Some(value) => value
    | None => await refresh()
    }
  | _ => await refresh()
  }
}

let readJson = async path => {
  switch await readText(path) {
  | Some(content) =>
    try {
      Some(JSON.parseOrThrow(content))
    } catch {
    | _ => None
    }
  | None => None
  }
}
