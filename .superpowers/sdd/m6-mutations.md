# M6 — mutation log

Every check in M6 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M6.1 — the user docs

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-11. The pages are `docs/configuration.org` (blob 523b7b7) and
`docs/handlers.org` (blob 898156f); the suite `tests/test-docs.sps`, 6 checks
(blob 145c284). The server is pinned at v0.5.0 (02ef95d).

The runner (scratch `m6mut/`): each mutant alone, one edit to the tree, the suite
run, the checks that went red and its status compared with those named before the
run, the file put back. A pre-flight checks that each cut matches its text once,
or at least once for a mutant that replaces every occurrence.

### The checks

| ID | check |
|---|---|
| DOC-VARS | configuration.org's table names the variables (websocket limits) reads, in its order |
| DOC-DEFAULTS | its defaults, read as the environment, are the library's, each in its variable's unit |
| DOC-NAMES | every name of the library's that docs/ writes is one (websocket) exports |
| DOC-READ | every Scheme block in docs/ reads as Scheme |
| DOC-ECHO | handlers.org's first program, on the fake shell: RFC 6455's handshake to /echo answered 101 with §1.3's accept, a masked Hello echoed as §5.7's frame, the client's close 1000 answered 1000 |
| DOC-404 | the same program answers any other path 404 |

Provenance (status 3): the suite's frames are §5.7's; the pages name
`websocket-accept`, `websocket-receive`, `websocket-send!` and `websocket-close!`,
so a scan that finds nothing cannot pass; handlers.org holds a program.

### The oracles

- **(websocket limits)**: `websocket-limits-environment-variables`, in its order, and
  `default-websocket-limits`, which the limits suite holds to the design's §7.
- **(websocket)**: what it exports.
- **RFC 6455**: §1.3's handshake and accept, §5.7's frames, §5.5.1's echoed close code.
- **handlers.org's own words**: /echo is echoed, anything else gets 404.

### The test-first runs

- **Before the pages:** the suite stopped at its first read, `open-file-input-port`
  on `docs/configuration.org`, "No such file or directory", status 2, as named.
- **On the first pages:** 5 of 6. DOC-ECHO read `#vu8(136 2 3 232)`, the close alone,
  where the echo was named. The stimulus was mine: the Hello and the client's close
  came in one read, so the binding answered the close before the procedure ran, and
  a send while the server's close is under way sends nothing (design §6, as
  websockets does). The close now comes in a read of its own. 6 of 6.

### The mutants

Run 1, predictions hashed before it (sha256 `79222c6d`): 16 mutants and the
baseline, **2 mismatches**.
- **M6-15**, the runner's: the mutant replaces every `websocket-close!`, and the
  pre-flight asked for one. The runner now takes a mutant that replaces all.
- **M6-11**, the suite's and mine. With `(websocket)` gone from the program's
  imports, the suite ended in a harness error, status 2, with 4 passes. Chez
  refuses an unbound identifier as the program is evaluated, and the program was
  loaded outside any check. I had predicted DOC-ECHO alone, expecting the refusal
  only when the handler ran. **Fixed:** `played` loads and plays the program inside
  each check, and a raise answers `(raised message)` in the check's place. M6-11's
  prediction became DOC-ECHO and DOC-404, before run 2.

Run 2, on the fixed suite, predictions hashed before it (sha256 `df2d5e0a`):
**0 mismatches**. Run 3, on the blobs above: **0 mismatches**. Run 4, the same blobs
rebased onto main's 270ce0e (#72): **0 mismatches**.

