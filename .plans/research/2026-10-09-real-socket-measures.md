# The binding on a real socket: what it costs, what the kernel holds, and the pong's timing

M4.3 step 3, 2026-10-09. The evidence for decision 0005's amendment ("call/cc") and 0001's
("From queueing, as now"), and for the design's §9 items measured here.

**Where.** Darwin 25.6.0 arm64, Chez 10.4.1, libuv 1.52.1. Linux 6.12.76-linuxkit aarch64 in
Docker, Ubuntu 24.04.5, libuv 1.48.0 (CI's), Chez 10.4.1. main at bb9c226, the server pinned
at v0.4.0 (388ec43).

**How.** Each probe ran the server's libuv shell on 127.0.0.1:0, as `tests/test-socket.sps`
does. Its clients ran on the same loop, or in a python child where the server's heap was
measured. A mutant or a prototype was a shadow copy of one library placed first on the
library path, so the repository was never edited.

## A connection's cost

The server's own method: its `.plans/research/spike/m7-exit-budget.sps`. A python child holds
the connections. The heap is read after two full collections, and a connection's cost is
(heap with 500 − heap with 100) / 400. Darwin only, since the Linux image has no python.

| a connection | heap, B |
|---|---|
| the server's, idle after a GET (its spike at v0.4.0, 24 holds) | 1,793 to 2,073 |
| a coroutine parked at an `await` (the same spike) | 3,634 |
| a raw taker, switched, its thunk parked at `await` | 6,390 |
| the binding, its procedure parked at a bare `await` | 7,519 |
| the binding, in `websocket-receive`, after the 101 (5 holds) | 11,096 to 11,414 |
| the same, after 10 echoes (5 holds) | 10,289 to 10,334 |

At v0.1.0 the server's records gave 1,875 to 1,971 B for an idle connection, and 3,637 to
3,639 B for a parked `await` (its design §5.2). Its v0.4.0 holds the same.

**A receive's wait.** Its way back out of `await`, for the stream's `&client-closed`, was a
one-shot continuation (`call/1cc`). Shadow bindings, a hold each:

| the way back | after the 101, B | after 10 echoes, B | an echo round trip allocates, B |
|---|---|---|---|
| `call/1cc` | 11,096 to 11,414 | 10,289 to 10,334 | 8,807 to 8,855 |
| `call/cc` | 7,898 to 8,367 | 6,885 to 7,166 | 8,868 to 8,872 |
| `guard` | 8,384 | 6,723 | 8,873 to 8,909 |
| none (wrong; the floor) | 8,222 | 7,287 | — |

The allocation is the whole process's, server and client, over 2,000 rounds, three times
each. The binding suite passed 55 of 55 with either of `call/cc` and `guard`.

In the socket suite's own setting (clients on the loop, 100 connections waiting at a bare
`await`, then 100 in a receive, the footprints back to back), a receive's wait held more
than an `await`'s by:

| | Darwin | Linux |
|---|---|---|
| `call/1cc`, probe | 2,778 to 3,485 | 4,237 to 4,277 |
| `call/cc`, probe | 78 to 294 | 879 to 980 |
| `call/1cc`, the suite | 4,006, 4,047 | 2,796 |
| `call/cc`, the suite (10 runs) | −439 to 911 | −432 to 335 |

The fake shell does not show it: about 170 B by `call/1cc` and −20 B by `call/cc` there.

**Peers.** websockets 17.1's documentation, read in a browser (`topics/memory.html`): "64 KiB
of memory for each connection" with its defaults, and "14 KiB per connection if you disable
compression entirely". coder, gorilla, tungstenite and ws document none.

## Re-arming at every read

An echo of a 5-byte text, 20,000 round trips, five times, twice each way. With the binding's
re-arm of the ping clock at every read it took 100.5 to 102.2 µs a round trip. A shadow that
never armed `ping` took 100.9 to 102.2 µs. No difference shows past the noise.

## What the kernel takes, and holds at a close

