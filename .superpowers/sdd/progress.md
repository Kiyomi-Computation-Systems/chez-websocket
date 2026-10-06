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

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **the planning record, M0 and the design and plan, as three stacked PRs** (the three entries above), bottom-up.
- **#1, the planning record,** as 8b05b85. Its tree is c7932e7's, and its parent is 27ad906, the license. It kept its branch, since #2 was based on it. It had no CI: docs only, with the workflow arriving in #2.
- **#2, M0 and its `make prod` fix,** as 3e6ca8b. It was retargeted to main and rebased from c7932e7: its two commits now sit on 8b05b85 at 6d81e2e, which has the tested tree (4f44296's). The squash has the same tree, and its parent is 8b05b85.
- **#3, the design and the plan,** as b4ebf9c. It was retargeted and rebased from 4f44296 to cde6d08, which has the tested tree (06423bb's). Then, before the merge, 7d223cb corrected one sentence of decision 0001: it had said the quiet-client ping works as websockets' does, but websockets pings every 20 s whether the client is quiet or not, and only the numbers are the same. The squash has 7d223cb's tree, and its parent is 3e6ca8b.
- **CI.** Each merged on `linux` SUCCESS at its head: #2 on 6d81e2e (run 37291030695) and #3 on 7d223cb (run 37291382024; cde6d08's, 37291194670, had passed too). Each run had 1 suite, 4 expected passes, and the six pins checked in two steps.
- **Main's own runs.** The run on #2's squash, 37291161874, was main's first. It built Chez from source, since a PR's cache is not visible to main. #3 merged only after it had finished, so it was not cancelled. The run on #3's squash, 37291611106, was green too, and this reflect was pushed after it.
- **Branches.** All three deleted, local and remote. No PR is open.
- **The ritual's script.** The server's `move-up.sh` checks that a rebased tip's parent is main, which fails for a PR of two commits. Its copy here checks that the branch's commits sit on main, by count, beside the tree.

`make test` green on main: one suite, 4 expected passes, every pin ok.

NEXT: M1.1, SHA-1 (`(websocket sha1)`, RFC 3174's vectors and RFC 6455's example digest; `make check-imports` begins), when the owner asks.

---

M1.1 — SHA-1. Branch `feat/m1.1-sha1`. 2026-10-05.

**`(websocket sha1)`**: `sha1 : Bytevector -> Bytevector`, RFC 3174 over a padded copy of the message, in `(rnrs)` alone. It is for the accept value only (RFC 6455 §4.2.2).

**`tests/test-sha1.sps`, twelve checks:**
- RFC 3174 §7.3's four test cases, each pattern repeated as its driver repeats it;
- RFC 6455 §4.2.2's digest of its example key and the GUID;
- six inputs at the padding's edges, 0, 55, 56, 63, 64 and 65 bytes, whose digests are two peers' that agreed, Perl's Digest::SHA and OpenSSL;
- what a hash allocates, which the plan did not ask for (below).

**`make check-imports` starts**, as the plan says. It is a suite, `tests/test-imports.sps`, which `make test` runs with the others and the target runs alone. It reads each library under `src/` with Chez's own reader, and holds its imports to `(rnrs ...)` and pure `(websocket ...)` libraries, named plainly. Every library is pure until M4 brings the binding. It has one check per library, one today.

**Tests first.** The suite ran red before the library existed (`library (websocket sha1) not found`, exit 255). Then all eleven vector checks were red against a stub that returned twenty zero bytes (exit 1). Then green.

**Departed from the plan: the allocation check.** Measuring the first version found 5,888 bytes allocated for each block: Chez 10.4.1 allocates for a `+` or a bitwise call of four or more arguments, which the schedule's xor and the step's sum were. They are now nested calls of three. A hash allocates its padded copy, its schedule and its digest, and nothing else: 832 bytes for the 60-byte key and GUID, down from 12,608. The twelfth check holds the slope: ten blocks more allocate exactly their padded copy's 640 bytes more.

**A source garbled.** A summarizing fetch of RFC 3174 printed TEST3's digest wrong (`3C CD 4C DA` for `3C D4 C4 DA`). So every vector was read from the RFCs' raw text, and both peers agree with each published digest.

**Thirty-two mutants** (`m1-mutations.md`), each with the checks it would redden named before the run, and every one matched:
- the padding off by one each way reddens the 55-byte check alone, and the two 56-byte checks;
- hashing only the first block reddens exactly the eight inputs of two blocks or more;
- three allocation mutants redden the allocation check alone;
- eight import mutants: six imports refused, an empty `src/` exits 2, and a file that is not a library is named.

One survives by construction: a length field written as 32 bits agrees below 512 MiB, recorded as a scope statement.

`make test` green before the commit (Darwin arm64): three suites, 17 expected passes, every pin ok. `make prod` green.

NEXT: M1.2, base64, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **M1.1** (the entry above), from #4, as 53fa639.
- **The squash** has 6feb8ba's tree (719688a), the head CI tested, and its parent is 33534e7.
- **CI.** #4 merged on `linux` SUCCESS at 6feb8ba (run 37294481730): three suites, 17 expected passes, the allocation check among them green on Linux as on the laptop. Main's run on the squash, 37295886274, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m1.1-sha1` deleted, local and remote. No PR is open.

`make test` green on main: three suites, 17 expected passes, every pin ok.

