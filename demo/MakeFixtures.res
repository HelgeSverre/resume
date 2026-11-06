// Generates the synthetic HOME tree used by demo/resume.tape. Keeping this in
// ReScript lets the demo exercise the same JSON encoders and Node bindings as
// the application without ever touching a real agent history.

open NodeProcess

type tool = Claude | Codex | Amp | OpenCode | Kimi | Copilot | Antigravity | Pi | Junie

type session = {
  tool: tool,
  id: string,
  title: string,
  project: string,
  preview: string,
  age: float,
  messages: int,
}

@module("node:fs/promises")
external remove: (string, {"recursive": bool, "force": bool}) => promise<unit> = "rm"
@module("node:fs/promises")
external utimes: (string, float, float) => promise<unit> = "utimes"
@module("node:path")
external resolve: string => string = "resolve"
@new external makeDate: float => 'date = "Date"
@send external toISOString: 'date => string = "toISOString"

let minute = 60000.
let hour = 60. *. minute
let day = 24. *. hour
let iso = ms => makeDate(ms)->toISOString
let object = JsonUtil.object
let string = JsonUtil.string
let number = JsonUtil.float
let array = JSON.Encode.array
let textContent = text => array([object([("type", string("text")), ("text", string(text))])])

let sessions = [
  {
    tool: Claude,
    id: "7f3a9c21-2b4d-4e6f-8a01-aaaa00000001",
    title: "Add login and signup flow",
    project: "acme-api",
    preview: "Wired the /login route and refreshed session cookies for signed-in users.",
    age: 4. *. minute,
    messages: 14,
  },
  {
    tool: Codex,
    id: "c0de2222-1111-4222-8333-aaaa00000002",
    title: "Fix billing webhook retries",
    project: "billing-svc",
    preview: "Idempotency keys now dedupe duplicate webhook deliveries.",
    age: 18. *. minute,
    messages: 9,
  },
  {
    tool: Amp,
    id: "T-a1b2c3d4-0003",
    title: "Refactor login middleware",
    project: "acme-api",
    preview: "Extracted a requireUser guard and added clean 401 handling.",
    age: 42. *. minute,
    messages: 22,
  },
  {
    tool: OpenCode,
    id: "ses_4a1b2c3d40004aaaa00000004",
    title: "Build search index",
    project: "docs-site",
    preview: "Generated a lunr search index across all markdown pages.",
    age: 66. *. minute,
    messages: 7,
  },
  {
    tool: Kimi,
    id: "ses_k1a2b3c4-0015-4abc-8def-aaaa00000015",
    title: "Add session resume command",
    project: "acme-cli",
    preview: "Resume now restores the working dir for a chosen kimi session.",
    age: 30. *. minute,
    messages: 12,
  },
  {
    tool: Copilot,
    id: "cp00000a-1111-4222-8333-aaaa0000000a",
    title: "Wire up OAuth device flow",
    project: "acme-api",
    preview: "Added device-code polling and stored the refresh token securely.",
    age: 50. *. minute,
    messages: 9,
  },
  {
    tool: Antigravity,
    id: "ag00000b-2222-4333-8444-aaaa0000000b",
    title: "Refactor rendering pipeline",
    project: "acme-web",
    preview: "Split the renderer into layout and paint passes for clarity.",
    age: 90. *. minute,
    messages: 0,
  },
  {
    tool: Claude,
    id: "5e000005-2b4d-4e6f-8a01-aaaa00000005",
    title: "Dashboard skeleton loaders",
    project: "acme-web",
    preview: "Replaced layout shift with skeleton placeholders.",
    age: 2. *. hour,
    messages: 11,
  },
  {
    tool: Pi,
    id: "p1a2b3c4-0006-4abc-8def-aaaa00000006",
    title: "",
    project: "login-proxy",
    preview: "Cache login sessions in redis instead of in memory.",
    age: 3. *. hour,
    messages: 8,
  },
  {
    tool: Junie,
    id: "ju000007-1111-4222-8333-aaaa00000007",
    title: "Migrate schema to v3",
    project: "billing-svc",
    preview: "Added invoices and credits, backfilled in small batches.",
    age: 5. *. hour,
    messages: 6,
  },
  {
    tool: Amp,
    id: "T-a1b2c3d4-0008",
    title: "Login rate limiting",
    project: "login-proxy",
    preview: "Added a sliding window limiter keyed by ip and user.",
    age: 8. *. hour,
    messages: 16,
  },
  {
    tool: Codex,
    id: "c0de9999-1111-4222-8333-aaaa00000009",
    title: "Compress blog images",
    project: "blog",
    preview: "Converted hero images to avif with a webp fallback.",
    age: 14. *. hour,
    messages: 5,
  },
  {
    tool: Claude,
    id: "a0000010-2b4d-4e6f-8a01-aaaa00000010",
    title: "API pagination cursors",
    project: "acme-api",
    preview: "Switched offset paging over to keyset cursors.",
    age: day +. 2. *. hour,
    messages: 19,
  },
  {
    tool: OpenCode,
    id: "ses_b1c2d3e40011aaaa00000011",
    title: "Docs nav redesign",
    project: "docs-site",
    preview: "Collapsible sidebar plus on-page anchor links.",
    age: 2. *. day,
    messages: 10,
  },
  {
    tool: Pi,
    id: "p9a8b7c6-0012-4abc-8def-aaaa00000012",
    title: "",
    project: "infra",
    preview: "Infra dns cleanup: removed dangling records and renewed certs.",
    age: 3. *. day,
    messages: 13,
  },
  {
    tool: Junie,
    id: "ju000013-1111-4222-8333-aaaa00000013",
    title: "Review login scopes",
    project: "acme-api",
    preview: "Mapped roles onto scopes and removed unused grants.",
    age: 4. *. day,
    messages: 7,
  },
  {
    tool: Amp,
    id: "T-a1b2c3d4-0014",
    title: "Avatar upload crash",
    project: "acme-web",
    preview: "Guarded against a missing mime on empty uploads.",
    age: 6. *. day,
    messages: 9,
  },
]

