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
  used: Dict.t<bool>,
  dirty: Dict.t<bool>,
  mutable changed: bool,
}

@module("node:fs/promises")
external removeDirectory: string => promise<unit> = "rmdir"

// ReScript wraps JavaScript errors thrown from async fs calls in JsExn. Keep
// the unwrapping here so callers distinguish absence from access/I/O failures.
let isMissingFsError: exn => bool = %raw(`error => {
  const raw = error?.RE_EXN_ID === "JsExn" ? error._1 : error;
  return raw?.code === "ENOENT" || raw?.code === "ENOTDIR";
}`)

let isMissingProcessError: exn => bool = %raw(`error => {
  const raw = error?.RE_EXN_ID === "JsExn" ? error._1 : error;
  return raw?.code === "ESRCH";
}`)

@val @scope("process")
external isProcessAlive: (int, int) => unit = "kill"

@val external schedule: (unit => unit, int) => unit = "setTimeout"

let wait = milliseconds =>
  Promise.make((resolve, _reject) => schedule(() => resolve(), milliseconds))

let readText = async path => {
  try {
    Some(await NodeFs.readFile(path, "utf8"))
  } catch {
  | _ => None
  }
}

let readPersistentText = async path =>
  try {
    Some(await NodeFs.readPersistentFile(path, "utf8"))
  } catch {
  | _ => None
  }

let decodeEntries = content => {
  let entries = Dict.make()
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
                entries->Dict.set(key, {mtimeMs, size, value})
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
  entries
}

let loadEntries = async path =>
  try {
    decodeEntries(await NodeFs.readPersistentFile(path, "utf8"))
  } catch {
  | _ => Dict.make()
  }

let loadCache = async home => {
  let path = joinMany([home, ".cache", "resume", "sessions-cache-v2.json"])
  let entries = await loadEntries(path)

  {
    path,
    entries,
    used: Dict.make(),
    dirty: Dict.make(),
    changed: false,
  }
}

let nextWrite = ref(0)
let nextLock = ref(0)

let lockPath = cachePath => cachePath ++ ".lock"
let lockOwnerPath = lock => join(lock, "owner")
let lockGraceMilliseconds = 30_000.

type heldLock = {path: string, ownerPath: string, token: string}

let pathForKey = key => key->String.split("\x00")->Array.get(1)

// Only ENOENT and ENOTDIR mean a cached session is gone. Permission and I/O
// failures are transient: evicting those entries would turn a temporary
// filesystem issue into permanent cache loss.
let isMissingPath = async path => {
  try {
    let _ = await stat(path)
    false
  } catch {
  | error => error->isMissingFsError
  }
}

// Only evict entries for files that no longer exist. An adapter can fail before
// reaching a valid entry; treating every untouched entry as deleted would make
// a transient read failure discard that adapter's warm cache.
let missingKeys = async (~shouldContinue=() => true, keys) => {
  let missing = await AsyncPool.map(~shouldContinue, keys, async key =>
    switch pathForKey(key) {
    | Some(path) if await isMissingPath(path) => Some(key)
    | _ => None
    }
  )
  missing->Array.filterMap(value => value)
}

let lockOwnerPid = content => {
  let firstPart = content->String.trim->String.split(":")->Array.get(0)
  switch firstPart->Option.flatMap(value => Int.fromString(value)) {
  | Some(pid) => Some(pid)
  | None => None
  }
}

let isLockOwnerAlive = content =>
  switch lockOwnerPid(content) {
  | Some(pid) =>
    try {
      isProcessAlive(pid, 0)
      true
    } catch {
    // EPERM still proves another user's process exists. Only ESRCH is a
    // positive indication that the recorded owner is gone.
    | error => !isMissingProcessError(error)
    }
  | None => false
  }

let lockIsStable = (before, after) =>
  before->mtimeMs == after->mtimeMs && before->size == after->size

// mkdir is the atomic operation here: no contender can observe a half-created
// directory as its own. An owner file is diagnostic/recovery metadata only.
// We recover immediately only locks whose recorded PID is certainly dead; an
// incomplete or unreadable lock gets a grace period so a just-created lock is
// never stolen while its creator is writing the owner record.
let tryReclaimLock = async path => {
  let ownerPath = lockOwnerPath(path)
  try {
    let before = await stat(path)
    let owner = await readPersistentText(ownerPath)
    let after = await stat(path)
    let age = Date.now() -. after->mtimeMs
    let shouldReclaim = if !lockIsStable(before, after) {
      false
    } else {
      switch owner {
      | Some(content) if !isLockOwnerAlive(content) =>
        // A valid, dead PID is safe to reclaim without waiting for the
        // grace period. Malformed owner data is handled below as incomplete.
        switch lockOwnerPid(content) {
        | Some(_) => true
        | None => age >= lockGraceMilliseconds
        }
      | Some(_) => false
      | None => age >= lockGraceMilliseconds
      }
    }
    if shouldReclaim {
      // Re-stat and re-read immediately before removal. If a different run
      // replaced the directory or owner record, do not unlink its lock.
      let latest = await stat(path)
      if lockIsStable(after, latest) {
        switch (await readPersistentText(ownerPath), owner) {
        | (current, expected) if current == expected => {
            let _ = await NodeFs.unlink(ownerPath)->Promise.catch(_ => Promise.resolve())
            let _ = await removeDirectory(path)->Promise.catch(_ => Promise.resolve())
          }
        | _ => ()
        }
      }
    }
  } catch {
  | _ => ()
  }
}

