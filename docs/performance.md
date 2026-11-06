# Loading performance

Measured on the local macOS arm64 machine with Node.js v26.10.0, comparing the
original project against this implementation. Results are local measurements,
not a cross-machine performance guarantee. Raw aggregate samples are in
[performance-results.json](performance-results.json); no session titles, paths,
IDs, or message contents are included.

The initial sections below record the earlier progressive-loading comparison;
the final section records the completed streaming and refactoring work.

## Interactive startup

Five runs per build, alternating order, with separate warmed application caches.
Both builds read the same live history through symlinked home directories. Each
subprocess had a 140-column, 40-row pseudo-terminal. The first rendered search
line marks the first screen; the first highlighted session marks usable results.
The old picker only renders after loading completes. The new picker's ready
status marks the completion of its scan and cache save. Node process startup is
included. Each cache was populated once before collecting the warm samples.

| Median | Before | After | Change |
| --- | ---: | ---: | ---: |
| First screen | 1,053 ms | 79 ms | 13.3× faster |
| First selectable session | 1,053 ms | 120 ms | 8.8× faster |
| All loading complete | 1,053 ms | 878 ms | 17% less time |

The captured-stdout workflow was also exercised through a pseudo-terminal:
stdin and stderr remained terminals, stdout was a pipe, and Enter produced only
the correctly quoted resume command. Clipboard writes were stubbed for that
fixture. Escape and results arriving after closing are covered by automated tests.

## Collection and caching

The committed benchmark can compare any two already-built source trees:

```sh
node lib/es6/scripts/Benchmark.mjs /path/to/before /path/to/after 6
RESUME_BENCH_COLD=1 node lib/es6/scripts/Benchmark.mjs /path/to/before /path/to/after 6
```

It runs each sample in a fresh Node process, alternates build order, isolates
cache files, and prints aggregate JSON. By default each build starts from the
same existing cache snapshot; `RESUME_BENCH_COLD=1` starts each cache empty.
Adapters read the real history but benchmark cache writes stay in temporary
storage, which is removed on completion. The script measures collection,
deduplication and cache persistence, without the interactive UI or process
startup. A first-adapter result time in its output is not equivalent to a usable
screen in the old implementation.

The following results use empty initial caches, followed by five warmed samples
per build:

| Measurement | Before | After |
| --- | ---: | ---: |
| Warm median collection + deduplication + cache save | 839 ms | 721 ms |
| First scan with an empty parsed cache, one sample each | 18.75 s | 18.44 s |
| Normalized sessions discovered | 5,424 | 5,888 |
| Warm median maximum event-loop delay | 49.8 ms | 47.9 ms |

The new scan returns 464 additional sessions: 429 OpenCode v2-only records and
35 Poolside summaries. Pi returns the same 138 sessions. Raw OpenCode rows in the
old adapter included duplicate JSON/SQLite copies; the new adapter deduplicates
before returning its results.

The last warm sample's OpenCode adapter time fell from 726 ms to 312 ms while
returning 1,473 unique sessions. This is an individual sample, not a median or an
isolated causal measurement. OpenCode now caches parsed message metadata, reads
messages concurrently, and counts SQLite messages in a grouped query. The file
scheduler keeps up to eight tasks active rather than waiting at batch barriers.
SQLite queries run in short-lived worker threads, keeping their synchronous work
off the terminal's event loop.

## Remaining limits

Cold scans still take roughly 18 seconds on this history. Full JSONL reads,
string processing, parsing and directory traversal remain significant work;
cold-scan event-loop stalls peaked around 290 ms. The new UI appears before
that work and streams adapter groups, but does not make every parsing operation
interruptible. Streaming JSONL parsing or isolating transcript parsing in workers
is the next performance investigation.

The first run after upgrading must refresh the Claude and Pi parsed entries to
apply the title fixes. Their cache namespaces changed intentionally. Comparing
an old warmed cache with a new invalidated cache exaggerates the new build's
startup cost; alternating both builds against one shared cache is also invalid
because they discard each other's parser versions. The comparisons above use
independent caches.

Search was already approximately 5 ms across this history before these changes;
search indexing was left unchanged. File discovery still stats cached files,
OpenCode still opens worker threads for its SQLite queries, and previews are
loaded as part of each adapter rather than lazily for only the selected row.

## Follow-up: fixes, streaming and shared read budget

A second comparison used one immutable macOS/APFS history snapshot for both
builds, separate initially empty caches, and four alternating samples per build
(one cold plus three warmed). This matters because live agent histories keep
changing: reparsing an actively growing large rollout is not a cache-hit sample.
The baseline already includes progressive loading and the initial OpenCode v2
and Poolside support, before the subsequent bug fixes. Raw aggregates are in
[performance-results-followup.json](performance-results-followup.json).

| Measurement | Before fixes | After fixes |
| --- | ---: | ---: |
| Warm median full collection/cache save | 729 ms | 504 ms |
| Warm median peak process RSS | 1,887 MiB | 319 MiB |
| One cold scan | 22.30 s | 20.83 s |
| Cold peak process RSS | 1,706 MiB | 531 MiB |
| Sessions discovered in the frozen cohort | 5,924 | 5,925 |

Warm collection improved about 31%, and cold peak RSS fell about 69%. Cold wall
time changed only modestly and is not presented as an improvement: the corrected
parser now reads rollouts that the previous implementation skipped. Streaming
JSONL, cached parsed metadata, and one shared eight-reader budget bound memory;
active append-only files are still reparsed when their stat changes. Incremental
parsing of growing transcripts remains a possible later optimization.

Developer scripts are now authored as `scripts/Benchmark.res` and
`scripts/SnapshotHistory.res`. Build them with `npm run build`, then run:

```sh
node lib/es6/scripts/SnapshotHistory.mjs /path/to/new-snapshot
HOME=/path/to/new-snapshot RESUME_BENCH_COLD=1 node lib/es6/scripts/Benchmark.mjs /path/to/before /path/to/after 4
```

The snapshot helper requires macOS copy-on-write cloning and refuses an existing
destination. It clones SQLite DB/WAL files while holding a read transaction and
rewrites Kimi's absolute storage references into the snapshot. Snapshot data stays
local and must be removed after use; reports contain aggregates only.
