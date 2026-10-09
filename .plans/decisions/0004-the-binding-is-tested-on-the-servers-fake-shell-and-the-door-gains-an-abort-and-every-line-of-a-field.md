# 0004: The binding is tested on the server's fake shell, and the door gains an abort and every line of a field

Date: 2026-10-08
Status: accepted (user decision, 2026-10-08, by form, M4.2: "Server's fake shell", "Door
change: abort" and "Every line, in the release", each the recommended). The door change
shipped in chez-http-server v0.4.0 (388ec43, tagged 2026-10-09), pinned here by M4.2.
Design: [the design](../2026-10-04-chez-websocket-design.md) §8 and §9

## Context

The binding's waits need a coroutine, which only the server's shells run (design §8).
Three questions of the design's §9 needed the server's door:
- a close the transport cannot force;
- a client that sends and does not read;
- a field split over lines.

Each was measured on chez-http-server v0.3.0, Darwin arm64, before the form.

**The driver.** The server keeps a fake shell in its `tests/`. It runs the server's own
core, parser and 101, the hand-off, coroutines and a fake clock.
- With the server's `tests/` on this project's library path, a taker shaped as the
  binding was driven through six of the prototype's seven scenarios as the binding needs:
  - a frame sent with the handshake, written back after the 101;
  - a read waking the parked `await`;
  - the deadline passing at 20,000 ms on the fake clock, and not at 19,999;
  - the drain call;
  - a close waiting 2 turns behind a write the client had not read;
  - the stream's close raising `&client-closed`, with no failure recorded.

  The form said "7 of 7". The seventh, a deadline asked for after the close, was one of
  the three differences below.
- None of the server's 23 test library names is one of this project's (measured again at
  v0.4.0: 23, none).
- The fake's door differed from the libuv shell's in three ways, each measured, and each
  for a client that stops reading:
  - a deadline asked for after the close was not armed;
  - a raise in a deadline's call escaped to the test;
  - a waiting thunk's raise closed the stream only after its write.

**A close the transport cannot force.** The probe:
- 16 MiB written to a client that read nothing, the close asked for, then a deadline of
  300 ms;
- the deadline passed at 496 ms, and the stream stayed open until the client left at
  2,998 ms;
- a raise in the deadline's call closed it at 497 ms, the server logging `taker-failed`;
- a prototype `transport-abort!` closed it at 498 ms, its write told `ECANCELED`, and
  nothing was logged.

**A field over two lines**, through the fake shell's parse: the first line, against every
line joined with a comma.
- A split `Connection` or `Upgrade`: 400, against 101.
- A split `Sec-WebSocket-Protocol`: the first line's offer, against the handler's
  preferred.
- Two `Sec-WebSocket-Key` lines, or two `Sec-WebSocket-Version` lines: 101, against 400.

## Decision

By form, the recommended of each:

1. **The binding is tested on the server's fake shell**, its `tests/` put on this
   project's library path, last. Weighed:
   - our own driver over the server's private scheduler: it copies about 115 lines of
     the fake's door, and skips the parse, the 101 and the hand-off;
   - a runner in the server: a release, and still no 101.
2. **The door gains an abort** (the server's decision 0024). `transport-abort!` closes
   the stream at once, dropping what is unsent. The binding aborts where it must close a
   client that does not read.

   Weighed: the binding raising there. It needs no server change, but `taker-failed`
   would be logged for every client that merely stopped reading, and the fake could not
   show it.
3. **The handshake reads every line of a field** (the server's decision 0024):
   `request-header-values`, its lines joined with a comma. Weighed:
   - the first line, documented;
   - the server's internal libraries.

The server's fake shell is made to do what its libuv shell does for a client that stops
reading, in the same release (its decision 0024's third item).

## Consequences

- **The pin.** The three shipped in chez-http-server v0.4.0, which this project pins
  from M4.2. That pin brings chez-libuv v0.7.4.
- **The fake shell is the server's test code, not its interface**, and nothing promises
  it across versions. So `tests/test-driver.sps` holds, through the pin, what the
  binding needs of it, and of the door's abort and every line of a field. A server pin
  that changes any of that fails there.
- **The send side's bound for a client that sends and does not read is still M4.3's**,
  to decide by form. It needs no door change, and closes such a client with the abort.
- **M4.3 tests the binding through the fake shell**, and on a real socket.