NEXT: M1.2, base64 (`(websocket base64)`: RFC 4648 §10's vectors both ways, a decode's refusals, then RFC 6455's accept value), when the owner asks.

---

FIX — `make prod` ON A FRESH CLONE. Branch `fix/prod-on-fresh-clone`, cut from main at 304639d. 2026-10-05.

On the owner's ask. chez-http-server's #136 fixed the same gap there, and its entry found it here.

**Measured first** (Darwin arm64, Apple M1; GNU Make 3.81, git 2.50.1, Chez 10.4.1, libuv 1.52.1). A fresh worktree of main at 304639d, its submodule never cloned (`git submodule status` shows `vendor/chez-http-server` with a leading `-`). `make prod` stopped at its first line: `make: *** vendor/chez-http-server/vendor/chez-libuv: No such file or directory.  Stop.`, then `make: *** [prod] Error 2`, exit 2. Nothing was cloned or built. 53fa639, before the reflect above landed, gave the same; its Makefile is the same blob.
- `prod` had no prerequisite, and its first line enters chez-libuv, inside the server's checkout.
- `test` reaches `submodules` only through `build` and `deps`, after that line.
- No other rule enters a submodule first: `deps` names `submodules`, the rest reach it through `build`, and `clean`'s chez-libuv line ignores its error.

**Fixed.** `prod` depends on `submodules`, as the server's does. The comment above it gains one sentence saying why. The three recipe lines are unchanged; the first, `$(MAKE) -C $(LIBUV_DIR) prod`, stays on the owner's word.

**Green**, exit 0 in 9 s, in the same worktree with the fixed Makefile laid in (blob 0a3fd1f, this commit's):
- `submodules` cloned six checkouts, each at its pin: the server, chez-libuv, chez-httparse with byte-machine under it, uriparse and chez-srfi;
- chez-libuv's `prod` linked the shim once, at `-O2`, and its `check-prod` passed;
- the suite ran on that shim: three suites, 17 expected passes (door 4, imports 1, SHA-1 12), every pin ok;
- the closing `check-prod` passed.

No relink-guard line appears anywhere in the run, and nothing is linked between the two `check-prod` runs. On the prod shim the count is the same as `make test`'s, each measured: no suite here reads chez-libuv's counters, so none skips a check, as six of the server's do.

**On a cloned checkout** (this worktree, once `make test` had cloned it), `make prod` passed too, exit 0 in 3 s. `submodules` printed its three commands and cloned nothing. The rest ran as above.

**Watched to fail.** One mutant of the fixed Makefile, cut by exact match: the cut refuses a string found other than once. It ran with `make -f` in a second fresh worktree of 304639d, never cloned, with the fixed Makefile laid in.

| mutant | the edit | result |
|---|---|---|
| FC | `prod`'s `submodules` prerequisite removed | red, exit 2: `make: *** vendor/chez-http-server/vendor/chez-libuv: No such file or directory.  Stop.` at the first line; nothing cloned or built |

FC is the rule as it stood, with the new comment: its red is the one measured first. CI runs `make submodules` as a step of its own, then check-pins, build, test and check-help, and never `make prod`. So CI would not see FC: only `make prod` on a fresh clone does.

**Shared state.** No `git submodule deinit`: in a linked worktree it edits the common `.git/config`, which the main checkout reads. The never-cloned checkouts were fresh worktrees in this session's scratchpad, each keeping its submodules' git directories under its own `.git/worktrees/<name>/modules`, and both were removed with `git worktree remove --force`. The common config's `submodule.*` lines were the same before and after.

**Records.** This entry only. No CHANGELOG entry: tooling only. README.org does not name `make prod`.

`make test` green before the commit (Darwin arm64): three suites, 17 expected passes, every pin ok. `make check-help` green.

NEXT: M1.2, base64, when the owner asks; this PR first goes through review and the closing ritual.

---

M1.2 — BASE64, and decision 0002. Branch `feat/m1.2-base64`. 2026-10-05.

**DECIDED (0002), on the owner's word: "keep our own".** The owner asked whether a Chez base64 library already existed, and the brief had looked only inside the server's pins. What exists, read from source:
- Industria 2.3.0's `(industria base64)` and hashing 1.4.0's `(hashing sha-1)`, both MIT on Akku;
- SRFI 207's procedures, which no chez-srfi carries, and whose decoder skips whitespace.

SHA-1 and base64 stay this library's own. The brief's line cites the record.

**`(websocket base64)`**: `base64-encode : Bytevector -> String` and `base64-decode : String -> (U Bytevector #f)`, RFC 4648 §4, in `(rnrs)` alone. The encode writes its characters to a string port, since `string-set!` is `(rnrs mutable-strings)`'s, not `(rnrs)`'s.

**`tests/test-base64.sps`, 24 checks:**
- RFC 4648 §10's seven vectors, both ways;
- the whole alphabet both ways, its 48 bytes three peers' (Python, Perl, OpenSSL);
- RFC 6455's keys: §1.3's decoded; §4.1's decoded as printed, and its bytes encoded as erratum 3150 corrects it;
- RFC 6455's accept value, `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`, through `(websocket sha1)`;
- the four refusals: a wrong length, a character outside the alphabet (one beyond ASCII among them), padding before the end, and three or more padding characters.

The import audit reads the new library with no change: two checks.

**Taken without a form: a decode accepts a last digit's set bits.** The plan's three refusals do not name them, RFC 4648 §3.5 lets a decoder refuse them, and RFC 6455 does not ask it to. RFC 6455 §4.1's own example key sets them; erratum 3150 corrects it. Four of five peers accept that key: websockets and ws (measured), and coder and gorilla (by Go's documentation). tungstenite refuses it. The design's §3 now says so, for M4.1.

**Tests first.** The suite ran red before the library existed (`library (websocket base64) not found`). Against a stub, 19 checks failed and 5 passed: the empty encode, and the four refusals, which a decode refusing everything passes. Each of those five has its own mutant.

**Seventeen mutants** (`m1-mutations.md`), each red set named before the run, and every one matched. B-11, a decode that requires the unused bits to be zero, reddens the printed §4.1 key alone.

`make test` green before the commit (Darwin arm64): four suites, 42 expected passes, every pin ok.

NEXT: M1.3, the UTF-8 checker, when the owner asks.

---

MERGED to main on 2026-10-05: **the `make prod` fix**, from #5, and **M1.2 with decision 0002**, from #6 (the two entries above).
- **#5, merged by the owner, as d0b6ec3.** It has the tree of its tested head, bcd376b (`linux` SUCCESS), and its parent is 304639d. Main's run on it, 37298523208, was green. Its merge had no reflect of its own, so this records it. Its branch is gone, local and remote.
- **#6, on the owner's "do closing ritual", as cbf2a7d.** It was rebased onto d0b6ec3 after #5 merged, 2018102 to 1638522. Both had added to this ledger: #5's entry stayed first, and M1.2's follows it. The tree changed by #5's own lines alone. The squash has 1638522's tree (bd7a1a4), and its parent is d0b6ec3.
- **CI.** #6 merged on `linux` SUCCESS at 1638522 (run 37298771912), after 2018102's had passed too (37297653847): four suites, 42 expected passes. Main's run on d0b6ec3 had finished before #6 merged, so the merge cancelled nothing. Main's run on the squash, 37298896656, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m1.2-base64` deleted, local and remote. No PR is open.

`make test` green on main: four suites, 42 expected passes, every pin ok.

NEXT: M1.3, the UTF-8 checker (`(websocket utf8)`: RFC 3629 §4's grammar at its edges, the refusals, and a character split across pieces at every byte), when the owner asks.

---

M1.3 — UTF-8, and M1's exit. Branch `feat/m1.3-utf8`. 2026-10-05.

**`(websocket utf8)`**, an incremental checker in `(rnrs)` alone:
- `utf8-start`, the state before any byte;
- `utf8-feed : (U Utf8State #f) Bytevector Nat Nat -> (U Utf8State #f)`, the state after the bytes from start to end, or `#f` at the first of them that cannot go on;
- `utf8-whole? : (U Utf8State #f) -> Boolean`.

A state is a fixnum: 0 between characters, and otherwise the bytes a character still needs and the range its next byte must fall in. A byte is refused as soon as no row of RFC 3629 §4 can go on with it. So an overlong form, a surrogate, or a code point past U+10FFFF fails at the byte that shows it, and the connection can fail at once (RFC 6455 §8.1).
- **A refusal is final.** Fed `#f`, a feed answers `#f`, and `#f` is never whole. So `(utf8-whole? (utf8-feed utf8-start bv 0 n))` checks a whole text, such as a close reason, in one call.
- **A range outside the bytevector is an assertion violation** naming `utf8-feed`.

**`tests/test-utf8.sps`, 28 checks,** built from tables of the oracles' cases:
- every row of §4 at its edges, and five kinds of refusal at their indexes, each fed a byte at a time and as one piece, and again after an "A" in the same piece;
- every row's first tail refused at both edges;
- §7's examples, and a character's first bytes alone, unfinished;
- in pieces:
  - each refusal split after its first byte;
  - each character split at every byte and at every pair of bytes;
  - an empty piece inside a character or a refusal;
  - §7's text split at every byte and fed a byte at a time;
- the range a feed reads, a range outside its bytevector, the start state, and a refusal, final and never whole;
- what a feed allocates: nothing, per call or per byte, on a mebibyte the check confirms is whole.

The import audit reads the new library with no change: three checks.

**The oracles.** §4's grammar and §7's examples come from the RFC's raw text. Two incremental decoders were fed every case of every check, in its pieces. The cases were read from the test's own tables. Node's fatal `TextDecoder` agreed with all of them. Python's agreed with all but the surrogate cases, which it refuses a byte late, so the checks hold the grammar's index.

**Departed from the plan: the allocation check**, as in M1.1, since the checker runs on every byte of every text message.

**Speed.** Each figure is the mean of four 16 MiB feeds after a warm-up (Darwin arm64, `--program`'s default optimize level):

| text | ns a byte |
|---|---|
| ASCII | 1.75 |
| §7's examples repeated, a 32-byte period | 2.67 |
| a seeded random mix of 1-, 2-, 3- and 4-byte characters, 60/20/15/5% | 4.82 |
| the same at 25% each | 4.69 |

Each byte past a character's first unpacks the state with fixnum shifts, and takes its next state from two constants. The generic shifts M1.3 first used are calls out of line in Chez 10.4.1. On the same four texts that version measured 1.75, 6.28, 6.95 and 7.95. The periodic text is the fastest of the three mixed ones, since the branch predictor learns its period. Character lengths in an unpredictable order cost more.

**Tests first.** The first suite ran red before the library existed (`library (websocket utf8) not found`). Then it ran against a stub that kept every state whole: 11 checks failed and 11 passed, each since given its own mutant. The review's suite then ran against M1.3's first library: 26 passed and 2 failed, the range assertion and the refusal's finality. Both were red until the library changed.

**The review.** A code review of PR #7 reported 15 findings, and all were fixed here:
- untested edges and piece shapes, where mutants that accept invalid UTF-8 passed the first suite;
- the API raising on its own `#f`;
- an unchecked range;
- an allocation check that a per-call cost or an early refusal slipped past;
- the 2x from the shifts;
- records: raise-reds, unnamed mutants and the periodic corpus.

For M4, the design and plan now note that Chez's decoders drop a leading U+FEFF. M4.3 delivers it, checked by an echo.

**Forty-three mutants** (`m1-mutations.md`): M1.3's own, re-cut, plus 21 from the review. Each red set was named before the run, and all matched. U-20 survives as an equivalent mutant, since Chez folds `need`'s constant ranges. A copy of the harness that names raised checks shows that only R-14 and R-15, whose property is not raising, redden through a raise. M1.3's first run had four mismatches, kept in the log.

**M1's exit.** The primitives are done: SHA-1 (M1.1), base64 (M1.2, with decision 0002) and UTF-8. Each is pure and held to its RFC's vectors: 64 checks among them (12, 24 and 28), and the import audit's three. README.org's status says so.

`make test` green before the commit (Darwin arm64): five suites, 71 expected passes, every pin ok. `make prod` green.

NEXT: M2, the frame codec, starting with M2.1's decode, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **M1.3 and M1's exit** (the entry above), from #7, as 3de361b. **M1 is complete.**
- **The squash** has 2f57f4f's tree (6d25208), the head CI tested, and its parent is 7b4d51d.
- **CI.** #7 merged on `linux` SUCCESS at 2f57f4f (run 37311050241): five suites, 71 expected passes, the allocation checks among them. 66379d1, the head before the review, had passed too (37300352629). Main's run on 7b4d51d had finished before #7 merged. Main's run on the squash, 37311901827, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m1.3-utf8` deleted, local and remote. No PR is open.
- **M1 in all.** SHA-1 (#4), base64 with decision 0002 (#6) and UTF-8 (#7), with #5's `make prod` fix between them: 64 checks among the three libraries and the import audit's three, and 92 mutants, each named before its run.

`make test` green on main: five suites, 71 expected passes, every pin ok.

NEXT: M2, the frame codec, starting with M2.1's decode (`(websocket frame)`: headers whole and split at every byte, the three length forms at their edges, unmasking at every offset, each refusal with its 1002, RFC 6455 §5.7's examples), when the owner asks.

---

FIX — THE SHA-1 REVIEW. Branch `fix/sha1-review`, cut from main at 85e51c0. 2026-10-05.

On the owner's "fix them". A code review of the merged SHA-1 code (53fa639, PR #4) reported 15 findings. The library was right: its digests matched hashlib, OpenSSL and Perl's Digest::SHA from 0 bytes to 512 MiB. The findings were in the suite, the records and the import audit, which came in with SHA-1.

**The library.** `(websocket sha1)` works its words with R6RS's fixnum operations, and rotates with `fxrotate-bit-field` where it called the generic shifts out of line. A 60-byte hash takes 2,789 ns, down from 4,384, and allocates the same. Its header says which calls Chez 10.4.1 compiles inline, measured: `fxand`, `fxior` and `fxxor` at any number of arguments, and `fx+` and `+` only at two. Words stay fixnums on any 64-bit Chez, and a fixnum operation raises rather than answer wrong.

**`tests/test-sha1.sps`, sixteen checks**, four of them new and one replaced:
- 4 MiB less a byte, whose length in bits sets every bit of the length field from 3 to 24; the other inputs set only some. Three peers agreed on its digest.
- A hash is pure: two digests held at once are each their own, a hash leaves its message as it was, and a hash run inside another, from a timer interrupt, disturbs neither. Under a schedule shared by every call, the last fails. No thread is needed.
- What a hash allocates, at six lengths up to 2,000 blocks, against what the test allocates for RFC 3174's padded message, 80-word schedule and digest. It replaces the ten-block slope, which a cost paid once a call cancelled (the flaw M1.3's review fixed in the UTF-8 suite).
- No hash runs outside a check, so a library that raises fails its checks (exit 1), not the harness (exit 2).

**The shared measure.** `(ws-testing)` exports `allocated`, and the UTF-8 suite drops its copy, and with it `(chezscheme)`. The measure:
- takes the least of three counts, each from its own depth of the stack, 100 frames apart;
- takes off an empty thunk's count;
- checks the counter first.

A count also takes in a new stack segment when the measured call reaches past the end of the current one. M1.1's measure read other than 640 at 75 of 40,001 stack depths. The review had proposed three counts from one depth, which read wrong at 15 of 9,001 depths. Three depths read wrong at none of 40,001.

**Reading a red.** A failed check's line is followed by what it expected and what it got, and a harness error names what was raised. So the mutation runner reads raises from the log, without a copy of the harness.

**The import audit** reads every form in a file, and every extension Chez looks for a library under, so neither a form after the library nor a `sha1.ss` beside `sha1.sls` slips past. It refuses `(rnrs eval)`, whose environment reaches any library. It passes over names that begin with ".", such as an editor's lock file, which it used to fail on.

**Records.** M1.1's notes on M1-24 and on the 63-, 64- and 65-byte checks claimed more than the checks held. Both are corrected in `m1-mutations.md`.

**127 mutants** (`m1-mutations.md`, M1.1's review), each red set named before the run:
- M1.1's 24, re-cut for the fixnum library;
- the review's 39: purity, allocation, the length field bit by bit, and a raise;
- the harness's five, eight runs between the two suites;
- the import audit's 14, old and new;
- M1.3's 42, against the shared measure.

The first run had one mismatch, a prediction error: an unmasked step sum now overflows `fx+` and raises, rather than growing a bignum. Every red set matched after the change to three depths. C-2, C-4, C-5 and M1-24 survive, by design or as the scope statement, and so do bits 25 to 31 of the length field and M1.3's U-20, as before.

`make test` green before the commit (Darwin arm64): five suites, 75 expected passes, every pin ok. Each allocation suite was green over 30 runs. `make prod` green.

NEXT: M2, the frame codec, starting with M2.1's decode, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **the SHA-1 review's fix** (the entry above), from the stacked #8, #9 and #10, as fc0a363, d6c393b and bed354e.
- **The squashes.** Each has the tree of the head CI tested, and each sits on the one before: fc0a363 on 85e51c0, d6c393b on fc0a363, bed354e on d6c393b.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #8 at 2e8c9be (run 37336474865), 71 expected passes;
  - #9, rebased onto #8's squash, at 9167159 (run 37337229296), 75;
  - #10, rebased onto #9's, at ea3fbf7 (run 37337401681), 75.

  Main's run on bed354e, 37337545541, was green too, and this reflect was pushed after it.
- **Branches.** `fix/sha1-review-1-measure`, `fix/sha1-review-2-sha1` and `fix/sha1-review-3-audit` deleted, local and remote. No PR is open.

`make test` green on main: five suites, 75 expected passes, every pin ok.

NEXT: M2, the frame codec, starting with M2.1's decode (`(websocket frame)`: headers whole and split at every byte, the three length forms at their edges, unmasking at every offset, each refusal with its 1002, RFC 6455 §5.7's examples), when the owner asks.

---

FIX — THE BASE64 REVIEW. Branch `fix/base64-review`, cut from main at 1d3792f. 2026-10-05.

On the owner's "fix them". A code review of the merged base64 code (cbf2a7d, PR #6) reported six findings. The library's answers were right. Two findings were gaps in the suite, and four were in the library.

**`tests/test-base64.sps`, 27 checks**, three of them new:
- Each character beside a run of the alphabet in ASCII is refused, and so are the two either side of ASCII's end. Five of the decode's six range edges had no check. Mutants that took `[`, `` ` ``, `{` or `:` for a digit, or raised on `@`, passed every check.
- "Zm/=" decodes to "fo", the three peers' answer. The choice to accept a last digit's set bits was held only before two "=".
- What each allocates: an encode its string and a decode its bytes, from 0 to 3,000 bytes. Main's encode failed this through its string port.

**`(websocket base64)`:**
- one table: the decode's values come from the encode's alphabet;
- groups worked with fixnum operations, and put together with `fx*`, since Chez 10.4.1 calls `fxarithmetic-shift-left` out of line;
- the encode writes into a string of its known length;
- whole groups first, then the one short group.

An encode of a digest takes 87 ns, down from 216, and a decode of a key 126 ns, down from 222. Each allocates only its answer.

**44 mutants** (`m1-mutations.md`, M1.2's review), each red set named before the run:
- eight test-first, against main's library;
- M1.2's 17, re-cut, two of them split in two;
- the review's 17.

The first runs had two prediction errors. The test-first sets left out the allocation check, which main's library fails unmutated. BR-13, as first cut, was equivalent: Chez's type pass compiled its `bitwise-ior` as `fxior`. After the re-cut, all 44 matched. BR-13a and BR-14a survive as equivalents. BR-14 survives as the scope statement: the speed is measured, not checked.

**Records.** M1.2's note that B-11 held the set-bits choice is corrected: it held it only before two "=".

`make test` green before the commit (Darwin arm64): five suites, 78 expected passes, every pin ok. The base64 suite was green over 30 runs. `make prod` green.

NEXT: M2, the frame codec, starting with M2.1's decode, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **the base64 review's fix** (the entry above), from #11, as e8329ff.
- **The squash** has 96e9e08's tree (49da078), the head CI tested, and its parent is 1d3792f.
- **CI.** #11 merged on `linux` SUCCESS at 96e9e08 (run 37341505829): five suites, 78 expected passes, tallied from its log against the local count. Main's run on e8329ff, 37342458274, was green too, and this reflect was pushed after it.
- **Branches.** `fix/base64-review` deleted, local and remote. No PR is open.

`make test` green on main: five suites, 78 expected passes, every pin ok.

NEXT: M2, the frame codec, starting with M2.1's decode (`(websocket frame)`: headers whole and split at every byte, the three length forms at their edges, unmasking at every offset, each refusal with its 1002, RFC 6455 §5.7's examples), when the owner asks.

---

M2.1, STEP 1 — THE HEADER. Branch `feat/m2.1-decode-1-header`, cut from main at d1e6547. 2026-10-05.

On the owner's "start M2, the frame codec". M2.1 was built whole, then cut in two by form ("Two stacked PRs"): this step is the header, and step 2, stacked on it, the payload. Each step was proved green on its own, in a scratch worktree of main with its files laid in, with its mutants run on its own tree.

**`(websocket frame)`**, an incremental decoder of the frames a client sends, in `(rnrs)` alone. This step reads headers:
- `make-frame-decoder`, a decoder before any byte;
- `frame-read-header! : FrameDecoder Bytevector Nat Nat -> (Values (U 'more 'header 'refused) Nat)`, which reads a header's bytes and answers once the header is whole, or once a byte refuses the frame;
- `frame-fin?`, `frame-kind`, `frame-length` and `frame-left`, which tell the header, and `frame-refusal`, which answers `(1002 why)`.

So the protocol (M3) can judge a frame by its header, its cap among the rules, before any payload is held (decision 0001).
- **The refusals of design §4**, each with 1002: a reserved bit set, an unknown opcode, a control frame not final, an unmasked frame, a control frame over 125 bytes, a length not in its shortest form, and a 64-bit length with its top bit set. Each comes at the first byte that shows it, as the UTF-8 checker's do: a 64-bit length whose first six bytes are zero is under 65,536, and is refused at the sixth. A refusal is final.
- **Two assertion violations** naming `frame-read-header!`: a range outside its bytevector, and a header read while a payload is unfinished. Their checks come with the payload read, in step 2.

**`tests/test-frame.sps`, 16 checks**, built from tables: 63 headers and 53 refusal cases.
- RFC 6455 §5.7's unmasked frames are refused at their second byte.
- Every kind of header at each length form's edges: whole, a byte at a time, split at every byte (495 cuts) and at every pair of bytes (2,052), with an empty piece inside, and without its last byte, when it answers nothing yet. The length forms at the plan's edges, 125, 126, 65,535 and 65,536, and 2^63 − 1, written out by hand.
- Each refusal at its index, with 1002: whole, a byte at a time, and split at every byte. A refusal is final.

The suite builds its own headers by §5.2. It stops with a provenance failure, exit 3, unless they are the length forms' edges written out by hand.

The import audit reads the new library with no change: four checks.

**The oracles.** RFC 6455's raw text, and Node's ws 7.5.10, a server's decoder found on this machine (nothing was downloaded). A shim logged every decoder the suite made, 3,441, and ws was fed each one's bytes in the same pieces. No answer disagreed (m2-mutations.md). Where the two differ, the difference is ws's own:
- it accepts a length not in its shortest form (62 cases);
- it caps a length at 2^53 − 1, with 1009, so a top-bit length gets 1009 where ours gets 1002 (34);
- it judges a header only once it holds two bytes, and a 64-bit length once it holds all eight.

Where both refused a stream fed a byte at a time, both refused at the same byte.

**Taken without a form:**
- A refusal at the first byte that shows it. RFC 6455 does not say when, and the peers read a whole field first.
- `frame-refusal` names its reason, for the protocol's log.

**Tests first.** The suite ran red before the library existed (`library (websocket frame) not found`, exit 255), and all 16 checks were red against a stub that decodes nothing.

**36 mutants and a baseline** (m2-mutations.md), each red set named before the run, and all matched. D-35 and D-37 survive this step: they mutate a header read's two assertions, whose checks come in step 2.

`make test` green before the commit (Darwin arm64): six suites, 95 expected passes, every pin ok. `make prod` green.

NEXT: step 2, the payload, stacked on this.

---

M2.1, STEP 2 — THE PAYLOAD. Branch `feat/m2.1-decode-2-payload`, stacked on `feat/m2.1-decode-1-header`. 2026-10-05.

**`frame-read-payload! : FrameDecoder Bytevector Nat Nat Bytevector Nat -> Nat`** unmasks the payload's next bytes into a destination the caller gives it, as many as both the bytes and the payload have: design §4's "then its payload as it arrives, unmasked (§5.3) into the core's buffer". A range outside its bytevector, a payload read with none left, and a destination without room are assertion violations naming it, and nothing is read or written.

**`tests/test-frame.sps`, 30 checks**, 14 of them new:
- RFC 6455 §5.7's masked text and pong decode to "Hello".
- After a whole frame in the same piece, each refusal comes a frame later.
- Payloads unmasked at every offset, split at every byte and every pair, and into any place of a destination. Frames back to back, of every kind, split at every byte and fed a byte at a time. §5.7's 256-byte and 64 KiB messages, masked.
- The API: ranges, reads out of turn and a destination's room, for both reads; the bytes read left as they were; and two decoders at once.
- What decoding allocates: nothing, per call or per byte, on 1,051,344 bytes of 80 frames.

The suite's `in-pieces` now reads payloads, and `merged` joins a frame's payload pieces, so each check of step 1 runs through changed helpers. The provenance check holds the suite's masked frames to §5.7's too.

**The oracles.** ws 7.5.10 was fed every decoder of the whole suite, 4,034, as in step 1, and again no answer disagreed (m2-mutations.md).

**Taken without a form:** the decoder's shape, two reads with the destination the caller's.

**Departed from the plan:**
- **The allocation check**, as in each of M1's slices, since the decoder runs on every byte the server reads.
- **The word path.** The first library unmasked a byte at a time, at 4.64 ns a byte. Of three shapes measured, a word at a time was fastest, at 1.85, though Chez 10.4.1 calls its 32-bit bytevector accessors out of line (m2-mutations.md). A read of fewer than four bytes builds no key word.

**Found and recorded for M2.2.** The plan's M2.2 asks for "a decode of each encode". The decoder refuses an unmasked frame (§5.1), and the server's frames are unmasked. So M2.2's check must mask each encode before decoding it, with the suite's own masking, which its provenance check holds to §5.7.

**Tests first.** Against step 1's library, the suite stopped at once (`attempt to reference unbound identifier frame-read-payload!`, exit 255). With a payload read that reads nothing, step 1's 16 checks passed and all 14 new ones failed.

**55 mutants and a baseline** (m2-mutations.md), each red set named before the run, on this step's tree: step 1's 36 again, since the helpers changed, and this step's 19. The first run had one mismatch, a prediction error (D-32). D-35 and D-37, which survive step 1, are red here. W-5 survives by design: without the word path the answers are the same, only slower, and the speed is measured, not checked.

`make test` green before the commit (Darwin arm64): six suites, 109 expected passes, every pin ok. The frame suite was green over 30 runs. `make prod` green.

NEXT: M2.2, the encoder, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **M2.1, the frame decoder** (the two entries above), from the stacked #12 and #13, as eb949fc and bd1062c.
- **The squashes.** Each has the tree of the head CI tested: eb949fc has 5e39a0b's, on d1e6547, and bd1062c has 0ff2014's, on eb949fc. #13 was rebased onto eb949fc from 14c72c7, and its tree did not change.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #12 at 5e39a0b (run 37352340826): six suites, 95 expected passes;
  - #13, rebased onto #12's squash, at 0ff2014 (run 37355046214): six suites, 109.

  Main's run on bd1062c, 37355178558, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m2.1-decode-1-header` and `feat/m2.1-decode-2-payload` deleted, local and remote. No PR is open.

`make test` green on main: six suites, 109 expected passes, every pin ok.

NEXT: M2.2, the encoder (the server's frames, unmasked and in shortest form: §5.7's unmasked examples byte for byte, and a decode of each encode, masked first), when the owner asks.

---

M2.2 — THE ENCODER, AND M2'S EXIT. Branch `feat/m2.2-encode`. 2026-10-05.

**`frame-encode : (U 'text 'binary 'close 'ping 'pong) Bytevector [Nat Nat] -> Bytevector`** makes the server's frame of a kind whole, in a bytevector of its own: final, unmasked, and its length in its shortest form (design §4). Its payload is the bytevector's bytes from start to end, the whole bytevector by default, and the bytevector is left as it was. A kind the server never sends, a continuation among them, a control frame over 125 bytes, or anything but a range of a bytevector, is an assertion violation naming it.

**`tests/test-frame.sps`, 40 checks**, 10 of them new:
- §5.7's unmasked frames a server sends, byte for byte: "Hello" as text and as a ping, and the 256-byte and 64 KiB binary messages.
- The length forms at their edges, and every kind a server sends at each edge: one final frame, unmasked, its length in its shortest form.
- A decode of each encode, masked first, as M2.1 found it must be: the decoder refuses an unmasked frame.
- A payload from a range; the kinds, the control frames and the ranges refused; the payload left as it was; and what an encode allocates: its frame, and nothing else.

The provenance check holds the suite's unmasked headers to §5.7's frames and to the edges written out by hand.

**The oracles.** ws 7.5.10's encoder was given every encode the suite made, 81 of them, and answered the same bytes for each. ws's sender refuses the four control frames over 125 bytes that ours refuses (m2-mutations.md).

**Taken without a form:**
- The encoder's shape: a whole frame. The design's protocol answers `(write bv)`, and the server's transport makes each write a libuv write of its own, copied at the call, so a header and a payload apart would be two.
- A payload from a range, as the decoder's reads and `transport-write!` take one: a pong can echo a ping's payload from the core's buffer.

**Departed from the plan:**
- **§5.7's fragmented message is not encoded.** The plan asks for "§5.7's unmasked examples, byte for byte", and one of them is a message in two frames. Design §4 has the server send each message as one final frame, so the encoder makes no continuation and no frame without FIN. A check holds that it refuses a continuation.
- **The allocation check**, as in each of M1's slices and M2.1.
- **`check-range`, shared with the decoder's reads**, now checks for a bytevector and two fixnums first, so anything but a range of a bytevector is an assertion naming the caller. Before, a string was refused by `bytevector-length`.

**Tests first.** Against M2.1's library, the suite stopped at once (`attempt to reference unbound identifier frame-encode`, exit 255). Against a stub that answers an empty bytevector, the 30 decoder checks and the payload's check passed, and the other 9 new ones failed.

**92 mutants and a baseline** (m2-mutations.md), each red set named before the run: M2.1's 55 again, since the decode of each encode runs the decoder, and 37 new. The first run had one mismatch, an equivalent mutant: Chez's optimizer makes E-34's `(apply frame-encode (list …))` the direct call, which allocates nothing. Cut again, as a copy of the payload, it matched, and the final run on this commit's blobs had 0 mismatches. E-18 survives by design: a 64-bit length's first four bytes are zero for any payload under 2^32 bytes, and no test holds 4 GiB.

**M2's exit.** The frame codec is done: the decoder (M2.1) and the encoder. One library, 40 checks, held to RFC 6455's §5.2, §5.3, §5.5 and §5.7, with ws 7.5.10 fed every case. README.org's status says so.

`make test` green before the commit (Darwin arm64): six suites, 119 expected passes, every pin ok. The frame suite was green over 30 runs. `make prod` green.

NEXT: M3.1, messages and limits, `(websocket protocol)` and `(websocket limits)`, when the owner asks.

---

M2.2'S REVIEW. Branch `fix/m2.2-review`, stacked on `feat/m2.2-encode` (#14). 2026-10-05.

The owner's `/code-review high` on #14 found ten things, and all ten are fixed, on the owner's "fix all" (m2-mutations.md has each):
- **Checks.** Both range checks now pass a non-fixnum end, which no check held, and the decoder's a non-fixnum start and a string. The allocation check measures each frame again from a range. A new check refuses a close of one byte.
- **The library.** `frame-encode` refuses a close of one byte (§5.5.1: a close's body is empty, or begins with its two-byte code). Its opcode is found in `kinds`, which the decoder reads: one table. The 125-byte limit is `control-max`, which both read. The length's form is decided once, and written with `bytevector-uint-set!`.
- **The suite.** Its encoder tables are derived from `kinds` and `data-lengths`, a close encoded at two bytes where it was at one. The allocation check sizes each frame from its lengths, not its list.
- **The records and the README.** E-21 is cut so its reds no longer rest on unwritten bytes. The README says the codec builds the server's frames: it does not write them.

**Tests first.** The review's suite against #14's library: 40 passes, and the close of one byte red. The gaps of findings 1 and 3, as mutants of #14's library, survived #14's suite and went red under the review's.

**The oracles.** ws 7.5.10 again: the same bytes for all 81 encodes. It refuses the control frames over 125 bytes too, and its `close` can never send one byte.

**98 mutants and a baseline**, each red set named before the run, 0 mismatches on the first run. M2.1's rows again, with D-8 to D-10 cut on `control-max`. M2.2's rows are re-cut on the review's code, with E-1 to E-5 retired with the `case` they cut. 12 rows are new. A check of every cut, before the run, found D-8's stale and it was cut again. E-18 still survives by design.

`make test` green before the commit (Darwin arm64): six suites, 120 expected passes, every pin ok. The frame suite was green over 30 runs. `make prod` green.

NEXT: the closing ritual for #14 and this, on the owner's word; then M3.1, messages and limits, when the owner asks.

---

MERGED to main on 2026-10-05, on the owner's "do closing ritual": **M2.2, the frame encoder, M2's exit, and M2.2's review** (the two entries above), from the stacked #14 and #15, as 2dff51b and a656beb. **M2 is complete.**
- **The squashes.** Each has the tree of the head CI tested: 2dff51b has fe724c0's, on 3d18c87, and a656beb has 3969de3's, on 2dff51b. #15 was rebased onto 2dff51b from ad3c58b, and its tree did not change.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #14 at fe724c0 (run 37359369359): six suites, 119 expected passes;
  - #15, rebased onto #14's squash, at 3969de3 (run 37362101663): six suites, 120.

  Main's run on a656beb, 37362391949, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m2.2-encode` and `fix/m2.2-review` deleted, local and remote. No PR is open.

`make test` green on main: six suites, 120 expected passes, every pin ok.

NEXT: M3.1, messages and limits (`(websocket protocol)` and `(websocket limits)`), when the owner asks.

---

M3.1, STEP 1 — THE LIMITS. Branch `feat/m3.1-1-limits`, cut from main at 71d6626. 2026-10-05.

On the owner's "start M3.1". M3.1 was built whole, then cut in two by form ("Two stacked PRs", the recommended): this step is the limits, and step 2, stacked on it, the protocol. Each step was proved green on its own, in a scratch worktree of main with its files laid in, with its mutants run on its own tree.

**DECIDED by form (2026-10-05), the recommended: "Also 16 messages"** (0001's amendment). Reading was to stop once the queue held a cap's worth of bytes. An empty message adds no bytes, so empty messages could queue without end while a handler is busy. Measured on a prototype of the core: one 16 KiB read of empty text frames, 6 bytes each, queued all 2,730 and never stopped reading, the step allocating 80 B a message. Reading now also stops at 16 queued messages, websockets' `max_queue`, and `CHEZ_WS_MAX_QUEUE` overrides it. Its variable lands here, and the queue in step 2.

**`(websocket limits)`**: the limits record and its reading from an environment's strings, in `(rnrs)` alone.
- `make-websocket-limits`, `default-websocket-limits`, `websocket-limits-with`, `websocket-limits-from-environment` and `websocket-limits-environment-variables`, and the seven accessors. The names are apart from the server's `limits-` ones.
- The design's six variables, and `CHEZ_WS_MAX_QUEUE`. Durations are given in whole seconds and kept in ms, the unit the server's transport arms a deadline in.
- A value is ASCII digits and nothing else. Each field has a least value: a cap and a queue of 1, a pong timeout of 1 s, and 0 for the rest. A low water above the high water is refused. The reading names the variable it refuses, and the constructor the field.

**`tests/test-limits.sps`, 14 checks:**
- the defaults, and the variables in the fields' order;
- each variable alone, and all at once: sizes in their unit, durations in whole seconds;
- each bound at its edge and below it, and the water marks;
- malformed values, for every variable: a sign, a radix or exactness prefix, an exponent, a fraction, a space, a word, and a digit outside ASCII; and leading zeros;
- what the constructor and `websocket-limits-with` make and refuse.

The import audit reads the new library with no change: five checks.

**The oracles.** The design's §7 table, decision 0001 and its amendment, and the server's conventions, from its `(http-server limits)`.

**Taken without a form:**
- **A value is ASCII digits alone.** The server reads with `string->number`, which takes more: measured, `"#x10"` reads as 16 and `"+5"` as 5.
- **The least values.** A close timeout of 0 is accepted, as the server's drain of 0 is: the stream closes as the close is sent.
- **`websocket-limits-with`**, as the server's `limits-with`, since a handler may give limits of its own (design §7). It checks what it makes, as the constructor does.

**Tests first.** The suite ran red before the library existed (`library (websocket limits) not found`, exit 255). Against a stub whose fields are all 0, and which reads and checks nothing, 13 checks failed and one passed: the constructor's field order, which L-32 kills.

**34 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree: 0 mismatches. The first run, on the whole slice, had one mismatch among them, a prediction error (L-10).

`make test` green before the commit (Darwin arm64): seven suites, 135 expected passes, every pin ok. `make prod` green.

NEXT: step 2, the protocol, stacked on this.

---

M3.1, STEP 2 — THE PROTOCOL. Branch `feat/m3.1-2-protocol`, stacked on `feat/m3.1-1-limits`. 2026-10-05.

**DECIDED by form (2026-10-05), the recommended: "Answer it in M3.1".** A client's close can arrive in the bytes M3.1 reads, and the plan had put "a close received" in M3.2. The step answers it here, as design §5 says, and the plan says so. M3.2 keeps the server's own close, closes that cross, the close timeout and the stream's end.

**`(websocket protocol)`**: `make-ws-state` and `ws-step`, design §5's step, pure, in `(rnrs)` and the project's pure libraries.
- Its events are `(bytes bv start end)`, `(send kind payload)` and `(taken nbytes)`.
- Its actions are `write`, `deliver`, `read-stop`, `read-start`, `close-stream`, `closed` and `log`.
- **Messages, whole or fragmented**, each of its first frame's kind. A continuation with no message begun, or a message begun before the last ended, fails 1002.
- **Control frames between fragments.** A ping is answered at once with its payload, and a pong is answered with nothing.
- **The cap.** A frame that would take its message past the cap fails 1009 at its header, before its payload is held.
- **UTF-8.** A text fails 1007 at the read that brings a bad byte, and at its end if it ends mid-character.
- **A client's close** is answered with its code, or with an empty close, and the stream is closed, cleanly. A close of one byte, or of a code an endpoint may not send, fails 1002, and a reason not UTF-8 fails 1007.
- **Failing** writes a close with the code, closes the stream, logs why, and tells 1006.
- **Reading on.** Reading stops once the queue holds a cap's worth of bytes or 16 messages, and the step reads no further. The rest of the read waits, kept: the server's transport hands a taker each read's bytevector to keep. A take that makes room reads it, a message at a time, then answers `read-start`.

**`tests/test-protocol.sps`, 46 checks**, from tables of its oracles' cases:
- messages whole, fragmented, back to back, and cut at every point and every pair of points;
- the fragment rules, control frames, the cap at its edge and at the default, and UTF-8 at the bad byte and at the message's end;
- every decoder refusal, a client's close and its checks, and sending;
- reading on, by bytes and by count, and what waits;
- the API, the bytes left as they were, what reading allocates, what a connection keeps, and two connections at once.

The import audit reads the new library with no change: six checks.

**The oracles.** RFC 6455's raw text: §5.4–§5.7, §7.1.4–§7.1.7, §7.4.1 and §7.4.2, and §8.1. RFC 3629 §4's grammar. Decision 0001 and its amendment, and the design's §5. Node's ws 7.5.10, a server's receiver, was fed every connection the suite made, 563, each read in the same pieces. 527 answered the same, 13 read nothing, and no answer disagreed. The rest are ws's own:
- 18 judge UTF-8 only at a message's end;
- 3 accept close codes 1012 to 1014, which §7.4.1 does not define and IANA's registry added later;
- 2 are M2.1's, a length not in its shortest form and a top-bit length.

**Taken without a form:**
- **A delivered text is its UTF-8 bytes**, and a close's reason too: the binding decodes them, since Chez's decoders drop a leading U+FEFF (design §6). A text is sent from a string. `string->utf8` keeps U+FEFF, measured: `EF BB BF 41`.
- **A failure tells 1006 and an empty reason**, since no close came (§7.1.5, §7.1.6), and logs `(log failed code why)`.
- **The caller's mistakes are assertion violations** naming `ws-step`: a read while reading is stopped, a read or a send after the end, a take of a message not queued, and an event out of the vocabulary or of the wrong shape.
- **Reading starts again once the queue is under both bounds.** Decision 0001's "until the handler takes one" is the same whenever one take brings it under.
- **The close codes are §7.4.1's list**, as the design has it.

**Departed from the plan:**
- **The client's close**, by form (above), and **the queue's count**, by step 1's.
- **The allocation check**, as in each of M1's and M2's slices. A message read in one frame is read into the bytevector it is delivered in, and a fragmented one into a buffer that doubles, never past the cap. Grown by each fragment alone, one-byte fragments to 1 MiB would copy about 2^39 bytes on the server's one loop.
- **What a connection keeps**, checked with a guardian: no message once delivered, and no read once its bytes are read. A connection lives as long as its WebSocket.

**Tests first.** The suite ran red before the library existed (`library (websocket protocol) not found`, exit 255). Against a stub whose step answers nothing and refuses nothing, 45 checks failed and one passed: the bytes left as they were, which M-82 kills. The first library run was green. Then writing the mutants found gaps, and checks for them came after: what a connection keeps, the buffer's doublings, a take while reading, events of the wrong shape, two connections' control frames, and a take after the end with reading stopped. Each was watched to fail under its mutants. Six lines no check could tell from their absence were shown redundant and taken out (m3-mutations.md).

**124 rows** (m3-mutations.md), each red set named before the run, on this step's tree: step 1's 35 again, with the protocol's checks in their red sets, and this step's 89. The first run had 11 mismatches, all prediction errors: each an extra red, and none a survivor. The final run on this commit's blobs had 0 mismatches. Every check has a killer that reddens it by value. No mutant survives.

`make test` green before the commit (Darwin arm64): eight suites, 182 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: M3.2, the closing handshake (a close sent, closes crossing, the close timeout, the stream's end), when the owner asks; the two PRs first go through review and the closing ritual.

---

M3.1'S REVIEW. Branch `fix/m3.1-review`, stacked on `feat/m3.1-2-protocol` (#17). 2026-10-05.

The owner's `/code-review high` on #16 and #17 found nine things, and all nine are fixed, on the owner's "fix all" (m3-mutations.md has each):
- **A message's buffer grows as its bytes arrive** (finding 1). It used to be allocated at the length a header announced, so one 14-byte header made the server allocate 1 MiB. It now starts empty and doubles as payload arrives. In a message's last frame, once a doubling would reach half its end, it takes the whole end. It never holds more than four times what has arrived.
  - Measured against #17: a header announcing 1 MiB, alone, allocates 0 B, where it was 1,048,576 B. 1 MiB in one frame, read in 16 KiB pieces, allocates 2,080,912 B, about twice, at the same speed (1.99 ms against 1.98 ms). Read whole, it allocates the same as before.
  - A floor of 16 KiB up front did as well or worse in every case, so it took no form. Plain doubling capped at the end measured 3,129,056 B, since one doubling landed just under the end.
- **Each limit is a fixnum at most** (finding 2): the server's transport arms a deadline only for a fixnum of ms. A value past one is refused as the program starts, naming its variable.
- **The guards no check held** (finding 3) now have rows: a take of -1 or 1.0, and a read starting at -1 or 0.0, or ending at 1.0. A sweep of every guard and branch for a mutant found more, now checked or recorded:
  - an override that is not a pair;
  - `websocket-limits-with` on a base other than the defaults;
  - eight lines no mutant had reached (S-1 to S-7, and S-9);
  - one equivalent mutant (S-8), and `digits?`'s length test, which can never fail, taken out.
- **An ended connection lets go of its unfinished message** (finding 4). It is checked on the live heap, since the buffer is out of a guardian's reach.
- **The records** say six lines, not five (finding 5). The record type's predicate and accessors carry signature comments (finding 6). The water marks are found by name (finding 7). `(websocket frame)` exports `frame-control?`, with its check, in place of the protocol's own `control-kind?` (finding 8). The limits table carries each field's accessor (finding 9).

**Tests first.** The review's suites against #17's libraries:
- the frame suite stops at once, `frame-control?` unbound;
- the limits suite fails the fixnum check alone;
- the protocol suite fails the growth check, `(1048576 1048592)` for `(0 2080416)`, and the ended connection's, `(kept 1000448)`.

The rows that held guards #17 already had pass there. Their gap mutants, Q-1 to Q-5 and L-35, pass #17's suites, and each fails its check here.

**145 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this branch's tree. The first run had four mismatches:
- **E-1 survived.** The ended connection's check compared two heaps measured apart, and they moved by about 87 KB between measures. It now measures each connection's footprint, back to back, after a warm-up, against half the fragment.
- **Three were prediction errors.**

The final run had 0 mismatches. S-8 survives, an equivalent mutant. M2's 98 frame mutants ran again, since the frame suite gained a check: 0 mismatches, and D-6 reddens `frame-control?`'s check too. ws 7.5.10 was fed the review's 582 connections, and no answer disagreed.

`make test` green before the commit (Darwin arm64): eight suites, 186 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: the closing ritual for #16, #17 and this, on the owner's word; then M3.2, the closing handshake, when the owner asks.

---

MERGED to main on 2026-10-05: **M3.1, messages and limits, and M3.1's review** (the three entries above), from the stacked #16, #17 and #18, as 4451059, e5fe824 and e2258f1. #16 merged on the owner's "squash merge 16", and #17 and #18 on "do closing ritual".
- **The squashes.** Each has the tree of the head CI tested:
  - 4451059 has 4d6afaa's, on 71d6626;
  - e5fe824 has 4d967a1's, on 4451059;
  - e2258f1 has 1b5c34d's, on e5fe824.

  #17 was rebased onto 4451059 from c38c973, and #18 onto e5fe824 from a4af357. Neither tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #16 at 4d6afaa (run 37370400287): seven suites, 135 expected passes;
  - #17, rebased onto #16's squash, at 4d967a1 (run 37375982588): eight suites, 182;
  - #18, rebased onto #17's squash, at 1b5c34d (run 37377285363): eight suites, 186.

  Main's runs on 4451059 (37375592089) and e5fe824 (37377254756) finished before the next merge. Main's run on e2258f1, 37377490495, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m3.1-1-limits`, `feat/m3.1-2-protocol` and `fix/m3.1-review` deleted, local and remote. No PR is open.

`make test` green on main: eight suites, 186 expected passes, every pin ok.

NEXT: M3.2, the closing handshake (a close sent, closes crossing, the close timeout, the stream's end), when the owner asks.

---

M3.2, STEP 1 — THE SERVER'S CLOSE, AND CLOSES CROSSING. Branch `feat/m3.2-1-server-close`, cut from main at d643ec9. 2026-10-05.

On the owner's "start M3.2". M3.2 was built whole, then cut in three by form ("Three stacked PRs", the recommended), one PR to each bullet of the plan's:
1. this step, the server's close and closes crossing;
2. step 2, the close timeout;
3. step 3, the stream's end.

Each step was proved green on its own, in a scratch worktree of main with its files laid in, with its mutants run on its own tree.

**DECIDED by form (2026-10-05), the recommended: "Deliver as before"** (0001's second amendment). The design said nothing of messages that come after the server's close, before the client's answer. Measured on two prototypes of the core, at the default limits:
- 16 messages queued and the rest of the read waiting: a 17th, and the client's close.
- Delivering as before, the server's close leaves that close unread until the close timeout.
- Reading on and dropping messages instead, the connection ends at once, cleanly, with the client's 1000.
- Two messages the client sends after the server's close are delivered, or dropped.

The peers:
- websockets 17.2 queues them, and pauses reading past 16 frames whether closing or not;
- ws 7.5.10, run on a fake socket, delivers them.

So messages after the server's close are delivered as before. The close timeout bounds the wait, and M4's binding can take on behalf of a procedure that has ended.

**`(websocket protocol)`**:
- **The server's close**, `(close code reason)` (§7.1.2), is written with its code and reason, and `(arm-deadline close)` is answered with it.
  - Its code must be one an endpoint may send, and its reason a string of at most 123 bytes in UTF-8, the most a close holds past its code (§5.5). Anything else is an assertion naming ws-step.
  - Once a close is sent, another answers nothing, and a send is the caller's mistake (§5.5.1).
- **After it, reading goes on as before** (by form), and a ping is answered, since no close has been received (§5.5.2).
- **The client's close then ends the handshake**, crossing or answering. Nothing more is written; the deadline is disarmed, the stream closed, and its code and reason told, or 1005, cleanly (§7.1.5, §7.1.6).
- **Failing once the server's close is sent writes no second close** (§7.1.7).
- **Whenever the connection ends with the deadline armed**, the step answers `(disarm-deadline)` first.

**`tests/test-protocol.sps`, 59 checks**, 11 of them new:
- the server's close, its code and reason, and the codes and reasons it refuses;
- closes crossing, cut at every point, and the client's answer;
- a bad answer, and failing, with no second close;
- a ping and messages after the server's close;
- a close or a send once a close is sent, or after the end;
- the server's close while reading is stopped.

The import audit reads the library with no change: six checks.

**The oracles.** RFC 6455's raw text: §5.5, §5.5.1, §5.5.2, §7.1.2, §7.1.5 to §7.1.7, and §7.4.1. The design's §5. The form.

ws 7.5.10 was fed every connection the step's suite made, 651. Each event went in turn to its WebSocket, on a fake socket. 578 answered the same and 35 stepped nothing. The rest are ws's own:
- 18 judge UTF-8 only at a message's end;
- 14 echo a close's reason too, where ours echoes its code alone (M3.1);
- 3 accept 1012 to 1014;
- 2 are M2.1's length forms;
- 1 answers no ping once its close is sent, though §5.5.2 asks for one.

No answer disagreed.

**Taken without a form:**
- **A close's code is from §7.4.1's list**, the same one M3.1 checks a client's against. So 1012 to 1014 are refused, though websockets and ws send them.
- **A close's reason is a string**, as a text's payload is. Over 123 bytes, it is refused, as ws refuses it.
- **A close once one is sent, or after the end, answers nothing**, as websockets' and ws's `close` do.
- **The step disarms its deadline when the connection ends.** The server's transport closes a stream only once its writes are written, so a deadline left armed could pass after the end.

**Tests first.** The step's suite against main's library (M3.1's, 132c307) gave 48 passes, and the 11 new checks red.

**174 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree:
- M3.1's review's 145, re-cut where this step rewrote their lines, each red set grown by the checks of this step it also reddens;
- this step's 29.

0 mismatches. C-3 is equivalent here: nothing reads the deadline after the end until step 2. Every check has a killer that reddens it by value.

`make test` green before the commit (Darwin arm64): eight suites, 197 expected passes, every pin ok. `make prod` green.

NEXT: step 2, the close timeout, stacked on this.

---

M3.2, STEP 2 — THE CLOSE TIMEOUT. Branch `feat/m3.2-2-close-timeout`, stacked on `feat/m3.2-1-server-close`. 2026-10-05.

**`(websocket protocol)`**:
- **`(deadline-passed)`**: the close sent was not answered in time. The stream is closed anyway, nothing is written, and 1006 is told, not cleanly (§7.1.5). This is websockets' `close_timeout`, by its deadline's kind. A deadline passing with none armed is the caller's mistake, an assertion naming ws-step.
- **An ended connection lets go of a read that waited for the queue**, since the timeout can end a connection whose reading had stopped.

**`tests/test-protocol.sps`, 63 checks**, 4 of them new:
- the close timeout, a message unfinished or not, and a close after it;
- a deadline passing with none armed, and one of the wrong shape;
- the default queue holding the client's close back until the timeout (by form);
- what an ended connection keeps.

**Found while writing the mutants:**
- **The wrong-shape row was refused for another reason.** It stepped a deadline of the wrong shape on an open connection, where none is armed, so the mutant that drops the shape's check would have survived it. Before the first run, the row was moved to step it while the close's deadline is armed.
- **The retention check answers `kept` when the read is kept**, not #f. A kept read and a raise printed alike, and now print apart.

**The oracles.** The design's §5, and websockets' `close_timeout` (the peer survey).

ws 7.5.10 was fed every connection, 660. 584 answered the same and 36 stepped nothing. 2 are "ours waits for a take; ws reads on", the default queue's and the retention check's. The rest are ws's own, as in step 1. No answer disagreed.

**Tests first.** The step's suite against step 1's library (00559db) gave 59 passes, and the 4 new checks red.

**179 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree:
- step 1's 174, each red set grown by this step's checks it also reddens;
- this step's 5.

0 mismatches. C-3, equivalent in step 1, is killed here. Every check has a killer that reddens it by value.

`make test` green before the commit (Darwin arm64): eight suites, 201 expected passes, every pin ok. `make prod` green.

NEXT: step 3, the stream's end, stacked on this.
