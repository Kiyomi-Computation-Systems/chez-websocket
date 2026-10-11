# The Autobahn lane: the suite, its peers, and what it measured (2026-10-09)

For [decision 0008](../decisions/0008-autobahn-runs-on-every-pr-against-an-echo-server-at-16-mib-gated-both-ways-on-a-ratchet-that-lists-what-was-measured.md), M5.
Sources read at tags; numbers quoted from raw files, not summaries.

## Autobahn|Testsuite 25.10.1

Tag v25.10.1, commit 6ed6f439dc7ed0d7432fe2cf7481b110905ecc5c, `autobahntestsuite/autobahntestsuite/`.

- **The image.** `crossbario/autobahn-testsuite:25.10.1@sha256:519915fb568b04c9383f70a1c405ae3ff44ab9e35835b085239c258b6fac3074`,
  linux/amd64 alone, 15 layers, 388,877,802 B compressed (`docker manifest inspect`), 1,038,104,806 B
  on disk. `FROM pypy:2-7-bullseye`; its `CMD` runs the fuzzing server, so a fuzzing client run names
  its command (`wstest -m fuzzingclient -s ...`).
- **The cases.** 517 in its registry; 1.* to 10.* are 301, since 12.* and 13.* (216) are
  permessage-deflate's and there is no 11.*. 9.9.1 is commented out.
- **9.* and 10.1.1** (`case/case9_*.py`, `case10_1_1.py`):

  | cases | payload | sent as | wait |
  |---|---|---|---|
  | 9.1.1-9.1.6 text, 9.2.1-9.2.6 binary | 64 KiB, 256 KiB, 1, 4, 8, 16 MiB | one frame | 10-100 s |
  | 9.3.1-9.3.9 text, 9.4.1-9.4.9 binary | 4 MiB | fragments of 64 B to 4 MiB | 100 s |
  | 9.5.1-9.5.6 text, 9.6.1-9.6.6 binary | 1 MiB | one frame, written in chops of 64 B to 2 KiB | 1000 s |
  | 9.7.1-9.7.6 text, 9.8.1-9.8.6 binary | 0 B to 4 KiB | 1,000 round trips | 60-480 s |
  | 10.1.1 | 64 KiB text | auto-fragmented at 1,300 B | 10 s |

  Over 1 MiB: 24 cases (9.1.4-6, 9.2.4-6, 9.3.*, 9.4.*). Exactly 1 MiB: 14 (9.1.3, 9.2.3, 9.5.*, 9.6.*).
- **Verdicts** (`case/case.py`). `behavior`: OK, NON-STRICT (a SHOULD not kept, still conformant),
  INFORMATIONAL (forced by 7.1.6, 7.13.1, 7.13.2), FAILED, UNIMPLEMENTED (12.*, 13.* without
  compression). `behaviorClose`: OK, FAILED, UNCLEAN, WRONG CODE, FAILED BY CLIENT, INFORMATIONAL.
- **The index** (`fuzzing.py`, `json.dumps(..., sort_keys = True, indent = 3)`): an object holding
  the agent, holding each case: `behavior`, `behaviorClose`, `duration`, `remoteCloseCode` (null when
  none came), `reportfile`.
- **Exit status.** wstest exits 0 when cases fail, and a connection that fails
  (`Connection to ... failed`) stops the run there, still 0.
- **The close.** The client expects the server to drop TCP within 1 s of the closing handshake
  (autobahn-python 0.10.9, `protocol.py`, `serverConnectionDropTimeout = 1`), else UNCLEAN.
- **The NON-STRICT cases** (`case3_2.py`, `case3_4.py`, `case5_15.py`): OK expects the echo of the
  message sent before the bad frame; NON-STRICT expects none. 3.2 sends its frames back to back;
  3.4 sends each a byte at a time (`chopsize = 1`).

## Peers

At tags: python-websockets 17.2 (a1664f4), ws 8.22.0 (297202c), tungstenite-rs v0.30.0 (7f4aeaf),
coder/websocket v1.8.15 (9c8faad), gorilla/websocket v1.5.3 (ce903f6), Deno v2.9.7 (0c07124),
uWebSockets v20.80.0 (3ffd6f4).

