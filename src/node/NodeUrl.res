// Node.js url bindings

@module("node:url")
external fileURLToPath: string => string = "fileURLToPath"

type url
@module("node:url") external pathToFileURL: string => url = "pathToFileURL"
@get external href: url => string = "href"
let fileUrl = path => pathToFileURL(path)->href
