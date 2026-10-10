## Global Constraints

Every task brief in this project is bound by the following. They are the house rules chez-http-server and its siblings enforce, restated in chez-websocket's spellings.

- Toolchain floors: Chez Scheme 10.4.1 (the full system, threaded build; Petite is rejected), libuv 1.48.0 or later in the 1.x series (1.44.0 until the server's v0.4.1, which brings chez-libuv v0.8.0) through chez-libuv's own acquisition paths, which pass a system libuv below it over for the vendored build; CMake 3.10 or later where CMake is used, which is only that vendored build: libuv's CMakeLists asks for 3.10. The 3.26 written here until the v0.4.1 pin is the floor of chez-httparse's, uriparse's and byte-machine's own CMake presets, which this build never runs, as the server's global constraints say since its v0.4.1. Measured here 2026-10-04 on Darwin arm64 (Apple M1): Chez 10.4.1 `tarm64osx`, threaded; libuv 1.52.1; CMake 4.3.3.
- Dependencies are pinned checkouts by gitlink at release tags: chez-http-server, and through it the pins it carries (chez-libuv, chez-httparse with byte-machine under it, uriparse, chez-srfi for SRFI-64), each held at the commit its parent records. A pin moves alone, on its own commit, with a check that it moved. No other dependency without a decision record.
- The core is pure: its libraries import `(rnrs)` and this project's own pure libraries, and nothing else. Only the binding imports `(http-server)`, and only the binding and the tests import `(chezscheme)`. `make check-imports` (`tests/test-imports.sps`) holds it.
- Every `.sls` and `.sps` carries a `#!r6rs` line. Libraries contain their own code; no shared include bodies. Exported procedures carry a Typed-Racket-style signature comment.
- Exit-status vocabulary for Scheme lanes: 0 pass, 1 assertion failure(s), 2 harness/configuration/registration error (includes empty selection), 3 provenance failure. Empty selection is failure at every layer.
- Every `tests/test-*.sps` ends with its own `(exit ...)`; SRFI-64 sets no process status. Assertions compare against a value only success can produce, never `#f`, never bare truthiness.
- A test is finished when it has been watched to fail: the named mutation breaks the asserted property and nothing else, is recorded in the milestone's mutation log, and is reverted. A survivor is a missing test, a scope statement, or the finding itself, and which one is measured.
- Numbers in a test come from an oracle (an RFC's or FIPS 180's vector, a peer's measured behaviour, Autobahn's verdict), never from running the code under test.
- Socket tests bind `127.0.0.1:0` and cap by iteration count, never wall-clock. Timeout tests drive a fake clock.
- Every count that enters a record is re-measured on the tree at the time of writing, dated and platform-stamped; do not carry numbers forward by arithmetic.
- Conventional Commits. Run `make test` before every commit; fix failures first. CI is Linux only.
- Prefer a check to a comment: a load-bearing invariant becomes a make target, a test, or an assertion.