| peer | where it runs | pinned by digest | echo cap for the lane, default | passes | expectations file |
|---|---|---|---|---|---|
| python-websockets | by hand (`compliance/README.rst`) | no | 32 MiB, 1 MiB | read by eye | its README notes |
| ws | scripts, not in CI | — | default, 100 MiB | none | no |
| tungstenite-rs | every PR, its own job, and by hand | no | default, 64 MiB | each case exactly (`jq` + `diff`) | `autobahn/expected-results.json` |
| coder/websocket | daily CI, as a client | no | 1 GiB, 32 KiB | OK, NON-STRICT, INFORMATIONAL | no |
| gorilla/websocket | by hand | no | unlimited, unlimited | read by eye | no |
| Deno | its release job | yes, this digest | default, 64 MiB | OK, NON-STRICT, INFORMATIONAL, `behavior` alone | no |
| uWebSockets | its Linux build, and by hand | yes, this digest | 100 MiB, 16 KiB | OK, NON-STRICT, INFORMATIONAL, both fields | no |

- python-websockets notes NON-STRICT for 3.2, 3.3, 4.1.3, 4.1.4, 4.2.3, 4.2.4, 5.15 (its library
  closes before the app echoes) and 6.4.1-6.4.4, and FAILED for 7.1.5.
- tungstenite records 6.4.3 and 6.4.4 NON-STRICT, and 7.1.6, 7.13.1, 7.13.2 INFORMATIONAL.
- **Failing a connection.** python-websockets (`protocol.py` `fail`, `discard`): a server sends its
  close, sends EOF (a half-close), and drops what arrives until the client's EOF. ws
  (`websocket.js` `receiverOnError`, `close`): it stops parsing but keeps reading and dropping,
  sends its close, then `socket.end()`; a 30 s timer destroys the socket if the client never ends.

## Measured

Darwin 25.6.0 arm64 (Docker Desktop 29.2.1, an aarch64 VM, Autobahn emulated); Linux in Docker:
6.12.76-linuxkit aarch64, `chez-libuv-noble-scratch:10.4.1` (Ubuntu 24.04, Chez 10.4.1, libuv
1.48.0, prod shim). The echo server is `tests/autobahn/echo.sps`, the server at v0.4.1 (520f70e).

**Full runs, cases 1.* to 10.*:**

| where | cap | runs | OK | NON-STRICT | INFORMATIONAL | FAILED | stopped short |
|---|---|---|---|---|---|---|---|
| Linux, echo in a container on a docker network | 16 MiB | 13 | 291 | 7 | 3 | 0 | 0 |
| Linux, the same | 1 MiB | 3 | 267 | 7 | 3 | 24 | 0 |
| macOS, echo on the host, via `host.docker.internal` | 16 MiB and 1 MiB | 11 | | | | | 3 |

- Linux: each run 13 to 16 s of wstest, the same verdicts in every run of a cap. The 24 FAILED at 1
  MiB each closed 1009, in all 3 runs.
- macOS: a run stopped short when a connection to the echo server timed out (at 6.17.2, 9.3.3 and
  6.20.4), after the three cases below. Complete runs took 19 to 43 s. One of 3.4, 4.1.5 and
  4.2.5 or more came out NON-STRICT in 4 of the 11 runs. At 1 MiB, 7 of 96 over-cap cases (4 runs) carried no close code.
- 2,000 WebSocket connections opened from the Mac to the echo server there, one after another
  (ws 7.5.10): none failed; the slowest opened in 12 ms.

**The ten cases with a bad frame after a message, alone, 30 runs each:**

| case | Linux NON-STRICT | of which no close | macOS NON-STRICT |
|---|---|---|---|
| 3.2, 3.3, 4.1.3, 4.1.4, 4.2.3, 4.2.4, 5.15 | 30 each | 0 | 30 each |
| 3.4 | 12 | 2 | 3 |
| 4.1.5 | 11 | 0 | 2 |
| 4.2.5 | 14 | 1 | 2 |

**The lost close, a raw client** (a 4 MiB text frame in 64 KiB writes against a 1 MiB cap; the
control sends a frame with a reserved bit, then nothing):

