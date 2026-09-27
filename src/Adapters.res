type adapter = {
  tool: Session.tool,
  collect: (string, Cache.t) => promise<array<Session.t>>,
}

let registry = [
  {tool: Claude, collect: Claude.collectClaude},
  {tool: Codex, collect: Codex.collectCodex},
  {tool: Amp, collect: Amp.collectAmp},
  {tool: OpenCode, collect: (home, _cache) => OpenCode.collectOpenCode(home)},
  {tool: Kimi, collect: Kimi.collectKimi},
  {tool: Copilot, collect: Copilot.collectCopilot},
  {tool: Junie, collect: Junie.collectJunie},
  {tool: Pi, collect: Pi.collectPi},
  {tool: Antigravity, collect: (home, _cache) => Antigravity.collectAntigravity(home)},
  {tool: Gemini, collect: (home, _cache) => Gemini.collectGemini(home)},
  {tool: Vibe, collect: (home, _cache) => Vibe.collectVibe(home)},
  {tool: Kilo, collect: (home, _cache) => SqliteAgents.collectKilo(home)},
  {tool: Hermes, collect: (home, _cache) => SqliteAgents.collectHermes(home)},
  {tool: Devin, collect: (home, _cache) => SqliteAgents.collectDevin(home)},
]

// One failing adapter must never take down the whole listing.
let collectOne = async (home, cache, adapter) =>
  switch await adapter.collect(home, cache) {
  | sessions => sessions
  | exception _ =>
    Console.error(`Warning: ${Session.toolName(adapter.tool)} adapter failed`)
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
