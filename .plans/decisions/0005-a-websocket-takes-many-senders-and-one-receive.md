# 0005: A WebSocket takes many senders and one receive

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, in M4.3 step 1's review: "Many
senders, one receive", the recommended).
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