let json = value => JSON.stringify(value)
let jsonl = rows => rows->Array.map(json)->Array.join("\n") ++ "\n"
let write = async (path, contents) => {
  await NodeFs.mkdirWithRecursive(NodePath.dirname(path), {"recursive": true})
  await NodeFs.writeFile(path, contents)
}
let padded = i =>
  i < 10 ? "000" ++ Int.toString(i) : i < 100 ? "00" ++ Int.toString(i) : "0" ++ Int.toString(i)
let messageText = (~index, ~last, session) =>
  index == 0
    ? session.title
    : last
    ? session.preview
    : Int.mod(index, 2) == 0
    ? "Can you take a look at this?"
    : "Done."

let turns = (session, ~updated, makeRow) => {
  let rows = []
  for index in 0 to session.messages - 1 {
    let last = index == session.messages - 1
    let role = last || Int.mod(index, 2) != 0 ? "assistant" : "user"
    let timestamp = updated -. Int.toFloat(session.messages - 1 - index) *. 1000.
    rows->Array.push(makeRow(role, messageText(~index, ~last, session), timestamp))
  }
  rows
}

let run = async home => {
  let now = Date.now()
  let cwd = session => NodePath.joinMany([home, "projects", session.project])
  let updated = session => now -. session.age
  let codexIndex = []
  let junieIndex = []
  let kimiIndex = []
  let antigravityCwd: Dict.t<JSON.t> = Dict.make()

  let writeClaude = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let rows = [object([("type", string("ai-title")), ("aiTitle", string(session.title))])]
    turns(session, ~updated=at, (role, text, timestamp) =>
      object([
        ("type", string(role)),
        ("message", object([("role", string(role)), ("content", textContent(text))])),
        ("cwd", string(workingDirectory)),
        ("timestamp", string(iso(timestamp))),
      ])
    )->Array.forEach(row => rows->Array.push(row))
    await write(
      NodePath.joinMany([
        home,
        ".claude",
        "projects",
        "-Users-dev-code-" ++ session.project,
        session.id ++ ".jsonl",
      ]),
      jsonl(rows),
    )
  }

  let writeCodex = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let created = iso(at -. Int.toFloat(session.messages) *. 1000.)
    let meta = object([
      ("id", string(session.id)),
      ("cwd", string(workingDirectory)),
      ("timestamp", string(created)),
    ])
    let rows = [object([("type", string("session_meta")), ("payload", meta)])]
    turns(session, ~updated=at, (role, text, timestamp) =>
      object([
        ("type", string("response_item")),
        ("payload", object([("role", string(role)), ("content", textContent(text))])),
        ("timestamp", string(iso(timestamp))),
      ])
    )->Array.forEach(row => rows->Array.push(row))
    await write(
      NodePath.joinMany([
        home,
        ".codex",
        "sessions",
        "2026",
        "05",
        "rollout-2026-05-31-" ++ session.id ++ ".jsonl",
      ]),
      jsonl(rows),
    )
    codexIndex->Array.push(
      object([
        ("id", string(session.id)),
        ("thread_name", string(session.title)),
        ("updated_at", string(iso(at))),
      ]),
    )
  }

  let writeAmp = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let messages = turns(session, ~updated=at, (role, text, timestamp) =>
      object([
        ("role", string(role)),
        ("content", textContent(text)),
        ("meta", object([("sentAt", number(timestamp))])),
      ])
    )
    let path = NodePath.joinMany([home, ".local", "share", "amp", "threads", session.id ++ ".json"])
    await write(
      path,
      json(
        object([
          ("id", string(session.id)),
          ("title", string(session.title)),
          ("created", number(at -. Int.toFloat(session.messages) *. minute)),
          ("messages", array(messages)),
          (
            "env",
            object([
              (
                "initial",
                object([
                  ("trees", array([object([("uri", string("file://" ++ workingDirectory))])])),
                ]),
              ),
            ]),
          ),
        ]),
      ) ++ "\n",
    )
    await utimes(path, at /. 1000., at /. 1000.)
  }

  let writeOpenCode = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    await write(
      NodePath.joinMany([
        home,
        ".local",
        "share",
        "opencode",
        "storage",
        "session",
        session.id ++ ".json",
      ]),
      json(
        object([
          ("id", string(session.id)),
          ("title", string(session.title)),
          ("directory", string(workingDirectory)),
          (
            "time",
            object([
              ("created", number(at -. Int.toFloat(session.messages) *. minute)),
              ("updated", number(at)),
            ]),
          ),
        ]),
      ),
    )
    for index in 0 to session.messages - 1 {
      let timestamp = at -. Int.toFloat(session.messages - 1 - index) *. 1000.
      let role = Int.mod(index, 2) == 0 ? "user" : "assistant"
      await write(
        NodePath.joinMany([
          home,
          ".local",
          "share",
          "opencode",
          "storage",
          "message",
          session.id,
          "msg_" ++ padded(index) ++ ".json",
        ]),
        json(
          object([
            ("id", string("msg_" ++ padded(index))),
            ("role", string(role)),
            ("time", object([("created", number(timestamp)), ("completed", number(timestamp))])),
            ("summary", object([("title", string(session.preview))])),
          ]),
        ),
      )
    }
  }

  let writeJunie = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let events = []
    for index in 0 to session.messages - 2 {
      events->Array.push(
        object([
          ("kind", string("TaskState")),
          ("text", string("running step " ++ Int.toString(index + 1))),
        ]),
      )
    }
    events->Array.push(
      object([("kind", string("UserPromptEvent")), ("presentablePrompt", string(session.preview))]),
    )
    await write(
      NodePath.joinMany([home, ".junie", "sessions", session.id, "events.jsonl"]),
      jsonl(events),
    )
    junieIndex->Array.push(
      object([
        ("sessionId", string(session.id)),
        ("taskName", string(session.title)),
        ("updatedAt", string(iso(at))),
        ("projectDir", string(workingDirectory)),
      ]),
    )
  }

  let writePi = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let rows = [
      object([
        ("type", string("session")),
        ("id", string(session.id)),
        ("cwd", string(workingDirectory)),
        ("timestamp", string(iso(at -. Int.toFloat(session.messages) *. 1000.))),
      ]),
    ]
    turns(session, ~updated=at, (role, text, timestamp) =>
      object([
        ("type", string("message")),
        ("role", string(role)),
        ("message", object([("role", string(role)), ("content", textContent(text))])),
        ("timestamp", string(iso(timestamp))),
      ])
    )->Array.forEach(row => rows->Array.push(row))
    await write(
      NodePath.joinMany([home, ".pi", "agent", "sessions", session.id ++ ".jsonl"]),
      jsonl(rows),
    )
  }

  let writeKimi = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let sessionDir = NodePath.joinMany([
      home,
      ".kimi-code",
      "sessions",
      "wd_" ++ session.project,
      session.id,
    ])
    await write(
      NodePath.join(sessionDir, "state.json"),
      json(
        object([
          ("title", string(session.title)),
          ("createdAt", string(iso(at -. Int.toFloat(session.messages) *. minute))),
          ("updatedAt", string(iso(at))),
          ("lastPrompt", string(session.preview)),
        ]),
      ),
    )
    let wirePath = NodePath.joinMany([sessionDir, "agents", "main", "wire.jsonl"])
    await write(
      wirePath,
      jsonl(
        turns(session, ~updated=at, (role, text, _timestamp) =>
          object([
            ("type", string("context.append_message")),
            ("message", object([("role", string(role)), ("content", textContent(text))])),
          ])
        ),
      ),
    )
    await utimes(wirePath, at /. 1000., at /. 1000.)
    kimiIndex->Array.push(
      object([
        ("sessionId", string(session.id)),
        ("sessionDir", string(sessionDir)),
        ("workDir", string(workingDirectory)),
      ]),
    )
  }

  let writeCopilot = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let rows = [
      object([
        ("type", string("session.start")),
        (
          "data",
          object([
            ("sessionId", string(session.id)),
            ("context", object([("cwd", string(workingDirectory))])),
          ]),
        ),
        ("timestamp", string(iso(at -. Int.toFloat(session.messages) *. 1000.))),
      ]),
    ]
    for index in 0 to session.messages - 1 {
      let last = index == session.messages - 1
      let role = Int.mod(index, 2) == 0 ? "user" : "assistant"
      rows->Array.push(
        object([
          ("type", string(role ++ ".message")),
          ("data", object([("content", string(messageText(~index, ~last, session)))])),
          ("timestamp", string(iso(at -. Int.toFloat(session.messages - 1 - index) *. 1000.))),
        ]),
      )
    }
    await write(
      NodePath.joinMany([home, ".copilot", "session-state", session.id, "events.jsonl"]),
      jsonl(rows),
    )
  }

  let writeAntigravity = async session => {
    let workingDirectory = cwd(session)
    let at = updated(session)
    let root = NodePath.joinMany([home, ".gemini", "antigravity-cli"])
    let conversation = NodePath.joinMany([root, "conversations", session.id ++ ".pb"])
    await write(conversation, "synthetic-protobuf-conversation")
    await write(
      NodePath.joinMany([root, "brain", session.id, "task.md.metadata.json"]),
      json(
        object([
          ("artifactType", string("ARTIFACT_TYPE_TASK")),
          ("summary", string(session.preview)),
          ("updatedAt", string(iso(at))),
        ]),
      ),
    )
    await utimes(conversation, at /. 1000., at /. 1000.)
    antigravityCwd->Dict.set(workingDirectory, string(session.id))
  }

  await remove(home, {"recursive": true, "force": true})
  for index in 0 to sessions->Array.length - 1 {
    switch sessions->Array.get(index) {
    | Some(session) =>
      await NodeFs.mkdirWithRecursive(cwd(session), {"recursive": true})
      switch session.tool {
      | Claude => await writeClaude(session)
      | Codex => await writeCodex(session)
      | Amp => await writeAmp(session)
      | OpenCode => await writeOpenCode(session)
      | Junie => await writeJunie(session)
      | Pi => await writePi(session)
      | Kimi => await writeKimi(session)
      | Copilot => await writeCopilot(session)
      | Antigravity => await writeAntigravity(session)
      }
    | None => ()
    }
  }
  await write(NodePath.joinMany([home, ".codex", "session_index.jsonl"]), jsonl(codexIndex))
  await write(NodePath.joinMany([home, ".junie", "sessions", "index.jsonl"]), jsonl(junieIndex))
  await write(NodePath.joinMany([home, ".kimi-code", "session_index.jsonl"]), jsonl(kimiIndex))
  await write(
    NodePath.joinMany([home, ".gemini", "antigravity-cli", "cache", "last_conversations.json"]),
    json(JSON.Encode.object(antigravityCwd)),
  )
  Console.log(`wrote ${Int.toString(sessions->Array.length)} sessions to ${home}`)
}

switch argv->Array.get(2) {
| Some("--help") | Some("-h") =>
  Console.log("Usage: node lib/es6/demo/MakeFixtures.mjs FIXTURE_HOME")
| Some(path) if path != "" =>
  let destination = resolve(path)
  if (
    destination == resolve("/") || destination == resolve(".") || destination == resolve(homedir())
  ) {
    Console.error("Choose a dedicated fixture directory")
    exit(2)
  } else {
    run(destination)->ignore
  }
| _ => {
    Console.error("usage: node lib/es6/demo/MakeFixtures.mjs <home-dir>")
    exit(1)
  }
}
