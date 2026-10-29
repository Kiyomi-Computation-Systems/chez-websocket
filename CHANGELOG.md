# Changelog

All notable changes to chez-websocket are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Pinned at chez-http-server v0.9.1**, from v0.9.0. The pins under it are v0.9.0's:
  chez-libuv v0.11.0, chez-httparse v0.5.0 with byte-machine v0.8.0, and uriparse
  v0.8.0. The pin needs no change to the library's code, and `(http-server)` exports
  what it did.
  - A procedure registered with `request-on-done!` costs the server about 240 B a
    request, from about 725, and the test host leaves a pulled body's failure out of
    its log, as `serve` does. The binding uses neither.
  - An idle WebSocket costs what it did. On Linux x86-64, measured the same hour, it
    held 5,512 to 5,674 B on v0.9.1 and 5,514 to 5,679 B on v0.9.0, and the server's
    own idle connection 2,128 to 2,144 B and 2,140 to 2,144 B.
  - Autobahn|Testsuite's 301 cases keep their verdicts: 291 OK, 7 NON-STRICT and 3
    INFORMATIONAL.

## [0.4.0] - 2026-10-28

`websocket-limits-from-environment` in the facade, for a host that reads its settings
through a lookup of its own.

### Added

- **`websocket-limits-from-environment` is in the facade.** It builds the limits from
  the `CHEZ_WS_` variables a lookup procedure gives, as `environment-websocket-limits`
  is built from `getenv`. A host that reads its settings through a procedure of its
  own, such as circuit's `run-server`, passes that procedure, and hands the limits to
  `websocket-handshake` or `websocket-accept`.

## [0.3.0] - 2026-10-28

`websocket-handshake`, for a host on the server whose requests and responses are its
own, on chez-http-server v0.9.0.

### Added

- **`websocket-handshake`, the handshake for a host of its own.** A host on the server
  whose requests and responses are its own, such as a framework, gives it the request's
  method, a reader of every line of a field, the request's host and your procedure,
  with settings and limits as for `websocket-accept`. It answers one of two:
  - **accepted:** the `101`'s fields as string pairs, read with
    `handshake-accepted-headers`, and the take-over to hand the server's
    `switch-protocols`, `handshake-accepted-take-over`. A host that wraps the take-over
    answers what it answers;
  - **refused:** `handshake-refused-status` and `handshake-refused-headers`, answered
    with no body.

  `handshake-accepted?` and `handshake-refused?` tell them apart. `docs/handlers.md`
  has a section on it.
- **Contributor docs.** `CONTRIBUTING.md` covers setup, the checks CI runs, what to do
  when a change moves a verdict, the server pin, `Akku.manifest`, the Makefile,
  `docs/` or `examples/`, and the rules for code, tests and pull requests. A pull
  request template and bug and feature issue templates follow it, and README.org has
  Contributing and Security sections. The docs suite holds all four files to the
  checkout: each `make` target they run must be one the Makefile documents, and each
  file they name must exist.

### Changed

- **`websocket-accept` is built on `websocket-handshake`.** What it takes and answers is
  unchanged.
- **`(websocket handshake)`'s `handshake-answer` answers its fields as string pairs**,
  not bytevector pairs. The facade doesn't export it and the docs don't name it, but a
  program that imports `(websocket handshake)` itself and hands its fields to the server
  must now turn them into bytes.
- **Pinned at chez-http-server v0.9.0**, from v0.7.0 by way of v0.8.0. The pins under
  it: chez-libuv v0.11.0, as before; chez-httparse v0.5.0 with byte-machine v0.8.0;
  and uriparse v0.8.0. The pin needs no change to the library's code.
  - `(http-server)` exports sixteen more names, among them `request-header-list`,
    `request-has-body?`, `request-on-done!`, `sized-body`, `next-body-piece` and the
    connection's addresses and ports. A program that imports all of `(http-server)`
    beside `(websocket)` and defines one of them itself no longer loads: rename its
    own, or import `(http-server)` with `except`. The binding and the examples
    define none of them.
  - A connection costs about 5.6 KB, from 5.3 KB. On v0.9.0 an idle WebSocket holds
    5,463 to 5,680 B of heap, 5,608 to 5,613 B after 10 echoes, and the server's own
    idle connection 2,079 to 2,246 B. On v0.7.0, measured the same hour, they were
    5,314 to 5,429 B, 5,331 to 5,485 B and 1,808 to 1,977 B: the server's connection
    grew by about 270 B, and a WebSocket's with it.
  - Autobahn|Testsuite's 301 cases keep their verdicts: 291 OK, 7 NON-STRICT and 3
    INFORMATIONAL.
