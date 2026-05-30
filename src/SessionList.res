let key = session => Session.toolName(session.Session.tool) ++ ":" ++ session.id

@send external sortInPlace: (array<'a>, ('a, 'a) => int) => array<'a> = "sort"

let byNewest = (left: Session.t, right: Session.t) => {
  if left.updatedAtMs > right.updatedAtMs {
    -1
  } else if left.updatedAtMs < right.updatedAtMs {
    1
  } else {
    0
  }
}

let mergeAndSort = sessions => {
  let byKey = Dict.make()

  sessions->Array.forEach(session => {
    let sessionKey = key(session)
    switch Dict.get(byKey, sessionKey) {
    | Some(existing) =>
      if session.Session.updatedAtMs >= existing.Session.updatedAtMs {
        Dict.set(byKey, sessionKey, session)
      }
    | None => Dict.set(byKey, sessionKey, session)
    }
  })

  byKey->Dict.valuesToArray->sortInPlace(byNewest)
}

let visible = (~query, sessions) =>
  sessions
  ->mergeAndSort
  ->Array.filter(session => Session.matchesQuery(session, query))
