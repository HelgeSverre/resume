// Bounded task scheduling shared by file collectors and cache maintenance.
@val external promiseAll: array<promise<'a>> => promise<array<'a>> = "Promise.all"

let map = async (~shouldContinue=() => true, items: array<'a>, fn: 'a => promise<'b>): array<
  'b,
> => {
  let results: array<option<'b>> = Array.make(~length=items->Array.length, None)
  let next = ref(0)
  let worker = async () => {
    while next.contents < items->Array.length && shouldContinue() {
      let index = next.contents
      next.contents = index + 1
      switch items->Array.get(index) {
      | Some(item) => results[index] = Some(await fn(item))
      | None => ()
      }
    }
  }
  let _ = await promiseAll(
    Array.make(~length=min(8, items->Array.length), ())->Array.map(_ => worker()),
  )
  results->Array.filterMap(value => value)
}