- **Release archives leave out `AGENTS.md`**, as they already left out `.plans/` and
  `.superpowers/`. That holds for `git archive` and GitHub's source tarballs, and
  Akku's scan skips `AGENTS.md` too. v0.2.0's tarball still carries it.

### Fixed

- **The socket suite's let-go check holds on chez-http-server v0.9.0.** It went red in
  4 of 6 runs there with nothing kept. Chez's collector marks some objects of the
  oldest generation in place, and a marked segment's dead objects still count in
  `bytes-allocated`. The check now collects with nothing marked in place. It passed 10
  of 10 runs on v0.9.0 and on v0.7.0, and still fails for a binding that keeps each
  read's bytevector, at 18,816 to 18,992 B.

## [0.2.0] - 2026-10-24

Examples and a published docs site, on chez-http-server v0.7.0. The library's code is
unchanged from 0.1.0 but for its comments.

### Added

- **Examples**, in `examples/`: an echo server, a chat room, and a clock that sends a
  tick each second while it still reads. Each runs with
  `make run PROGRAM=examples/<name>.sps` and serves a page at `/` to try it from a
  browser, and `tests/test-examples.sps` plays each one as a client would.
- **A docs site.** `make site` renders `docs/` through chez-cmark-gfm, pinned by
  `Akku.lock`, into `build/site/`, and `make check-site` fails on a page missing from
  the nav, a broken link or anchor, or a heading GitHub anchors differently. CI runs
  it on every push; the Pages workflow publishes the site on a release tag or by hand,
  at <https://kiyomi-computation-systems.github.io/chez-websocket/>.

### Changed

- **Pinned at chez-http-server v0.7.0**, from v0.5.0 by way of v0.6.0. The pins under
  it: chez-libuv v0.11.0 (still libuv 1.48 or later), chez-httparse v0.4.5 with
  byte-machine v0.7.0, and uriparse v0.6.2.
  - Once the binding closes a connection's stream, the server bounds each write the
    close waits for by its write timeout, `CHEZ_HTTP_WRITE_TIMEOUT` (60 s), and aborts
    the connection past it. The binding arms its close timeout, 10 s by default, as it
    closes, so with the defaults a close ends as before. A close timeout set above the
    server's write timeout can now end sooner for a client that reads nothing.
  - A SIGTERM or SIGINT sent the moment the server logs `listening` drains it.
  - The server's test fake, which the binding and driver suites load, now keeps what a
    client sends while the binding has stopped reading, its end too, until it reads
    again, as the server does. One binding check had a client's end wake a send that
    waited past the high water at once; the server never tells it then. The check now
    holds what the server does: the send goes on once the client reads, the end read
    after it, or the write timeout ends it.
  - Every other check passes as on v0.6.0, and a connection still costs about 5.3 KB.
- **The user docs are Markdown**, ready to build into a static site, and laid out as
  chez-libuv's are. `docs/README.md` is their home. `docs/handlers.md` and
  `docs/configuration.md` replace the `.org` pages, and new pages cover installing,
  how it works, every export (`docs/reference.md`), testing and performance. The docs
  suite reads the Markdown: it runs each Scheme block, named on its fence (`scheme
  name=echo`), and checks the reference's entries against what `(websocket)` exports,
  each link, each `make` target, and that the measured pages give only numbers the
  repository records.

## [0.1.0] - 2026-10-11