**Before anything is unsent.** A raw taker wrote 64 KiB pieces to a client reading nothing,
keeping 1 MiB outstanding, until no done had come for 2,000 turns:
- Linux: 2,560 KiB, three runs alike.
- Darwin, seven runs: 2,752, 1,600, 768, 768, 768, 3,392 and 704 KiB.
- The sysctls: Linux tcp_rmem 4096 131072 6291456 and tcp_wmem 4096 16384 4194304; Darwin
  sendspace and recvspace 131072, autorcvbufmax and autosndbufmax 4194304.

Through the binding, 16 KiB sends to a client reading nothing returned until it was behind:
- Linux: 175 sends, 2,867,900 B, three runs alike.
- Darwin: 77, 47, 47, 140, 47 and 47 sends, from 770,236 to 2,294,320 B.

**At a close.** The procedure sent B bytes, then closed; the close timeout was 1 s, and the
client read nothing for 3 s, then read:
- For B of 64 KiB and of 1 MiB, the client read every frame and the close, then EOF, on both
  platforms. All of it was in the kernel, every write done, so the close began at once. It
  was graceful: the shell disarmed the close timeout the binding had armed as it asked for
  the close.
- Darwin, 1 MiB, the client then reading nothing, netstat every 10 s: the server's side stayed
  in FIN_WAIT_2 with nothing to send, and the client's Recv-Q held 1,048,965 B, through the
  look at 60 s. By the look at 70 s both were gone. The client, reading at 180 s, read all
  1,048,965 B, then ECONNRESET.

## The pong's timing with a throttled reader

Linux, default limits: a ping after 20 s of quiet, 20 s for its pong. The procedure sent a
burst of 4 MiB as 1 KiB messages, then waited. A client on the loop read at a set rate and
answered each ping with a pong as it read it, as a browser does. Times are from the 101.

| rate, KiB/s | as built: the pong timed from the ping's queueing | a prototype: from the ping's done |
|---|---|---|
| 32 | failed 1011 at 127.9 s | 128.0 s |
| 48 | 85.7 s | 85.4 s |
| 64 | 64.1 s | 64.1 s |
| 80 | 51.3 s | 51.4 s |
| 96 | 43.0 s | 42.9 s |
| 112 | not failed; all read by 36.8 s | — |
| 128 | not failed; all read by 32.1 s, then pinged every 20 s | not failed; 32.2 s |

- **Each client failed was live.** It read all 4 MiB, then the ping and the close together.
- **The backlog ahead of the ping was in the kernel.** The core arms `ping` only once no more
  than the low water is unsent. So the ping's write is done nearly at once, and timing the
  pong from that done changes nothing.
- **With a ping timeout of 60 s**, readers at 32, 48 and 64 KiB/s read all 4 MiB, and none was
  failed in 200 s.

**A client that reads nothing.** Bursts of 2.7 to 4.9 MB, the two cores side by side, 100 s
each:
- **Up to 4.1 MB**, both were failed with `1011 ping-timeout`.
- **At 4.2 and 4.3 MB**, the as-built core failed it the same. The prototype logged nothing:
  its ping was unsent below the high water, and nothing was armed.
- **From 4.4 MB**, both were behind and failed by the write timeout.
- **So the kernel took 3.8 to 4.1 MB** from this client, which had read its 101. At 4.1 MB the
  binding was never behind, so the kernel held at least 4.1 MB less the high water. At
  4.4 MB it was behind, so the kernel held less than 4.4 MB less the high water.

## The late resumes and the read's bytevector

These are held by `tests/test-socket.sps`. Each was a survivor of step 1's review on the fake
shell, which logs no late resume.
- **The server's drain under a waiting receive.** R-6, R-7 and R-6b each logged
  `late-resume await`.
- **A send that waited, then the client's close.** K-50b logged three.
- **A read's bytevector, kept by R-20.** The heap after a message, less the heap after a
  1-byte one, was 1,016 B for a 1,000-byte message read at once, and 4,112 to 4,136 B for a
  4,000-byte one. Unmutated, it was 8 to 144 B.

