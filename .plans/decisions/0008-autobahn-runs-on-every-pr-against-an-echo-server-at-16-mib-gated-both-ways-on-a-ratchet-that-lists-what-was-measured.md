# 0008: Autobahn runs on every PR against an echo server at 16 MiB, gated both ways on a ratchet that lists what was measured

Date: 2026-10-09
Status: accepted (user decision, 2026-10-09, by form, each the recommended: "Here and in
CI", then "16 MiB", "Server slice after the lane" and "Every PR and push", then "List what
was measured"). Amended 2026-10-10, M5's review: "Container on Docker Desktop", "Keep both
building on a miss".
Plan: [the milestone plan](../2026-10-04-chez-websocket-milestone-plan.md) M5
Design: [the design](../2026-10-04-chez-websocket-design.md) §8, §9

## Context

M5 is the Autobahn lane: Autobahn|Testsuite's fuzzing client against an echo server built
from this library, in Linux CI, gated on its `index.json`, with a ratchet holding each case's
verdict (chez-http-server's decision 0022). Pulling the image needed the owner's word.

- **The image.** `crossbario/autobahn-testsuite:25.10.1`, digest
  `sha256:519915fb568b04c9383f70a1c405ae3ff44ab9e35835b085239c258b6fac3074`, the one 0022
  recorded; the registry's manifest still named it on 2026-10-09. It is built for
  linux/amd64 alone: 15 layers, 388,877,802 bytes to download, 1,038,104,806 bytes on disk.
  It pulled here in 17 s.
- **The cases.** 1.* to 10.*, 301 of them: 12.* and 13.* are permessage-deflate's, and
  there is no 11.*. The 9.* cases echo messages up to 16 MiB: 24 are over 1 MiB, and 14
  exactly 1 MiB.
- **Its exit status is no verdict.** wstest exits 0 whatever its cases show, and a connection
  that fails ends its run there, still 0 (its `fuzzing.py`).
- **Measured** (the [research record](../research/2026-10-09-autobahn-lane.md)): the echo
  server on Linux arm64 in Docker (Ubuntu 24.04, libuv 1.48.0, the prod shim), Autobahn under
  emulation, each full run 13 to 16 s.
  - At a 16 MiB cap: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL, the same in 13 runs. At the
    default 1 MiB: 24 of the 291 FAILED, each closed 1009, the same in 3 runs.
  - **NON-STRICT, 7:** 3.2, 3.3, 4.1.3, 4.1.4, 4.2.3, 4.2.4 and 5.15 send a message, then a
    frame the server must fail, back to back. The core reads both at once and fails before
    the handler has echoed the message. Autobahn's strict verdict wants the echo first, and
    calls the rest conformant. python-websockets records the same seven, and 6.4.x.
  - **Either, 3:** 3.4, 4.1.5 and 4.2.5 send the same a few bytes at a time. OK in all 16
    full Linux runs; but run alone, 30 times, NON-STRICT 12, 11 and 14 times. On macOS, 3, 2
    and 2 times in 30, and one of them or more in 4 of 11 full runs.
  - **INFORMATIONAL, 3:** 7.1.6, 7.13.1 and 7.13.2, as the cases themselves say.
- **macOS reaches the echo server through Docker Desktop**, which has no host network: the
  container connects to `host.docker.internal`, which it forwards to the Mac's loopback.
  There 3 of 11 full runs stopped short, a connection timing out. With the echo server in a
  Linux container, none of 21 did; and 2,000 connections opened from the Mac itself all
  opened, the slowest in 12 ms.
- **A lost close.** When the server fails a connection, its core writes the close and closes
  the stream at once (design §4, RFC 6455 §7.1.7). If the client is still sending, closing a
  socket with its bytes unread makes the kernel reset the connection, and a reset can destroy
  the close before the client reads it.
  - A client streaming a 4 MiB message at a 1 MiB cap got no close frame in 100 of 100 tries
    on macOS. On Linux it got 1009 in 100 of 100, but 14 ended in a reset.
  - The control, a bad bit and then nothing more sent, got 1002 and a clean end, 100 of 100
    on both.
  - In Autobahn at a 1 MiB cap: 7 of 96 over-cap cases on macOS (4 runs), and 0 of 72 on
    Linux (3 runs); on Linux, 3 of 90 lone runs of the three varying cases.
  - The server's own HTTP closes half-close and linger for exactly this (its decision 0011). A
    taken stream's close does not: `taker-close!` stops reading and closes the handle once
    its writes are done. python-websockets and ws both send their close, half-close, and
    drop what comes until the client ends.
- **Peers** (from source, at tags; the research record). tungstenite runs Autobahn on every
  PR and holds every case's verdict in a file, compared exactly. uWebSockets runs it in its
  Linux build, Deno in its release job, and coder/websocket daily. Deno, uWebSockets and coder
  pass OK, NON-STRICT and INFORMATIONAL on every case, with no file. python-websockets and
  gorilla run it by hand. Deno and uWebSockets pin this digest.

## Decision

1. **The image is pulled here and in CI** ("Here and in CI"), by digest, by `make autobahn`.
2. **The echo server's cap is 16 MiB** ("16 MiB"), the suite's largest message, set through
   `CHEZ_WS_MAX_MESSAGE_BYTES` in the lane's environment alone. The library's default stays 1
   MiB.
3. **CI runs the lane on every PR and push, in a job of its own** ("Every PR and push"). The
   setup both jobs need is one composite action, `.github/actions/setup`.
4. **The gate** reads `index.json` against `tests/autobahn/verdicts.txt`: each case's
   behavior, behaviorClose and the close code the server sent, held both ways, as
   chez-http-server's ratchet holds its corpora (its decision 0008). A verdict that moves
   either way fails, and so does a case only one side has, so a run that stops short fails.
   The gate's status is the suites': 0, 1, or 2 for what it cannot read.
5. **A case measured to vary lists what was measured** ("List what was measured"): 3.4,
   4.1.5 and 4.2.5 each `OK|NON-STRICT OK 1002|none`, and pass with any of them. Every other
   case is exact.
6. **The lost close is a chez-http-server slice, after the lane** ("Server slice after the
   lane"): a taken stream's close half-closes and lingers as the server's HTTP closes do.
   Then its release, pinned here alone, and `none` measured again.

Taken without a form, by precedent:
- The gate is Scheme, `(ws-autobahn)`, with a JSON reader of its own, as the server reads
  oha's report. No JSON library is pinned.
- `make autobahn` starts the echo server in an environment of its own (`env -i`), so no
  `CHEZ_HTTP_` or `CHEZ_WS_` variable of the caller's changes what the cases see.
- On macOS it goes through `host.docker.internal`, and a run that stops short fails the gate,
  which says why.

**Weighed, not taken:**
- **"CI only"**: never pulled here, each look at the verdicts a push and a run (Deno,
  coder/websocket). **"Not yet."**
- **"Both, as two agents"**: 1 MiB and 16 MiB in one run, the default's 24 FAILED gated too.
  **"The default, 1 MiB"**: 24 FAILED, by design.
- **"Here, in the protocol"**: a failure keeps the stream open, dropping what comes, until the
  client's end or the close timeout; with no half-close in the door, the client sees no end
  until then. **"Open list only."**
- **"Daily"** (coder/websocket); **"Releases only"** (Deno).
- **"NON-STRICT passes everywhere"** (Deno, uWebSockets, coder): loses which seven are
  reliably non-strict. **"Make them strict first"**: the binding lets a waiting handler run
  before it reads further frames of the same read, so all ten score OK; a design change of
  its own, unmeasured.

## Consequences

- `make test` holds the gate itself (`tests/test-autobahn.sps`): 13 suites, 368 expected
  passes. Its mutants, and the lane's own, are in `m5-mutations.md`.
- `make autobahn` needs Docker, and on macOS a run sometimes stops short.
- CI time grows by the lane's job, beside the suite's.
- Until the server slice's pin, a client still sending when the server fails it may not read
  the close: always on macOS, rarely on Linux.

## Amendment of 2026-10-10 (M5's review)

A /code-review (xhigh) over #60-#63 reported fourteen findings. The owner said "fix all".
Two forms decided the choices among them, each the recommended.

- **"Container on Docker Desktop".** On macOS and Windows the echo server runs in a Linux
  container, beside the fuzzing client on a Docker network of its own. Linux and CI keep the
  host network.
  - Through Docker Desktop's forwarding, 3 of 11 macOS runs had stopped short. With the echo
    server in a container, none of 26 did.
  - Windows had taken the host network's path, which Docker Desktop lacks.
  - The image is `tests/autobahn/echo.Dockerfile`: multi-stage, Chez from its release, the
    tree under `/app`, run as a user of its own, with a HEALTHCHECK on `/health/ready`.
    `make echo-image` builds it and `make docker-smoke` checks it starts, is ready, and
    stops.
  - Measured on macOS: the first build took 242 s, 226 s of it compiling Chez, then 7 s
    after a change. The image is 138 MB, and a warm run took 17 s.
  - On the host the echo server takes any free port and reads it back from its `listening`
    line, no longer port 9001.
- **"Keep both building on a miss".** On a Chez cache miss both jobs still build Chez, about
  171 s each, since a job ahead of them would add about 8-10 s to every run. A run by hand
  with `chez-cache-salt` misses the cache, so the setup action's build-and-save path is
  proven now.

**Fixed without a form:**
- **The ratchet lists whole verdicts,** `" | "` between them. A pairing of fields never seen
  no longer passes: 3.4 OK with no close code was admitted before. 4.1.5 lists the two
  verdicts measured; 3.4 and 4.2.5 list three. All 180 of the flip runs' verdicts are listed.
- **An empty index, `{}`,** is read as a run of no case. wstest writes it when no connection
  opened, measured. The gate had called it a harness error.
- **The short-run hint** says how many of the ratchet's cases did not run, and that the log
  says whether a connection failed. It no longer names a cause.
- **`make autobahn` checks the pins**, as `make test` does.
- **A CRLF checkout reads alike.** The gate drops a CR before a LF; Chez's native transcoder
  keeps it (eol style `none`, measured). `.gitattributes` keeps the scripts and the ratchet LF.
- **`gate-main`, in `(ws-autobahn)`, is gate.sps's body.** A wrong count of paths, a path it
  cannot read, or any raise at all is status 2.
- **`tests/test-autobahn-run.sps` holds `run.sh` without Docker.** A stand-in for docker plays
  the run.
  - It holds the stale index, the caller's environment, a server that ends early or without
    stopping, a failing docker, two runs at once, and a run told to stop.
  - That last showed a trap that let the script carry on: a signal now exits, and the exit
    stops the server.
- **The tally and the suite's line reader** share `(ws-autobahn)`'s code.

`make test`: fourteen suites, 381 expected passes. The mutants are in `m5-mutations.md`.
