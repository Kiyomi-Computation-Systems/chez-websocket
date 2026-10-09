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
  was graceful, and the close timeout never armed.
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
