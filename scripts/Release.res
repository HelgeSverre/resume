// Run after compiling, before packing. Never choose a channel from unvalidated
// event input: the pushed tag must exactly identify this package version.
@module("node:fs/promises")
external appendFile: (string, string) => promise<unit> = "appendFile"
@new external failure: string => exn = "Error"

let main = async () => {
  let manifest = await NodeFs.readPersistentFile("package.json", "utf8")
  let json = JSON.parseOrThrow(manifest)
  if JsonUtil.stringAt(json, ["name"]) != Some("@helgesverre/resume") {
    throw(failure("Unexpected package name"))
  }
  let version = JsonUtil.stringAt(json, ["version"])->Option.getOr("")
  if (
    !RegExp.test(/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[a-zA-Z0-9.-]+)?$/, version)
  ) {
    throw(failure("Invalid release version"))
  }
  if (
    NodeProcess.env->Dict.get("GITHUB_REF_TYPE") != Some("tag") ||
      NodeProcess.env->Dict.get("GITHUB_REF_NAME") != Some("v" ++ version)
  ) {
    throw(failure("The pushed tag must equal v" ++ version))
  }
  let channel = version->String.includes("-") ? "next" : "latest"
  let output = "version=" ++ version ++ "\ndist-tag=" ++ channel ++ "\n"
  switch NodeProcess.env->Dict.get("GITHUB_OUTPUT") {
  | Some(path) => await appendFile(path, output)
  | None => throw(failure("GITHUB_OUTPUT is required"))
  }
  NodeProcess.stdout->NodeProcess.write("Validated " ++ version ++ " → " ++ channel ++ "\n")
}

let _ = main()->Promise.catch(error => {
  Console.error(error)
  NodeProcess.exit(1)
  Promise.resolve()
})
