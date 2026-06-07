type adapter = {
  name: string,
  collect: (string, Cache.t) => promise<array<Session.t>>,
}

let registry = [
  {name: "codex", collect: Codex.collectCodex},
  {name: "claude", collect: Claude.collectClaude},
  {name: "junie", collect: Junie.collectJunie},
  {name: "pi", collect: Pi.collectPi},
  {name: "amp", collect: Amp.collectAmp},
  {name: "opencode", collect: (home, _cache) => OpenCode.collectOpenCode(home)},
  {name: "kimi", collect: Kimi.collectKimi},
  {name: "copilot", collect: Copilot.collectCopilot},
  {name: "antigravity", collect: (home, _cache) => Antigravity.collectAntigravity(home)},
]

// One failing adapter must never take down the whole listing.
let collectOne = async (home, cache, adapter) =>
  switch await adapter.collect(home, cache) {
  | sessions => sessions
  | exception _ =>
    Console.error(`Warning: ${adapter.name} adapter failed`)
    []
  }

let collectSessionsFromHome = async home => {
  let cache = await Cache.loadCache(home)
  let groups = await AdapterUtil.all(
    registry->Array.map(adapter => collectOne(home, cache, adapter)),
  )
  await Cache.saveCache(cache)
  groups->Array.flat
}