## Step 3's review: the server's park, the suite's cap, and a client that stops reading

**The server parks its coroutines by `call/1cc`** (its scheduler's `suspend!`). A shadow
copy with `call/cc` there, on the server's scheduler alone, measured a coroutine parked at an
`await` some calls deep (Darwin): 2,000 at once for the heap, and 20,000 wake-and-park cycles
of one for the time and the allocation.

| depth | parked, `call/1cc` | parked, `call/cc` | a cycle, `call/1cc` | a cycle, `call/cc` |
|---|---|---|---|---|
| 4 | 3,836 to 3,864 B | 727 to 728 B | 131 to 136 ns, 403 B | 151 to 154 ns, 493 B |
| 16 | 4,056 B | 925 to 957 B | 125 to 140 ns, 403 B | 184 to 212 ns, 493 B |
| 64 | 4,784 B | 1,685 to 1,718 B | 136 to 141 ns, 403 B | 260 to 336 ns, 493 B |
| 256 | 7,696 B | 4,761 to 4,793 B | 137 to 143 ns, 403 B | 146 to 174 ns, 493 B |

- **Through the server's spike** (`m7-exit-budget.sps`'s last measure), a parked coroutine held
  3,639 to 3,660 B, and 640 to 679 B with the shadow.
- **An idle WebSocket**, the binding by `call/cc`, held 8,366 to 8,475 B after the 101 and
  6,709 to 6,798 B after 10 echoes; with the shadow, 4,867 to 4,879 B and 4,972 to 5,150 B.
- **An echo round trip** took 101.8 to 112.7 µs and allocated 8,682 to 8,764 B. With the
  shadow it took 98.9 to 106.4 µs and allocated 8,642 to 8,762 B.
- **The server's scheduler, waits, shell and contract suites** passed on the shadow: 21, 37,
  204 and 200.
- **The server's own records** say why one-shot (its design §5.1 and §5.2):
  - Its first spike timed suspend and resume alike either way, 30 to 36 ns.
  - A stale one-shot continuation fails at once, where a stale full one re-ran the program
    from inside `uv-run`.
  - It never measured the parked heap by `call/cc`.

So `call/cc` saves about 3 KB a parked coroutine at every depth, for 90 B and 20 to 200 ns
more a wake and park, and loses that loud failure. Decided by form, "A server slice next":
the change is the server's own slice, after this step, then a pin here.

**The suite's cap.** The most turns any of its waits took was 366 on Darwin (S-SILENT's 400 ms
of deadlines) and 205 on Linux. A turn with nothing to do took about 1.2 ms on Darwin (5,000
in 6,011 ms). At the old cap, 200,000 turns, a wait that never came would have run about 240
s, past `make test`'s 120 s.

