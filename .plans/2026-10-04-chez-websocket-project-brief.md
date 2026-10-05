# chez-websocket: WebSocket (RFC 6455) for chez-http-server — project brief

Date: 2026-10-04
Status: the planning record. The design and the milestone plan come next, each with
its decisions by form.

## Goal

A server-side WebSocket library for Chez Scheme, over chez-http-server's door. A
handler takes a client's WebSocket handshake. Its code then reads each message with a
call that waits, sends messages and closes, as RFC 6455 asks, on the server's own
loop and thread. It is built test-first, and Autobahn|Testsuite holds it to the RFC
in CI.

## What is settled (2026-10-04)

The owner decided these in chez-http-server, by form, on asking to "begin the
websocket path" (that repository's decision
[0022](https://github.com/Kiyomi-Computation-Systems/chez-http-server/blob/v0.3.0/.plans/decisions/0022-websocket-is-a-sibling-library-chez-websocket-rfc-6455-only-its-code-can-wait-and-autobahn-gates-it.md)):

1. **A sibling library of its own**, this repository: private, BSD 3-Clause, on
   `main`. It holds a pure protocol core and a binding over the server's transport,
   and it pins chez-http-server at a release tag.
2. **Its code can wait.** A WebSocket handler reads with a call that waits for the
   next message, as Python's websockets, Go's coder/websocket and gorilla/websocket,
   and Rust's tungstenite read.
3. **v1 is RFC 6455 alone.** permessage-deflate is declined, as RFC 7692 §5 allows,
   and there is no client.
4. **Autobahn gates it**, in Linux CI. Its image is pinned by digest, and a ratchet
   holds each case's result: 301 cases without compression.

The server's part is done. Its door
([0016](https://github.com/Kiyomi-Computation-Systems/chez-http-server/blob/v0.3.0/.plans/decisions/0016-an-upgrade-is-taken-by-answering-switch-protocols-and-handed-over-as-a-transport-the-server-keeps.md))
lets a handler answer `(switch-protocols headers take-over)`. The server writes the
101, then calls `take-over` with the stream, as a transport of seven verbs, and the
bytes it read past the request. Since
[0023](https://github.com/Kiyomi-Computation-Systems/chez-http-server/blob/v0.3.0/.plans/decisions/0023-a-take-over-may-answer-awaiting-its-thunk-runs-on-a-coroutine-and-its-waits-are-told-when-the-stream-closes.md),
a take-over may answer `(awaiting thunk)`. Its thunk runs on a coroutine, where it
can `await`. Once the stream has closed, the wait it is in, or else its next,
raises `&client-closed`. Server v0.3.0, tagged 2026-10-04 on 5528fa4, is the first
release with both.

## Where it stops

- **No HTTP.** The server parses the request and writes the 101. This library checks
  the handshake's fields, chooses what the 101 says, and from then on speaks frames
  over the transport.
- **No TLS.** The owner deploys behind Caddy, which terminates TLS and passes
  WebSocket upgrades through to plaintext HTTP/1.1.
- **No compression, no client, no WebSocket over HTTP/2** (RFC 8441), in v1.

## The shape: a pure core and a binding

- **The core is pure**: bytes in, actions out. It covers the handshake's check, the
  frame codec, and the protocol: fragments, control frames, the close handshake,
  UTF-8 and the limits. It imports `(rnrs)` and its own pure libraries, so every
  rule of the RFC is tested without a socket.
- **The binding is the shell.** It feeds the transport's reads to the core, and
  turns the core's actions into writes, closes and deadlines. A handler's code
  reads by parking on `await`, on the coroutine the take-over's `awaiting` thunk
  runs on.

## What it starts from

Read 2026-10-04 and recorded with sources in the server's 0022:
- **RFC 6455.**
  - The server checks the handshake (§4.2.1) and answers `Sec-WebSocket-Accept`:
    the base64 of the SHA-1 of the key and a GUID (§4.2.2). Its example key
    `dGhlIHNhbXBsZSBub25jZQ==` gives `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`.
  - A client's frames MUST be masked (§5.1), and a length MUST use its shortest
    encoding (§5.2).
  - Control frames carry at most 125 bytes and are never fragmented (§5.5).
  - A close is answered with a close (§5.5.1), and the server closes TCP first
    (§7.1.1). Codes 1005, 1006 and 1015 are never sent (§7.4.1).
  - Text MUST be valid UTF-8, and the connection fails with 1007 if not (§5.6,
    §8.1).
  - Limits SHOULD be capped (§10.4). A server meant for particular sites SHOULD
    check `Origin`, answering 403 (§10.2).
- **Peers.** Four of five read with a call that waits; Node's ws delivers to a
  callback. Default message caps run from 32 KiB (coder) to none (gorilla). Only
  coder and gorilla check `Origin` by default.
- **The server.** An idle connection holds about 20 KB (its CHANGELOG's `[0.1.0]`),
  and a parked `await` 3,637 to 3,644 B (its design §5.2).
- **Neither SHA-1 nor base64** exists in the server or its dependencies, so this
  library writes both.

## Milestones

The milestone plan will set the slices. In outline:
- **M0, the skeleton:** the pin, the Makefile, Linux CI and a first suite.
- **M1, the primitives:** SHA-1, base64 and a UTF-8 checker, pure, held to FIPS 180's
  and RFC 4648's vectors and RFC 3629 §4's byte-sequence grammar.
- **M2, the frame codec**, pure.
- **M3, the protocol**: the pure state machine.
- **M4, the handshake and the binding.** `Origin` is decided then (0022). This is
  where the library first runs on the server.
- **M5, the Autobahn lane.** Pulling its image needs the owner's word.
- **M6, v0.1.0.**

## Standing risks

- **The door may lack something.** For example, a taker's waiting thunk is run by
  the server's shell, and `await` refuses outside a coroutine. So the binding's
  tests may need a way to run one without a socket. Anything the door lacks goes
  back to chez-http-server as a slice of its own (its plan §15).
- **Autobahn's image is linux/amd64 only.** It runs natively on CI's runners; on
  the arm64 development machine it needs emulation.
- **CI reads five private repositories**: chez-http-server, chez-libuv,
  chez-httparse, uriparse and byte-machine. The owner's read token must reach
  them all, as the Actions secret `SUBMODULES_READ_TOKEN` here.