| ID | mutation | named red | status | result |
|---|---|---|---|---|
| BASE | none | none | 0 | as named |
| M6-1 | `CHEZ_WS_PING_INTERVAL`'s default 20 s → 30 s | DOC-DEFAULTS | 1 | as named |
| M6-2 | `CHEZ_WS_WRITE_TIMEOUT`'s row removed | DOC-VARS | 1 | as named |
| M6-3 | the two waters' rows swapped | DOC-VARS | 1 | as named |
| M6-4 | the close timeout written 10000 ms | DOC-DEFAULTS | 1 | as named |
| M6-5 | `CHEZ_WS_MAX_QUEUE` written `CHEZ_WS_MAX_QUE` | DOC-VARS | 1 | as named |
| M6-6 | `websocket-send!` written `websocket-send` in the table | DOC-NAMES | 1 | as named |
| M6-7 | the guard example's last paren dropped | DOC-READ | 1 | as named |
| M6-8 | the echo sends the message with `"!"` after it | DOC-ECHO | 1 | as named |
| M6-9 | the echo's path `/echo` → `/chat` | DOC-ECHO | 1 | as named |
| M6-10 | the example's 404 → 400 | DOC-404 | 1 | as named |
| M6-11 | the program's import of `(websocket)` dropped | DOC-ECHO, DOC-404 | 1 | as named (run 2) |
| M6-12 | the library's default ping interval 20000 → 30000 ms | DOC-DEFAULTS | 1 | as named |
| M6-13 | the facade's export of `websocket-subprotocol` dropped | DOC-NAMES | 1 | as named |
| M6-14 | the handshake table's 403 → 401 | none | 0 | as named, survived |
| M6-15 | every `websocket-close!` in handlers.org → `websocket-shut!` | none | 3 | as named (run 2) |
| M6-16 | the table's header `Variable` → `Name` | DOC-VARS | 1 | as named |

Every check has a killer by value:
- **DOC-VARS** by M6-2, the list without `CHEZ_WS_WRITE_TIMEOUT`; M6-3 with the waters
  swapped; M6-5 with `CHEZ_WS_MAX_QUE`; M6-16, `()`.
- **DOC-DEFAULTS** by M6-1, `30000` in the ping interval's place; M6-4, `10000000` in
  the close timeout's; M6-12, the library's `30000` against the page's `20000`.
- **DOC-NAMES** by M6-6, `("websocket-send")`, and M6-13, `("websocket-subprotocol")`.
- **DOC-READ** by M6-7, `(unread …)` for the guard example, the other three `read`.
- **DOC-ECHO** by M6-8, `#vu8(129 6 … 33 …)`, the Hello with `!`; M6-9,
  `((unread need-input) #f …)`, the 404's head; M6-11, `(raised "attempt to reference
  unbound identifier")`.
- **DOC-404** by M6-10, `400`, and M6-11.
- **M6-15**: `PROVENANCE-ERROR docs: the pages' names were not found: the scan reads
  nothing`, status 3.

**The survivor, a scope statement.** M6-14: the suite holds the variables, the
names, the blocks and the first program, not the pages' prose or their tables of
statuses and codes. Those are the handshake's and the protocol's, held to the RFC by
their own suites; a page that misstates one is not seen here.

### On Linux

`chez-libuv-noble-scratch:10.4.1` (Linux 6.12.76-linuxkit aarch64, dash, libuv
1.48.0), every suite run as `make test` runs it, the pins checked on the host:
fifteen suites, 392 expected passes on the rebased tree, each suite's count Darwin's. The image names
Chez `scheme`, so `chez` was a wrapper script in the container: a link named `chez`
looks for `chez.boot`.

## M6's review

Platform as above, 2026-10-11. `/code-review` (xhigh) over #73 and #74 reported 14
findings, and the owner said "fix all". The suite is now 8 checks (blob a93876e); the
pages are `docs/handlers.org` (blob 244cd05) and `docs/configuration.org` (blob
6bb2cd9).

### What changed in the suite

| ID | now |
|---|---|
| DOC-DEFAULTS | a cell reads only as digits then ` s` for a duration, digits alone for a size or a count, the units the design's §7 names; anything else is `(unreadable row)` |
| DOC-NAMES | also `websocket?`, `&websocket-…` (asked for its record type, being syntax) and `handshake-settings…` |
| DOC-FIELDS | new: the fields handlers.org lists are the design's §7's, in order, each one `websocket-limits-with` takes |
| DOC-READ | `#+begin_src` and `#+end_src` in any case; a block never ended is `(unterminated text)` |
| DOC-ECHO, DOC-404 | the program's forms run as a top-level program's (R6RS §8.1), definitions and expressions in any order |
| DOC-FRAGMENTS | new: every other block runs where its words put it, in a handler when it names `request`, else in a WebSocket's procedure; the names it takes from around it (`request`, `ws`, `settings`, `chat`, `upload`) the suite gives |

