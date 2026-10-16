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
    amendment). A list is read by its leftmost element, the client-facing hop's, by
    RFC 7239 §4's order (0003's amendment of 2026-10-09, by form).
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
         (taken nbytes)  (written nbytes)  (deadline-passed)
actions  (write bv)  (deliver kind payload)  (read-stop)  (read-start)
         (arm-deadline kind)  (disarm-deadline)  (close-stream)  (abort-stream)
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
    timeout, and so does a client that is behind (the write side, below).
  - A close sent and not answered within 10 s aborts the stream, writing nothing, and
    1006 is told: websockets' `close_timeout`, which ends in `transport.abort()`.
    The client has had its time, so what is unsent is dropped (0006).
  - The 10 s run from the close's queueing, as websockets', ws's and coder's do (0006's
    amendment, by form: "From queueing, as peers do"). So at a close a client reads
    what was unsent before it, and the close, within them: at the default high water,
    25.6 KiB/s. The close timeout is at least 1 s.
  - The stream's end with no close received closes the stream, writes nothing, and
    tells 1006 (§7.1.5), as websockets and ws do.
  - At the close timeout and at the stream's end, no more bytes will come, so what
    waits for the queue is read first, whatever the queue holds: at most the rest
    of one read. A client's close among it is told with its code, cleanly
    (M3.2's review).
  - Codes 1005, 1006 and 1015 are never sent (§7.4.1). They are what the handler is
    told when a close carried no code (1005), or when the stream ended without one
    (1006).
- **The write side** (0006, by form: "Reading stops past the high water"), as the
  read side.
  - Each `write` the step answers counts its bytes unsent. `(written nbytes)` takes
    them off: the binding steps it as each write's done comes, whatever the done says.
    A done that tells a failure is then stepped as the stream's end too (step 2's
    review).
  - Once a step leaves more than the high water unsent (256 KiB, the server's own),
    the client is behind.
    - Reading stops, and the ping clock with it. A read that passes the high water
      stops at the frame that did, and keeps the rest waiting, as a full queue does.
    - While the connection is open, `write` is armed: the write timeout, 60 s. After
      the server's close, the close deadline goes on in its place.
  - While open, each `written` while behind re-arms `write`. After the server's close,
    nothing is re-armed: the close deadline stands. One that leaves no more than the
    low water (64 KiB) ends it: `write` disarmed, if armed, what waits read, then
    reading started, and the clock afresh, unless the queue is full.
  - Falling behind and catching up, nothing waiting, end a step with constant tails, as
    the clock's re-arming does, so a send that waits for every done costs what it did
    before 0006 (step 2's review).
  - When `write` passes, the client has read nothing for the write timeout. The step
    answers `(abort-stream)`, writes nothing, and logs `failed` with no code and
    `write-timeout`. It lets go of what waits for the queue, and tells 1006.
  - `ws-behind?` tells the binding whether the client is behind; a send waits while it
    is. A `written` after the end only counts.
- **Failing** (§7.1.7) sends a close with its code, unless the server's close was
  sent, then closes the stream, and logs why, with the code of the close it wrote,
  if it wrote one. Nothing the client sends after it is
  read. The handler is told 1006 and an empty reason, since no close came (§7.1.5,
  §7.1.6).
- **A delivered text is its UTF-8 bytes**, checked, and a close's reason too; the
  binding decodes them (§6). A send of text gives a string, which the step
  writes in UTF-8, and a send of binary a bytevector.
- **Time is a deadline's kind.** The step reads no clock. It names the deadline it
  needs by kind: `ping` (quiet), `pong`, `close` or `write` (0006). The binding arms it for that
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
| `write` | `transport-write!`, in writes of 64 KiB at most (0006's amendment, by form: "In 64 KiB writes"); each done stepped as `(written nbytes)`, and one that tells a failure as `(end why)` too (0006) |
| `deliver` | the message queued for `websocket-receive`, which is resumed if it waits |
| `read-stop`, `read-start` | the transport's verbs |
| `arm-deadline`, `disarm-deadline` | `transport-deadline!`, the transport's one deadline, armed for the kind's time (`ping` the ping interval, `pong` the ping timeout, `close` the close timeout, `write` the write timeout); when it passes, a `deadline-passed` |
| `close-stream` | the deadline armed for the close timeout, its call `transport-abort!`, then `transport-close!`, which closes once what is unsent has been written: a client that has not read it within the close timeout, timed from here as peers time a close, is aborted. A close that begins at once, nothing unsent, disarms the deadline, in both of the server's shells (0006) |
| `abort-stream` | `transport-abort!`, which closes at once and drops what is unsent: the close timeout, or the write timeout, has passed (0006) |
| `closed` | the WebSocket's end: every receive and send after it raises `&websocket-closed`; a receive or a send that waits is woken at once |
| `log` | a line on the current output port, as the server logs: `websocket-` and the core's name, then each detail (M4.3) |

- **The facade, as built in M4.3.** `(websocket-accept request proc [settings
  [limits]])`. The settings default to no subprotocols and `same-host`, and the
  limits to the environment's, `environment-websocket-limits`. The binding reads
  them once, as a program that imports it starts: Chez runs a library's body before
  the program's, so a malformed `CHEZ_WS_` value stops the program before its first
  line (§7). The facade exports the binding's verbs, `make-handshake-settings`, and
  the limits' constructors and accessors.
- **The handshake reads every line of a field**, `request-header-values` joined with
  ", " (RFC 9110 §5.3; 0004).
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
- **`websocket-send!`** steps a `send` and writes its frame. While the core says the
  client is behind (`ws-behind?`), it parks (0006): more than 256 KiB unsent, until a
  done brings that to 64 KiB or less. It parks before it writes, and after a write that
  puts the client behind (0006's amendment, by form: "Wait before writing too"), so
  many procedures sending make the server hold no more than one does. These are the server's own stream water marks
  (`CHEZ_HTTP_WRITE_HIGH_WATER`, `_LOW_WATER`), compared as the server compares them.
  - A send woken by the connection's end raises `&websocket-closed`.
  - **While the server's close is under way**, a send sends nothing: it waits for the
    connection's end, then raises `&websocket-closed`. This is websockets' way
    (`send_context`). The design was silent here, and the core refuses a send then as
    the caller's mistake, which a drain's close would make of a handler's next send
    (M4.3).
- **`websocket-close!`** steps a `close` (1000 by default) and returns; the handshake
  finishes on its own. A code an endpoint may not send, or a reason past 123 bytes, is
  refused naming `websocket-close!`, by the core's `ws-sendable-close?`. The binding
  asks the core whether the connection is open (`ws-open?`), and keeps no phase of
  its own (M4.3's review).
- **Many senders, one receive** (0005, by form). Any number of coroutines may wait to
  send on a WebSocket. All are woken at the low water, and each goes on in turn while
  the client is not behind. One receive may wait,
  and a second is refused naming `websocket-receive`. Each wait knows the WebSocket
  whose procedure runs on its coroutine, from a parameter set around the procedure.
- **The stream's close.** When the stream closes, whoever closed it, the wait the
  thunk is in raises `&client-closed` (0023). The binding turns that into the
  connection's end: 1006, unless the closing handshake had finished.
  - **The close call** (`transport-on-close!`) steps the stream's end, `(end closed)`,
    so the core reads what waits for the queue first. Both of the server's shells tell
    the wait before they run the close call (its `shell.sls`, `handle-closed!`; its
    fake's `close-begun!`; the driver suite's D-OUTSIDE holds the order). So the close
    call first marks the wait the WebSocket's procedure is in, wherever it waits, as
    ended, and nothing wakes it: that would be a late resume.
    - M4.3 first registered a close call that woke every wait, and took it out for
      that late resume. Without one, a procedure that spent the `&client-closed` in a
      wait of its own waited forever at its next receive. Its review put it back as
      above.
  - **A wait's `&client-closed`** on the procedure's own WebSocket ends the wait, and
    the receive or send sees the end. On another connection's WebSocket it goes on
    out, to the procedure whose stream closed, and the other connection goes on (0005).
- **The server's drain.** On `transport-on-drain!`, the binding starts a closing
  handshake with 1001, "going away" (§7.4.1).
- **The procedure's end.**
  - If it returns, the binding closes with 1000.
  - If it lets its own WebSocket's `&websocket-closed` out, nothing more is done or
    logged. Nor if it lets `&client-closed` out: that is its stream's close (M4.3).
    Another WebSocket's `&websocket-closed` is any other raise (M4.3's review).
  - Any other raise closes with 1011, and is logged `websocket-handler-failed`, its
    detail as the server logs one: a condition as `display-condition` shows it, on one
    line, a record by its type's name, a string displayed, and anything else written.
  - The thunk lets nothing out, so the server logs nothing for it.

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
| `CHEZ_WS_CLOSE_TIMEOUT` | 10 s | time for the client's close, after the server's, and to read what was unsent when a close was asked for; past it, the stream aborted | websockets' `close_timeout`; 0006 |
| `CHEZ_WS_WRITE_HIGH_WATER` | 262144 | bytes unsent before a send waits, and reading stops | the server's own; 0006 |
| `CHEZ_WS_WRITE_LOW_WATER` | 65536 | bytes unsent when both go on again | the server's own; 0006 |
| `CHEZ_WS_WRITE_TIMEOUT` | 60 s | time for each write's done while the client is behind, from past the high water until the low water; past it, the stream aborted | the server's own `CHEZ_HTTP_WRITE_TIMEOUT` (0006) |

Durations are in seconds, as the server's are. A value is a whole number in ASCII
digits, nothing else. Each has a least value: a cap and a queue of 1, since a cap
of 0 would stop reading for good; a pong timeout of 1 s, since one of 0 would pass
as its ping went; a write timeout of 1 s, since one of 0 would pass as reading
stopped; a close timeout of 1 s, since one of 0 would abort a close before the
client could read it (0006's amendment); 0 for the rest. Each is a fixnum at most, since the server's
transport arms a deadline only for a fixnum of ms. A low water above the high water
is refused.

## 8. Testing

- **The pure core** is held to vectors from its sources:
  - RFC 3174's SHA-1 test vectors, and RFC 6455 §4.2.2's digest of its example key;
  - RFC 4648 §10's base64 vectors;
  - RFC 3629 §4's grammar for UTF-8;
  - RFC 6455 §5.7's example frames.

  Autobahn's cases run on a socket, in their own lane (M5), not as core tests. Time is
  the `deadline-passed` events a test steps, so no test waits.
- **The handshake's answers meet the server's own rules** for what a handler answers,
  its `switch-fault` and `response-fault`. The door suite holds that, beside the
  door's verbs, so the pure suites need no server (M4.1's review).
- **The binding** runs on the server's fake shell (0004, by form in M4.2). Its waits
  need a coroutine, which only the server's shells run. Its fake shell runs the
  server's own core, parser and 101, the hand-off, coroutines, and a clock the test
  moves.
  - **The suites' path.** The server's `tests/` is last on the suites' library path
    (`TEST_LIBDIRS`), with chez-httparse's test harness, which the server's
    `(response-reader)` needs to read what the client reads. Neither is on the path
    `make run` and `make dev` use, and `make test` refuses to run if one is.
  - **The driver suite** (`tests/test-driver.sps`) holds, through the pin, what the
    binding needs of the fake, since nothing promises the server's test code across
    versions. It also checks that no borrowed library has one of this project's names.
  - **How a test plays the client.** `fake-shell-feed-input!` delivers the client's
    bytes only while the taker reads, as libuv does, so a test of read-stop feeds its
    bytes that way. `fake-shell-deliver!` hands over one event, and places a read,
    or the client's end, between two turns (M4.2's review). Since the server's
    v0.7.0, an event given while the taker has stopped reading is kept until it
    reads again, as the server keeps it.
  - **The binding suite** (`tests/test-binding.sps`, M4.3) also:
    - drains the scheduler after the fake's timer fires
      (`fake-shell-schedule!`), as the libuv shell drains it after every turn;
    - closes the stream under the binding by wrapping the switch's take-over
      (`(http-server switch)`), as the server does when its drain times out;
    - reads a wait's end before the client has read the close, so the end's own
      wake is seen, not the stream's later close.
    - plays two connections at once, on two fakes, one procedure sending to or
      receiving from the other's WebSocket (M4.3's review);
    - holds what a read costs the binding: no more than a taker that only re-arms its
      deadline, the read and take events being filled in, not made, and a step's
      actions performed by a loop, not by `for-each` over a closure;
    - runs with no `CHEZ_WS_` variable set, which `make test` sees to, and refuses to
      run otherwise, since the binding reads them as the program starts;
    - plays a client that reads nothing by delivering its bytes while the binding
      reads, with no later turn between: `fake-shell-feed-input!` settles before each
      delivery, so it plays a client that reads (step 2);
    - plays a client that reads at a rate, each write the client's once it has read
      its last byte (`reading-at!`, step 2's review).
  - **What the fake cannot show.** It logs a late resume nowhere, and its coroutines do
    not show what a waiting procedure's stack holds. So these are held on the real
    socket (M4.3's step 3):
    - the binding letting go of a resume it has called;
    - its close call marking its procedure's wait ended;
    - a read's bytevector let go after its step, by the heap;
    - what a procedure waiting in a receive holds (0005's amendment).
- **A real socket** (`tests/test-socket.sps`, M4.3 step 3). The server's libuv shell
  listens on `127.0.0.1:0`, with its clients on the same loop. Every wait is capped by an
  iteration count, as the server's own socket lane does it (its `(shell-testing)`, on
  chez-libuv's `(uv-testing)`, both borrowed onto the suites' path). Each check has a
  server of its own, closed with its clients before the next. The suite:
  - reads the server's log for `late-resume`, through the drain's close under a receive
    seen to wait and a send seen to wait;
  - fails a silent client on the shell's own timer, timing the ping and the close from
    what the server writes, through a transport over the shell's (`wrapping`, shared with
    the binding suite in `(ws-play)`);
  - measures the heap back to back: a read's bytevector against half its frame, at
    16,000 bytes, which one read takes whole, and checks that each did (0007). It also measured a receive's wait
    against a wait by `call/1cc` until 2026-10-09, when that check was retired before the
    server's v0.4.1 pin (0005's amendment of that date);
  - caps each wait at 4,000 turns, over ten times the most any took, and ends a check's
    waiting at the first wait that reaches it, so a check that cannot finish costs about
    5 s, not the suite;
  - and its numbers are both platforms' (the [measures](research/2026-10-09-real-socket-measures.md)).
  The driver suite holds what it needs of the server's libuv shell and `(shell-testing)`,
  as it holds the fake's.
- **Autobahn|Testsuite** runs in Linux CI on every PR and push, and by `make autobahn`
  (M5, 0008). Its fuzzing client, from its image pinned by digest, runs its 301 cases
  without compression against `tests/autobahn/echo.sps`, whose cap is 16 MiB, the
  largest message they send.
  - **Where the echo server runs.** On Linux, on the host, on a free port it reads back.
    On Docker Desktop (macOS, Windows), which has no host network, in a Linux container
    beside the fuzzing client (0008's amendment).
  - **The gate.** wstest exits 0 whatever its cases show. So the gate, `(ws-autobahn)`,
    holds the run's `index.json` against the ratchet, `tests/autobahn/verdicts.txt`, both
    ways: each case's behavior, behaviorClose and the close code the server sent.
  - **Varying cases.** A case measured to vary with how the client's bytes fall into reads
    lists each whole verdict seen: 3.4, 4.1.5 and 4.2.5 (0008).
  - **Held without Docker.** `tests/test-autobahn.sps` holds the gate, and
    `tests/test-autobahn-run.sps` holds `run.sh`, a stand-in for docker playing the run.

## 9. Open, and decided later

- **A close lost to a reset** (M5; found by the Autobahn lane). When the server fails a
  connection while the client is still sending, it closes its socket with the client's
  bytes unread, and the kernel resets the connection. On macOS the client never read the
  close, in 100 of 100 tries; on Linux 14 of 100 ended in a reset. The server's HTTP
  closes half-close and linger for this (its decision 0011); a taken stream's close does
  not. **Decided by form** (0008): a chez-http-server slice after the lane, its release
  pinned here alone. **Done** (2026-10-11): the server's v0.5.0 half-closes a taken stream
  and lingers (its decision 0026), pinned by #69. On macOS a client still sending read the
  close in 100 of 100 tries, where v0.4.1 read it in 70, every one ending in an error. The
  close timeout bounds the close's writes; after them the server's linger,
  `CHEZ_HTTP_LINGER_TIMEOUT` (30 s), bounds the wait for the client's close. The ratchet no
  longer lists `none` (0008's amendment of 2026-10-11).

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
  - **Decided in M4.2, by form** (0004): the server gives every line,
    `request-header-values` (its v0.4.0), and M4.3's facade joins them with commas.
- **The binding's test driver**: decided in M4.2, by form: the server's fake shell
  (0004, §8).
- **What a connection costs:** measured in M4.3, beside the server's own, measured
  again at the pin. The server's records give about 20 KB for an idle connection (its
  CHANGELOG's `[0.1.0]`) and 3,637 to 3,644 B for a parked `await` (its design §5.2).
  Both are from its v0.1.0, before the guards its v0.4.0 hoisted and chez-libuv v0.7.4
  (M4.2's review).
  - **Measured in M4.3 step 3** (Darwin; the server's own method; the
    [measures](research/2026-10-09-real-socket-measures.md)). An idle WebSocket in a
    receive held 11,096 to 11,414 B of heap. At v0.4.0 the server held 1,793 to 2,073 B
    for an idle connection and 3,634 B for a parked `await`, as at v0.1.0. A raw taker
    parked at `await` held 6,390 B.
  - **The receive's wait escaped by a one-shot continuation**, which held a stack segment
    while it waited. By `call/cc` it holds about 3 KB less (0005's amendment, by form).
  - **The server parks its coroutines the same way** (M4.3 step 3's review). Its
    scheduler's `suspend!` is `call/1cc`, and a parked coroutine held 3,639 to 3,660 B. By
    `call/cc` it held 640 to 679 B, and an idle WebSocket 4.9 KB, not 8.4 KB. The cost is
    90 B and 20 to 200 ns more each wake and park, and a stale continuation no longer fails
    at once ([the measures](research/2026-10-09-real-socket-measures.md)).
    - **Decided by form, "A server slice next"**: the server changes `suspend!` in a
      slice of its own after M4.3 step 3, keeping a check that a coroutine's continuation
      is not invoked twice; then its release is pinned here, alone.
  - **Measured before the v0.4.1 pin** (2026-10-09, Darwin; the socket suite's setting,
    its clients in the same heap). A connection at a bare `await` held 7,907 to 8,484 B at
    v0.4.0 and 5,253 to 5,292 B at v0.4.1. A receive held 462 to 984 B more at v0.4.0, and
    303 to 340 B more at v0.4.1 (0005's amendment of that date). After a 4,000-byte
    message the heap read about 2.9 KB above the reading after the next, and about 620 B
    a connection more than at v0.4.0. Two 1-byte messages read the same, so that is the
    heap falling between the readings, and nothing is kept (0007's amendment of
    2026-10-11; the server's plan settled it).
  - **Measured again for v0.1.0** (2026-10-11, Darwin; the server's method; on its
    v0.5.0). An idle WebSocket in a receive held 5,281 to 5,435 B, and 5,353 to 5,477 B
    after 10 echoes; the server's own idle connection 1,900 to 2,055 B
    ([the measures](research/2026-10-09-real-socket-measures.md), its section "For
    v0.1.0, on the server's v0.5.0").
  - **Measured again at the v0.6.0 pin** (2026-10-12, Darwin; the server's method; v0.5.0
    beside it the same hour). An idle WebSocket in a receive held 5,330 to 5,397 B on
    v0.6.0 and 5,353 to 5,367 B on v0.5.0, and S-LETGO's floor read the same on both
    ([the measures](research/2026-10-09-real-socket-measures.md), its section "At the
    server's v0.6.0 pin").
  - **Measured again at the v0.7.0 pin** (2026-10-16, Darwin; the server's method; v0.6.0
    beside it the same hour). An idle WebSocket in a receive held 5,332 to 5,344 B on
    v0.7.0 and 5,179 to 5,477 B on v0.6.0, and S-LETGO's floor read the same on both
    ([the measures](research/2026-10-09-real-socket-measures.md), its section "At the
    server's v0.7.0 pin").
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
  - **Before v0.4.0, the one way through was a raise.** A raise in a taker's call
    closes the stream at once, and the server logs `taker-failed`.
  - **Decided in M4.2, by form** (0004): a door change in the server,
    `transport-abort!` (its v0.4.0), which closes the stream at once and drops what is
    unsent. M4.3's binding aborts where it must close a client that does not read.
  - **Named in M4.3 step 2** (0006): every close the binding asks for gives the
    client the close timeout to read what was written, then aborts; the close timeout
    passing aborts at once, as websockets' does. Measured on the fake shell before:
    each of the five closes waited for the hour.
  - **Its review, by form** ("From queueing, as peers do"): the close timeout runs
    from the close's queueing, as peers time theirs, and is at least 1 s. So a client
    reading slower than the high water over the close timeout, 25.6 KiB/s, is aborted
    at a close: 200 KiB, then a close, read at 15 KiB/s, is aborted at 15 s, the
    client given two of its four 64 KiB writes. Timing the close from its done, the
    write timeout before it, was measured and not taken: a client reading nothing
    would be held 60 s after a close, not 10 s.
- **A client that sends and does not read** (M4; M3.3's review). Nothing in the core
  bounds it.
  - With the queue full, reading and the ping clock stop, and nothing is armed (0001).
    A handler parked in a send to that client takes nothing, so nothing wakes the
    connection until the server's close, the stream's end or the drain.
  - While reading runs, any bytes re-arm `ping` (0001's amendment of 2026-10-06), so a
    client that keeps sending is never failed with 1011, though it never reads the
    ping.
  - **M4.3 decides, by form**, how the send side bounds it. With the abort, the bound
    needs no door change (0004).
  - **Decided in M4.3 step 2, by form** (0006, "Reading stops past the high water"):
    past the high water, reading stops and a write timeout runs, 60 s,
    `CHEZ_WS_WRITE_TIMEOUT` ("60 s, its own variable").
  - **Its review, by form** (0006's amendment): a send waits before it writes too, so
    20 procedures sending 64 KiB to a client that reads nothing hold 262,184 B, not
    1,310,920 B; and a frame goes in writes of 64 KiB, so a client reading 10 MiB at
    100 KiB/s reads it whole, where one write was aborted at 65 s.
- **When the pong's time starts** (M4.3; M3.3's review). The step arms `pong` as it
  writes the ping, so its 20 s start when the ping is queued. Behind up to 256 KiB
  unsent (§6), and the kernel's buffer, a ping reaches a slow reader late, and a live
  client can be failed with 1011. websockets times the pong from the ping's drain
  (`asyncio/connection.py:822`, `:828`). Arming `pong` on the ping's `written` instead
  would leave nothing armed for a ping stuck behind a client that does not read.
  M4.3's real-socket suite measures it with a throttled reader.
  - **Measured in step 2** on the fake shell: 300 messages of 1 KiB to a client
    reading one write a second. On main it is failed with 1011 at 45 s, 255 sent.
    With 0006's write side, all 300 are sent by 197 s, and it is failed at 237 s,
    its ping behind the low water's 64 KiB.
  - Since 0006 the core sees each write's done, so it could time the pong from the
    ping's, as websockets does. Then the write timeout would still bound a ping stuck
    past the high water. A ping stuck below it would have nothing armed.
  - **Measured in step 3 on a real socket** (Linux; 0001's amendment of 2026-10-09).
    After a 4 MiB burst, live readers at 96 KiB/s and below were failed with 1011, and
    readers at 112 and 128 KiB/s were kept. The backlog ahead of the ping was in the
    kernel, so timing from the ping's done failed the same rates, within 0.3 s. It also
    left a client reading nothing, sent 4.2 or 4.3 MB, with nothing armed.
  - **Decided by form, "From queueing, as now"**: no change. A longer
    `CHEZ_WS_PING_TIMEOUT` keeps slow readers; at 60 s, readers at 32 to 64 KiB/s were
    kept.
- **A late resume after a handler's own deadline** (M4.3's review; 0005).
  - **The gap.** A handler's `with-deadline` can end a waiting receive. A message
    delivered in that turn, before the coroutine runs, wakes a wait that has ended, and
    the server logs `late-resume await`. The message stays queued, and the next
    receive gets it.
  - **What a fix needs.** The server's waits give no way to ask whether a wait still
    stands. A door change would: a resume that answers whether it woke, quietly.
  - Not asked of the server yet.
- **Every read re-arms the transport's deadline** (M4.3; M3.3's review): 55 to 57 ns a
  read in the review's measure of the transport's `taker-deadline!`, about 0.2% of a
  loopback read. Re-arming only when the deadline passes, from a flag a read sets,
  would cost nothing a read, but a quiet client would be pinged up to 40 s after its
  last byte, and a dead one found within 60 s, against 0001's 20 s and 40 s. M4.3
  measures it beside a connection's cost.
  - **Measured in step 3, and kept.** An echo round trip on a real socket took 100.5 to
    102.2 µs with the re-arm and 100.9 to 102.2 µs without it. No difference shows.
