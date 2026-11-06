// Decode records as a stream; malformed or partially written rows are ignored,
// while errors in the visitor itself propagate to the collector's file boundary.
let forEach = (path, visit) =>
  NodeFs.forEachLine(path, line => {
    switch JsonUtil.parse(line) {
    | Some(row) => visit(row)
    | None => ()
    }
  })
let read = async path => {
  let rows = []
  await forEach(path, row => rows->Array.push(row))
  rows
}
