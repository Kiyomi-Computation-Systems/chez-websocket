# 0006: A client that does not read is aborted, and past the high water reading stops and a write timeout runs

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, M4.3 step 2: "Reading stops past
the high water" and "60 s, its own variable", each the recommended). Where the binding
aborts is the design's to name (0004), and was not asked.
Design: [the design](../2026-10-04-chez-websocket-design.md) §5–§7 and §9

## Context

A client that stops reading leaves the server's writes unsent. Two gaps in the design's
§9 come from it:
- **A close the transport cannot force.** `transport-close!` waits for every write, so
  a close the binding asks for never finishes.
- **A client that sends and does not read.** Nothing in the core bounds it.

0004 gave the server's door an abort, `transport-abort!`, for both.

**Measured on main, 1d8ed80** (the server's fake shell, Darwin arm64, 2026-10-09). The
client reads nothing after the 101, and an hour of fake time runs.

| case | what happens |
|---|---|
| any close the binding asks for: the close timeout, the pong timeout, a 1002, a close's echo, the stream's end | the close waits behind one write of 4 to 7 B, for the hour |
| a send waiting past the high water, the queue full | reading stops, nothing is armed, for the hour |
| the same, the client pinging every 10 s | each ping re-arms the clock; 734 B of pongs held after the hour |
| 1 MiB of 125-byte pings | all read; 1,016,514 B of pongs held |

A client that does read, but slowly, also fails. With 300 messages of 1 KiB sent and one
write read a second, it is failed with 1011 at 45 s, 255 sent: the pong's time starts as
the ping is queued, behind 255 KiB (§9).

**Three bounds, prototyped and measured the same way**, with the time 20 s:

| | reading stops past the high water | a send waits at most a time | the handler's own deadline |
|---|---|---|---|
| a send waiting, the queue full | aborted at 25 s | aborted at 25 s | for the hour |
| the same, the client pinging | aborted at 25 s, 14 B held | aborted at 25 s, 18 B held | for the hour |
| 1 MiB of pings | reading stopped at 274,432 B in; 265,938 B held | 1,016,514 B held | 1,016,514 B held |
| the slow reader | all 300 sent by 197 s | aborted at 25 s, 255 sent | failed at 45 s |
| a send and its done, a client reading | 1,381 B; about 382 ns | 1,381 B; about 365 ns | 1,381 B; about 357 ns |
| a send that waits | +65 B, the prototype's appends | +565 B, its `with-deadline` | 0 |
| what changes | the core and the binding | the binding | the docs |

The slow reader still fails under the first, at 237 s. Once reading starts again, its
ping waits behind the low water's 64 KiB, and the pong's time runs from the queueing
(§9; step 3).

**Peers**, read at their release tags, citations checked by hand:
- **Closing.**
  - websockets 17.2 sets a deadline of `close_timeout`, 10 s, as it sends a close, then
    calls `transport.abort()` (`asyncio/connection.py:910-911`, `:942-957`).
  - ws 8.22.0 destroys the socket 30 s after its close (`websocket.js:1323-1327`,
    `constants.js:10`).
  - coder/websocket v1.8.15 gives the close 5 s each way, then closes the connection
    (`close.go:185`, `:199`; `conn.go:164`).
  - gorilla/websocket v1.5.3 leaves closing to the application.
- **A send waiting.** None bounds one itself.
  - websockets' `drain()` waits with no time (`connection.py:1072-1078`).
  - ws never waits (`sender.js:563-571`).
  - coder and gorilla take the caller's context or write deadline (`conn.go:171-182`;
    gorilla `conn.go:783-790`).
- **Pongs.**
  - websockets and ws answer every ping, whatever is unsent (`protocol.py:690-694`;
    `websocket.js:1265`).
  - coder and gorilla write each pong inside the read, under 5 s and 1 s (coder
    `read.go:303`, `:323`; gorilla `conn.go:35`, `:1158-1169`). So reading waits for
    the write.

## Decision

1. **Where the binding aborts** (the design's to name, as 0004 asked).
   - Every close the binding asks for gives the client the close timeout to read what
     was written; then the stream is aborted. The binding arms the transport's deadline
     for the close timeout, its call `transport-abort!`, and then asks for the close.
     When nothing is unsent the close begins at once, and both shells disarm the
     deadline as a close begins.
   - When the close timeout passes, the server's close unanswered, the core answers
     `(abort-stream)`: the client has had its time. websockets' rule.
2. **Reading stops past the high water** (by form).
   - The core counts what is written and not yet sent, as it counts the queue. Each
     write's done is stepped as `(written nbytes)`, whatever it says.
   - Once more than the high water is unsent, the client is behind: reading stops, the
     ping clock with it, and the write deadline runs while the connection is open.
     After the server's close, the close deadline goes on in its place.
   - Each done while behind re-arms the write deadline. One that leaves no more than
     the low water ends it, and reading starts again, the clock afresh, unless the queue
     is full.
   - A send waits while the client is behind.
   - The write deadline passing aborts the stream, writing nothing. It logs
     `websocket-failed` with no code and `write-timeout`, lets go of any read waiting
     for the queue, and tells 1006.
3. **60 s, its own variable** (by form): `CHEZ_WS_WRITE_TIMEOUT`, 60 s by default, the
   server's own `CHEZ_HTTP_WRITE_TIMEOUT`. At least 1 s: one of 0 would pass as reading
   stopped.

Weighed:
- **"A send waits at most a time".** Only the binding changes, but pongs to a pinging
  client stay unbounded, as in websockets and ws, and a slow reader is cut.
- **"The handler's own deadline".** coder's and gorilla's way, the caller's. Nothing is
  bounded unless every handler wraps every send.
- **"The ping timeout, 20 s".** No new variable, but no setting of its own, and shorter
  than the server's own write timeout.

## Consequences

- **What a client that does not read can make one connection hold** is the high water,
  256 KiB by default, and the one write that passes it: a send's frame, or a pong,
  since a read stops at the pong that passes it. That is beside 0001's two caps of
  messages.
- **Time is still a deadline's kind** (design §5): the core names `write`, and the
  binding arms it for the write timeout. The core gains an event, `(written nbytes)`,
  an action, `(abort-stream)`, and `ws-behind?`. The binding keeps no unsent count of
  its own.
- **A send waits on the core's word.** It waits while `ws-behind?` says so, and all
  waiting sends go on as a done ends it (0005), or at the end.
- **While behind, nothing is read**, a ping or a close included. A client's close that
  waits is read when reading starts again, or at the close timeout or the stream's end.
  At the write timeout it is let go.
- **A slow reader is no longer cut by the send side**, while each write is done within
  the write timeout of the last. It can still be failed by the pong's timing (§9),
  which step 3 measures with a throttled reader.
- **On a real socket** the kernel takes some writes before any is unsent, so these
  bounds start later; step 3 measures by how much.
