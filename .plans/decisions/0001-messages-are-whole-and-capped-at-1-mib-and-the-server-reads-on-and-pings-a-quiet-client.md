# 0001: Messages are whole and capped at 1 MiB; the server reads on while a handler is busy, and pings a quiet client

Date: 2026-10-04
Status: accepted (user decision, 2026-10-04, by form: "1 MiB", "Read on, ping",
"Whole messages", each the recommended)
Design: [the design](../2026-10-04-chez-websocket-design.md) §5–§7

## Context

The design needed three choices that shape every handler: how big a message may be,
whether a connection is read and kept alive while its handler is busy, and what a
read returns. Five peers' defaults were read from source at their release tags
([the survey](../research/2026-10-04-peer-defaults.md)):
- **The largest message:** coder 32,768 bytes; websockets 1 MiB; tungstenite 64 MiB
  (16 MiB a frame); ws 100 MiB; gorilla none. Four of them close with 1009 when it is
  passed, and three check each frame's announced length before reading its payload.
- **Keepalive:** only websockets pings by default: every 20 s, closing with 1011 if
  no pong comes within 20 s. coder, gorilla, tungstenite and ws ship none.
- **Reading while busy:** websockets reads on into a queue of 16 frames, then pauses,
  and answers a ping at once. coder and gorilla answer a ping only while the
  application reads, and tungstenite on its next read, write or flush.
- **The read:** every peer's main read returns a whole message. websockets, coder and
  gorilla also offer a read of one message in pieces.

Here:
- An idle server connection holds about 20 KB, and the server allows 10,000 by
  default (chez-http-server's CHANGELOG `[0.1.0]`, `CHEZ_HTTP_MAX_CONNECTIONS`).
- The server enables no TCP keepalive: `uv-tcp-keepalive!` is called nowhere in its
  `src/` at v0.3.0. So a client that vanishes without closing holds its connection,
  and the coroutine its handler waits on, until the server shuts down, unless
  something here notices.
- RFC 6455 §10.4: a server SHOULD limit a message's size.

## Decision

By form, the recommended answer to each of three questions:

1. **A message is capped at 1 MiB by default**, websockets' default. A data frame
   whose announced length would take its message past the cap fails the connection
   with 1009, before any of its payload is held. `CHEZ_WS_MAX_MESSAGE_BYTES`
   overrides it.
2. **The server reads on while a handler is busy, and pings a quiet client.**
   - Whole messages wait in a queue for `websocket-receive`. Once the queue holds a
     cap's worth of bytes, reading stops until the handler takes one.
   - A ping is answered at once.
   - A client that has sent nothing for 20 s is pinged. If no pong comes within 20 s,
     the connection fails with 1011, as websockets' 20 s/20 s does.
   - `CHEZ_WS_PING_INTERVAL` and `CHEZ_WS_PING_TIMEOUT` override the times; an
     interval of 0 turns pinging off.
3. **`websocket-receive` returns a whole message**: text as a string, binary as a
   bytevector. There is no read of pieces in v1.

## Consequences

- **What one connection can be made to hold:** about two caps of messages, the queue
  and the message arriving, so about 2 MiB at the default. That is beside the
  server's 20 KB and a parked coroutine's 3,637 to 3,644 B.
- **A dead client is found within 40 s**, and the ping that finds it is 2 bytes, sent
  only to a client that has gone quiet.
- **The ping clock stops while reading has stopped.** When the queue is full, the
  server stops reading the connection itself, so a pong it has not read is not the
  client's fault. The ping clock runs again once reading does.
- **A text message is checked as UTF-8 as it arrives**, so a bad byte fails the
  connection with 1007 at once (RFC 6455 §8.1). The check does not wait for the
  message's end, which websockets' `recv` and ws do.
- **The other defaults** are in the design (§7), taken without a form, each with its
  source:
  - the closing handshake's timeout, 10 s, websockets';
  - the send side's water marks, 256 KiB and 64 KiB, the server's own.
- **A read of pieces** can be added later without changing what
  `websocket-receive` does.
- **Weighed and not taken:**
  - a 64 KiB cap, which is tighter (625 MiB across 10,000 connections) but refuses
    common payloads;
  - 64 MiB, tungstenite's: one client could make the server hold 64 MiB;
  - no cap, gorilla's, which §10.4 advises against;
  - reading on without pings, which leaves a vanished client until shutdown;
  - reading only inside `websocket-receive`, as coder, gorilla and tungstenite do:
    one message at most, but pings answered only then, and no keepalive possible;
  - whole messages plus a streaming read, which means more API and more states in v1.
