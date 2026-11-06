// Keep synchronous SQLite work off the terminal's event loop.
type worker
type url
type response = {rows: array<JSON.t>, failed: bool}
@module("node:worker_threads") @new
external createWorker: (
  url,
  {"workerData": {"path": string, "sql": string}, "stderr": bool, "execArgv": array<string>},
) => worker = "Worker"
@get external stderr: worker => 'stream = "stderr"
@send external asString: 'buffer => string = "toString"
@send external once: (worker, string, 'a => unit) => unit = "once"
let workerUrl: url = %raw(`new URL("./NodeSqliteWorker.mjs", import.meta.url)`)

@send external terminate: worker => promise<int> = "terminate"
let activeWorkers: ref<array<worker>> = ref([])
let activeWorkerCount = () => activeWorkers.contents->Array.length
let cancelAll = async () => {
  let workers = activeWorkers.contents
  activeWorkers.contents = []
  let _ = await Promise.all(
    workers->Array.map(worker => worker->terminate->Promise.catch(_ => Promise.resolve(0))),
  )
}

let query = (path, sql) =>
  // `exists`/directory reads in adapters can complete just after the picker
  // aborts. Do not let that continuation create a worker after `cancelAll`
  // has taken its snapshot; it would otherwise keep the selected launch
  // waiting for a query that is no longer useful.
  if ScanControl.cancelled() {
    Promise.resolve([])
  } else {
    Promise.make((resolve, _reject) => {
      let settled = ref(false)
      let finish = rows => {
        if !settled.contents {
          settled.contents = true
          resolve(rows)
        }
      }
      try {
        let worker = createWorker(
          workerUrl,
          {
            "workerData": {"path": path, "sql": sql},
            "stderr": true,
            // A file-based worker needs none of the parent's command-line mode
            // flags. In particular, inherited --input-type, --eval, and --test
            // either reject a worker file or run the wrong program. Suppress only
            // runtime experimental notices; real query/worker failures still report.
            "execArgv": ["--disable-warning=ExperimentalWarning"],
          },
        )
        activeWorkers.contents->Array.push(worker)
        // Node 22 emits SQLite's experimental warning from the worker. Route it
        // through the same status reporter as adapter warnings instead of drawing
        // raw stderr over the picker.
        worker
        ->stderr
        ->NodeReadline.on("data", chunk => Diagnostics.warn(chunk->asString->String.trim))
        worker->once("message", (response: response) => {
          if response.failed {
            Diagnostics.warn("Warning: could not read SQLite session database")
          }
          finish(response.rows)
        })
        worker->once("error", _ => {
          Diagnostics.warn("Warning: SQLite worker failed")
          finish([])
        })
        worker->once("exit", _ => {
          activeWorkers.contents = activeWorkers.contents->Array.filter(active => active != worker)
          finish([])
        })
      } catch {
      | _ => {
          Diagnostics.warn("Warning: could not start SQLite worker")
          finish([])
        }
      }
    })
  }
