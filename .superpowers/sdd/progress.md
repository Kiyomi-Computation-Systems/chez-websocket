# chez-websocket — subagent-driven development ledger

`progress.md` is the spine; `global-constraints.md` binds every task brief. Read both before starting slice work. Close-outs are recorded here.

---

M-1 — PLANNING. Branch `docs/planning-record`. 2026-10-04.

**Where it began.** In chez-http-server, on the owner's "Let's begin the websocket path", four forms decided the library (that repository's decision 0022): a sibling library, this one; code that reads with a call that waits; RFC 6455 alone; Autobahn in Linux CI. On "Create it now" the repository was made, private, its first commit the siblings' BSD 3-Clause license (27ad906). The server then gained the door change this library needs, decision 0023 (a take-over may answer `(awaiting thunk)`), and released it as v0.3.0, tagged on 5528fa4 on 2026-10-04.

**Delivered:**
- **The brief** (`.plans/2026-10-04-chez-websocket-project-brief.md`): the goal, what is settled and where, where the library stops, the pure core and the binding, the facts it starts from, the milestones in outline, the standing risks.
- **This ledger and `global-constraints.md`**, the server's house rules in this project's spellings.
- **`AGENTS.md`**, the server's, with this project's dependency (chez-http-server at a release tag, carrying chez-libuv, chez-httparse and uriparse).
- **`README.org`** says the project is in planning, and **`CHANGELOG.md`** holds an empty Unreleased.

**Measured environment, 2026-10-04:** Darwin 25.6.0 arm64 (Apple M1, 8 cores). Chez Scheme 10.4.1 `tarm64osx`, threaded; libuv 1.52.1 (Homebrew pkg-config); CMake 4.3.3; Docker 29.2.1.

**Not done here:** no code, no Makefile and no CI. They are M0's, stacked on this.

NEXT: M0, the skeleton, stacked on this branch. Then the design and the milestone plan, with their decisions by form.

---

M0 — THE SKELETON. Branch `feat/m0-skeleton`, stacked on `docs/planning-record`. 2026-10-04.

**The pin.** chez-http-server is a submodule at `vendor/chez-http-server`, pinned at v0.3.0 (5528fa4). The pins it carries are used through it, each held at the commit its parent records: chez-libuv d46654c (v0.7.3), chez-httparse 0b7058e (v0.4.5) with byte-machine c338a57 (v0.7.0) under it, uriparse 5ecd88f (v0.6.2), chez-srfi 7879b52. A server pin that moves brings them along, with nothing here to restate. The server's test client, vtest2, is not cloned.

**The Makefile** has the server's targets: `help`, `check-help`, `submodules`, `check-pins`, `deps`, `build`, `dev`, `run`, `test`, `prod` and `clean`. `check-pins` checks:
- the server at `SERVER_PIN`;
- each carried pin at its parent's gitlink, and absent counts as a mismatch;
- no checkout with tracked edits.

The library path is `src`, `tests`, the server's `src/`, then the carried pins' `src/` and SRFI-64's link tree.

**CI** is the server's Linux job without its test clients:
- ubuntu-24.04, with Chez 10.4.1 built from source and cached;
- `make submodules` reads the private repositories through `SUBMODULES_READ_TOKEN`, and a step before checkout stops the run by name if the secret is missing;
- then check-pins, build, test and check-help.

**Not yet green on GitHub:** this repository has no secrets. The owner adds `SUBMODULES_READ_TOKEN`, with Contents read-only on chez-http-server, chez-libuv, chez-httparse, uriparse and byte-machine.

**The first suite, `tests/test-door.sps`, runs the door through the pin.** The server's facade loads from the library path. Its verbs behave as v0.3.0 documents them, and the binding will call them:
- a transport made of procedures hands a write of a bytevector alone as all of it, with no procedure to tell;
- a disarmed deadline is handed `#f` twice;
- a read's bytes, and then its end, reach the taker's procedures;
- `await` on no coroutine is refused, naming `await`, before `register` runs.

Four checks; `(ws-testing)` is the server's `(testing)`, named apart.

**Tests first.** The suite ran red before the build (`library (srfi :64) not found`, exit 255). Its first run after the build hit a mistake of mine: `bytevector` is Chez's, not R6RS's, so it is now `u8-list->bytevector`.

