# 0001: Messages are whole and capped at 1 MiB; the server reads on while a handler is busy, and pings a quiet client

Date: 2026-10-04
Status: accepted (user decision, 2026-10-04, by form: "1 MiB", "Read on, ping",
"Whole messages", each the recommended). Amended 2026-10-05 by form (M3.1):
"Also 16 messages", the recommended; and again (M3.2): "Deliver as before", the
recommended. Amended 2026-10-06 by form (M3.3's review): "Any bytes", the
recommended. Amended 2026-10-09 by form (M4.3 step 3): "From queueing, as now", the
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

M3.2's review (2026-10-05) changed what the close timeout does with the held-back
close. The timeout, and the stream's end, now read what waits before they end, the
queue's bound aside: at most the rest of one read. So in the probe above, when the
timeout passes, the 17th message is delivered and the client's close is told with its
code, cleanly, where it had been 1006. The decision stands: messages after the
server's close are delivered as before, and the wait is the close timeout.

## Amendment of 2026-10-06 (M3.3's review): anything received answers the ping

M3.3's review found what item 2 left open. Item 2 fails the connection "if no pong
comes within 20 s". As M3.3 built it, any bytes received re-arm the ping clock, a
pong or not, while the pong is awaited too. Probed on the review's core (Darwin
arm64, Chez 10.4.1): the ping's deadline passing, then one read, then the pong's
deadline.
- **Any bytes, as built.** A whole message, the first fragment of one, or the first
  500 bytes of a 1,000-byte frame: each re-armed ping, and the pong's deadline pinged
  again. On M3.3's core (dd532f7), the review's probe sent one message an interval,
  and one byte an interval, for 10,000 intervals each, and neither was failed.
- **Only a pong**, a prototype of websockets' rule: each of the three was failed with
  1011, the frame half arrived among them.

websockets 17.2 waits for the pong alone (`asyncio/connection.py:826-843`), but it
pings every 20 s, busy or not.

Decided by form, the recommended, "Any bytes":
- **While the pong is awaited, any bytes received re-arm ping**, as before it. The
  connection fails with 1011 only if nothing comes within 20 s of the ping. A read of
  no bytes changes nothing.
- **A live client in the middle of a long frame** is not failed for a pong that waits
  behind it.
- **A client that keeps sending but has stopped reading** is never failed with 1011,
  since it never sees the ping. That is left to M4's send side (the design's §9).

Weighed and not taken: "Only a pong". A client that sends but does not answer would
be failed at 40 s, but so would a live one whose pong waits behind its own frame. The
core would have grown by about 11 lines.

**"A dead client is found within 40 s"** holds while the server reads. While the queue
is full, reading and the ping clock stop and nothing is armed (item 2). A client that
filled the queue and vanished is found only by a take, the server's close, the
stream's end or the server's drain, and a handler parked in a send to it takes
nothing (the design's §9).

## Amendment of 2026-10-09 (M4.3 step 3): the pong timed from the ping's queueing, measured

**The question** (the design's §9, from M3.3's review). The core arms `pong` as it writes
the ping, so the pong's 20 s start when the ping is queued. Whatever was sent before the
ping waits ahead of it, so a slow reader that is live can be failed with 1011. websockets
times the pong from the ping's drain. Step 2 measured it on the fake shell. Step 3
measured it on a real socket.

**Measured** (Linux, libuv 1.48.0, CI's; [the measures](../research/2026-10-09-real-socket-measures.md)).
A burst of 4 MiB as 1 KiB messages, then a client reading at a set rate and answering
each ping as it reads it, as a browser does:
- **As built, from queueing:** live readers at 32, 48, 64, 80 and 96 KiB/s were failed
  with 1011, at 128, 86, 64, 51 and 43 s. Each had read all 4 MiB, then the ping and the
  close together. Readers at 112 and 128 KiB/s were never failed.
- **The backlog ahead of the ping is in the kernel.** The ping clock runs only while no
  more than the low water is unsent (0006), so the ping's write is done nearly at once.
  Linux took 2,560 KiB from a client that never read. From one that read its 101 and
  then stopped, it took 3.8 to 4.1 MB, bounded by where the binding fell behind. macOS
  took 704 to 3,392 KiB.

**The options:**
- **"From queueing, as now"**: the numbers above. A client that reads nothing is failed at
  the pong's timeout for every burst the kernel holds. Past the high water, the write
  timeout fails it.
- **"From the ping's done, as websockets"**: a prototype. The same rates were failed, within
  0.3 s. And a client that read nothing, sent 4.2 or 4.3 MB, was never failed in 100 s: its
  ping stayed unsent below the high water, with nothing armed.
- **"Ping timeout 60 s"**: readers at 32, 48 and 64 KiB/s read all 4 MiB, and none was
  failed in 200 s. A client gone would be failed 60 s after its ping, not 20 s.

websockets pings every 20 s and fails at 20 s, timed from the drain. coder, gorilla,
tungstenite and ws send no ping of their own (the [peer defaults](../research/2026-10-04-peer-defaults.md)).

**Decided by form, the recommended: "From queueing, as now".** Nothing changes.
- **A live client reading a backlog slower than about the backlog over the interval and the
  timeout is failed with 1011**: at 96 KiB/s and below after a 4 MiB burst on Linux
  loopback, where 112 KiB/s was kept.
  The cause is what the kernel holds ahead of the ping, which no server sees. A handler
  whose clients read slowly after large bursts can give a longer ping timeout,
  `CHEZ_WS_PING_TIMEOUT` (`(websocket limits)`).
- **A client that stops reading after its handshake is failed at the interval and the
  timeout:** 40.02 s after the take-over, whether nothing or 1 MiB had been sent, the
  kernel taking it (M4.3 step 3's review, Darwin). That needs the clock running. With
  pinging off, or with the queue full because the handler takes nothing, nothing is
  armed: a client that sent 17 messages and read nothing was not failed in 100 s.