| server | 4 MiB, close frame read | ends | control |
|---|---|---|---|
| macOS (Node 20.10.0 client) | 0 of 100 | 59 EPIPE, 41 ECONNRESET | 1002, a clean end, 100 of 100 |
| Linux (the image's Python 2 client) | 100 of 100, 1009 | 86 EOF, 14 ECONNRESET | 1002, EOF, 100 of 100 |

The server logged `message-too-big` 100 times on each. Its core writes the close and closes the
stream (`protocol.sls` `fail!`); the server's `taker-close!` stops reading and closes the handle
once its writes are done (`shell.sls`), with no half-close.

**The lane's speed here:** the image pulled in 17 s; `make autobahn` took 23 s on macOS.

## Measured at M5's review (2026-10-10)

- **A run that never connects** (nothing listening at the URL): wstest prints `Connection to
  ... failed`, exits 0, and writes `index.json` as `{}`.
- **Chez's native transcoder keeps CRs:** `(native-eol-style)` is `none`, and a line
  `1.1.1 OK OK 1000\r\n` reads back with its CR.
- **The echo server in a container** (`tests/autobahn/echo.Dockerfile`, Docker Desktop on
  macOS, aarch64):
  - the first build took 242 s, 226 s of it compiling Chez 10.4.1, and 7 s after a change
    to the tree;
  - the image is 138 MB;
  - a full run took 14 s, every case as the ratchet holds it;
  - `make autobahn` took 248 s from no image, and a warm run 17 s;
  - `make docker-smoke` took 6 s, its HEALTHCHECK ready and the server stopped.
- **The varying cases, paired:** all 180 of the 60 flip runs' verdicts for 3.4, 4.1.5 and
  4.2.5 are among the ratchet's whole verdicts.
- **CI's job start:** a job started 3 to 4 s after its run was created, and its `Set up job`
  took 1 s (runs 38016701245, 38016703127).

## Measured again on the server's v0.5.0 (2026-10-11)

The server's v0.5.0 (02ef95d, pinned here by #69) half-closes a taken stream and lingers
(its decision 0026). Measured the same day against v0.4.1 (520f70e, this repository at
2879eb0) as the control. Darwin 25.6.0 arm64, Docker Desktop 29.2.1 (8 CPUs). The echo
server is `tests/autobahn/echo.sps` in `chez-libuv-noble-scratch:10.4.1` (aarch64, libuv
1.48.0, the prod shim) on the network `ab-net`, and Autobahn emulated. The runs are M5's
flips: the ten bad-frame cases, one wstest a run.

**3.4, 4.1.5 and 4.2.5, three tries a run:**

| cell | runs a server | v0.4.1 NON-STRICT | v0.4.1 no close | v0.5.0 NON-STRICT | v0.5.0 no close |
|---|---|---|---|---|---|
| as M5 | 30 | 1 of 90 | 0 | 4 of 90 | 0 |
| the echo held to 0.25 CPU | 30 | 3 of 90 | 0 | 2 of 90 | 0 |
| the echo and a busy loop on one CPU | 30 | 32 of 90 | 1 (3.4) | 27 of 90 | 0 |
| the same, alternating blocks of 50 | 150 | 137 of 450 | 0 | 127 of 450 | 0 |
| **all** | 240 | 173 of 720 | **1 of 720** | 160 of 720 | **0 of 720** |

- M5's rate of NON-STRICT, 37 of 90, came back only with the echo server contending for
  a CPU. A CPU quota alone does not slow a server that is mostly idle.
- The seven cases that are always NON-STRICT were NON-STRICT OK 1002 in every run, on both
  servers.
- So on Linux these cases show the lost close too rarely to tell the servers apart: v0.4.1
  lost the 1002 once in 720 tries.

**The lost close, M5's raw clients** (`rst.js` and `rst.py`, unchanged): a 4 MiB text frame
in 64 KiB writes against a 1 MiB cap, 100 connections a row, and the control (a reserved
bit, then nothing):

| where | server | close frame read | ends | control |
|---|---|---|---|---|
| macOS, the echo on the host (Node 20.10.0) | v0.4.1 | 1009 in 70 of 100 | 74 EPIPE, 26 ECONNRESET | 1002, a clean end, 100 |
| | v0.5.0 | 1009 in 100 of 100 | 100 clean | 1002, a clean end, 100 |
| Linux, the echo on `ab-net` (the image's Python 2) | v0.4.1 | 1009 in 100 of 100 | 94 EOF, 6 ECONNRESET | 1002, EOF, 100 |
| | v0.5.0 | 1009 in 100 of 100 | 100 EOF | 1002, EOF, 100 |

The server logged `message-too-big` 100 times in each row. M5 measured v0.4.1 on macOS at 0
of 100 read; today 70, every connection still ending in an error.

**The lane on the new ratchet** (`make autobahn`, the echo in its image on Docker Desktop):
three full runs, each 301 cases as the ratchet holds them, 7 or 8 NON-STRICT.
