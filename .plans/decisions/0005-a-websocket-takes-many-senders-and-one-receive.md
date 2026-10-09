# 0005: A WebSocket takes many senders and one receive

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, in M4.3 step 1's review: "Many
senders, one receive", the recommended). Amended 2026-10-09 by form (M4.3 step 3):
"call/cc", the recommended.
Design: [the design](../2026-10-04-chez-websocket-design.md) §6

## Context

M4.3's first binding kept one waiting receive and one waiting send per WebSocket, in a
slot each. But the server runs every connection's procedure on its own coroutine, and a
procedure may reach another connection's WebSocket. A chat server's broadcast sends to
every client from whichever procedure received the message. The review found:
- **A lost wake.** Two procedures waiting to send to one slow client overwrote each
  other's resume, and the first waited forever.
- **A wrong end.** A procedure waiting on another connection's WebSocket, whose own
  client left, ended that other connection (1006). A wait's `&client-closed` is about
  the stream of the coroutine that waits, not about the WebSocket it waits on.

Peers, read from their sources at their release tags (the review's research,
2026-10-09):

| peer | two receives at once | two sends at once | senders waiting on backpressure |
|---|---|---|---|
| websockets 17.2 | refused, `ConcurrencyError` (`asyncio/connection.py:302-306`) | allowed (`:914`) | all woken together (`:1054-1060`) |
| coder/websocket v1.8.15 | documented as not allowed (`conn.go:30`, `read.go:29`) | allowed, serialized (`write.go:27-28`) | the runtime's channel order |
| gorilla/websocket v1.5.3 | one reader (`doc.go:122-134`) | one writer; a detected second panics (`conn.go:616-626`) | none |
| tungstenite v0.30.0 | impossible by type (`&mut self`) | impossible by type | none: the write answers `WriteBufferFull` |
| ws 8.22.0 | no receive call: messages are events | allowed, queued | none: the caller watches `bufferedAmount` |

## Decision

By form, the recommended:
- **Any number of coroutines may send.** Those waiting past the high water all go on
  together once no more than the low water is unsent, as websockets wakes its drain
  waiters.
- **One receive may wait.** A second receive while one waits on the WebSocket is the
  caller's mistake: an assertion violation naming `websocket-receive`, as websockets
  refuses it.

Weighed:
- **"Many of both"**: receives queued, each message to the oldest. No peer documents
  it.
- **"One of each"**: gorilla's rule. A broadcast would need its own queue per client.

## Consequences

- **Each wait knows whose it is.** A waiter carries the WebSocket whose procedure runs
  on the coroutine that waits, from a parameter set around the procedure. The server's
  scheduler runs a parameterize's winders as a coroutine parks and resumes.
- **A wait's `&client-closed`** on the procedure's own WebSocket ends that wait, and the
  receive or send sees the connection's end. On another WebSocket it goes on out, to
  the procedure whose stream closed, and the other connection goes on.
- **The binding has a close call again** (`transport-on-close!`). Both of the server's
  shells tell the wait first, then run it. It marks the wait its procedure is in as
  ended, wherever it waits, so nothing wakes it, which would be a late resume. Then it
  steps the stream's end.
  - So a procedure that spends the `&client-closed` in a wait of its own still finds
    its WebSocket ended.
  - The driver suite's D-OUTSIDE holds that order: the close call is noted before the
    thunk's `&client-closed`.
- **A late resume after a handler's own deadline stays possible.** A message delivered
  in the turn a handler's `with-deadline` ends its receive wakes a wait that has ended,
  and the server logs `late-resume await`. The message stays queued. The server's waits
  give no way to ask whether a wait still stands, so this needs a door change (design
  §9).

## Amendment of 2026-10-09 (M4.3 step 3): a wait's way back is a full continuation

**The gap.** A receive or a send that waits needs a way back out of the server's `await`,
for the `&client-closed` its own stream's close raises there. `await` raises it with
`raise`, so a handler cannot return from it. The way back was `call/1cc`, a one-shot
continuation. The binding's comment said a `guard` "costs a waiting coroutine kilobytes".
Measured on a real socket, as the server measures its own connections, the one-shot
continuation held a stack segment of its own while the procedure waited:
- an idle WebSocket in `websocket-receive` held 11,096 to 11,414 B of heap after the 101,
  and 10,289 to 10,334 B after 10 echoes;
- the server's own idle connection held 1,793 to 2,073 B, and a raw taker parked at
  `await` 6,390 B.

The fake shell does not show it ([the measures](../research/2026-10-09-real-socket-measures.md)).

**The options, measured** (Darwin, 400 connections held by a python child):
- **"call/cc"**: 7,898 to 8,367 B after the 101, and 6,885 to 7,166 B after echoes. An echo
  round trip allocates the same within 0.5%.
- **"guard"**: 8,384 B and 6,723 B. The same allocation, and more lines change. It also
  disproves the binding's comment.
- **"Keep call/1cc"**: no change.

The binding suite passed 55 of 55 with each. websockets 17.1 documents 14 KiB a
connection with compression off; coder, gorilla, tungstenite and ws document none.

**Decided by form, the recommended: "call/cc".** `park!`'s way back is a full
continuation, and the comment says what was measured.

**Consequences:**
- **An idle WebSocket costs about 3 KB less**, about 8 KB in all. Most of it is the server's
  switched connection and its parked coroutine.
- **The socket suite holds it**: a procedure waiting in a receive holds less than 2 KiB a
  connection more than one at a bare `await`.
  - Measured in that suite's setting: 2,778 to 4,277 B more by `call/1cc`, and at most 980 B
    by `call/cc`, on Darwin and Linux.
  - Its mutant, `call/1cc` again, reddens that check alone.