let releaseLock = async held => {
  switch await readPersistentText(held.ownerPath) {
  | Some(token) if token == held.token => {
      let _ = await NodeFs.unlink(held.ownerPath)->Promise.catch(_ => Promise.resolve())
      let _ = await removeDirectory(held.path)->Promise.catch(_ => Promise.resolve())
    }
  | _ => ()
  }
}

let rec acquireLock = async (~path, ~shouldContinue=() => true, ~attempt=0) => {
  if !shouldContinue() {
    None
  } else {
    try {
      await mkdirWithRecursive(path, {"recursive": false})

      // We are the only process that can see this directory before the owner
      // record is written. If cancellation won the race with mkdir, remove the
      // incomplete lock instead of making a cancelled picker wait for retries.
      if !shouldContinue() {
        let _ = await removeDirectory(path)->Promise.catch(_ => Promise.resolve())
        None
      } else {
        nextLock.contents = nextLock.contents + 1
        let token =
          Int.toString(NodeProcess.pid) ++
          ":" ++
          Int.toString(nextLock.contents) ++
          ":" ++
          Float.toString(Date.now())
        let ownerPath = lockOwnerPath(path)
        try {
          await writeFile(ownerPath, token)
          Some({path, ownerPath, token})
        } catch {
        | error => {
            let _ = await removeDirectory(path)->Promise.catch(_ => Promise.resolve())
            throw(error)
          }
        }
      }
    } catch {
    | _ if !shouldContinue() || attempt >= 100 => None
    | _ => {
        await tryReclaimLock(path)
        if !shouldContinue() {
          None
        } else {
          await wait(25)
          await acquireLock(~path, ~shouldContinue, ~attempt=attempt + 1)
        }
      }
    }
  }
}

let writeCache = async cache => {
  let unusedKeys = []
  cache.entries->Dict.forEachWithKey((_, key) => {
    if cache.used->Dict.get(key) == None {
      unusedKeys->Array.push(key)
    }
  })
  let staleKeys = await missingKeys(~shouldContinue=() => !ScanControl.cancelled(), unusedKeys)

  if !ScanControl.cancelled() && (cache.changed || staleKeys->Array.length > 0) {
    let dir = dirname(cache.path)
    await mkdirWithRecursive(dir, {"recursive": true})
    let lock = lockPath(cache.path)
    switch await acquireLock(~path=lock, ~shouldContinue=() => !ScanControl.cancelled()) {
    | None => Diagnostics.warn("Warning: timed out waiting to save session cache")
    | Some(held) if ScanControl.cancelled() => await releaseLock(held)
    | Some(held) => {
        try {
          // A second process may have completed its scan while this process was
          // parsing files. Preserve those entries and apply only our fresh ones.
          let merged = await loadEntries(cache.path)
          // Recheck after acquiring the lock: a session path may have been
          // recreated while this process was waiting, in which case another run
          // could already have added a fresh entry for it.
          let confirmedStaleKeys = await missingKeys(
            ~shouldContinue=() => !ScanControl.cancelled(),
            staleKeys,
          )
          if !ScanControl.cancelled() {
            confirmedStaleKeys->Array.forEach(key => merged->Dict.delete(key))
            cache.dirty->Dict.forEachWithKey((_, key) => {
              switch cache.entries->Dict.get(key) {
              | Some(entry) => merged->Dict.set(key, entry)
              | None => ()
              }
            })

            let cacheData = {
              "version": "2",
              "entries": merged,
            }

            switch JSON.stringifyAny(cacheData) {
            | Some(json) =>
              // Check immediately before starting the atomic write. Once the
              // temporary write starts, always rename it so cancellation never
              // exposes a half-written cache or leaves a completed temp file.
              if !ScanControl.cancelled() {
                nextWrite.contents = nextWrite.contents + 1
                let temporary =
                  cache.path ++
                  "." ++
                  Int.toString(NodeProcess.pid) ++
                  "." ++
                  Float.toString(Date.now()) ++
                  "." ++
                  Int.toString(nextWrite.contents) ++ ".tmp"
                try {
                  await writeFile(temporary, json)
                  await NodeFs.rename(temporary, cache.path)
                } catch {
                | error =>
                  let _ = await NodeFs.unlink(temporary)->Promise.catch(_ => Promise.resolve())
                  throw(error)
                }
              }
            | None => ()
            }
          }
        } catch {
        | error => {
            await releaseLock(held)
            throw(error)
          }
        }
        await releaseLock(held)
      }
    }
  }
}

let saveCache = async cache => {
  if !ScanControl.cancelled() {
    try {await writeCache(cache)} catch {
    | _ => Diagnostics.warn("Warning: could not save session cache")
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
    cache.dirty->Dict.set(key, true)
    cache.used->Dict.set(key, true)
    value
  }

  switch cache.entries->Dict.get(key) {
  | Some(entry) if entry.mtimeMs == info->mtimeMs && entry.size == info->size =>
    cache.used->Dict.set(key, true)
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
