// Imported through a minimal ESM stdin/eval bootstrap to exercise worker flags.
let main = async () => {
  let home = NodeProcess.env->Dict.get("HOME")->Option.getOr(NodeProcess.homedir())
  let sessions = await OpenCode.collectOpenCode(home, await Cache.loadCache(home))
  Console.log(
    JSON.stringify(
      JSON.Encode.array(sessions->Array.map(session => JSON.Encode.string(session.Session.id))),
    ),
  )
}
main()->ignore