The first release: WebSocket (RFC 6455) for
[chez-http-server](https://github.com/Kiyomi-Computation-Systems/chez-http-server), in
Chez Scheme. A handler takes a WebSocket by answering what `websocket-accept` returns,
and its procedure reads each message with a call that waits, sends, and closes. The
rules are pure libraries that import nothing but `(rnrs)` and each other (SHA-1,
base64, UTF-8, the frame codec, the protocol, the handshake and the limits), and a
binding runs them over the server's transport. It is pinned at chez-http-server v0.5.0, which brings chez-libuv
v0.9.0 (libuv 1.48 or later), chez-httparse v0.4.5 with byte-machine v0.7.0, and
uriparse v0.6.2.

### Added

- **`websocket-accept`** checks a client's opening handshake (RFC 6455 §4.2.1). It
  answers `101`, or refuses with `400`: a method other than `GET`, no `Upgrade:
  websocket`, no `Connection: upgrade`, a key that is not sixteen bytes in base64, or a
  version other than 13, answered with `Sec-WebSocket-Version: 13`. Every line of a
  field is read, joined with commas (RFC 9110 §5.3).
- **Origins.** A browser's page from another host is refused `403`, unless the
  handler names that origin or accepts any. A request with no `Origin` is not a
  browser's, and is accepted.
- **Subprotocols.** The first the handler lists that the client offered is chosen, and
  the `101` names it.
- **A handler's own settings and limits.** `make-handshake-settings` names a
  handler's subprotocols and origins, and `make-websocket-limits`, or
  `websocket-limits-with` over `default-websocket-limits` or
  `environment-websocket-limits`, its limits. `websocket-accept` takes both
  (`docs/handlers.org`).
- **Whole messages.** `websocket-receive` waits for the next message and gives a
  string for text or a bytevector for binary, however the client split it into
  frames. `websocket-send!` sends one as a frame. One receive may wait at a time; any
  number of coroutines may send.
- **Limits, each with a default and an environment variable,** the eight `CHEZ_WS_`
  variables, read as the program starts (`docs/configuration.org`). A
  message over the cap, 1 MiB by default, closes with `1009` before its payload is
  held. Text is checked as UTF-8 as it comes, and closes with `1007` at its first bad
  byte. A text that begins with U+FEFF keeps it.
- **Reading on.** While the handler is busy the server reads on, keeping up to 16
  messages or a cap's worth of bytes, then stops reading until the handler receives.
- **The ping clock.** Pings are answered. A client quiet for 20 s is pinged, and one
  that sends no pong in 20 s more is closed with `1011`.
- **The closing handshake** (RFC 6455 §7). `websocket-close!` closes with a code and
  a reason; a client's close is answered with its code. `&websocket-closed` gives the
  code, the reason, and whether a close went each way: `1005` for a close with no
  code, `1006` when none came, neither ever sent. A procedure that returns closes with
  `1000`, one that raises anything but the connection's end with `1011`, logged, and
  the server's shutdown with `1001`. The close half-closes and lingers, so a client
  still sending reads the close frame, not a reset (chez-http-server v0.5.0).
- **A client that does not read.** Past 256 KiB unsent, a send waits and reading
  stops, until the client reads down to 64 KiB. A client past that mark that takes
  longer than the write timeout, 60 s, over a write is cut off, and so is one that has
  not read the server's close within the close timeout, 10 s.
- **No compression and no client.** `permessage-deflate` is declined (RFC 7692 §5).
- **User docs.** `docs/handlers.org` shows a handler taking a WebSocket, reading,
  sending and closing, and what each close means. `docs/configuration.org` lists the
  eight `CHEZ_WS_` variables, their defaults and their least values.
- **The tests hold it to other code's verdicts:** RFC 3174's SHA-1 vectors, RFC 4648's
  base64 vectors, RFC 3629's UTF-8 grammar, RFC 6455's examples and rules, Chrome's
  handshakes, and the values peers computed alike (Python, Node, Perl, OpenSSL, ws).
  [Autobahn|Testsuite](https://github.com/crossbario/autobahn-testsuite)'s fuzzing
  client runs against an echo server built from the library, and a ratchet holds each
  case's verdict, both ways. `make test` runs fifteen suites and 394 checks.

### Measured

Measured 2026-10-11 on an Apple M1 (8 cores), macOS 26 (Darwin 25.6.0, arm64),
against chez-http-server v0.5.0.

- **Autobahn|Testsuite 25.10.1**, its 301 cases without compression (all but 12.x and
  13.x; there is no 11.x), against the echo server at a 16 MiB cap, the largest
  message they send. The echo server ran in a Linux container (Ubuntu 24.04, arm64)
  on Docker Desktop 29.2.1, and Autobahn's amd64 image under emulation, as `make
  autobahn` runs them on macOS. None failed. Two runs: 291 OK, 7 NON-STRICT and 3
  INFORMATIONAL; then 290, 8 and 3, case 3.4 NON-STRICT. Cases 3.4, 4.1.5 and 4.2.5
  are OK or NON-STRICT with how the client's bytes fall into reads, and the ratchet
  lists both.
- **Memory**, on macOS, Chez Scheme 10.4.1 `tarm64osx` and libuv 1.52.1. By the
  server's own method (a python child holds the connections; the heap after two full
  collections; a connection's cost is the heap with 500 less the heap with 100, over
  400), five holds each:

  | an idle connection | heap |
  |---|---|
  | a WebSocket, its procedure waiting in `websocket-receive` after the `101` | 5,281 to 5,435 B |
  | the same, after 10 echoes | 5,353 to 5,477 B |
  | the server's own connection, idle after a GET, for scale | 1,900 to 2,055 B |

[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/releases/tag/v0.1.0
