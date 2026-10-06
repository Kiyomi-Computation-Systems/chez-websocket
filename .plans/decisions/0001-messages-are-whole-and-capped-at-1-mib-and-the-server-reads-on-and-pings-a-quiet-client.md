# 0001: Messages are whole and capped at 1 MiB; the server reads on while a handler is busy, and pings a quiet client

Date: 2026-10-04
Status: accepted (user decision, 2026-10-04, by form: "1 MiB", "Read on, ping",
"Whole messages", each the recommended). Amended 2026-10-05 by form (M3.1):
"Also 16 messages", the recommended; and again (M3.2): "Deliver as before", the
recommended.
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
     the connection fails with 1011. These are websockets' numbers, but websockets
     pings every 20 s whether the client is quiet or not; here only a quiet client
     is pinged.
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

## Amendment of 2026-10-05 (M3.1): the queue counts messages too

Building M3.1 found what item 2 left open. Reading stopped once the queue held a
cap's worth of bytes, and an empty message adds no bytes. So while a handler is
busy, or waits in a send to a client that does not read, a client could queue
empty messages without end. Measured on a prototype of the core (Darwin arm64,
Chez 10.4.1):
- an empty masked text frame is 6 bytes (RFC 6455 §5.2: two of header, four of
  key);
- one read of 16 KiB, the server's read buffer, carries 2,730 of them;
- the prototype queued all 2,730 and never stopped reading, and its step
  allocated 80 B a message, before the binding queues anything.

Decided by form, the recommended, "Also 16 messages":
- **Reading also stops once 16 messages are queued**, websockets' `max_queue`
  (which counts frames). `CHEZ_WS_MAX_QUEUE` overrides it.
- **Reading starts again once the queue is under both bounds**: under a cap's
  worth of bytes and under 16 messages. Item 2's "until the handler takes one"
  is the same whenever one take brings it under both.
- **The step reads no further than the message that fills the queue.** The rest
  of that read waits, kept: the server's transport hands a taker each read's
  bytevector to keep (chez-libuv copies each read into a fresh one). It is read
  as takes make room, a message at a time, before reading starts again. In the
  prototype, the read of 2,730 queued 16 and stopped, and each take then read one
  more.

Weighed and not taken: the same bound with no setting; a floor of 1 KiB a
message toward the cap's worth, at most 1,024 empty messages at the default;
and bytes alone, as first decided.

**What one connection can be made to hold** is then two caps' worth at most: the
queue under a cap's worth, and the message that fills it, up to the cap. While
reading is stopped, the rest of one read waits too, and no message arrives.

## Amendment of 2026-10-05 (M3.2): reading on goes on after the server's close

Building M3.2 found what item 2 left open. Once the server has sent its close, the
client may not have seen it yet, so messages can still come before its answering
close. Reading stops while the queue is full, so the client's close can sit unread
behind it. Measured on two prototypes of the core (Darwin arm64, Chez 10.4.1):
- **At the default limits**, a read of 16 messages, a 17th and the client's close
  delivered the 16 and stopped reading, the rest waiting. Then the server's close:
  - delivered as before, the client's close stayed unread, until the close timeout
    would tell 1006;
  - with messages dropped once the close is sent, the step read on, and the
    connection closed at once, cleanly, with the client's 1000.
- **Two messages the client sends after the server's close** were delivered, or
  dropped: 2 of 2, or 0 of 2.
- **The core's lines**, the prototypes': +82/-22, or +97/-23.

The peers, read from source or run:
- websockets 17.2 queues them, and pauses reading past 16 frames whether closing or
  not (`asyncio/connection.py:740-749`, `asyncio/messages.py:266-289`);
- ws 7.5.10, run on a fake socket, delivers them.

Decided by form, the recommended, "Deliver as before":
- **A message that comes after the server's close is delivered as before**, and
  reading on is unchanged: websockets' way.
- **The close timeout bounds the wait** for a client's close held back by a full
  queue.
- **M4's binding can take on behalf of a procedure that has ended**, so that
  procedure's queue never holds the close back.

Weighed and not taken: "Drop them". Once its close is sent, the server would read on
whatever the queue holds, dropping data messages and answering pings, and read what
waits at once. The handshake would end as soon as the client answered, but a
message the client sent before seeing the close would be lost, unlike both peers.

The form said 16 messages were queued. The probe it rested on had run with a queue
of 2. It was run again at the default, 16, after the answer, with the same outcome.
