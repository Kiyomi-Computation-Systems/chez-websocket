# Changelog

All notable changes to chez-websocket are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Examples**, in `examples/`: an echo server with a page for the browser, a chat
  room, and a clock that sends a tick each second while it still reads. Each runs
  with `make run PROGRAM=examples/<name>.sps`, and `tests/test-examples.sps` plays
  each one as a client would.

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

[Unreleased]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kiyomi-Computation-Systems/chez-websocket/releases/tag/v0.1.0
