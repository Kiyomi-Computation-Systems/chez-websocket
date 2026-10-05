# chez-websocket — the design (SDD rung 2)

Date: 2026-10-04
Status: for review. Its three choices were decided by form
([0001](decisions/0001-messages-are-whole-and-capped-at-1-mib-and-the-server-reads-on-and-pings-a-quiet-client.md)).
Brief: [the project brief](2026-10-04-chez-websocket-project-brief.md)
Plan: [the milestone plan](2026-10-04-chez-websocket-milestone-plan.md)

## 1. What it is

A handler of chez-http-server's takes a WebSocket by answering what
`websocket-accept` returns. The library checks the client's opening handshake
(RFC 6455 §4.2.1). It either refuses it with an HTTP response, or answers the server's
door: `(switch-protocols headers take-over)` (server decision 0016). After the 101,
its take-over answers `(awaiting thunk)` (server decision 0023), and the thunk runs
the handler's procedure with a WebSocket, on the coroutine the server gives it. There
the procedure reads with `websocket-receive`, which waits, and writes with
`websocket-send!` and `websocket-close!`.

```scheme
(import (rnrs) (http-server) (websocket))

(serve
 (lambda (request)
   (if (string=? (request-path request) "/echo")
       (websocket-accept request
         (lambda (ws)
           (let loop ()
             (websocket-send! ws (websocket-receive ws))
             (loop))))
       (make-response 404 #f '() (string->utf8 "not found\n")))))
```

The loop ends when the client closes: `websocket-receive` raises `&websocket-closed`,
and a handler that lets it out has ended the connection quietly (§6).

## 2. The libraries

| library | pure? | what |
|---|---|---|
| `(websocket sha1)` | yes | SHA-1 of a bytevector, for the accept value only |
| `(websocket base64)` | yes | RFC 4648 §4 encode, and decode for checking a key |
| `(websocket utf8)` | yes | an incremental UTF-8 checker (RFC 3629 §4), resumable across pieces |
| `(websocket frame)` | yes | the frame codec: an incremental decoder, and the server's encoder (§5.2) |
| `(websocket protocol)` | yes | a connection's state machine: messages, control frames, the closing handshake, the limits, the ping clock |
| `(websocket handshake)` | yes | the opening handshake's check, and the 101's fields (§4.2) |
| `(websocket limits)` | yes | the limits record, and its reading from an environment's strings |
| `(websocket private binding)` | no | the shell: the core over the server's transport, the waits, the environment |
| `(websocket)` | — | the facade a handler imports |

The pure libraries import `(rnrs)` and each other, nothing else. Only the binding
imports `(http-server)`, and only the binding and the tests import `(chezscheme)`.
`make check-imports` holds this from M1, as the server's does.

## 3. The opening handshake (§4.2)

`websocket-accept` reads the request through the server's accessors and checks it
in this order, answering the first failure:

| check (§4.2.1) | refused with |
|---|---|
| the method is `GET` | 400 |
| `Upgrade` lists `websocket`, case-insensitively | 400 |
| `Connection` lists `upgrade`, case-insensitively | 400 |
| `Sec-WebSocket-Version` is `13` | 426, with `Sec-WebSocket-Version: 13` (§4.2.2 /version/) |
| `Sec-WebSocket-Key` is the base64 of 16 bytes | 400 |
| `Origin` is one the handler accepts | 403 (§4.2.2 /origin/; decided in M4) |

- **The server has already refused** what is not HTTP/1.1 and what has a body: an
  upgrade is an HTTP/1.1 request with no body (0016).
- **Accepted, the 101 carries** `Upgrade: websocket` and `Sec-WebSocket-Accept`. That
  is the base64 of the SHA-1 of the key and RFC 6455's GUID (§4.2.2). The server adds
  `Connection: upgrade` itself.
- **Subprotocols.** A handler may name the subprotocols it speaks, in its order of
  preference. The first of them the client offered is chosen and sent back. When
  none matches, none is sent and the handshake still succeeds (§4.2.2 /subprotocol/).
  This is coder's and gorilla's way; `websocket-subprotocol` tells the handler which
  was chosen.
- **`Sec-WebSocket-Extensions` is never answered**, so permessage-deflate is
  declined (RFC 7692 §5; 0022).

## 4. Frames (§5.2)