**Twelve mutants, each red** (`m0-mutations.md`). The absent-pin mutant found that `git -C` in a submodule that was never cloned climbs to the server and names its commit. `check_pin` now asks for the checkout's own `.git` first, and every mutant was run again on the final Makefile.

**`make prod` ran the suite on a dev shim**, found by running every target once before the merge. `make clean`, `run`, `dev` and `prod` had not run, and `prod` passed while testing the wrong thing. After building and checking chez-libuv's prod shim, its `make test` asked chez-libuv for the default flavor, dev, and chez-libuv relinked. `prod` now runs the suite with `FLAVOR=prod` and ends with chez-libuv's `check-prod`, which reads what the last build left. That was red first, then green. A pass-through of the flavor in `deps` survived its mutant, since make hands a command-line variable to sub-makes, and was taken out. chez-http-server's `make prod` has the same shape (M0-13 in `m0-mutations.md`).

**README.org** gains the CI badge and how to build.

`make test` green before the commit (Darwin arm64): one suite, 4 expected passes, every pin ok (six); `make prod` green, its two `check-prod` runs with no relink between.

NEXT: the design and the milestone plan, with their decisions by form; then M1, the primitives.

---

THE DESIGN AND THE MILESTONE PLAN (SDD rungs 2 and 3). Branch `docs/design-and-plan`, stacked on `feat/m0-skeleton`. 2026-10-04.

**The survey.** A Sonnet agent read five peers' server defaults from source at their release tags, with file and line for each (`.plans/research/2026-10-04-peer-defaults.md`): Python websockets 17.2, coder/websocket v1.8.15, gorilla/websocket v1.5.3, tungstenite v0.30.0, ws 8.22.0. I checked four of its citations again by hand against the fetched files: websockets' timeouts, `max_size`, `max_queue` and `write_limit`; coder's read limit; tungstenite's two sizes; ws's `maxPayload` and close timeout. One fact is measured here: `uv-tcp-keepalive!` is called nowhere in the server's `src/`, so the server enables no TCP keepalive.

**DECIDED (0001), by form, each the recommended:**
- **"1 MiB" cap**, websockets' default. A frame that would pass it fails 1009 before its payload is held.
- **"Read on, ping".** The server reads on while a handler is busy, queueing whole messages up to a cap's worth, then stops reading. It answers pings at once. A client quiet for 20 s is pinged, and no pong within 20 s fails 1011: websockets' 20 s/20 s.
- **"Whole messages"**: `websocket-receive` returns a string or a bytevector.

**The design** (`.plans/2026-10-04-chez-websocket-design.md`):
- the libraries: six pure ones and a binding;
- the opening handshake's checks and answers;
- the frame codec's refusals;
- the protocol as a pure step, `ws-step`, with tagged-list events and actions, its deadlines named by kind as the server core's are;
- the binding over the transport and the waits;
- six environment variables;
- testing, and what is decided later (Origin and the binding's test driver in M4).

Taken without a form, each with its source:
- `&websocket-closed`, raised by every receive and send once the connection has closed, after the queued messages;
- subprotocols in the handler's order, none matching still succeeding (coder's and gorilla's way);
- the close timeout, 10 s (websockets');
- the send water marks, 256 KiB and 64 KiB (the server's own).

**The plan** (`.plans/2026-10-04-chez-websocket-milestone-plan.md`): M1, SHA-1, base64 and UTF-8; M2, the frame codec; M3, the protocol in three slices; M4, the handshake, the test driver and the binding; M5, Autobahn; M6, v0.1.0.

**Corrected while writing.** The first draft had the core reading the time from `(tick now)` events. A quiet-client clock needs the time when bytes arrive, and the core reads no clock. So the core names a deadline's kind (`ping`, `pong`, `close`) and the binding arms it, as the server's core does.

`make test` green before the commit (Darwin arm64): one suite, 4 expected passes, every pin ok. Nothing tested changed.

NEXT: M1.1, SHA-1, when the owner asks; the three PRs first go through review and the closing ritual. CI stays red at its token step until the owner adds `SUBMODULES_READ_TOKEN` here.