And: the suite refuses to run with a `CHEZ_WS_` variable set, as the binding suite does;
rows of no cells, and a row with no last bar, are read; lines are `(ws-autobahn)`'s
`text-lines`, a CR before a LF dropped; `concat` and `copy` come from `(ws-play)`.

### The mutants

Predictions hashed before the run (sha256 `4c9189fc`): M6-1 to M6-16 named again for the
new suite, and M6-17 to M6-34 new. **0 mismatches.**

| ID | mutation | named red | status | result |
|---|---|---|---|---|
| BASE | none | none | 0 | as named |
| M6-1 to M6-16 | as above | as above | as above | as named, each |
| M6-17 | the ping interval's default written `off` | DOC-DEFAULTS | 1 | as named |
| M6-18 | written `20 ms` | DOC-DEFAULTS | 1 | as named |
| M6-19 | the queue's written `16 s` | DOC-DEFAULTS | 1 | as named |
| M6-20 | every `&websocket-closed` in handlers.org → `&websocket-shut` | DOC-NAMES | 1 | as named |
| M6-21 | the facade's export of `&websocket-closed` dropped | DOC-NAMES | 1 | as named |
| M6-22 | the field `max-queue` written `max-queued` | DOC-FIELDS | 1 | as named |
| M6-23 | `write-timeout-ms` left out of the fields | DOC-FIELDS | 1 | as named |
| M6-24 | the settings fragment's subprotocol `chat v2` | DOC-FRAGMENTS | 1 | as named |
| M6-25 | the limits fragment's field `max-message-byte` | DOC-FRAGMENTS | 1 | as named |
| M6-26 | the guard fragment displays the reason | DOC-FRAGMENTS | 1 | as named |
| M6-27 | the guard fragment names `websocket-close-code` | DOC-NAMES, DOC-FRAGMENTS | 1 | as named |
| M6-28 | the guard block's markers upper case, a paren dropped | DOC-READ | 1 | as named |
| M6-29 | the last block's `#+end_src` removed | DOC-READ | 1 | as named |
| M6-30 | `(define greeting "hi")` after the program's `serve` | none | 0 | as named |
| M6-31 | the queue's row with no third cell and no last bar | none | 0 | as named |
| M6-32 | a bare `\|` line in the table | none | 0 | as named |
| M6-33 | `CHEZ_WS_MAX_QUEUE=3` set | none | 2 | as named |
| M6-34 | the guard fragment's echo with `!` after | DOC-FRAGMENTS | 1 | as named |

By value:
- **DOC-DEFAULTS**: M6-17 `((unreadable ("CHEZ_WS_PING_INTERVAL" "off" …)))`, M6-18 with
  `"20 ms"`, M6-19 with `"16 s"`.
- **DOC-NAMES**: M6-20 `("&websocket-shut")`, M6-21 `("&websocket-closed")`, M6-27
  `("websocket-close-code")`.
- **DOC-FIELDS**: M6-22 `(max-message-bytes (not-a-field max-queued) …)`, M6-23 the list
  without `write-timeout-ms`.
- **DOC-READ**: M6-28 `(unread "(guard …")` for the upper-case block, M6-29
  `(unterminated "(define upload-limits …")`.
- **DOC-FRAGMENTS**, in the fragments' order (the guard's, the settings', the limits'):
  M6-24 `(… 500 101)`, M6-25 `(… 101 500)`, M6-26 the guard's output `""` for `"1000"`,
  M6-27 `((raised "attempt to reference unbound identifier") "")`, M6-34 the echo
  `#vu8(129 6 … 33 …)`.
- **M6-33**: `HARNESS-ERROR docs: … a CHEZ_WS_ variable is set; make test unsets them
  ("CHEZ_WS_MAX_QUEUE")`, status 2.

