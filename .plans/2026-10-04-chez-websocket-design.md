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
| `Sec-WebSocket-Version` is `13` | 400, with `Sec-WebSocket-Version: 13` (§4.4; 0003) |
| `Sec-WebSocket-Key` is the base64 of 16 bytes | 400 |
| `Origin` is one the handler accepts | 403 (§4.2.2 /origin/; 0003) |

- **The checks are a pure library's, `(websocket handshake)` (M4.1).**
  - It is given the method, a reader of the request's fields and the request's host,
    as the server's `request-method`, `request-header` and `request-host` read them,
    and the handler's settings.
  - **A handler's settings**, its subprotocols and its origins, are made once with
    `make-handshake-settings`, and checked there. So a bad name stops the program
    where the settings are made, not at the first client. They keep copies of what
    they were made with (M4.1's review).
  - It answers either the 101's fields and the subprotocol chosen, or a refusal: its
    status, its fields, and the check that failed. Each answer's bytevectors and
    strings are its own (M4.1's review).
  - A refusal has no body, as the server's own refusals have none.
- **A wrong version is refused 400, not 426** (0003, by form, "400 with 13"). RFC 9110
  has a 426 carry `Upgrade`, and a sender of `Upgrade` put `upgrade` in `Connection`.
  The server lets no response but a 101 say that, and no peer answers a version with
  426.
- **The server has already refused** what is not HTTP/1.1 and what has a body: an
  upgrade is an HTTP/1.1 request with no body (0016).
- **A key's last digit may set bits past its data**, as RFC 6455 §4.1's own example
  does (its erratum 3150). Such a key is accepted, as four of five peers accept it
  (M1.2's mutation log).
- **Accepted, the 101 carries** `Upgrade: websocket` and `Sec-WebSocket-Accept`. That
  is the base64 of the SHA-1 of the key and RFC 6455's GUID (§4.2.2). The server adds
  `Connection: upgrade` itself.
- **Subprotocols.** A handler may name the subprotocols it speaks, in its order of
  preference. The first of them the client offered is chosen and sent back. When
  none matches, none is sent and the handshake still succeeds (§4.2.2 /subprotocol/).
  This is coder's and gorilla's way; `websocket-subprotocol` tells the handler which
  was chosen. As built in M4.1:
  - each name must be a token (RFC 6455 §4.1), or making the settings refuses it as
    the caller's mistake;
  - an offer is matched exactly, as a whole element of the client's list, as
    websockets and gorilla match it (coder ignores case).
- **Origin** (0003, by form, "Same host"; amended in M4.1's review on the owner's
  word).
  - A handler names `any`, or a list of origins, compared without regard to ASCII
    case, that may hold `same-host`: an Origin whose host and port, past its
    scheme's `://`, are the request's host.
  - **The scheme, when a proxy names it.** The request's `X-Forwarded-Proto` may name
    `http` or `https`: the scheme its client used, as Caddy writes it and no browser
    can. Then `same-host` also needs the Origin's scheme to be that one. Any other
    value, or none, is not compared, as coder and gorilla compare no scheme (0003's
    amendment).
  - A handler that names none gets `same-host`, coder's and gorilla's way.
  - A request with no `Origin` is accepted whatever the handler names. It is not a
    browser's, and a client that is not a browser may send any `Origin` it likes.
  - **An empty `Origin` is no origin** (RFC 6454 §7.1): it names no host, so
    `same-host` refuses it, as gorilla does; coder takes it as none. Taken without a
    form in M4.1's review, keeping what M4.1 built.
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
  would take its message past it fails 1009, before any of its payload is held. A
  message's buffer grows as its bytes arrive, never with what a header announces,
  so what a client makes the server hold follows what it sends.
- **Text is checked as UTF-8 as it arrives**, so a bad byte fails 1007 at once
  (§8.1). A message may end only on a whole character.
- **Control frames** may come between a message's fragments (§5.4). A ping is answered
  at once with a pong carrying its payload, unless a close has been received
  (§5.5.2). A pong is noted for the ping clock and otherwise ignored (§5.5.3).
- **Reading on** (0001 item 2, and its amendment of 2026-10-05). Each delivered
  message is queued for the handler, and `(taken nbytes)` takes one off. Once the
  queue holds a cap's worth of bytes, or 16 messages, the step answers `read-stop`
  and reads no further: the rest of the read waits, kept, since the transport
  hands a taker each read's bytevector to keep. A take that brings the queue under
  both reads what waits, a message at a time as the queue makes room, then answers
  `read-start`. A read while reading is stopped is the caller's mistake.
- **The ping clock** (0001 item 2, and its amendment of 2026-10-06). After 20 s with
  nothing received, the step sends a ping. If nothing comes within 20 s, it fails
  1011. The clock is stopped while reading is, since a pong the server has not read
  is not the client's fault.
  As built in M3.3, and its review:
  - The ping carries no payload: two bytes.
  - Any bytes received re-arm `ping`, after the read's own actions, while the pong is
    awaited too (by form, "Any bytes"). websockets waits for the pong alone, but it
    pings every 20 s, busy or not. A read of no bytes re-arms nothing.
  - When `pong` passes, the close written is 1011 with no reason, as every failure's
    is, and `ping-timeout` is logged. websockets writes "keepalive ping timeout".
  - The pong's 20 s start when the ping is queued, not when it is written (§9).
  - When reading stops, nothing is armed, until a take starts reading again and the
    clock afresh at `ping`, though a ping was out when it stopped.
  - The server's close takes the one deadline for its own, and the clock does not run
    again.
  - An interval of 0 turns it off.
  - Re-arming allocates nothing: a step's actions are reversed onto a constant tail,
    so a read costs the same with pinging on as off.
- **The closing handshake.**
  - A close received is answered with a close echoing its code, unless one was sent
    (§5.5.1).
  - Its code must be one an endpoint may send (1000–1003, 1007–1011, 3000–4999). A
    body of one byte, or any other code, fails 1002. A reason that is not UTF-8
    fails 1007 (§8.1), as websockets does.
  - Once a close has gone each way, the server closes the stream at once (§5.5.1,
    §7.1.1).
  - After the server's close, reading goes on as before: a message that comes is
    delivered, and a ping is answered, since no close has been received (§5.5.2).
    This is websockets' way, decided by form (0001's second amendment). A full
    queue nobody takes from leaves the client's close unread until the close
    timeout.
  - A close sent and not answered within 10 s closes the stream anyway, writing
    nothing, and 1006 is told: websockets' `close_timeout`.
  - The stream's end with no close received closes the stream, writes nothing, and
    tells 1006 (§7.1.5), as websockets and ws do.
  - At the close timeout and at the stream's end, no more bytes will come, so what
    waits for the queue is read first, whatever the queue holds: at most the rest
    of one read. A client's close among it is told with its code, cleanly
    (M3.2's review).
  - Codes 1005, 1006 and 1015 are never sent (§7.4.1). They are what the handler is
    told when a close carried no code (1005), or when the stream ended without one
    (1006).
- **Failing** (§7.1.7) sends a close with its code, unless the server's close was
  sent, then closes the stream, and logs why, with the code of the close it wrote,
  if it wrote one. Nothing the client sends after it is
  read. The handler is told 1006 and an empty reason, since no close came (§7.1.5,
  §7.1.6).
- **A delivered text is its UTF-8 bytes**, checked, and a close's reason too; the
  binding decodes them (§6). A send of text gives a string, which the step
  writes in UTF-8, and a send of binary a bytevector.
- **Time is a deadline's kind.** The step reads no clock. It names the deadline it
  needs by kind: `ping` (quiet), `pong` or `close`. The binding arms it for that
  kind's time, and its passing comes back as `(deadline-passed)`. This is how the
  server's core arms its own (`(arm-deadline kind)`). A connection needs one deadline
  at a time, which is what the transport has. Any bytes received re-arm `ping`.
  A new connection's deadline is `ping`, unless pinging is off. No step tells it:
  `ws-deadline` names it, and the binding arms it as it starts (M3.3). The server's
  shell names its own new connection's deadline, `idle`, and arms it. Here the core
  names it, so a binding that forgets leaves a silent client unpinged; M4.3's
  silent-client check holds it (M3.3's review).

## 6. The binding (the shell)

The take-over runs in place, inside the server's callbacks, and cannot wait (0016).
It makes the core's state, arms the deadline the state names (`ws-deadline`), and
starts reading. It feeds the core the bytes the server
read past the request (`retained`), and answers `(awaiting thunk)`. Each read's bytes
are stepped through the core in place, and the actions run at once:

| action | performed with |
|---|---|
| `write` | `transport-write!`; its `written` procedure counts what is unsent |
| `deliver` | the message queued for `websocket-receive`, which is resumed if it waits |
| `read-stop`, `read-start` | the transport's verbs |
| `arm-deadline`, `disarm-deadline` | `transport-deadline!`, the transport's one deadline, armed for the kind's time (`ping` the ping interval, `pong` the ping timeout, `close` the close timeout); when it passes, a `deadline-passed` |
| `close-stream` | `transport-close!` |
| `closed` | the WebSocket's end: every receive and send after it raises `&websocket-closed` |

- **`websocket-receive`** answers the oldest queued message and steps `(taken
  nbytes)`, or parks on `await` until one comes.
- **A text message's string keeps a leading U+FEFF.** UTF-8 allows it, and the
  checker accepts it. But Chez 10.4.1's `utf8->string` and its UTF-8 transcoders
  drop a leading byte-order mark: `EF BB BF 41` decodes to `"A"`. So the binding
  decodes text another way, and an echo of `EF BB BF 41` sends those four bytes
  back (found in M1.3's review).
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
| `CHEZ_WS_MAX_QUEUE` | 16 | messages queued before reading stops | 0001's amendment; websockets' `max_queue` |
| `CHEZ_WS_PING_INTERVAL` | 20 s | quiet time before a ping; 0 turns pinging off | 0001; websockets |
| `CHEZ_WS_PING_TIMEOUT` | 20 s | time for the pong; past it, 1011 | 0001; websockets |
| `CHEZ_WS_CLOSE_TIMEOUT` | 10 s | time for the client's close, after the server's | websockets' `close_timeout` |
| `CHEZ_WS_WRITE_HIGH_WATER` | 262144 | bytes unsent before a send waits | the server's own |
| `CHEZ_WS_WRITE_LOW_WATER` | 65536 | bytes unsent when it goes on again | the server's own |

Durations are in seconds, as the server's are. A value is a whole number in ASCII
digits, nothing else. Each has a least value: a cap and a queue of 1, since a cap
of 0 would stop reading for good; a pong timeout of 1 s, since one of 0 would pass
as its ping went; 0 for the rest. Each is a fixnum at most, since the server's
transport arms a deadline only for a fixnum of ms. A low water above the high water
is refused.

## 8. Testing

- **The pure core** is held to vectors from its sources:
  - RFC 3174's SHA-1 test vectors, and RFC 6455 §4.2.2's digest of its example key;
  - RFC 4648 §10's base64 vectors;
  - RFC 3629 §4's grammar for UTF-8;
  - RFC 6455 §5.7's example frames.

  Autobahn's cases become core tests where they need no socket, read as byte
  scripts. Time is the `deadline-passed` events a test steps, so no test waits.
- **The handshake's answers meet the server's own rules** for what a handler answers,
  its `switch-fault` and `response-fault`. The door suite holds that, beside the
  door's verbs, so the pure suites need no server (M4.1's review).
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

- **`Origin`**: decided in M4.1, by form: the request's own host by default (0003,
  §3).
- **A field split over lines** (M4.3; found in M4.1).
  - **The gap.** The server's `request-header` reads only a field's first line. Measured
    on v0.3.0: the server opens its door to `Connection: keep-alive` and
    `Connection: Upgrade` on two lines, but `request-header` reads `keep-alive`. So the
    handshake would refuse 400 a request the server took as an upgrade. The same holds
    for `Upgrade` over two lines. Of `Sec-WebSocket-Protocol` over two lines, the
    offers past the first line are missed: the handshake answers 101 without them
    (M4.1's review).
  - **Where it reaches.** RFC 9110 lets a list run over lines (§5.2, §5.3). Browsers
    send each field on one line, and Caddy rewrites `Connection` and `Upgrade` to one
    line each.
  - **What a fix needs.** `(websocket handshake)` reads lists. A reader that joins a
    field's lines with commas needs no change in it, and two `Sec-WebSocket-Key` or
    `Sec-WebSocket-Version` lines joined are refused 400, as websockets, coder and ws
    refuse them.
  - **M4 decides, by form**, with M4.2's door changes, whether the server gives the
    facade every line.
- **The binding's test driver** (M4, §8).
- **What a connection costs:** measured in M4, beside the server's 20 KB for an idle
  connection and 3,637 to 3,644 B for a parked `await`.
- **A close the transport cannot force** (M4; found building M3.2).
  - **The gap.** The server's `transport-close!` closes the stream only once every
    write has been written (chez-http-server v0.3.0, `shell.sls`: `taker-close!`
    and `taker-wrote!`). A client that stops reading leaves a write outstanding.
    So when the binding closes the stream on such a client, the connection stays
    open until the server drains. The close timeout is one such close. So is the
    pong's 1011, and every failure: each writes a close, then `close-stream`
    (M3.3's review).
  - **The server's advice falls short.** Its docs advise a deadline for such a
    client (`docs/handlers.org`). But a deadline's call can only ask for the same
    close again.
  - **The one way through today is a raise.** A raise in a taker's call closes the
    stream at once, and the server logs `taker-failed`.
  - **M4 decides, by form**, between:
    - a door change in the server: a close that drops what is unsent;
    - a bound of the binding's own.
- **A client that sends and does not read** (M4; M3.3's review). Nothing in the core
  bounds it.
  - With the queue full, reading and the ping clock stop, and nothing is armed (0001).
    A handler parked in a send to that client takes nothing, so nothing wakes the
    connection until the server's close, the stream's end or the drain.
  - While reading runs, any bytes re-arm `ping` (0001's amendment of 2026-10-06), so a
    client that keeps sending is never failed with 1011, though it never reads the
    ping.
  - **M4 decides, by form**, how the send side bounds it.
- **When the pong's time starts** (M4.3; M3.3's review). The step arms `pong` as it
  writes the ping, so its 20 s start when the ping is queued. Behind up to 256 KiB
  unsent (§6), and the kernel's buffer, a ping reaches a slow reader late, and a live
  client can be failed with 1011. websockets times the pong from the ping's drain
  (`asyncio/connection.py:822`, `:828`). Arming `pong` on the ping's `written` instead
  would leave nothing armed for a ping stuck behind a client that does not read.
  M4.3's real-socket suite measures it with a throttled reader.
- **Every read re-arms the transport's deadline** (M4.3; M3.3's review): 55 to 57 ns a
  read in the review's measure of the transport's `taker-deadline!`, about 0.2% of a
  loopback read. Re-arming only when the deadline passes, from a flag a read sets,
  would cost nothing a read, but a quiet client would be pinged up to 40 s after its
  last byte, and a dead one found within 60 s, against 0001's 20 s and 40 s. M4.3
  measures it beside a connection's cost.
