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