### Against #73's suite

Each new mutant run on #73's suite, on the review's pages, predictions hashed before
(sha256 `0f94940a`), to show what each fix catches that it did not. The first run was
void, my setup's: `(ws-play)` now exports `concat` and `copy`, which #73's suite defined
itself, so it could not load. With those two definitions taken out of the scratch copy,
the same helpers now imported: **0 mismatches**.
- **Passed there, red here** (the holes): M6-17 to M6-26, M6-28, M6-29, M6-33 (status 0)
  and M6-34. M6-27 was red there by DOC-NAMES alone.
- **Red there, green here** (the false reds): M6-30 by DOC-ECHO and DOC-404, the
  program's lambda refused; M6-31 by DOC-DEFAULTS, the row's default cell dropped; M6-32
  by DOC-VARS and DOC-DEFAULTS, a row of no cells.

### The pages, before their fixes

The new suite on #74's pages, before the closing bullet and the limits example changed:
8 of 8, as named. Their old code was valid, only made at every request.

## M6's second review

Platform as above, 2026-10-11. A second `/code-review` (xhigh) over #75 reported 12
findings; the owner said "fix the ones that matter", the five that were. The suite is 8
checks (blob 6d2cff6); the pages `docs/handlers.org` (blob a96762e) and
`docs/configuration.org` (blob 9da52e9).

### What changed

DOC-FRAGMENTS no longer guesses a fragment's role from the word `request`, nor holds every
other fragment to one fragment's echo. Each fragment carries an org `#+name:`, and the
suite's `fragment-plays` knows each by it: where it runs, how it is played, and what that
must give, from the page's words about it. Compared by name: a known fragment the page
lost is `(missing)`, a fragment the suite does not know `(unknown name)`.

| fragment | runs in | played with | must give |
|---|---|---|---|
| `closed-code` | a WebSocket's procedure | a masked Hello, then the client's close 1000 | the echo, and `1000` displayed |
| `chat-settings` | a handler | an offer of `chat.v1, chat.v2` from `https://app.example.com`; then a page from `https://elsewhere.example` | `(101 "chat.v2")`; `(403 #f)` |
| `upload-limits` | a handler | a frame announcing 2,000,000 bytes, its header alone | the 101, and nothing after it: no 1009 |

The limits fragment makes settings of its own, where it borrowed the chat example's.

### The mutants

Predictions hashed before the run (sha256 `ffda1147`): M6-1 to M6-34 named again, and
M6-35 to M6-42 new. **0 mismatches.** M6-7, M6-28 and M6-29, each a fragment made
unreadable or unterminated, now also redden DOC-FRAGMENTS: the page lost a fragment the
suite knows. The others are named as before.

