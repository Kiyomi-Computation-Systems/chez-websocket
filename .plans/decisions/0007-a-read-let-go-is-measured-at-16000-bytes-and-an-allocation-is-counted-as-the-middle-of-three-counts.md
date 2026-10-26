# 0007: A read let go is measured at 16,000 bytes, and an allocation is counted as the middle of three counts

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, before the server's v0.4.1 pin: "Fix
both checks here", the recommended). Amended the same day, #57's review: the counter is the
middle of three counts. Amended 2026-10-11: the 2.9 KB was the heap falling between
S-LETGO's two readings, which nothing keeps. Amended 2026-10-26, before the server's
v0.9.0 pin: S-LETGO's readings follow collections that mark no object in place.
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

Measured on Darwin arm64, 2026-10-09 ([the research record](../research/2026-10-09-real-socket-measures.md), its section "Before the server's v0.4.1 pin").

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
  drain without it. (Found on 2026-10-11, the amendment below: it keeps nothing.)

## Consequences

- **The pin moves to v0.4.1 alone.** Every suite passed on it, on Darwin and on Linux:
  twelve, 348 expected passes.
- **After a big message, v0.4.1 seemed to keep about 2.9 KB, and about 620 B a connection
  more than v0.4.0, until the next** (the amendment below). It keeps nothing: two 1-byte
  messages read the same (the amendment of 2026-10-11). A connection still
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

## Amendment of 2026-10-11 (the server's plan §14)

The server's plan listed what its full drain keeps after a big read (finding 4 above). It
settled the item by measurement on 2026-10-11, on its owner's form: **nothing is kept.**

- **The 2.9 KB is the heap falling between S-LETGO's two readings.** S-LETGO's shape, on
  this binding and the pinned server v0.5.0 (Darwin arm64), two runs each:

  | | a big message, then a small one | two 1-byte messages |
  |---|---|---|
  | one connection, 4,000 and 16,000 bytes | 2,880 to 2,984 B | 2,888 to 2,944 B |
  | ten connections, 4,000 bytes | 8,016 to 9,456 B | 8,544 to 9,536 B |

  Two readings near −54.8 KB, at ten connections, came where Chez gave the thread a fresh
  stack segment.
- **Why it falls.** Each wake's full capture, the server's since its decision 0025's
  review, uses up the thread's stack segment by the drain's depth, about 8 B a call,
  until Chez gives it a fresh one of about 64 KB. Ten connections are woken ten times a
  step. On v0.4.0 the drain was one-shot, and the heap did not fall so.
- **S-LETGO stands.** Its bound, half the 16,008-byte frame, is above the fall; a read
  kept still holds 16 KB more (R-20).
- **What the server's measuring found instead** was a waiting coroutine keeping the last
  value a wake handed it, and more of that kind, fixed in chez-http-server#178 for its
  next release. This binding wakes its receives with `#t`, so its connections never kept
  a message that way.

## Amendment of 2026-10-26 (before the server's v0.9.0 pin)

Run on the server's v0.9.0, S-LETGO went red in 4 of 6 runs of the socket suite, and in
none of 6 on v0.7.0 the same hour. The binding is the same on both.

- **The red readings** (the three differences, bound 8,004 B): −3,296, 9,040 and −61,544;
  −3,312, 9,080 and 2,840; −3,536, 9,256 and 2,960; −20,672, 26,496 and 2,840. One
  difference too high, its neighbour as far too low, and a third at the floor.
- **Nothing is kept.** S-LETGO's spike (`s-letgo-floor.sps`, 16,000 bytes) measured 2,880
  to 2,896 B, a big message then a small one, on both servers. A copy of the suite that
  read Chez's object counts by type at each reading found the live objects moving by the
  stack's floor alone, about 2.9 KB, and the live bytevectors not at all.
- **What moves is the heap no object owns:** `bytes-allocated` less every live object's
  bytes. On v0.9.0 it moved 5.8 to 6.9 KB, one way and then back, every third reading,
  in 7 of 9 runs; on v0.7.0 by 200 B at most, in 6 of 6.
- **The server's commit that brings it:** bisected over the server's history, it is
  #236's (d73b437), which keeps the handler's coroutine on the request's notice, and the
  connection on the notice, for the body's pull. Its parent moved it 96 B at most; it,
  6,768 B.
- **Why:** Chez's collector marks some objects of the oldest generation in place rather
  than copy them, and a segment it marks stays whole, the dead objects in it counted by
  `bytes-allocated` until a later collection frees them. With `in-place-minimum-generation`
  above the oldest generation, so that every live object is copied, the heap no object
  owns moved 32 B at most, in 5 of 5 runs on v0.9.0.

Measured on Darwin arm64, Chez Scheme 10.4.1.

### Decision

- **S-LETGO's readings follow two full collections that mark no object in place**:
  `footprint` collects with `in-place-minimum-generation` one above
  `(collect-maximum-generation)`. The 16,000-byte message and the bound, half its frame,
  stand.
  - Green: 10 of 10 runs on v0.9.0, and 4 of 4 on v0.7.0.
  - Kept, R-20's kind (the binding keeping each read's bytevector until the next read):
    red in 3 of 3 on v0.9.0, at 18,832 to 18,912 B, and on v0.7.0, in 2 of 2, at 18,816 to 18,992 B.

**Weighed, not taken:**
- **"The middle of the three differences"**, as the counter takes the middle of three
  counts. Every red run above had one difference off, and passes so. But that rests on
  the swing's shape, every third reading, which is the collector's to change.
- **"Count the live bytevectors"** by Chez's object counts. Exact for a kept bytevector,
  but blind to a read kept as anything else, and no longer the heap the rest of the
  suite's measures read.
- **"Ask the server to keep less"**: the notice keeps what its pull needs, and nothing it
  keeps grows. The dead objects are the collector's to count.

### Consequences

- **The fix lands on its own, before the pin**, green on v0.7.0; the pin's change runs it
  on v0.9.0.
- **The research spikes read the heap as before.** `ws-cost.sps` spreads 6 KB over 400
  connections, 15 B each; `s-letgo-floor.sps` did not swing in its own setting.