**The decoder** takes each read's bytes as they come, in pieces of any size. It
resumes where the last piece ended, so a header can straddle two reads. It answers a
frame's header once the header is whole, then its payload as it arrives, unmasked
(§5.3) into the core's buffer. It fails the connection with 1002 on:
- a reserved bit set (RSV1–3): no extension is ever negotiated;
- an unknown opcode (0x3–0x7, 0xB–0xF);
- an unmasked frame (§5.1);
- a length not in its shortest form, or a 64-bit length with its top bit set (§5.2);
- a control frame over 125 bytes, or not final (§5.5).

**The encoder** writes the server's frames unmasked (§5.1), each length in its
shortest form, and each message as one final frame.

## 5. The protocol (§5.4–§5.6, §6, §7)

`ws-step : State Event -> (values State (Listof Action))` is pure by contract, as the
server's `conn-step` is (its decision 0002). It allocates only Scheme data, reads no
clock, and never raises on a well-formed event. The state is linear: a step updates
the state it is given and returns it. Events and actions are tagged lists:

```
events   (bytes bv start end)  (end why)  (send kind payload)  (close code reason)
         (taken nbytes)  (deadline-passed)
actions  (write bv)  (deliver kind payload)  (read-stop)  (read-start)
         (arm-deadline kind)  (disarm-deadline)  (close-stream)
         (closed code reason clean?)  (log what . details)
```

- **Messages are whole** (0001 item 3). A data frame with FIN set is a message. One
  with FIN clear starts a fragmented message, which opcode-0 frames continue until FIN
  (§5.4). A continuation with no message begun, or a new message begun before the
  last has ended, fails 1002.
- **The cap** is 1 MiB by default (0001 item 1). A data frame whose announced length
  would take its message past it fails 1009, before any of its payload is held.
- **Text is checked as UTF-8 as it arrives**, so a bad byte fails 1007 at once
  (§8.1). A message may end only on a whole character.
- **Control frames** may come between a message's fragments (§5.4). A ping is answered
  at once with a pong carrying its payload, unless a close has been received
  (§5.5.2). A pong is noted for the ping clock and otherwise ignored (§5.5.3).
- **Reading on** (0001 item 2). Each delivered message adds its size to the bytes
  queued for the handler, and `(taken nbytes)` takes them off. Once a cap's worth is
  queued, the step answers `read-stop`, and `read-start` once the handler has taken
  one.
- **The ping clock** (0001 item 2). After 20 s with nothing received, the step sends
  a ping. If no pong comes within 20 s, it fails 1011. The clock is stopped while
  reading is, since a pong the server has not read is not the client's fault.
- **The closing handshake.**
  - A close received is answered with a close echoing its code, unless one was sent
    (§5.5.1).
  - Its code must be one an endpoint may send (1000–1003, 1007–1011, 3000–4999). A
    body of one byte, or any other code, fails 1002. A reason that is not UTF-8
    fails 1007 (§8.1), as websockets does.
  - Once a close has gone each way, the server closes the stream at once (§5.5.1,
    §7.1.1).
  - A close sent and not answered within 10 s closes the stream anyway: websockets'
    `close_timeout`.
  - Codes 1005, 1006 and 1015 are never sent (§7.4.1). They are what the handler is
    told when a close carried no code (1005), or when the stream ended without one
    (1006).
- **Failing** (§7.1.7) sends a close with its code, then closes the stream. Nothing
  the client sends after it is read.
- **Time is a deadline's kind.** The step reads no clock. It names the deadline it
  needs by kind: `ping` (quiet), `pong` or `close`. The binding arms it for that
  kind's time, and its passing comes back as `(deadline-passed)`. This is how the
  server's core arms its own (`(arm-deadline kind)`). A connection needs one deadline
  at a time, which is what the transport has. Any bytes received re-arm `ping`.

## 6. The binding (the shell)

The take-over runs in place, inside the server's callbacks, and cannot wait (0016).
It makes the core's state and starts reading. It feeds the core the bytes the server
read past the request (`retained`), and answers `(awaiting thunk)`. Each read's bytes
are stepped through the core in place, and the actions run at once:

| action | performed with |
|---|---|
| `write` | `transport-write!`; its `written` procedure counts what is unsent |
| `deliver` | the message queued for `websocket-receive`, which is resumed if it waits |
| `read-stop`, `read-start` | the transport's verbs |
| `arm-deadline`, `disarm-deadline` | `transport-deadline!`, the transport's one deadline, armed for the kind's time; when it passes, a `deadline-passed` |
| `close-stream` | `transport-close!` |
| `closed` | the WebSocket's end: every receive and send after it raises `&websocket-closed` |

- **`websocket-receive`** answers the oldest queued message and steps `(taken
  nbytes)`, or parks on `await` until one comes.
  - Once the connection has closed, it first answers the messages still queued.
  - After that it raises `&websocket-closed`, with the code, the reason and whether
    the close was clean. It raises again on every later call.
  - This follows the server's `&client-closed`, and the direct-style peers, whose
    read raises or returns an error once closed.
- **`websocket-send!`** steps a `send` and writes its frame. While more than 256 KiB
  is unsent, it parks until `written` brings that under 64 KiB. These are the server's
  own stream water marks (`CHEZ_HTTP_WRITE_HIGH_WATER`, `_LOW_WATER`).
- **`websocket-close!`** steps a `close` (1000 by default) and returns; the handshake
  finishes on its own.
- **The stream's close.** When the stream closes, whoever closed it, the wait the
  thunk is in raises `&client-closed` (0023). The binding turns that into the
  connection's end: 1006, unless the closing handshake had finished.
- **The server's drain.** On `transport-on-drain!`, the binding starts a closing
  handshake with 1001, "going away" (§7.4.1).
- **The procedure's end.**
  - If it returns, the binding closes with 1000.
  - If it lets `&websocket-closed` out, nothing more is done or logged.
  - Any other raise closes with 1011, and is logged, as the server logs
    `taker-failed`.

## 7. Configuration

Each default has an environment variable (12-factor, as the server's `CHEZ_HTTP_`
variables). They are read once, as the program starts, so a malformed value stops it
there. A handler may give `websocket-accept` limits of its own.

| variable | default | what | source |
|---|---|---|---|
| `CHEZ_WS_MAX_MESSAGE_BYTES` | 1048576 | the largest message; past it, 1009 | 0001; websockets |
| `CHEZ_WS_PING_INTERVAL` | 20 s | quiet time before a ping; 0 turns pinging off | 0001; websockets |
| `CHEZ_WS_PING_TIMEOUT` | 20 s | time for the pong; past it, 1011 | 0001; websockets |
| `CHEZ_WS_CLOSE_TIMEOUT` | 10 s | time for the client's close, after the server's | websockets' `close_timeout` |
| `CHEZ_WS_WRITE_HIGH_WATER` | 262144 | bytes unsent before a send waits | the server's own |
| `CHEZ_WS_WRITE_LOW_WATER` | 65536 | bytes unsent when it goes on again | the server's own |

Durations are in seconds, as the server's are.

## 8. Testing

- **The pure core** is held to vectors from its sources:
  - RFC 3174's SHA-1 test vectors, and RFC 6455 §4.2.2's digest of its example key;
  - RFC 4648 §10's base64 vectors;
  - RFC 3629 §4's grammar for UTF-8;
  - RFC 6455 §5.7's example frames.

  Autobahn's cases become core tests where they need no socket, read as byte
  scripts. Time is the `deadline-passed` events a test steps, so no test waits.
- **The binding** runs against a transport made of procedures (`make-transport`, as
  the door suite does). Its waits need a coroutine, which only the server's shell
  runs. M4 chooses between the server's fake shell (its `tests/`, put on the test
  library path) and a door change in the server.
- **A real socket.** One suite runs a server on `127.0.0.1:0` with a client on the
  same loop, capped by iteration count.
- **Autobahn|Testsuite** runs in Linux CI (M5): its fuzzing client against an echo
  server built from this library, 301 cases, the image pinned by digest. A ratchet
  holds each case's result (0022).

## 9. Open, and decided later

- **`Origin`** (M4, as 0022 says): what a handler states, and whether to check by
  default. coder and gorilla require the Origin's host to equal the request's Host;
  websockets, tungstenite and ws check nothing (the survey).
- **The binding's test driver** (M4, §8).
- **What a connection costs:** measured in M4, beside the server's 20 KB for an idle
  connection and 3,637 to 3,644 B for a parked `await`.
