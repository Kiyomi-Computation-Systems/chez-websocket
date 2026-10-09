# 0007: A read let go is measured at 16,000 bytes, and an allocation is counted as the middle of three counts

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, before the server's v0.4.1 pin: "Fix
both checks here", the recommended). Amended the same day, #57's review: the counter is the
middle of three counts.
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
  - Let go: 112 B on v0.4.0, and 2,872 to 2,952 B on v0.4.1; on Linux, 88 to 112 B and
    2,888 to 2,928 B.
  - Kept (R-20): 16,088 to 16,112 B on v0.4.0, and 18,872 to 18,968 B on v0.4.1; on
    Linux, 16,112 B and 18,896 to 18,920 B.
  - At 40,000 bytes the frame spans three reads, and a kept read holds only the last.
    R-20 stayed green there (`m4-mutations.md`).
- **`allocated` counts each call inside a `call/1cc`**, whose receiver Chez runs on a stack
  segment of its own, rather than at three depths. (Superseded the same day: the middle
  of three counts, made 100 frames apart, with no `call/1cc`; the amendment below.) The binding suite passed 6 of 6 on both
  servers. The copy that read 64 in 8 of 8 read 352 B for the binding and the taker alike,
  in 4 of 4.

**Weighed, not taken:**
- **"Server drain back to call/1cc"**: a server v0.4.2 whose drain is one-shot again. Both
  checks would then pass here unchanged. But a fresh coroutine that waits once would
  allocate 4,256 B again, where 1,177 to 1,242, and a request that waits 10,255 to
  10,556 B through the server, where 7,160 to 7,877 (the server's decision 0025's review).
- **"Find the server's mechanism first"**: why a full drain keeps about 2.9 KB, and about
  620 B a connection more than v0.4.0, after a big message, and a server change that keeps the full
  drain without it.

## Consequences

- **The pin moves to v0.4.1 alone.** Every suite passed on it, on Darwin and on Linux:
  twelve, 348 expected passes.
- **After a big message, v0.4.1 keeps about 2.9 KB, and about 620 B a connection more
  than v0.4.0, until the next** (the amendment below). It is recorded here and not fixed. A connection still
  holds less than on v0.4.0: 5,253 to 5,292 B at a bare `await`, where 7,907 to 8,484
  (0005's amendment of this date).
- **Every suite's allocation checks count the same way** (the middle of three counts, since
  the amendment below).
- **The checks' killers ran again** on both servers, each red as named (`m4-mutations.md`):
  R-20 for S-LETGO, and those of R-ALLOC, R-DONE-ALLOC, R-DONE-ALLOC-BEHIND, W-ALLOC and
  W-TAIL-ALLOC.

## Amendment of 2026-10-09 (#57's review)

A /code-review (xhigh) over #57 reported eight findings. On the owner's "fix all", three
forms decided the choices among them, each the recommended: "Record the gap", "Server
plan's open list" and "A stacked PR on #57".

- **S-LETGO checks that each frame came whole** (finding 1). A transport over the shell's
  counts the reads that bring 16,008 bytes or more. Unless all five big frames came so,
  the suite stops at status 3: the oracle has gone. Back at 40,000 bytes (PV-40K), or
  with the count's note dropped (PV-NONOTE), it stops so.
- **The counter is the middle of three counts, made 100 frames apart, with no `call/1cc`**
  (findings 2, 5 and 8). The decision above, a `call/1cc` around each count, is
  superseded. Measured (Darwin arm64):
  - On plain Chez, at 401 depths, with thunks from 0 to 400 frames deep, every count was
    alike, either way. So the 64 B is not a stack segment's end.
  - Near the server's scheduler, a coroutine's wake counted:

    | | v0.4.0 | v0.4.1 |
    |---|---|---|
    | 100 frames apart | 448 / 65,968 / 448 B | 576 / 512 / 512 B |
    | each inside a `call/1cc`, as #57 had it | 65,968 B, every call | 512 / 448 / 448 B |
    | 100 frames apart, each inside a `call/1cc` | 448 / 65,968 / 448 B | 512 / 512 / 512 B |

    65,968 B is a new stack segment.
  - With the `call/1cc` inside the three depths, the done check read 64 B again, in 5 of
    6 runs on v0.4.1.
  - Through the server's fake shell, a taker's write's done counted 512 B, then 576 and
    576. In the layouts that failed, the binding's counted 576 three times. Counting under
    a full `call/cc` changed nothing. A `guard` in the fake shell's `taker-call!` wraps
    both.
  - The least of the three then reads 64 B when only one side's first call counts 512.
    The middle of the three passed the binding suite in every run. On Darwin: 6 of 6 on
    each server, `make test` once on v0.4.0 and three times on v0.4.1, and run 4's two
    baselines. On Linux: 6 of 6 on v0.4.1, and `make test` twice on each server.
  - Two counts off the same way defeat it: on v0.4.0 a coroutine's spawn and park counted
    66,192 B at two depths of three. No check counts one.
- **The connection figure** (finding 7). With ten connections, v0.4.1 kept 9,344 to
  9,360 B, about 720 B more for each after the first; v0.4.0 kept 976 to 1,120 B, about
  104 B more for each. So v0.4.1 adds about 620 B a connection.
- **What a waiting receive holds** (finding 3, "Record the gap"): 0005's amendment of this
  date, and the socket suite's header.
- **What the server's drain keeps** (finding 4, "Server plan's open list"): the server's
  plan, its "Open, and not sliced" list (chez-http-server#161).
- The counter's comment says 4 of 7 runs, as the context above does (finding 6).
