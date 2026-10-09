# 0007: A read let go is measured at 16,000 bytes, and an allocation is counted on a stack segment of its own

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, before the server's v0.4.1 pin: "Fix
both checks here", the recommended).
Design: [the design](../2026-10-04-chez-websocket-design.md) §8

## Context

The server's v0.4.1 parks its coroutines, and enters them, on full continuations (its
decision 0025). Run on it, two checks went red besides S-PARK (0005's amendment of this
date), and neither through anything the binding does.

- **S-LETGO**, a read's bytevector let go after its step. The heap after a 4,000-byte
  message stayed 2,832 to 2,952 B above the heap after a 1-byte one. The bound was 2,004 B,
  half the frame, and v0.4.0 measured 104 to 112 B.
  - It is not the message: at 40,000 and 400,000 bytes it was 2,872 to 2,888 B. With ten
    connections it was 9,344 to 9,360 B, where v0.4.0 measured 976 to 1,120.
  - It goes with the server's drain. With the drain alone on a one-shot continuation again,
    it measured 0 to 200 B; with the park alone, 2,696 to 2,704 B.
- **R-DONE-ALLOC-BEHIND**, a write's done the core answers by re-arming the write timeout
  allocates nothing in the binding, no more than a taker's. It counted 64 B more in 4 of 7
  runs of the binding suite, and in none of 6 on v0.4.0.
  - Each count was the least of three calls, made 100 frames apart (`(ws-testing)`). There
    the same done counted 512 B at depth 0 and 576 B at 100 and 200, the binding's and the
    taker's alike. When the binding's three all counted 576, the check read 64.
  - It follows the code's layout. A copy of the suite with two print lines added read 64
    in 8 of 8 runs. Calls at eight depths, 50 frames apart, moved the miss to R-ALLOC, at
    −384 B.
  - With the server's drain alone, or its park alone, one-shot again, it passed 6 of 6.

Measured on Darwin arm64, 2026-10-09 ([the research record](../research/2026-10-09-real-socket-measures.md), its last section).

## Decision

- **S-LETGO sends a 16,000-byte message.** It is one frame of 16,008 bytes, read at once
  into the server's 16,384-byte read buffer, and the bound is half the frame, 8,004 B.
  - Let go: 112 B on v0.4.0, and 2,872 to 2,952 B on v0.4.1; on Linux, 112 B and 2,920
    to 2,928 B.
  - Kept (R-20): 16,088 to 16,112 B on v0.4.0, and 18,872 to 18,968 B on v0.4.1; on
    Linux, 16,112 B and 18,912 to 18,920 B.
  - At 40,000 bytes the frame spans three reads, and a kept read holds only the last.
    R-20 stayed green there (`m4-mutations.md`).
- **`allocated` counts each call inside a `call/1cc`**, whose receiver Chez runs on a stack
  segment of its own, rather than at three depths. The binding suite passed 6 of 6 on both
  servers. The copy that read 64 in 8 of 8 read 352 B for the binding and the taker alike,
  in 4 of 4.

**Weighed, not taken:**
- **"Server drain back to call/1cc"**: a server v0.4.2 whose drain is one-shot again. Both
  checks would then pass here unchanged. But a fresh coroutine that waits once would
  allocate 4,256 B again, where 1,177 to 1,242, and a request that waits 10,255 to
  10,556 B through the server, where 7,160 to 7,877 (the server's decision 0025's review).
- **"Find the server's mechanism first"**: why a full drain keeps about 2.9 KB, and about
  720 B more a connection, after a big message, and a server change that keeps the full
  drain without it.

## Consequences

- **The pin moves to v0.4.1 alone.** Every suite passed on it, on Darwin and on Linux:
  twelve, 348 expected passes.
- **After a big message, v0.4.1 keeps about 2.9 KB, and about 720 B more for each
  connection, until the next.** It is recorded here and not fixed. A connection still
  holds less than on v0.4.0: 5,253 to 5,292 B at a bare `await`, where 7,907 to 8,484
  (0005's amendment of this date).
- **Every suite's allocation checks count on fresh segments.**
- **The checks' killers ran again** on both servers, each red as named (`m4-mutations.md`):
  R-20 for S-LETGO, and those of R-ALLOC, R-DONE-ALLOC, R-DONE-ALLOC-BEHIND, W-ALLOC and
  W-TAIL-ALLOC.