**The park's reference, in the suite's setting.** 100 connections waiting at a bare `await`,
then 100 by `call/1cc` around `await` (the old `park!`'s shape), then 100 in a receive; the
heap back to back, five runs each:

| | by `call/1cc`, over `await` | a receive by `call/cc` | a receive by `call/1cc` |
|---|---|---|---|
| Darwin | 2,724 to 4,225 B | 12 to 1,027 B | 2,756 to 3,420 B |
| Linux | 3,908 to 3,971 B | 162 to 781 B | 3,325 to 3,337 B |

A receive by `call/cc` stayed under half the reference in every run, and one by `call/1cc`
over it.

**A client that stops reading after its handshake** (Darwin): failed at 40,020 and 40,024 ms
after the take-over, with 1 MiB sent first and with nothing, the ping's 20 s and the pong's
20 s. A client that sent 17 messages, which the handler never took, and read nothing, was not
failed in 100 s: with the queue full, reading and the ping clock stop, and nothing is armed.

## Before the server's v0.4.1 pin (2026-10-09)

The server's v0.4.1 (520f70e) parks its coroutines, and enters them, on full continuations
(its decision 0025). The evidence for 0005's amendment of this date ("Retire S-PARK") and
decision 0007 ("Fix both checks here").

**Where.** Darwin 25.6.0 arm64, Chez 10.4.1, libuv 1.52.1; and Linux aarch64 in Docker,
Ubuntu 24.04, libuv 1.48.0 (CI's), for the suites and S-LETGO's sizes. main at 43b18e7: v0.4.0
is the pinned checkout (388ec43), and v0.4.1 the server's own (520f70e, and a ledger commit).

**How.** Probes in the scratch `ws-spark/`, built from the socket suite's own helpers: a
server and its clients on one loop. A server's half-change was a shadow copy of its
`scheduler.sls` (and `waits.sls`) ahead of its `src/`; a binding mutant, a shadow copy of
the binding.

**S-PARK's setting:** 100 connections a path, each over 100 at a bare `await`, the heap back
to back, per connection. Three runs on each server, and two more with `park!` by `call/1cc`.

| | v0.4.0 | v0.4.1 |
|---|---|---|
| the reference, a wait by `call/1cc` around `await` | 2,792 to 4,048 B | −338 to 334 B |
| a receive, `park!` by `call/cc` | 462 to 984 B | 303 to 340 B |
| a receive, `park!` by `call/1cc` | 3,543 to 4,177 B | 453 to 490 B |
| a one-shot continuation escaped 4 calls deep, in the handler | 2,711 to 3,848 B | 3,436 to 3,557 B |
| the same, with no connection | 3,419 to 3,420 B | 3,419 to 3,420 B |
| a connection at a bare `await`, its client in the same heap | 7,907 to 8,484 B | 5,253 to 5,292 B |

**S-LETGO:** one connection, the heap after a big message less the heap after a 1-byte
one, three times (Darwin). The first of the three read about −61 KB in two of the probes,
a collection's; the rest:

| message | v0.4.0 | v0.4.1 | v0.4.1, drain one-shot | v0.4.1, park one-shot |
|---|---|---|---|---|
| 4,000 bytes | 104 to 112 B | 2,832 to 2,952 B | −168 to 200 B | 2,696 to 2,704 B |
| 16,000 bytes | 112 B | 2,872 to 2,952 B | | |
| 40,000 bytes | 112 B | 2,880 to 2,888 B | 0 B | |
| 400,000 bytes | 88 to 112 B | 2,872 to 2,880 B | 0 B | |

- Ten connections, 4,000 bytes: 976 to 1,120 B on v0.4.0, 9,344 to 9,360 B on v0.4.1.
- R-20 kept, at 16,000 bytes: 16,088 to 16,112 B on v0.4.0, 18,872 to 18,968 B on v0.4.1.
  At 40,000 bytes R-20 stayed green: the frame spans three reads of the server's
  16,384-byte buffer, and a kept read holds only the last.
- Linux, 16,000 bytes, two runs: 88 to 112 B, and 16,112 kept, on v0.4.0; 2,888 to
  2,928 B, and 18,896 to 18,920 kept, on v0.4.1.

**The binding suite's done count** (R-DONE-ALLOC-BEHIND), on v0.4.1, Darwin:
- the suite read 64 B in 4 of 7 runs, and 0 in 6 of 6 on v0.4.0, and 6 of 6 with the
  server's drain, or its park, alone one-shot again;
- per depth, the binding's and the taker's done counted 512 B at depth 0 and 576 B at
  100 and 200, an empty thunk 160 B at each;
- a copy of the suite with two print lines read 64 in 8 of 8 (the binding 416 B, the
  taker 352 B); at eight depths, 50 frames apart, it read 0, and R-ALLOC read −384 B;
- each count inside a `call/1cc`: 6 of 6 on both servers, on Darwin; the copy read 352 B
  for both in 4 of 4; on Linux every allocation check passed, 6 of 6 on v0.4.1.

### #57's review: the counter, measured again

Darwin arm64. Probes in the scratch `ws-spark/rv/`.
- **Plain Chez, no server.** An empty thunk, a 1 KiB bytevector, and thunks 50, 150 and
  400 frames deep, each counted at all 401 depths from 0 to 400, before and after a full
  capture. Every count was alike, whether counted directly or inside a `call/1cc`: 160 B,
  1,200 B, and 160 B for the deep ones.
- **The server's scheduler alone.** A coroutine woken and parked again, and one spawned and
  parked, each counted three times:

  | counted | wake, v0.4.0 | wake, v0.4.1 | spawn, v0.4.0 | spawn, v0.4.1 |
  |---|---|---|---|---|
  | 100 frames apart | 448 / 65,968 / 448 | 576 / 512 / 512 | 66,192 / 66,192 / 672 | 736 / 736 / 736 |
  | inside a `call/1cc` | 65,968, each | 512 / 448 / 448 | 66,192, each | 736 / 672 / 672 |
  | both | 448 / 65,968 / 448 | 512 / 512 / 512 | 66,192 / 66,192 / 672 | 672 / 736 / 736 |

- **The binding suite's done check, per call** (the binding's, then the taker's, each
  three calls 100 frames apart, an empty thunk 160 B throughout). In the layouts that
  failed: the binding 576 / 576 / 576 and the taker 512 / 576 / 576, the same counted
  inside a `call/1cc`, under a full `call/cc`, or neither, on v0.4.0 and v0.4.1 alike.
  Counted in pairs, the binding's call and the taker's at each depth: 64 / 0 / 0 on
  v0.4.1, and 64 / −64 / 0 on v0.4.0.
- **The binding suite, whole**, by counter:
  - the least of three, each inside a `call/1cc` (#57's): 6 of 6 on each server, though it
    counts a v0.4.0 wake as a new segment every time (above);
  - the least of three, 100 frames apart, each inside a `call/1cc`: 6 of 6 in one layout,
    and 1 of 6 once a helper procedure was added, on v0.4.1;
  - the middle of three, 100 frames apart, with or without a `call/1cc`: 6 of 6 on each
    server, each way.

## For v0.1.0, on the server's v0.5.0 (2026-10-11)

A connection's cost measured again for the first release (M6, by form: "Re-measure on
v0.5.0"). The README's "about 8 KB" was M4.3's figure at v0.4.0; the v0.4.1 pin's
measure above was the socket suite's setting, not this one.

**Where.** Darwin 25.6.0 arm64, Chez 10.4.1, libuv 1.52.1. The tree is M6's release
branch on main's 270ce0e, the server pinned at v0.5.0 (02ef95d) with chez-libuv v0.9.0.
Darwin only: the Linux image has no python.

**How.** The server's own method, as in [A connection's cost](#a-connections-cost):
a probe in the scratch `ws-cost/` starts the server's libuv shell on 127.0.0.1:0 with a
handler that accepts `/ws` with an echo procedure and answers anything else 200. A
python child holds the connections, says `ready`, and closes them when its stdin
closes. The heap is read after two full collections, once the child is ready, every
connection is the server's, and every procedure waits in `websocket-receive` (a count
around the receive says so). A connection's cost is (heap with 500 − heap with 100) /
400. Every hold ended with the child's exit 0 and no connection left. None of the
`CHEZ_WS_` variables was set.

| an idle connection, five holds each | heap |
|---|---|
| a WebSocket, its procedure in `websocket-receive` after the 101 | 5,281 to 5,435 B |
| the same, after 10 echoes of a 2-byte text | 5,353 to 5,477 B |
| the server's own connection, idle after a GET | 1,900 to 2,055 B |

Measured twice: first on fcbc598's tree, then on 270ce0e's, once #72 had merged (its
change is the Autobahn lane's `run.sh` alone). The table is the second's; the first gave
5,194 to 5,372 B, 5,316 to 5,524 B and 1,818 to 1,967 B.

The first row is the README's figure, about 5.3 KB. M4.3's, 7,898 to 8,367 B, was before
the server parked its coroutines by `call/cc` (its v0.4.1, decision 0025).