| ID | mutation | named red | status | result |
|---|---|---|---|---|
| M6-35 | the chat example drops its settings | DOC-FRAGMENTS | 1 | as named |
| M6-36 | the chat example's preference order swapped | DOC-FRAGMENTS | 1 | as named |
| M6-37 | the limits example drops its limits | DOC-FRAGMENTS | 1 | as named |
| M6-38 | the chat example's origins lose the app's | DOC-FRAGMENTS | 1 | as named |
| M6-39 | `closed-code`'s `#+name` removed | DOC-FRAGMENTS | 1 | as named |
| M6-40 | `chat-settings` named `chat-setting` | DOC-FRAGMENTS | 1 | as named |
| M6-41 | the chat example's origins `'any` | DOC-FRAGMENTS | 1 | as named |
| M6-42 | the upload cap 1 MiB | DOC-FRAGMENTS | 1 | as named |

By value, `chat-settings`' and `upload-limits`' entries:
- M6-35 and M6-38: `((403 #f) (403 #f))`, the app's page refused.
- M6-36: `((101 "chat.v1") (403 #f))`.
- M6-41: `((101 "chat.v2") (101 #f))`, the other site's page taken.
- M6-37 and M6-42: `(101 … #vu8(136 2 3 241))`, a close of 1009.
- M6-39: `("closed-code" (missing))` and `(unknown #f)`; M6-40: `("chat-settings" (missing))`
  and `(unknown "chat-setting")`.

**On the first review's suite** (fix/m6-review's head, 36978d5), the same eight on this
round's pages, predictions hashed before (sha256 `b8faec1e`): each passed, status 0, as
named. Its handler fragments answered 101 whatever their settings or limits, and it read
no names.

## The second review's rest (2026-10-16)

Darwin 25.6.0 arm64, Chez 10.4.1, on main's 6caf10b, the server at v0.6.0. The six
findings M6's second review left (the ledger said seven): its items 7 to 12. The suite is
8 checks (blob 05d650c).

### What changed

| item | finding | the change |
|---|---|---|
| 7 | a block's lines read with spaces trimmed only, `#+begin_src scheme` with one space | a directive is read as org reads it: its words, any spaces or tabs around and between them, in any case |
| 8 | `(ws-play)` exports the generic `copy` and `concat` | `bv-slice` and `bv-concat`, beside `b` and `bv`; its header says so |
| 9 | the docs suite imports `(ws-autobahn)` for `text-lines` alone | `text-lines` and the `split` under it are `(ws-text)`'s, a library of `(rnrs)` alone, which the gate and the suites import |
| 10 | `field?` tells a field by the refusal's `condition-who` | `field-set`: a name is a field when `websocket-limits-with` takes it, set to 100,000, and changes that field alone. A provenance guard holds the value to no default's |
| 11 | each page split into blocks up to three times, each block read up to six | split once; each block read once, its data kept in its record |
| 12 | DOC-NAMES evaluates names in `(rnrs)` and `(websocket)` | the names `library-exports` lists for `(websocket)`, as the check's title says |

Item 12 changes no answer today. `(rnrs)` exports no name the suite's prefixes match,
measured by `library-exports` the same day, so no page could tell the two apart. DOC-NAMES's
mutants (M6-6, M6-13, M6-20, M6-21, M6-27) are red as before.

### The mutants

Predictions hashed before the runs, on main's suite and on the fixed one (sha256
`1f95e61f`; the guard's, `5d0fa848`). **0 mismatches**, both ways.

| ID | mutation | main's suite | the fixed suite |
|---|---|---|---|
| DR-1 | a tab-indented block that does not read, appended to configuration.org | none, 0 | DOC-READ, 1 |
| DR-2 | the same written `#+begin_src  scheme`, two spaces | none, 0 | DOC-READ, 1 |
| DR-3 | the same written `#+begin_src` and `scheme` a tab apart | none, 0 | DOC-READ, 1 |
| DR-4 | `closed-code`'s `#+end_src` indented with a tab | DOC-READ, DOC-FRAGMENTS, 1 | none, 0 |
| DR-5 | `closed-code`'s `#+name:` and its name a tab apart | DOC-FRAGMENTS, 1 | none, 0 |
| DF-1 | the library renames `max-queue`, its refusal naming another who | none, 0 | DOC-FIELDS, 1 |
| DF-2 | the library's `ping-interval-ms` and `ping-timeout-ms` names swapped | none, 0 | DOC-FIELDS, 1 |
| DP-1 | the suite's `set-to` 16, the queue's default | | none, 3 |

By value, on the fixed suite:
- DR-1: `((unread "\t(websocket-accept request\n") read read read read)`. DR-2 and DR-3 alike.
- DF-1: `(max-message-bytes (not-a-field max-queue) ping-interval-ms …)`.
- DF-2: `(… (sets ping-interval-ms (ping-timeout-ms)) (sets ping-timeout-ms (ping-interval-ms)) …)`.
- DP-1: `PROVENANCE-ERROR docs: the value the fields are set to is a default`.

On main's suite, DR-4 and DR-5 were red where org reads the page as it is: the tab-indented
end was not an end, so `closed-code` ran on into `chat-settings`, and the name kept its tab.

**M6-1 to M6-42 again,** on the fixed suite, the runner rebuilt from the session's record
(its mutants' sha256 `ffda1147`, as recorded): BASE and all 42 as named, 0 mismatches. On
main's suite the same, before any change.
