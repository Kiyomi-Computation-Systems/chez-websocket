# M0 — mutation log

Every check in M0 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-04.
The suite mutants edit the vendored server, which `make check-pins` refuses, so
each ran the suite alone on the Makefile's library path. Every other mutant ran
its `make` target. All twelve were run again on the final Makefile, after
check-pins changed (below), with the same results.

| # | check | mutation | observed |
|---|-------|----------|----------|
| M0-1 | the library path (`make test`) | drop `$(SERVER_DIR)/src` from `LIBDIR_LIST` | exit 2; the suite exits 255, `library (http-server) not found` |
| M0-2 | the library path (`make test`) | drop a carried pin's `src/`, chez-httparse's | exit 2; the suite exits 255, `library (httparse decisions) not found`: the facade needs the pins the server carries |
| M0-3 | `make check-pins`, the server's pin | `SERVER_PIN` names v0.2.0's commit, 1c86771 | exit 2; `PIN MISMATCH: vendor/chez-http-server at 5528fa4…, expected 1c86771…` |
| M0-4 | `make check-pins`, a carried pin | chez-libuv checked out one commit back (765a0f4) | exit 2; `PIN MISMATCH` for chez-libuv, and `PIN DIRTY` for the server, whose gitlink it no longer matches |
| M0-4b | `make check-pins`, a carried pin | chez-srfi deinitialized | exit 2; `PIN MISMATCH: …/chez-srfi at <absent>`; the dirty check alone stays silent |
| M0-5 | `make check-pins`, the dirty check | a newline appended to uriparse's `README.org` | exit 2; `PIN DIRTY` for uriparse, and for the server, which sees its submodule's edit |
| M0-6 | `make check-help` | `prod` loses its `## ` description | exit 2; `check-help: 'prod' has no '## ' description` |
| M0-7 | door: a write of a bytevector alone | the server's `transport-write!` writes all but the last byte | exit 1; that check alone fails, 3 pass |
| M0-8 | door: a disarmed deadline | the server hands `0`, not `#f` | exit 1; that check alone fails, 3 pass |
| M0-9 | door: a read's bytes, then its end | the server hands the transport a procedure that drops the end | exit 1; that check alone fails, 3 pass |
| M0-10 | door: `await` refused before `register` | the server's `await` calls `register` before it asks for a coroutine | exit 1; that check alone fails, 3 pass |
| M0-11 | door: the refusal names `await` | the server's refusal names another verb | exit 1; that check alone fails, 3 pass |
| M0-13 | `make prod`, its closing `check-prod` | the suite runs without `FLAVOR=prod`, as first written | exit 2; chez-libuv relinks a dev shim before the suite (`relink-guard: shim provenance changed (flavor=dev …)`), and the closing `check-prod: FAIL: the counters moved …` |

All thirteen were reverted; `make test` is green afterwards (one suite, 4
expected passes, every pin ok), and so is `make prod`, whose two `check-prod`
runs pass with no relink between them.

Notes:
- **M0-4 is caught twice.** A carried pin that moves also makes the server's
  checkout dirty. The check that each carried pin sits where its parent
  records is what M0-4b alone reddens: `git status` reports nothing for a
  submodule that was never cloned.
- **M0-4b found a wrong message.** Its first run read `PIN MISMATCH: …/chez-srfi
  at 5528fa4…`, the server's commit: in a submodule that was never cloned,
  `git -C` climbs to the repository around it. The check failed as it should,
  but it named the wrong commit. `check_pin` now asks for the checkout's own
  `.git` first, and the dirty check skips a checkout that has none. The run
  above is after that change. chez-http-server's check-pins has the same
  shape.
- **M0-13 is a bug the targets' first run found.** `make prod` was the
  server's: build and check chez-libuv's prod shim, then `make test`. But the
  test's own build asks chez-libuv for its default flavor, dev, and chez-libuv
  relinks a shim built at another flavor. So the suite ran on a dev shim, and
  nothing said so. `prod` now runs the suite with `FLAVOR=prod`, and ends with
  chez-libuv's `check-prod`, which reads whatever shim the last build left. A
  first fix also passed `FLAVOR` on in `deps`. Its mutant, M0-12, survived:
  make hands a command-line `FLAVOR=prod` to every sub-make by itself, so that
  line was a redundant guard, and it went. M0-6 was run again, since `prod`'s
  help text changed. chez-http-server's `make prod` has the same shape.
- **M0-7 to M0-11 mutate the vendored server**, as chez-http-server's own M0
  mutated a vendored constant: each is the drift the pin guards against, read
  through the verbs the binding will call.
