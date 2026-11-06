open TestSupport

test(
  "release metadata routes candidates and stable versions and rejects mismatched refs",
  async context => {
    let home = await fixture(context, "resume-release-")
    let script = NodePath.joinMany([root(), "lib", "es6", "scripts", "Release.mjs"])
    let cases = [("1.1.0-rc.1", "next"), ("1.1.0", "latest")]
    for index in 0 to 1 {
      let (version, channel) = cases[index]->Option.getOrThrow
      await writeFile(
        NodePath.join(home, "package.json"),
        "{\"name\":\"@helgesverre/resume\",\"version\":\"" ++ version ++ "\"}",
      )
      let output = NodePath.join(home, version ++ ".txt")
      let env = environment(
        ~home,
        ~extra=[
          ("GITHUB_REF_TYPE", "tag"),
          ("GITHUB_REF_NAME", "v" ++ version),
          ("GITHUB_OUTPUT", output),
        ],
      )
      let result = runSync(execPath, [script], {cwd: home, env, encoding: "utf8"})
      equal(result.status, 0)
      equal(await readFile(output), "version=" ++ version ++ "\ndist-tag=" ++ channel ++ "\n")
      env->Dict.set("GITHUB_REF_NAME", "v9.9.9")
      equal(runSync(execPath, [script], {cwd: home, env, encoding: "utf8"}).status, 1)
      env->Dict.set("GITHUB_REF_NAME", "v" ++ version)
      env->Dict.set("GITHUB_REF_TYPE", "branch")
      equal(runSync(execPath, [script], {cwd: home, env, encoding: "utf8"}).status, 1)
    }
  },
)
