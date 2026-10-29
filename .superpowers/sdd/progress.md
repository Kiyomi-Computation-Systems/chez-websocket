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

**144 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this branch's tree. The first run had four mismatches:
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

**173 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree:
- M3.1's review's 144, re-cut where this step rewrote their lines, each red set grown by the checks of this step it also reddens;
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

**178 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree:
- step 1's 173, each red set grown by this step's checks it also reddens;
- this step's 5.

0 mismatches. C-3, equivalent in step 1, is killed here. Every check has a killer that reddens it by value.

`make test` green before the commit (Darwin arm64): eight suites, 201 expected passes, every pin ok. `make prod` green.

NEXT: step 3, the stream's end, stacked on this.

---

M3.2, STEP 3 — THE STREAM'S END. Branch `feat/m3.2-3-stream-end`, stacked on `feat/m3.2-2-close-timeout`. 2026-10-05.

**`(websocket protocol)`**:
- **`(end why)`, the stream's end** with no close received, 'eof or the errno. The stream is closed, nothing is written, and 1006 is told, not cleanly (§7.1.5). The deadline is disarmed if the server's close was sent. After the end, it answers nothing.
- **1005 and 1006 are never written.** No close the step sends carries them: its codes refuse them. Nothing is written at the stream's end.

**`tests/test-protocol.sps`, 68 checks**, 5 of them new:
- the stream's end at once, in a frame, between fragments, and while reading is stopped, at the end of file or an error;
- the stream's end after the server's close;
- what an ended connection answers to it;
- its shape;
- what an ended connection keeps.

**Found while writing the checks:** the end's shape check passed against step 2's library, which refuses every end. It now has rows an end must pass, at the end of file and at an error.

**The oracles.** RFC 6455 §7.1.5: with no close received, the code is 1006. §7.1.7: a close may be left out when the other side cannot read it.

ws 7.5.10 was fed every connection, 676. 596 answered the same and 38 stepped nothing. 4 are "ours waits for a take; ws reads on", and the rest are ws's own, as in step 1. Of the 72 connections that step a close, the stream's end or a deadline, 67 answered the same, 4 wait for a take, and 1 is ws's unanswered ping. No answer disagreed. On the stream's end, ws too writes nothing and tells 1006.

**Tests first.** The step's suite against step 2's library (4f944ea) gave 63 passes, and the 5 new checks red.

**184 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this step's tree:
- step 2's 178, each red set grown by this step's checks it also reddens;
- this step's 6.

0 mismatches. Every check has a killer that reddens it by value.

`make test` green before the commit (Darwin arm64): eight suites, 206 expected passes, every pin ok. `make prod` green.

**Recorded on the owner's word (2026-10-05): a close the transport cannot force** (design §9, for M4). The server's `transport-close!` waits for every write to be written (chez-http-server v0.3.0, `taker-close!`, `taker-wrote!`). So when the close timeout's `close-stream` reaches a client that stopped reading, the connection stays open until the server drains. Today only a raise in a taker's call closes such a stream at once, and the server logs it as `taker-failed`. M4 decides by form: a door change in the server, or a bound of the binding's own.

NEXT: M3.3, the ping clock (a quiet client pinged, and failed 1011 when the pong is late; any bytes re-arm it; stopped while reading is), when the owner asks; the three PRs first go through review and the closing ritual.

---

M3.2'S REVIEW. Branch `fix/m3.2-review`, stacked on `feat/m3.2-3-stream-end` (#21). 2026-10-05.

The owner's `/code-review high` of the M3.2 stack, #19 to #21, found seven things, and all seven are fixed, on the owner's "fix all" (m3-mutations.md has each):
- **What waits is read at the close timeout and at the stream's end** (findings 1 and 2). Both ended the connection with the rest of a read still unread, though it may hold the client's close: told 1006 where the client had closed. Now each reads what waits first, whatever the queue holds, since no more bytes will come: at most the rest of one read. A client's close among it is told with its code, cleanly. In the default queue's stall, the timeout now delivers the 17th message and tells the client's code, cleanly, where it told 1006.
- **A failure logs only the code of a close it wrote** (finding 3). Once the server's close is sent, failing writes no close, and the log said 1002 or 1007 or 1009 all the same. It now logs #f for the code.
- **A close's reason is measured, not encoded** (finding 4). The reason was encoded to be measured even for a close that answers nothing. It is now counted by RFC 3629 §3's rows, reading no further than its 124th byte. It is encoded only when the close is written, by one `close-frame`, which builds a failure's close too. Measured: a close once one is sent allocated 112 B for a 100-byte reason, and now 0.
- **The suite's duplicates** (findings 5 and 6). `run` and `any-pieces` are `run-from` and `any-pieces-from` with no events. One `let-go` and one `footprint` serve every retention check. `let-go` answers `kept`, so M3.1's P-KEEP now reddens by value too.
- **An end after the server's close lets go of an unfinished message** (finding 7). It held already, unchecked. The gap mutant R-15 passes #21's suite, and fails the new check.

Two lines no check could tell from their absence were taken out:
- `end!`'s release of the read that waits: every end now reads what waits first;
- `stream-end!`'s own check for an ended connection: `lost!` answers nothing once the connection has ended.

**Tests first.** The review's suite against #21's library (325e797) gave 66 passes. Six checks were red:
- the stall at the default queue, and the stream's end while reading is stopped;
- what waits read at the end, a new check;
- a client's bad close and failing after the server's close: the log's code;
- a close once one is sent allocating nothing: `(112 112)` for `(0 0)`.

The other new checks pass there. The reason's measure and the end's release behaved the same in #21; their mutants hold them.

**198 mutants and a baseline** (m3-mutations.md), each red set named before the run, on this branch's tree:
- step 3's 184, re-cut where the review rewrote their lines, less four withdrawn;
- the review's 18.

The first run had four mismatches:
- M-22's replacement named `code-bytes`, which the review took out: a harness error, re-cut;
- three prediction errors. `allocated` takes the least of three calls, so a mutant that writes a close only at the first call, moving the state to closing, measures 0.

The final run had 0 mismatches, and every check has a killer that reddens it by value. ws 7.5.10 was fed the suite's 698 connections, and no answer disagreed. 8 are the new log: ws reports the failure's code where ours wrote no close.

`make test` green before the commit (Darwin arm64): eight suites, 210 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: the closing ritual for #19, #20, #21 and this, on the owner's word; then M3.3, the ping clock, when the owner asks.

---

MERGED to main on 2026-10-05: **M3.2, the closing handshake, and M3.2's review** (the four entries above, and the design's open item recorded in step 3's), from the stacked #19, #20, #21 and #22, as a28c33f, 4b2c621, bdd2c0b and b682d58, on the owner's "do closing ritual".
- **The squashes.** Each has the tree of the head CI tested:
  - a28c33f has 60b6117's, on d643ec9;
  - 4b2c621 has 38cc6de's, on a28c33f;
  - bdd2c0b has d15246f's, on 4b2c621;
  - b682d58 has d2e58f7's, on bdd2c0b.

  #20 was rebased onto a28c33f from 89b77cb, #21 onto 4b2c621 from 4c07600, and #22 onto bdd2c0b from 20d59db. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #19 at 60b6117 (run 37386690010): eight suites, 197 expected passes;
  - #20, rebased onto #19's squash, at 38cc6de (run 37394347726): eight suites, 201;
  - #21, rebased onto #20's squash, at d15246f (run 37395095947): eight suites, 206;
  - #22, rebased onto #21's squash, at d2e58f7 (run 37395581625): eight suites, 210.

  Main's runs on a28c33f (37394298480), 4b2c621 (37395077735) and bdd2c0b (37395562361) each finished before the next merge. Main's run on b682d58, 37396047678, was green too, and this reflect was pushed after it.
- **Branches.** `feat/m3.2-1-server-close`, `feat/m3.2-2-close-timeout`, `feat/m3.2-3-stream-end` and `fix/m3.2-review` were deleted, local and remote. No PR is open.

`make test` green on main: eight suites, 210 expected passes, every pin ok.

NEXT: M3.3, the ping clock (a quiet client pinged, and failed 1011 when the pong is late; any bytes re-arm it; stopped while reading is), when the owner asks.

---

M3.3, STEP 1 — THE PING CLOCK. Branch `feat/m3.3-1-ping-clock`, cut from main at e2eadb5. 2026-10-05.

On the owner's "Start M3.3, the ping clock". The plan's M3.3 is the clock, then the protocol's mutation sweep. This step is the clock, and step 2 the sweep. They were built as two commits, each green on its own.

**DECIDED by form (2026-10-06), the recommended: "Two stacked PRs"**, on the sizes measured for it: this step +511/-37 (library +78/-20, tests +149/-15, design +20/-2, records +264), and step 2, stacked on it, +163/-5. "One PR" would have been 716 lines.

**`(websocket protocol)`**:
- **A new connection's deadline is `ping`**, unless the ping interval is 0, which turns pinging off. `ws-deadline : WsState -> (U 'ping 'pong 'close #f)` names the deadline armed, as the steps have told the binding. The binding arms a new connection's as it starts, as the server's shell arms a new connection's idle deadline.
- **Any bytes received re-arm `ping`**, after the read's own actions (design §5). That includes a message that comes while the pong is awaited.
- **When `ping` passes**, the client has sent nothing for the interval. A ping with no payload is written, two bytes, and `pong` is armed.
- **When `pong` passes**, nothing has come since. The connection fails with 1011, websockets' keepalive's code, logged as `ping-timeout`. Nothing is disarmed, since the deadline has passed.
- **The clock stops while reading has** (0001). The read that fills the queue answers `(read-stop)` and then `(disarm-deadline)`, ping or pong armed. A take that starts reading again arms `ping` afresh.
- **The server's close takes the one deadline** for its own. The clock does not run again; reading stopped after it leaves the close's deadline armed.

Each read re-arms the clock, which costs the step 32 B a read, measured three times: one action, and its place in the list.

**`tests/test-protocol.sps`, 84 checks**, 12 of them new:
- a new connection's deadline;
- the ping, and the pong's timeout;
- what re-arms the clock, and what does not;
- the clock stopped with reading, the server's close, and every end;
- pinging off;
- the API;
- the deadline named after each step, against the actions.

The suite's `lim` and `open` now turn pinging off, so a check of messages or closes sees no clock. The three checks that run at the default limits hold the clock's actions too: the cap, the 16-message queue, and the stall behind it.

**The oracles.** Decision 0001's item 2 and the design's §5. RFC 6455's raw text: §5.5.2, a ping may carry no payload; §5.5.3, an unsolicited pong; §7.4.1, 1011. websockets 17.2 at the tag: its keepalive pings every 20 s, busy or not, with four random bytes, and fails with 1011 when no pong comes in 20 s. ws 7.5.10 keeps no clock. Fed the suite's 730 connections, no answer disagreed; the 13 whose ping or pong deadline passed are the clock's, not replayed.

**Taken without a form:**
- **How the clock starts:** `ws-deadline`, a new export, which the binding reads as it starts. (Corrected by M3.3's review: this runs the other way from the server, whose shell names a new connection's first deadline itself, `idle`, and arms it, never reading its core's `conn-deadline`.)
- **When reading starts again, the clock starts afresh at `ping`**, though a ping was out when it stopped. 0001 says the clock "runs again once reading does".
- **The ping carries no payload.** 0001's consequences count it at 2 bytes. websockets' carries four random bytes, to match its pong.
- **The failure's close is 1011 with no reason**, as every failure's is, and `ping-timeout` is logged. websockets writes "keepalive ping timeout".

**Found while writing the mutants:** reading stopped after the server's close left the close's deadline armed, and no check held it. A `stop-clock!` that disarmed it, K-15, passed all 84 checks. The close check gained a row, and K-15 fails it.

**Tests first.** Named and hashed before the runs:
- against main's library, the suite stopped at once: `ws-deadline` unbound, exit 255;
- against main's library with a stub `ws-deadline` answering #f: 70 passes, and 14 red, exactly as named. They were the clock's eleven checks, all but the one for pinging off, and the three at the default limits.

**224 mutants and a baseline** (m3-mutations.md), each red set named before the run and hashed:
- M3.2's review's 198, seven re-cut where this step rewrote their lines, red sets changed by this step's checks;
- this step's 26.

Two limits mutants, L-12 and L-32, now stop the protocol suite at load: `open`'s interval of 0 is refused. The first run had three mismatches:
- two harness errors, a paren too many in C-5's and K-2's cuts;
- one prediction error: M-40 makes every take but of 0 refused, so five clock checks reddened through that raise.

The second run had 0 mismatches. Every check has a killer that reddens it by value.

`make test` green before the commit (Darwin arm64): eight suites, 222 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: step 2, the protocol's mutation sweep, stacked on this.

---

M3.3, STEP 2 — THE PROTOCOL'S MUTATION SWEEP, AND M3'S EXIT. Branch `test/m3.3-2-sweep`, stacked on `feat/m3.3-1-ping-clock`. 2026-10-05.

**The sweep.** The plan's M3.3 ends with the protocol's mutation sweep. Every guard and branch of `(websocket protocol)` and `(websocket limits)` was listed, as M3.1's review swept them, each with the mutants that flip it. There are 110 (M3.3's review found three more, below):
- 84 an earlier mutant of M3's flipped;
- 18 none flipped, and 3 one way only. The sweep's own mutants, W-1 to W-26, flip each of the 21. They include a close taken for a pong, an empty close read for a code, a data frame ended at every piece, and the reason of a close measured past its end. The sweep also changes five effects no mutant had changed.
- 4 have no mutant run, each recorded with why. Taking out `read!`'s test for a read's end, or flipping its answer to a header not yet whole, loops forever; its test for a header or a payload, flipped, reads no frame with a payload; and `header!`'s dispatch by kind takes every clause the suite reads.
- 1 was taken out.

**What it changed:**
- **`taken!`'s outer test for a full queue is taken out.** No check could tell it from its absence: `read!` stashes what waits again at a full queue, and the inner test asks again. The suite gave 84 passes against step 1's library and against this one.
- **A send of the wrong shape is checked**, a gap the sweep found. Its mutant, W-10, passed all 84 of step 1's checks. P-SENDAPI gained a row of three arguments, and W-10 now fails it.

**250 mutants and a baseline** (m3-mutations.md), each red set named before the run and hashed: step 1's 224, M-74 re-cut and M-79's red set grown, and the sweep's 26.
- **The first run stopped short.** I edited README.org while it ran, and the runner refuses to report on a tree that changed under it.
- **Run again untouched**, it had six mismatches, all prediction errors:
  - M-75 now reaches a take that leaves the queue full;
  - `allocated` keeps the least of three calls, so W-3's one-shot close measured 0 (M3.3's review: the check's gap, not a prediction error);
  - three mutants redden P-PURE through its refused second take;
  - W-8 reddens P-UTF8END through `ended-at`'s byte-at-a-time feed.
- **The final run had 0 mismatches.** Every check, 15 in the limits suite and 84 in the protocol suite, has a killer that reddens it by value.

ws 7.5.10 was fed the final suite's 731 connections. 623 answered the same, 47 stepped nothing, and 13 are the clock's. No answer disagreed.

**M3's exit.** The protocol is done: whole messages, the cap, UTF-8 as it comes, reading on with a bounded queue, the closing handshake, and the ping clock, as steps that read no clock and do no I/O. README.org's status says so.

`make test` green before the commit (Darwin arm64): eight suites, 222 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: M4.1, the handshake, when the owner asks; first this step and step 1 go through review and the closing ritual.

---

M3.3'S REVIEW — THE FIXES. Branch `fix/m3.3-review`, stacked on `test/m3.3-2-sweep`. 2026-10-06.

On the owner's `/code-review` at max effort, over #23 and #24: 15 findings, then "fix all". One choice was the owner's.

**DECIDED by form (2026-10-06), the recommended: "Any bytes"**, for "While a ping waits for its pong, what should count as the client answering?". Any bytes received re-arm ping while the pong is awaited too, as built. 0001 is amended: the connection fails 1011 if nothing comes within 20 s of the ping. Weighed: "Only a pong", websockets' rule, under which a live client whose pong waits behind its own 1,000-byte frame, half arrived, was failed with 1011.

**`(websocket protocol)`**:
- **`arm!` and `disarm!`** change the record and the action together. Every arm and disarm goes through them, so the slips the mutants make by hand cannot be written by accident (findings 3, 15).
- **The clock's stop moved from `deliver!` to `bytes!`**, after the read's own actions: `deliver!` is the queue's again (finding 15).
- **Re-arming allocates nothing.** A re-armed step's actions are reversed onto a constant tail, the server's `continued` idiom. A read cost 32 B more with pinging on; now it costs the same (finding 9).
- **An empty read re-arms nothing**, as "any bytes received" says (finding 14).
- **`read-waiting!`** is the read of what waits, at a take bounded and at the end not. `taken!` and `finish!` each had their own.
- Comments: the header's close-deadline bullet, `end!`'s invariant, the record's field, `ws-deadline`'s (finding 11).

**`tests/test-protocol.sps`, 85 checks**, one new:
- **K-ALLOC**: re-arming allocates nothing, pinging on against off, for one byte of a header, a message, a ping answered, and a take that starts reading again (finding 9).
- **K-REARM**: a ping answered and a message in one read, so the order of a re-armed read's own actions is held (finding 9).
- **K-ENDS**: a message before a failure, and a ping answered before a close, in one read, so an end keeps its step's earlier actions (finding 4).
- **K-API**: a passing after a client's close with ping armed, and after a failure with pong armed (finding 3).
- **K-AGREE** compares each step's named deadline with what its actions told, in five sequences: ended with ping or pong armed, and with pinging off (findings 7, 13).
- **K-PONGWAIT**: an empty read while the pong is awaited, then 1011 (finding 14). Renamed, with K-QUIET (finding 13).
- **P-API**: three improper lists (finding 5).
- **C-CLOSEALLOC** measures each close on a connection made afresh. `allocated` calls its thunk three times, so a close the first call wrote measured 0 (finding 8).
- `open` is made in the suite's body, so limits that refuse it are a harness error, exit 2, not exit 255.

**Records** (findings 1, 2, 6, 10, 11, 12):
- **0001's amendment of 2026-10-06**, by form, with the consequence it leaves: "a dead client is found within 40 s" holds while the server reads. A full queue stops the clock and leaves nothing armed (finding 1).
- **The design's §5**: the ping clock as amended; the pong's 20 s start when the ping is queued; re-arming allocates nothing. **§9**: the unforceable close widened to every close of a client that does not read, the pong's 1011 among them (finding 6); a client that sends and does not read, for M4's send side (findings 1, 2); when the pong's time starts, for M4.3's throttled reader (finding 10); the transport's deadline re-armed every read, about 56 ns.
- **The plan's M4.3**: a client silent after the 101, pinged and failed 1011, so a binding that never arms `ws-deadline`'s deadline fails it (finding 12).
- **Corrected**: every "N mutants and a baseline" since M3.1's review counted the baseline twice (144, 173, 178, 184, 198, 224 and 250); step 1's precedent for `ws-deadline` ran the other way, since the server's shell names its first deadline itself; step 2's reasons for the four rows with no mutant; W-3's C-CLOSEALLOC green was the check's gap, not a prediction error; the suite's header now says ws was fed every case but the clock's.

**Kept, with its reason** (finding 12): the first deadline stays out of band. The server arms its own first deadline out of band too: its shell chooses `idle`. M4.3's silent-client check holds a binding that forgets.

**Tests first.** Named and hashed before the run (`eb0e8dd`): against #24's library, 83 passes and 2 red, exactly as named: K-ALLOC, `(32 32 32 32)`, and K-PONGWAIT, whose empty read re-armed ping.

**Mutants** (m3-mutations.md), each red set named before its run and hashed:
- **The first run**, 269 rows: the sweep's 250 mutants and the baseline, 34 re-cut where the fixes rewrote their lines, red sets changed by the review's suite, and the review's 18, X-1 to X-18. Three mismatches:
  - C-25's re-cut left a paren too many, a harness error;
  - C-5 and K-2 were prediction errors, one cause: the stop in `bytes!` disarms whatever is armed, by the invariant that ping or pong is then, where `stop-clock!` asked for ping or pong. Each mutant breaks the invariant, so three default-limit checks no longer see them.
- **A second batch**, X-19 and X-20: the new guards the other way, named while listing them.
- **The final run**, 271 rows, 270 mutants and the baseline: 0 mismatches.
- **The gap run**, the review's library against #24's suite, 19 rows: 0 mismatches. Each review gap passes #24's suite whole.

Every check, 15 in the limits suite and 85 in the protocol suite, has a killer that reddens it by value, and each new row one through that row.

**The sweep, redone.** Step 2's inventory missed `event-of!`'s test for a list, and the other way of `room!`'s `max` and of `read!`'s `min`; X-5, X-6 and X-7 flip them. Listed again for the fixed library: 114 guards and branches, and 16 effects.

**ws 7.5.10** was fed the suite's 784 connections: 670 answered the same, 50 stepped nothing, and 16 are the clock's. No answer disagreed.

`make test` green before the commit (Darwin arm64): eight suites, 223 expected passes, every pin ok. The protocol suite was green over 30 runs. `make prod` green.

NEXT: the closing ritual for #23, #24 and this PR, when the owner asks; then M4.1.

---

MERGED to main on 2026-10-06: **M3.3, the ping clock, the protocol's mutation sweep and M3's exit, and M3.3's review** (the three entries above), from the stacked #23, #24, #25 and #26, as 4b506cc, 53270b6, 9e4e9db and 5c4f602, on the owner's "do closing ritual".
- **The squashes.** Each has the tree of the head CI tested:
  - 4b506cc has b68c834's, on e2eadb5;
  - 53270b6 has 1daeda7's, on 4b506cc;
  - 9e4e9db has 315e64a's, on 53270b6;
  - 5c4f602 has 6823e67's, on 9e4e9db.

  #24 was rebased onto 4b506cc from dd532f7, #25 onto 53270b6 from b927c0f, and #26 onto 9e4e9db from a3fc3f8. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #23 at b68c834 (run 37440548682): eight suites, 222 expected passes;
  - #24, rebased onto #23's squash, at 1daeda7 (run 37494502843): eight suites, 222;
  - #25, rebased onto #24's squash, at 315e64a (run 37494959966): eight suites, 223;
  - #26, rebased onto #25's squash, at 6823e67 (run 37495388407): eight suites, 223.

  Main's runs on 4b506cc (37494458004), 53270b6 (37494915633) and 9e4e9db (37495348555) each finished before the next merge. Main's run on 5c4f602, 37495752429, was green too, and this reflect was pushed after it.
- **The squash bodies of #23 and #24** say "224 mutants and a baseline" and "250", as the review corrected their commits' 225 and 251. #24's also says the review found three guards and branches its sweep missed.
- **Branches.** `feat/m3.3-1-ping-clock`, `test/m3.3-2-sweep`, `fix/m3.3-review` and `docs/m3.3-review-ledger` were deleted, local and remote. No PR is open.

**M3 is complete on main**: the protocol, `(websocket protocol)` and `(websocket limits)`, with M3.3's review's fixes.

`make test` green on main: eight suites, 223 expected passes, every pin ok.

NEXT: M4.1, the handshake (`(websocket handshake)`: design §3's checks and answers, subprotocols, and `Origin` by form), when the owner asks.

---

M4.1 — THE HANDSHAKE. Branches `docs/m4.1-1-decision`, `feat/m4.1-2-handshake` and `docs/m4.1-3-ledger`, stacked (by form, "Three stacked PRs": about 1,140 lines, over the ~400 mark). 2026-10-06.

**Delivered: `(websocket handshake)`**, pure: it imports `(rnrs)`, `(websocket sha1)` and `(websocket base64)`.
- **`handshake-answer`** is given the method, a reader of the request's fields and the request's host, as the server's `request-method`, `request-header` and `request-host` read them, and the handler's subprotocols and origins.
- **It answers** the 101's fields and the subprotocol chosen, or a refusal: its status, its fields, and the check that failed. The 101 carries `Upgrade: websocket`, `Sec-WebSocket-Accept`, and `Sec-WebSocket-Protocol` when a subprotocol is chosen.
- **The design's §3 checks, in its order**: method, Upgrade, Connection, version, key, Origin.
  - Upgrade and Connection are read as lists, without regard to case.
  - A key's last digit may set bits past its data, and the accept value is of the key as sent.
  - A refusal has no body, as the server's own have none.
- **Subprotocols**: the handler's first that the client offered, matched exactly as a whole element; none matching is no header and a 101. The handler's names must be tokens.
- **Origin**: `any`, or a list of origins that may hold `same-host`; no Origin is always accepted.
- The facade, `websocket-accept`, is M4.3's.

**DECIDED (0003), by form, each the recommended:**
- **"Same host"**: a handler that names no origins accepts an Origin of the request's own host, or none, and refuses others 403, coder's and gorilla's way.
- **"400 with 13"**: a wrong version is refused 400 with `Sec-WebSocket-Version: 13`, not the design's 426. RFC 9110 has a 426 carry `Upgrade`, with `upgrade` in `Connection`, and the server lets no response but a 101 say that.

**Measured** (Darwin arm64, server v0.3.0):
- **Chrome 152, against a probe on the server.** A page of the same origin sent `Origin: http://127.0.0.1:18741` with `Host: 127.0.0.1:18741`. A page on localhost sent `Origin: http://localhost:18741` to the same server.
- **Fields split over two lines.** The server opens its door to a Connection or an Upgrade list split that way, but `request-header` reads only the first line. That gap is recorded in the design's §9, for M4.3's facade.
- **A handler's 426.** With `Connection: upgrade`, the server answers 500. With `Upgrade` alone, it goes out with `Connection: close` to an upgrade request.
- **The research.** A Sonnet agent read the five peers, Autobahn's fuzzing client and Caddy from source at their tags, quotes checked by a script (`.plans/research/2026-10-06-peer-handshakes.md`). No peer answers a version with 426. Autobahn sends no `Origin`. Caddy passes `Host` and `Origin` unchanged to a plaintext upstream.

**Tests first.**
- **Before the library:** exit 255.
- **Decision 0003's checks**, named and hashed before the run (`32982d4`). Against the library before 0003, exactly R-VERSION, R-ORDER and O-DEFAULT went red.

**Mutants** (`m4-mutations.md`), each red set named before its run and hashed:
- **The first run**, 99 rows. Two mismatches, both prediction errors: O-14 and L-14 reach O-HOST too.
- **The last**, on the final blobs: 102 rows, 101 mutants and the baseline, 0 mismatches.
- L-2 is equivalent.
- Every one of the 23 checks has a killer by value.

Writing the mutants added rows that the draft suite would have let pass, and P-TOKEN, a check of its own. Each row has its mutant: an element with OWS after it, a value one character apart, untrimmed lists, a Z, an Origin missing its colon, a `://` that ends the Origin, and the token's character classes. It also made `origin-accepted?` a `cond`, and added S-4, so that every check has a killer by value.

**A real client.** Chrome 152 ran against a scratch probe answering with the library:
- a page of the same origin opened, with `protocol` superchat, the handler's first preference among the client's two, and no extensions;
- a page on localhost was refused 403 when it called 127.0.0.1, and opened when it called localhost.

**Records:**
- decision 0003, and the research;
- the design's §3, as built, and its §9: Origin decided, and a field split over lines, for M4.3;
- the plan's M4.1 and M4.3;
- the README's status.

`make test` green before the commit (Darwin arm64): nine suites, 247 expected passes, every pin ok. `make prod` green.

NEXT: review and the closing ritual, when the owner asks; then M4.2, the binding's test driver, by form.

---

M4.1'S REVIEW. Branches `fix/m4.1-review` and `docs/m4.1-review-ledger`, stacked on `docs/m4.1-3-ledger` (by form, "Two stacked PRs": 800 lines). 2026-10-06.

`/code-review` at high effort over #27 to #29 reported six findings. The owner discussed the first, and decided it on their word: "compare with X-Forwarded-Proto". Then: "fix the rest".

**DECIDED on the owner's word (0003's amendment): the scheme, when a proxy names it.**
- **The gap.** `same-host` compared only host and port, as coder and gorilla do. A browser leaves default ports out of both fields, so a page on `http://app.example.com` passed for `wss://app.example.com`. Behind Caddy, only a network attacker can make such a page.
- **The discussion's facts:**
  - Caddy writes `X-Forwarded-Proto` and replaces a client's; a browser cannot set it on a handshake.
  - Caddy sends no HSTS unless told to.
  - Chrome sends only `SameSite=None` cookies across schemes (Chrome's platform status).
  - Chrome 152 would not let an https page open `ws://`. Measured: a `SecurityError` for `ws://example.com`; sockets to `ws://127.0.0.1` and `ws://localhost` never reached the server.
- **The rule.** When `X-Forwarded-Proto` names `http` or `https`, `same-host` also needs the Origin's scheme to be that one. Any other value, or none, is not compared, so the check only ever refuses more.
- **Weighed:** "Keep host-only". A prototype, measured before the owner chose, was 20 lines and passed M4.1's 23 checks unchanged.

**The rest, fixed:**
- **An empty `Origin`** is refused under `same-host`, as M4.1 built it and as gorilla does. It names no host (RFC 6454 §7.1). This is now recorded in the design's §3 and held by rows in O-SAME, O-LIST and O-ANY. Taken without a form.
- **The design's §9:** a split `Sec-WebSocket-Protocol` is not refused 400. Its later offers are missed, and the 101 goes without them.
- **Fresh values.** Each answer's fields and its subprotocol's string are made for it (H-FRESH).
- **The server's rules move to the door suite** (D-SERVER), so the handshake's suite needs no server, as the plan says.
- **Settings checked once.** `make-handshake-settings` checks a handler's subprotocols and origins where they are made, and keeps copies (P-SETTINGS, P-KEEP). `handshake-answer` takes the settings.

**Tests first**, each named and hashed before its run:
- the review's suites against #29's library stopped at load, exit 255 (`3a9ccdc`);
- against stage 1, the settings API alone, exactly O-SCHEME, P-API, H-FRESH and P-KEEP went red, each for its named reason (`678dc43`).

**Mutants** (`m4-mutations.md`), each red set named before the run and hashed (`6684df1`):
- **All of M4.1's mutants, re-cut and re-predicted** on the review's library, and the review's own: A-29, and X-1 to X-18.
- **121 rows, 120 mutants and the baseline: 0 mismatches**, on the first run.
- **The gap run.** X-9, an empty Origin taken as none, passes #29's suite whole (23 passes). The review's suite reddens it.
- **L-2** is still equivalent.
- **Every check has a killer by value**: the handshake suite's 26, and D-SERVER.

**Records:**
- 0003's amendment, with its sources;
- the design's §3 (settings, fresh values, the scheme, the empty `Origin`), §8 (the door suite holds the server's rules) and §9;
- the research's section for the review.

`make test` green before the commit (Darwin arm64): nine suites, 251 expected passes, every pin ok. `make prod` green.

NEXT: the closing ritual for #27, #28, #29 and this review's PR, when the owner asks; then M4.2, the binding's test driver, by form.

---

MERGED to main on 2026-10-07: **M4.1, the handshake, and its review** (the two entries above), from the stacked #27, #28, #29, #30 and #31, as 2237959, 455e12e, fc1e09d, 2e2503a and ec26833, on the owner's "do closing ritual".
- **The squashes.** Each has the tree of the head CI tested:
  - 2237959 has 6150228's, on 6d8e59a;
  - 455e12e has 283ab80's, on 2237959;
  - fc1e09d has 8f75855's, on 455e12e;
  - 2e2503a has 005835e's, on fc1e09d;
  - ec26833 has 6b97cc9's, on 2e2503a.

  #28 was rebased onto #27's squash from f8936d8, #29 onto #28's from 64d9db1, #30 onto #29's from f6d588e, and #31 onto #30's from 40d55b9. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #27 at 6150228 (run 37546839222): eight suites, 223 expected passes;
  - #28, rebased onto #27's squash, at 283ab80 (run 37550934556): nine suites, 247;
  - #29, rebased onto #28's squash, at 8f75855 (run 37551133302): nine suites, 247;
  - #30, rebased onto #29's squash, at 005835e (run 37551319032): nine suites, 251;
  - #31, rebased onto #30's squash, at 6b97cc9 (run 37551504053): nine suites, 251.

  Main's runs on 2237959 (37550909005), 455e12e (37551111314), fc1e09d (37551305476) and 2e2503a (37551489373) each finished before the next merge. Main's run on ec26833, 37551682558, was green too, and this reflect was pushed after it.
- **Branches.** `docs/m4.1-1-decision`, `feat/m4.1-2-handshake`, `docs/m4.1-3-ledger`, `fix/m4.1-review` and `docs/m4.1-review-ledger` were deleted, local and remote. No PR is open.

**M4.1 is complete on main**: `(websocket handshake)`, with decision 0003 and its amendment.

`make test` green on main: nine suites, 251 expected passes, every pin ok.

NEXT: M4.2, the binding's test driver, by form, when the owner asks: the server's fake shell, or a door change in the server (design §8). The door questions in the design's §9 wait with it: a close the transport cannot force, a client that sends and does not read, and a field split over lines.

---

M4.2 — THE BINDING'S TEST DRIVER. Branches `docs/m4.2-1-decision`, `test/m4.2-2-driver` and `docs/m4.2-3-ledger`, stacked (by form, "Three stacked PRs": about 630 lines, over the ~400 mark). 2026-10-08 to 2026-10-09.

**Where it began.** On the owner's "Lets start the next step", M4.2's form chose, each the recommended: "Server's fake shell", "Door change: abort" and "Every line, in the release" (decision 0004).
- The door change went into the server as its decision 0024, stacked #146 to #150, merged 2026-10-09 (the last as 79370d3).
- It shipped in the server's v0.4.0, tagged on 388ec43 on 2026-10-09 (signed; tag object 3eebcd3).

**Delivered:**
- **The pin.** chez-http-server at v0.4.0 (388ec43), on its own commit. It brings chez-libuv v0.7.4 (27d84bb). The other pins it carries are unchanged: chez-httparse 0b7058e, byte-machine c338a57, uriparse 5ecd88f, chez-srfi 7879b52.
- **The server's `tests/`, last on the library path**, for its `(fake-shell)`. Its 23 test libraries share no name with this project's eight, and the directories before it would win any they did.
- **`tests/test-driver.sps`, twelve checks.** The server's fake shell drives a taker shaped as the binding will be (design §6), through the pin:
  - the bytes handed over with the take-over, echoed after the 101;
  - a read resuming the thunk parked on `await`;
  - read-stop and read-start;
  - the deadline on the fake clock: armed at now plus its time, and passing then, not a millisecond before;
  - the drain call, once;
  - a client that reads nothing:
    - a close waits behind the write it has not read;
    - a deadline asked for meanwhile is armed;
    - an abort at that deadline ends the stream, the write told `ECANCELED` and never read;
  - the stream's close while the thunk waits: `&client-closed`, and no failure;
  - a raise in the deadline's call, and one in the waiting thunk: each is the taker's failure, recorded, and closes the stream; the thunk's write is never read;
  - `request-header-values`: every line of a field, in order, through the server's parse; and `request-header`, the first.
- **The door suite**: an abort is handed to a transport's eighth procedure.

**Records:**
- decision 0004, from its draft of 2026-10-08;
- the design's §8 (the binding runs on the fake shell) and §9:
  - three items decided: a field split over lines, the driver, and a close the transport cannot force;
  - the send side's bound still M4.3's, by form;
- the plan's M4.2 and M4.3;
- the README's `make submodules` line.

**Corrected while writing: the form's "7 of 7".** The form said the fake shell "passed 7 of 7 scenarios at v0.3.0". The prototype ran S1 to S7, and S6, a deadline asked for after the close, was one of the three differences it named. Decision 0004 records six.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **Stage 0, on v0.3.0** (`550cfc1`): both new suites stopped at load, `transport-abort!` unbound, exit 255. The other eight passed: 246.
- **Stage 1, on v0.4.0** (`560f2b6`): every suite green.
  - The prediction said 11 checks in the driver suite, as stage 0's did. It has 12, a miscount of my own.
- **The gap run** (`1c8b920`): the driver suite on v0.4.0, with v0.3.0's fake shell first on the path. Exactly the four predicted went red, each for its reason:
  - the deadline asked for while the close waits (`#f`);
  - the abort (no deadline, so the client read the write);
  - the deadline's raise (it escaped to the test);
  - the thunk's raise (its write was read).

**Mutants** (`m4-mutations.md`):
- 27 mutants of the pinned server's fake shell, transport and view, each applied alone to a copy first on the library path, and the baseline.
- **28 rows, 0 mismatches**, on the first run (specs `7b25053`).
- Every new or changed check has a killer by value.
- The drain's "once" is held by two guards, the shell's and the taker's. Taking either away alone leaves the check passing; taking both reddens it.

`make test` green before the commit (Darwin arm64): ten suites, 264 expected passes, every pin ok. `make prod` green.

NEXT: review and the closing ritual, when the owner asks; then M4.3, the binding.

---

M4.2'S REVIEW. Branch `fix/m4.2-review`, stacked on `docs/m4.2-3-ledger`. 2026-10-09.

`/code-review` at extra-high effort over #32 to #34 reported nine findings. The owner said "fix all".

**The pin, alone (finding 1).** The closing ritual squashes each PR, so #33 would have landed the pin and the driver as one commit on main, where a pin moves alone (global-constraints).
- The pin commit, a2c6904, is now #35, based on #32; #33 is based on it.
- Nothing was rewritten: the stack is #32, #35, #33, #34 and this PR, renamed "1 of 4" to "4 of 4".

**The suites' path (findings 6, 7, 9).**
- **`TEST_LIBDIRS`.** The server's `tests/` is on the suites' path alone, last. chez-httparse's test harness is beside it, which the server's `(response-reader)` needs.
- **`make test` refuses to run** if either is on `LIBDIRS`, the path `make run` and `make dev` use.
- **D-NAMES** checks, by Chez's reader, that no borrowed library has one of this project's names, and that the fake shell and the response reader are among them.
- **`client-reads`** reads what the client read as a client would, by `(response-reader)`, not at bytes 9 to 12. Under a serializer whose status line ends in a bare LF, the old suite passed all 12 checks, and the review's reddens seven.

**The driver suite (findings 2, 3).**
- **How a test plays the client.** `fake-shell-deliver!` hands a taker its events whatever the read state. Only `fake-shell-feed-input!` honours read-stop, as libuv does. The suite's header and the design's §8 say so.
- **D-INSIDE** holds a read stopped from inside the taker's read, as the binding stops at a full queue.
- **D-BEHIND** arms a deadline before the close, so a close that had begun at once would show, disarmed.

**The records (findings 4, 5, 8).**
- The design's §6 names `transport-abort!` beside `close-stream`.
- The log's M-2 premise is corrected, and M-2 ran.
- The design's §9 says whose the server's numbers are, and M4.3 measures them again at the pin.
- Decision 0004 gains an amendment for the path, the client, and the pin's own PR.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **R0, the review's suites on the unmutated pin**: every suite green, 266 passes.
- **The runner: 33 rows, 1 mismatch, M-5.** I predicted read-start's mutant would redden D-INSIDE too, from a premise not checked: that the core stops reading when it calls the handler. For a GET with no body it does not. A probe found the connection reading through the hand-off, as the libuv shell's is.
- **The other rows, each as predicted:** two scratch trees for D-NAMES, two Makefile mutants, and the gap run.
- Every new or changed check has a killer by value.

`make test` green before the commit (Darwin arm64): ten suites, 266 expected passes, every pin ok. `make prod` green.

NEXT: the closing ritual for #32, #35, #33, #34 and this PR, bottom-up, when the owner asks; then M4.3, the binding.

---

MERGED to main on 2026-10-09, on the owner's "all green lets do the closing ritual": **M4.2, the binding's test driver, and its review** (the two entries above), from the stacked #32, #35, #33, #34 and #36, as 226bafa, 7f3ec58, 6555055, 38b4f76 and 6a9b997, bottom-up.
- **The squashes.** Each has the tree of the head CI tested:
  - 226bafa has 4140ae2's, on b1c9a3b;
  - 7f3ec58 has f688bd6's, on 226bafa: the pin alone on main, as the review asked;
  - 6555055 has 3532fcf's, on 7f3ec58;
  - 38b4f76 has a59c2de's, on 6555055;
  - 6a9b997 has 44e775a's, on 38b4f76.

  #35 was rebased onto #32's squash from a2c6904, #33 onto #35's from 2351f32, #34 onto #33's from 0f9d1dd, and #36 onto #34's from 4d08cae. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #32 at 4140ae2 (run 37912373312): nine suites, 251 expected passes;
  - #35, rebased onto #32's squash, at f688bd6 (run 37916108397): nine suites, 251;
  - #33, rebased onto #35's squash, at 3532fcf (run 37916328821): ten suites, 264;
  - #34, rebased onto #33's squash, at a59c2de (run 37916548401): ten suites, 264;
  - #36, rebased onto #34's squash, at 44e775a (run 37916761359): ten suites, 266.

  Main's runs on 226bafa (37916077209), 7f3ec58 (37916312031), 6555055 (37916529543) and 38b4f76 (37916744860) each finished before the next merge. Main's run on 6a9b997, 37916959722, was green too, and this reflect was pushed after it.
- **The subjects.** The squashes' subjects are the PRs' titles, "1 of 4" to "4 of 4". The commits inside #32, #33 and #34 still say "1 of 3" to "3 of 3", from before the review split the pin out.
- **Branches.** `docs/m4.2-1-decision`, `chore/m4.2-pin`, `test/m4.2-2-driver`, `docs/m4.2-3-ledger` and `fix/m4.2-review` were deleted, local and remote. No PR is open.

**M4.2 is complete on main:**
- decision 0004 and its amendment;
- the server pinned at v0.4.0, with chez-libuv v0.7.4;
- the suites' own path, with the server's fake shell on it;
- the driver suite.

`make test` green on main: ten suites, 266 expected passes, every pin ok.

NEXT: M4.3, the binding (`(websocket private binding)` and the facade), when the owner asks.

---

M4.3, STEP 1 — THE BINDING AND THE FACADE. Branches `docs/m4.3-1-design`, `feat/m4.3-1-binding` and `docs/m4.3-1-ledger`, stacked from main at 9135b59 (by form, "Three stacked PRs": about 1,480 lines, over the ~400 mark). 2026-10-09.

**Where it began.** On the owner's "Start m4.3". M4.3 is built in three steps, as the plan now says:
1. the binding and the facade, on the fake shell;
2. a client that does not read, with the send side's bound by form;
3. the real socket and the measures.

**Delivered:**
- **`(websocket private binding)`**, the shell of the design's §6. `websocket-accept` checks the handshake and answers a refusal or the switch.
  - It reads every line of a field, joined with ", " (0004).
  - The take-over makes the core's state, arms the deadline `ws-deadline` names, starts reading, feeds the core the bytes the server read past the request, registers the drain's close of 1001 "going away", and answers `(awaiting thunk)`.
  - Every action is performed at once, as the design's table has it. A `log` is a line on the current output port, as the server logs, prefixed `websocket-`.
- **The verbs.**
  - `websocket-receive` waits on `await`, answers queued messages before the end, and keeps a text's leading U+FEFF.
  - `websocket-send!` waits past the high water until the low water, as the server's streams do.
  - `websocket-close!` takes a code and a reason, or neither.
  - Once the connection has ended, `&websocket-closed` carries its code, reason and whether it closed cleanly.
- **The procedure's end.** Its return closes with 1000. A `&websocket-closed` or `&client-closed` it lets out does nothing more. Any other raise closes with 1011 and is logged `websocket-handler-failed`.
- **`(websocket)`, the facade**: the verbs, `make-handshake-settings`, the limits' constructors and accessors, and `environment-websocket-limits`, read as the program starts.
- **The import audit names its two exceptions**: the binding may import `(chezscheme)` and `(http-server)`, and the facade the binding. It checks that both are among the sources.
- **`tests/test-binding.sps`, 35 checks** on the server's fake shell, and a child program, `tests/start-with-environment.sps`, for the environment.

**Where it departs from the design, recorded in its §6 and §8:**
- **A send while the server's close is under way** sends nothing, waits for the end, and raises. The design was silent here; this is websockets' way.
- **No close call.** The binding registers none. Both shells tell the wait first, so a close call's wake would come after the wait had ended: a late resume. It was tried and taken out.
- **The log.** The design's table had no `log` row.
- **A `&client-closed` let out**, from a wait of the procedure's own, does nothing more.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **Stage 0:** the suite stopped at load, `(websocket)` not found, exit 255. The other ten suites were green: 266.
- **Stage 1:** a fault in the suite, not the binding. In Chez, `(rnrs)`'s `current-output-port` cannot be given to `parameterize`, and the suite stopped after 21 passes. Fixed, it gave 296, as predicted.
- **Stages 1c and 1d:** 299 and 304, as predicted. The mutant draft found eight checks missing, and they were added before the run.

**Mutants** (`m4-mutations.md`): the binding's, on a copy first on the suites' path, and the audit's, on a scratch tree.
- **Run 1: 83 rows, 1 mismatch**, K-16. My premise was wrong: the fake's timer does not drain the scheduler, so C-TIMEOUT had been seeing the stream's close. It now drains after each fire, as the libuv shell drains after every turn.
- **Run 2: 1 mismatch**, K-48. The changed check now saw it, and I had not predicted again the rows it reads.
- **Run 4: 86 rows, 85 mutants and the baseline, 0 mismatches**, with M-BOM gaining three texts one byte off U+FEFF.
- **Every new or changed check has a killer by value.**
- **Three survivors, as predicted** (K-45, K-50, K-50b): each a late resume, which the fake logs nowhere. Step 3's real socket holds them.

**CI's first run found the suite naming Chez `chez`.** Run 37921568542 failed V-ENV, (127 127): CI names Chez `scheme`, in `CHEZ`.
- The child now runs `"${CHEZ:-chez}"`. Shown red first on a PATH holding Chez only as `scheme`, then green: 35 there, and 304 under `make test`.
- Run 5 of the mutants, on the fixed suite: 86 rows, 0 mismatches.
- The fix is its own commit on the binding's branch. The ledger was rebased onto it.

`make test` green before the commit (Darwin arm64): eleven suites, 304 expected passes, every pin ok.

NEXT: step 2, a client that does not read: the abort where the binding closes such a client, and the send side's bound by form, measured on this binding first.

---

M4.3 STEP 1'S REVIEW. Branches `docs/m4.3-1-review-decisions`, `fix/m4.3-1-review` and `docs/m4.3-1-review-ledger`, stacked on `docs/m4.3-1-ledger` (#39) (by form, "Three stacked PRs": about 900 lines). 2026-10-09.

`/code-review` at extra-high effort over #37 to #39 reported twelve findings. The owner said "Fix all". Two needed a choice, made by form after the peers' and the proxies' sources were read (a Sonnet agent, its citations checked by hand):
- **"Many senders, one receive"**: decision 0005.
- **"Leftmost element"**: decision 0003's amendment of 2026-10-09.

**Fixed:**
1. **A wait's `&client-closed` is its own coroutine's stream's.** A procedure waiting on another connection's WebSocket, whose own client left, used to end that other connection. Now:
   - each waiter carries the WebSocket whose procedure waits in it, from a parameter set around the procedure;
   - the close on another's WebSocket goes on out, to the procedure whose stream closed.
2. **Many senders, one receive** (0005).
   - Senders waiting on one WebSocket all go on together at the low water. A second sender used to overwrite the first's resume.
   - A second receive while one waits is refused, naming `websocket-receive`.
3. **Another WebSocket's `&websocket-closed`, let out of a procedure,** is any other raise: 1011, logged. It used to leave the procedure's own connection open with nobody reading.
4. **The close call is back** (`transport-on-close!`). It marks the wait the WebSocket's procedure is in as ended, wherever it waits, then steps the stream's end. So a procedure that spent its `&client-closed` in a wait of its own no longer waits forever at its next receive.
5. **X-Forwarded-Proto is read by its leftmost element** (0003's amendment). A list used to skip the Origin's scheme check.
6. **The suites run with no `CHEZ_WS_` variable set.** The Makefile unsets them, and the binding suite refuses to run otherwise.
7. **The verbs refuse their own mistakes, naming themselves.** `websocket-close!` refuses a bad code or reason, by the core's new `ws-sendable-close?`, and `websocket-accept` refuses bad settings.
9. **A read costs the binding nothing beyond the transport's own work.** It allocated 80 B (measured against a taker that only re-arms its deadline). It now fills in a read event and a take event made once, and performs a step's actions by a loop.
10. **The binding asks the core whether it is open,** `ws-open?`, and keeps no closing flag of its own.
11. **The log lines are checked against the server's own `log-line`.**
12. **C-OUTSIDE closes the stream with the abort,** as the server's own close is at once.

**Skipped, as it needs a door change: finding 8.**
- **The gap.** A message delivered in the turn a handler's own deadline ends its receive wakes a wait that has ended. The server logs `late-resume await`, and the message stays queued.
- **Why.** The server's waits give no way to ask whether a wait still stands.
- **Where it is held.** It is in the design's §9, and R-DEADLINE holds that such a receive lets go of its wait.

**Records:**
- decision 0005;
- 0003's amendment;
- the design's §3, §6 and §9, and §8: two connections at once, what a read costs, the suites' environment, and what the fake cannot show.

**Tests first** (`m4-mutations.md`):
- **R0:** the protocol suite stopped at load; the binding suite red in exactly its five new checks; with a variable set, exit 2.
- **R0':** the forms' checks red, as predicted: eight in the binding suite, and the scheme check in the handshake suite.
- **Two runs were not hashed before they ran**, and each is recorded as such: R1's first run of the fixed tree, and the green run after three checks were widened.

**Mutants:** every earlier one re-cut against the rewritten binding and predicted again.
- **Run 1: 106 rows, 1 mismatch**, K-34b. X-FOREIGN-CLOSED passed on an assertion of the same text as the test's own, so it now also holds that what was raised is a `&websocket-closed`.
- **Run 2: 106 rows, 0 mismatches.**
- **Run 3:** the two mutants that undo the allocation fix, both red.
- **Five survivors, as predicted:** four late resumes the fake logs nowhere, and a read's bytevector kept. Step 3's real socket and footprint hold them.

`make test` green before the commit (Darwin arm64): eleven suites, 316 expected passes, every pin ok. `make prod` green.

NEXT: the PRs by form; then review and the closing ritual for #37 to #39 and this, when the owner asks; then step 2.

---

MERGED to main on 2026-10-09, on the owner's "all green lets do the closing ritual": **M4.3 step 1, and its review** (the two entries above), from the stacked #37 to #42, as c3936e8, a2d66d1, c6fb0b9, 7e1de70, c24e336 and 7548fcb, bottom-up.
- **The squashes.** Each has the tree of the head CI tested:
  - c3936e8 has 200915b's, on 9135b59;
  - a2d66d1 has 80dd5d8's, on c3936e8;
  - c6fb0b9 has d1c3e95's, on a2d66d1;
  - 7e1de70 has c98de54's, on c6fb0b9;
  - c24e336 has a3f45bb's, on 7e1de70;
  - 7548fcb has 348d838's, on c24e336.

  #38 was rebased onto #37's squash from df90789 (its two commits), #39 onto #38's from a92b7da (its two), #40 onto #39's from 0753d36, #41 onto #40's from 44fde97, and #42 onto #41's from 10a8074. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #37 at 200915b (run 37921560910): ten suites, 266;
  - #38, rebased, at 80dd5d8 (run 37929141243): eleven suites, 304;
  - #39 at d1c3e95 (run 37929372123): 304;
  - #40 at c98de54 (run 37929601512): 304;
  - #41 at a3f45bb (run 37929828514): 316;
  - #42 at 348d838 (run 37930058902): 316.

  Main's runs on c3936e8 (37929110860), a2d66d1 (37929352468), c6fb0b9 (37929584841), 7e1de70 (37929813717) and c24e336 (37930043456) each finished green before the next merge. This reflect was pushed after main's run on 7548fcb, 37930275643, green.
- **Branches.** `docs/m4.3-1-design`, `feat/m4.3-1-binding`, `docs/m4.3-1-ledger`, `docs/m4.3-1-review-decisions`, `fix/m4.3-1-review` and `docs/m4.3-1-review-ledger` were deleted, local and remote. No PR is open.

**M4.3 step 1 is complete on main:**
- the binding and the facade, held on the server's fake shell;
- decision 0005, many senders and one receive;
- decision 0003's amendment, X-Forwarded-Proto's leftmost element;
- the suites run with no `CHEZ_WS_` variable set.

`make test` green on main: eleven suites, 316 expected passes, every pin ok.

NEXT: M4.3 step 2, a client that does not read: the abort where the binding closes such a client, and the send side's bound by form, measured on this binding first. Step 3's real socket carries the five survivors: four late resumes the fake logs nowhere, and a read's bytevector kept.

---

M4.3 STEP 2: a client that does not read. Branches `docs/m4.3-2-design`, `feat/m4.3-2-bound` and `docs/m4.3-2-ledger`, stacked on main 1d8ed80 (by form, "Three stacked PRs": about 1,240 lines). 2026-10-09.

**Measured first**, on main and on the server's fake shell (Darwin arm64): a client that reads nothing after the 101, an hour of fake time.
- Each of the five closes the binding asks for (the close timeout, the pong's, a 1002, a close's echo, the stream's end) waited the hour behind one unread write of 4 to 7 B.
- A send waiting past the high water with the queue full: nothing armed, the hour.
- The same with the client pinging every 10 s: each ping re-armed the clock; 734 B of pongs held.
- 1 MiB of 125-byte pings: all read, 1,016,514 B of pongs held.
- A client reading one write a second, 300 messages of 1 KiB: failed with 1011 at 45 s, 255 sent, the pong's time running from the queued ping.

Three bounds were prototyped and measured the same way, and the peers read at their tags (a Sonnet agent; its citations checked by hand). None of websockets, ws, coder and gorilla bounds a waiting send itself.

**Decision 0006:**
- **Where the binding aborts**, the design's to name (0004): every close gives the client the close timeout to read what was written, then aborts; the close timeout's own passing aborts at once, as websockets' `close_timeout` ends in `transport.abort()`.
- **By form, "Reading stops past the high water"**: the core counts what is written and not yet done. Past the high water the client is behind: reading and the ping clock stop, and a write timeout runs, re-armed by each done. At the low water reading starts again. The timeout's passing aborts with 1006, logged `write-timeout`.
- **By form, "60 s, its own variable"**: `CHEZ_WS_WRITE_TIMEOUT`, the server's own `CHEZ_HTTP_WRITE_TIMEOUT`.

**What landed:**
- `(websocket limits)`: `write-timeout-ms`, at least 1 s; the facade exports its accessor; `make test` unsets the variable.
- `(websocket protocol)`: `(written nbytes)`, `(abort-stream)`, the `write` kind and `ws-behind?`. A read stops at the frame that passes the high water, the rest waiting, so a client that does not read makes the server hold the high water and one write past it.
- `(websocket private binding)`: each done stepped, with an event made once; `abort-stream` performed; `close-stream` arms the close timeout, then asks for the close; a send waits while the core says behind. The binding keeps no unsent count of its own.

**Measured again on this tree**, the same probe:
- The closes: the close timeout aborted at 15 s; the pong's at 55 s; the 1002, the echo and the end 10 s after each was asked for.
- A send waiting, with the queue full or the client pinging: aborted at 65 s, 14 B held.
- 1 MiB of pings: reading stopped at 274,432 B in; 2,065 pongs, 262,255 B, held; aborted at 65 s.
- The slow reader: all 300 sent by 197 s. Then failed at 237 s, its ping behind the low water's 64 KiB, as the design's §9 now says: step 3's throttled reader.
- A send and its done, a client that reads: 1,381 B a cycle as on main, about 383 ns against 357. A send that waits for every done: 48.7 B more, the append and the disarm of falling behind and catching up.

**Where it departs from the plan and the design**, each recorded in the design:
- **The bound is the core's, not the binding's.** The form chose it over a binding-only send timeout, which left pongs unbounded.
- **A new variable**, by form.
- **The close timeout now aborts** (M3.2's close timeout closed): the core answers `(abort-stream)`.
- **X-FOREIGN's client reads before it sends**: B reads nothing while behind, and libuv delivers nothing to a stream that does not read.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **Stage 0**: the limits and protocol suites stopped at load; the binding suite red in exactly its six new checks.
- **Stages 1 to 3**: the limits, the core, the binding, each as predicted, to 335.
- **Stage 4**: with `CHEZ_WS_WRITE_TIMEOUT` set, the binding suite refused to run until the Makefile unset it. My prediction's count for the other ten suites was wrong, 320 for 284; the behaviour was as predicted.
- **Stage 5**: four checks the mutant plan found missing, and a redundant clause taken out: 337.

**Mutants:**
- **Run 1: 42 rows, 41 mutants and the baseline, 0 mismatches.**
- **Run 2: step 1's K-16 re-cut**, 0 mismatches.
- **Every new or changed check has a killer by value.**
- **One survivor, as predicted**: the close's deadline armed after the close is asked for, which neither shell can tell from before.

`make test` green before each commit (Darwin arm64): eleven suites, 337 expected passes, every pin ok. `make prod` green.

NEXT: the PRs by form; review and the closing ritual when the owner asks; then step 3: the real socket and the measures, the five survivors of step 1's review, and the pong's timing with a throttled reader.

---

M4.3 STEP 2'S REVIEW. `/code-review` at xhigh over #43 to #45: 12 findings, the owner's "fix all". Branches `docs/m4.3-2-review-decision`, `fix/m4.3-2-review-core`, `fix/m4.3-2-review-binding` and `docs/m4.3-2-review-ledger`, stacked on `docs/m4.3-2-ledger` (by form, "Four stacked PRs": +630 −172; the decision and design 133 lines, the core and limits 187, measured green alone at 339, the binding 311, the ledger 171). 2026-10-09.

**Measured first** (the scratch `rv/measures.md`), on the fake shell, the tree as built beside four prototypes: 64 KiB writes; a send that waits before it writes; and two ways to time a close, "the write timeout, then the close timeout" and "the close timeout, re-armed by each done".
- **The close** (findings 1 and 4): 200 KiB sent then a close, read at 15 KiB/s, was aborted at 15 s, none of the message read. Both prototypes closed it cleanly at 18 s; at 5 KiB/s only the first did. A client reading nothing was aborted 10 s after a close, or 60 s under the first. A close timeout of 0 aborted every close at the next tick.
- **A large message** (finding 3): 10 MiB read at 100 KiB/s was aborted at 65 s as one write, read whole in 64 KiB writes; +14,294 B a 1 MiB send on the fake, a small send unchanged.
- **Many senders** (finding 2): 20 procedures sending 64 KiB to a client reading nothing held 1,310,920 B; 262,184 B with a send that waits before it writes.

**Decided by form**, 0006's amendment:
- **"From queueing, as peers do"**, not the recommended ("Write timeout, then close timeout"): the close timeout runs from the close's queueing, as websockets', ws's and coder's do, documented (25.6 KiB/s at the default high water), and is at least 1 s.
- **"Wait before writing too"**, the recommended.
- **"In 64 KiB writes"**, the recommended, asked again after the owner's "what do peers do": none of websockets, ws, coder and gorilla measures progress inside a message; nginx's `send_timeout` runs between two writes, and the server's own write timeout covers each piece of a streamed body.

**What landed:**
- `(websocket limits)`: the close timeout at least 1 ms, so 1 s read from the environment.
- `(websocket protocol)` (findings 10 and 11): `over-high?`, the one comparison `held?` and `past-high?` share; falling behind's actions consed onto a step's own, not appended; a done that catches the client up, nothing waiting, answers the constant `caught-up`; `written!` tests the phase once. A send that waits for every done costs 2,325.2 B a cycle, main's 2,324.9, not step 2's 2,373.6.
- `(websocket private binding)`: a frame in writes of 64 KiB at most, each done its own (finding 3); a done that tells a failure stepped as the stream's end too (finding 5, the design's); a send that waits before it writes while the client is behind (finding 2).
- The docs (findings 1, 4, 6, 7): 0006's amendment; the design's §5 to §9; the limits' header; the core suite's header.
- The binding suite (findings 8, 9, 12): B-SLOW's 255 derived; `holding` and `spying` share `wrapping`; three older checks drive the clock with `tick!`; a client that reads at a rate, `reading-at!`.

**Measured again on this tree:** 200 KiB then a close at 15 KiB/s is aborted at 15 s, the client given two of its 64 KiB writes; a close timeout of 0 is refused; 10 MiB at 100 KiB/s is read whole; 20 senders hold 262,184 B. A send and its done, 1,381.2 B a cycle, as before.

**Where it departs from the plan and the design**, each recorded in the design:
- **The close keeps its timing**, by form, against the recommendation: a client reading under 25.6 KiB/s loses the end at a close.
- **The close timeout's least is 1 s**, not 0.
- **A send waits before it writes** too, so 0005's "all go on together" is now "each in turn while the client is not behind".
- **A frame goes in several writes.**
- **A failed done ends the connection**: 0006's "whatever it says" now steps the failure as the stream's end too.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **Stage 0**: the tests alone, as predicted: six red, each by value.
- **Stage 1** did not match: four red for none. Three core checks expected the catch-up's disarm, which the first cut dropped as the clock's arm replaces it; it was put back, as a constant. The pieces check's 150 s outlasted the clock armed afresh at the catch-up, a ping written; the check now turns pinging off.
- **Stage 1b**: 341, as predicted. **Stage 2**: W-CLOSING-REARM, the check run 1 found missing: 342, as predicted.

**Mutants:**
- **Run 1: 58 rows, 57 mutants and the baseline, 2 mismatches**, each my prediction: P-EDGE-HIGH's re-cut reaches the read's hold too, and two of step 2's reds no longer happen since findings 10 and 11. And PW-1 reddened W-CLOSING only through a raise, which stage 2's check closed.
- **Run 2: the core's 31 rows and the baseline, 0 mismatches.**
- **Every new or changed check has a killer by value.** The one survivor is step 2's, as predicted.

`make test` green before each commit (Darwin arm64): eleven suites, 342 expected passes, every pin ok. `make prod` green.

NEXT: the PRs by form; review and the closing ritual when the owner asks; then step 3: the real socket and the measures, step 1's review's survivors, and the pong's timing with a throttled reader.

---

MERGED to main on 2026-10-09, on the owner's "all green lets do the closing ritual": **M4.3 step 2, and its review** (the two entries above), from the stacked #43 to #49, as aa8ceea, 9044e73, 4af7472, 677a62f, eb280f7, 1d3bc06 and 3254abf, bottom-up.
- **The squashes.** Each has the tree of the head CI tested:
  - aa8ceea has be263d1's, on 1d8ed80;
  - 9044e73 has 0a67069's, on aa8ceea;
  - 4af7472 has 7477a32's, on 9044e73;
  - 677a62f has f06479f's, on 4af7472;
  - eb280f7 has a7132d3's, on 677a62f;
  - 1d3bc06 has c313cf8's, on eb280f7;
  - 3254abf has 5ea34cb's, on 1d3bc06.

  #44 was rebased onto #43's squash from be263d1, #45 onto #44's from b9c9d77, #46 onto #45's from 01ed4a6, #47 onto #46's from bbfaf36, #48 onto #47's from 523454c, and #49 onto #48's from 2b1d206: one commit each. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #43 at be263d1 (run 37937961012): eleven suites, 316;
  - #44, rebased, at 0a67069 (run 37953647263): 337;
  - #45 at 7477a32 (run 37953946207): 337;
  - #46 at f06479f (run 37954239751): 337;
  - #47 at a7132d3 (run 37954522168): 339;
  - #48 at c313cf8 (run 37954815790): 342;
  - #49 at 5ea34cb (run 37955099877): 342.

  Main's runs on aa8ceea (37953616777), 9044e73 (37953923211), 4af7472 (37954218990), 677a62f (37954505701), eb280f7 (37954794823) and 1d3bc06 (37955079852) each finished green before the next merge. This reflect was pushed after main's run on 3254abf, 37955370840, green.
- **Branches.** `docs/m4.3-2-design`, `feat/m4.3-2-bound`, `docs/m4.3-2-ledger`, `docs/m4.3-2-review-decision`, `fix/m4.3-2-review-core`, `fix/m4.3-2-review-binding` and `docs/m4.3-2-review-ledger` were deleted, local and remote. No PR is open.

**M4.3 step 2 is complete on main:**
- decision 0006 and its amendment: a client that does not read is aborted; past the high water reading stops and the write timeout runs, `CHEZ_WS_WRITE_TIMEOUT`, 60 s;
- the close timed from queueing, as peers time it, at least 1 s;
- a send that waits before it writes while the client is behind; a frame written in pieces of 64 KiB; a failed done as the stream's end.

`make test` green on main: eleven suites, 342 expected passes, every pin ok.

NEXT: M4.3 step 3, when asked: the real socket on 127.0.0.1:0 and the measures (a connection's cost beside the server's, the pong's timing with a throttled reader, what the kernel holds at a close), and step 1's review's survivors (four late resumes the fake logs nowhere, a read's bytevector kept).

---

M4.3 STEP 3, THE REAL SOCKET. On "lets start step 3". Branches `docs/m4.3-3-decisions`, `feat/m4.3-3-socket` and `docs/m4.3-3-ledger`, stacked on bb9c226 (by form, "Three stacked PRs": the records 263+/9−, measured green alone at 342; the code 376+/16−; the ledger). 2026-10-09.

**Measured first**, on Darwin and on Linux in Docker (libuv 1.48.0, CI's): [the research record](../../.plans/research/2026-10-09-real-socket-measures.md), and the probes in the scratch `s3/`.
- **The survivors, on the real shell.** R-6, R-7 and R-6b each logged `late-resume await` when the drain closed the stream under a waiting receive, and K-50b logged three after a send that waited. R-20 kept 1,016 B of a 1,000-byte read on the heap.
- **A connection's cost,** by the server's own method:
  - an idle WebSocket in a receive held 11,096 to 11,414 B;
  - the server at v0.4.0 held 1,793 to 2,073 B for an idle connection and 3,634 B for a parked `await`, as at v0.1.0;
  - the receive's way back, `call/1cc`, held about 3 KB of the WebSocket's.
- **Re-arming at every read:** 100.5 to 102.2 µs an echo with it, and 100.9 to 102.2 µs without it. No difference shows, so it stays, with no form.
- **The kernel:** Linux took 2,560 KiB from a client that never read; macOS 704 to 3,392 KiB. A close behind what it took is graceful.
- **The pong with a throttled reader:** after a 4 MiB burst, live readers at 96 KiB/s and below were failed with 1011. Timing the pong from the ping's queueing or from its done made no difference.

**Decided by form**, both the recommended:
- **"call/cc (Recommended)"**, 0005's amendment: a receive's or send's way back out of `await` is a full continuation. An idle WebSocket holds about 3 KB less, and an echo allocates the same within 0.5%.
- **"From queueing, as now (Recommended)"**, 0001's amendment: no change.
  - Timing from the done failed the same readers, and left a client that reads nothing, sent 4.2 or 4.3 MB, with nothing armed.
  - A 60 s timeout kept readers at 32 to 64 KiB/s. The caveat is now in the limits' header.

**What landed:**
- `(websocket private binding)`: `park!`'s `call/1cc` is now `call/cc`. Its comment says what was measured; the old one had said a `guard` costs a waiting coroutine kilobytes.
- `tests/test-socket.sps`, six checks. The server's libuv shell runs on 127.0.0.1:0, its clients on the same loop, every wait capped by turns:
  - an echo and a close;
  - a silent client failed on the shell's own timer;
  - the drain under a waiting receive, with no late resume (R-6, R-7, R-6b);
  - a send that waited, then the client's close, with no late resume (K-50b);
  - a read's bytevector let go, by the heap (R-20);
  - a receive's wait within 2 KiB of a bare `await`'s, by the heap (the form's).
- The path: chez-libuv's `tests/` among `TEST_ONLY_DIRS`, for `(uv-testing)`, which the server's `(shell-testing)` is built on. The driver suite's borrowed list and its names check include it.
- The records:
  - decisions 0001, 0005 and 0006;
  - the design's §8 and §9, and the plan's M4.3;
  - the limits' header: the ping timeout's caveat;
  - the README's status: M4 is done;
  - the research record.

**Where it departs from the plan and the design:**
- **A measure changed code.** The plan's step 3 was to measure; a connection's cost led to `call/cc`, by form.
- **The design's §8 promised the late resumes and the read's bytevector** on the real socket. The suite also holds a receive's wait, by the heap.
- **The bounds of the two heap checks** are derived from both platforms' numbers, recorded in the suite's header.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **Stage 0:** the suite and the path, on main's binding. As predicted, only the park check was red, at 4,047 B: twelve suites, 347 passes.
- **Stage 1:** `call/cc`.
  - Its first run is void. The edit was refused, since the file had not been read in the session, so it ran stage 0's tree, red at 4,006 B.
  - Rerun on the fixed tree: 348, as predicted.

**Mutants:** 12 rows, 11 mutants and the baseline.
- **Run 1: 1 mismatch,** a prediction error. K-32 also reddened B-CATCHUP, step 2's check; K-32's set had been predicted in step 1's review.
- **Run 2: 0 mismatches.** **Run 3,** on the final blobs: 0.
- **On Linux**, each binding mutant reddened the same socket check, by value.
- **Every new or changed check has a killer by value.** B-LINGER-AFTER survives, as in step 2.

**Stable:** the socket suite 20 of 20 on Darwin. Its heap checks measured, in the suite:
- Darwin: let-go 88 to 144 B against 2,004, and park −439 to 911 B against 2,048;
- Linux: 104 to 136 B, and −432 to 335 B.

`make test` green before the commit (Darwin arm64): twelve suites, 348 expected passes, every pin ok. `make prod` green.

With this, every bullet of the plan's M4.3 is held, and M4 is done once it merges.

NEXT: the PRs by form; review and the closing ritual when the owner asks; then M5, the Autobahn lane, whose image needs the owner's word to pull.

---

M4.3 STEP 3'S REVIEW. `/code-review` at xhigh over #50 to #52: 13 findings, the owner's "fix all". Branches `docs/m4.3-3-review-records`, `fix/m4.3-3-review-helpers`, `fix/m4.3-3-review-socket` and `docs/m4.3-3-review-ledger`, stacked on `docs/m4.3-3-ledger`. By form, "Four stacked PRs": the records +88/−11; the helpers +101/−82, measured green alone at 348; the socket suite and the driver +208/−147; then this ledger. 2026-10-09.

**Measured first** ([the research record](../../.plans/research/2026-10-09-real-socket-measures.md), its review section; probes in the scratch `s3rv/`):
- **The suite's cap** (finding 1). The most turns any wait took was 366 on Darwin and 205 on Linux. An idle turn took about 1.2 ms on Darwin, so the old cap, 200,000 turns, ran a wait that never came for about 240 s, past `make test`'s 120 s.
- **The park's reference** (finding 4). A wait by `call/1cc` around `await`, the old `park!`'s shape, held 2,724 to 4,225 B over a bare `await` in the suite's own setting. A receive by `call/cc` held 12 to 1,027 B, and one by `call/1cc` 2,756 to 3,420 B, on Darwin and Linux.
- **The server's park** (finding 7). The server parks every coroutine by `call/1cc` in its scheduler's `suspend!`.
  - By `call/cc` a parked coroutine held 640 to 679 B, not 3,639 to 3,660 B. An idle WebSocket held 4.9 KB, not 8.4 KB.
  - The server's scheduler, waits, shell and contract suites passed on that shadow.
  - By depth, `call/cc` saved about 3 KB at every depth, for 90 B and 20 to 200 ns more each wake and park.
  - The owner asked why the server chose one-shot continuations. Its records answer: its spike timed them alike, a stale one fails at once, and it never measured the parked heap by `call/cc`.
- **A client that stops reading** (finding 9). It was failed 40.02 s after the take-over, with or without 1 MiB sent first. One whose 17 messages the handler never took was not failed in 100 s.

**Decided by form:** "A server slice next (Recommended)". After this step the server changes `suspend!` in a slice of its own, keeping a check that a coroutine's continuation is not invoked twice, and its release is then pinned here.

**What landed:**
- **`tests/ws-play.sls`** (finding 12): the frames, `accepting`, `wrapping`, `logged`, `limits` and `closed`, moved verbatim from the binding suite, which imports them. The socket suite uses them too.
- **`tests/test-socket.sps`:**
  - the cap is 4,000 turns, and a check's first wait to reach it ends that check's waiting (finding 1);
  - S-SILENT times the ping and the close from what the server writes, through a transport over the shell's. The interval is 100 ms and the timeout 300 ms, each with a window of its own (findings 2 and 5);
  - S-DRAIN and S-SENDERS see the procedure waiting before they go on (finding 6);
  - a binary's payload is not copied, and the 8 MiB wait counts bytes first (finding 11);
  - S-PARK compares a receive's wait with the in-run reference, and says status 3 if the reference falls under 1 KiB (finding 4);
  - S-LETGO counts its messages.
- **`tests/test-driver.sps`:** D-SHELL holds the server's libuv shell as the socket suite drives it (finding 8).
- **The records** (findings 3, 7, 9, 10 and 13):
  - the README qualifies "never held", and its long line is wrapped;
  - 0001's claim is measured;
  - 0006 and the research record say the close timeout is armed, then disarmed;
  - the design's §8 and §9, the plan, and the research record's review section.

**Where it departs from the review:**
- **Finding 7's fix is the server's**, by form, after this step. Here it is measured and recorded.
- **KS-4 and KW-1 ran on the socket suite alone.** Halving the ping interval, or not waiting after a send, changes too many of the binding suite's checks to predict.

**Tests first**, each red set named and hashed before its run (`m4-mutations.md`):
- **My rewrite's first run had a fault of my own.** S-LETGO counted 4 messages for 10: a `let` read the count before the measure ran. It was made `let*` before stage 0.
- **Stage 0**, the review's tests on #52's library: twelve suites, 349, as predicted.

**Mutants:** 20 rows, 19 mutants and the baseline.
- **Run 1: 1 mismatch,** a prediction error. MK-1 stops the driver suite at load too, now that D-SHELL imports `(shell-testing)`.
- **Run 2: 0 mismatches.**
- **On Linux** each binding mutant reddened the same socket check, by value. A check that reaches the cap took 10 s; K-47's two took 19 s.
- **Every new or changed check, and each of S-SILENT's four bounds, has a killer by value.** B-LINGER-AFTER survives, as in step 2.

`make test` green before each commit (Darwin arm64): twelve suites, 349 expected passes, every pin ok. On Linux every suite passed, and the socket suite 10 of 10.

NEXT: the PRs; review and the closing ritual when the owner asks (#50 to #52, then these four, bottom-up); then the server's park slice, by form, and its pin.

---

MERGED to main on 2026-10-09, on the owner's "all green lets do the closing ritual": **M4.3 step 3, and its review** (the two entries above), from the stacked #50 to #56, as af6ba8a, fe3252d, ea56b45, 05a2823, e93585f, 9c23608 and ffdde55, bottom-up.
- **The squashes.** Each has the tree of the head CI tested:
  - af6ba8a has 5ff8a35's, on bb9c226;
  - fe3252d has 53f235b's, on af6ba8a;
  - ea56b45 has b148cf9's, on fe3252d;
  - 05a2823 has 0987cb0's, on ea56b45;
  - e93585f has 4f645a6's, on 05a2823;
  - 9c23608 has f483b54's, on e93585f;
  - ffdde55 has ccb767a's, on 9c23608.

  #51 was rebased onto #50's squash from d3c5184, #52 onto #51's from 38f2737, #53 onto #52's from 6a3c46b, #54 onto #53's from 6541729, #55 onto #54's from 7e99fdc, and #56 onto #55's from 1dd911c: one commit each. No tree changed.
- **CI.** Each PR merged on `linux` SUCCESS, its log tallied against the local count:
  - #50 at 5ff8a35 (run 37969816485): eleven suites, 342;
  - #51, rebased, at 53f235b (run 37975670117): twelve suites, 348;
  - #52 at b148cf9 (run 37975943856): 348;
  - #53 at 0987cb0 (run 37976222249): 348;
  - #54 at 4f645a6 (run 37976633269): 348;
  - #55 at f483b54 (run 37976968999): 349;
  - #56 at ccb767a (run 37977313885): 349.

  Main's runs on af6ba8a (37975651183), fe3252d (37975925939), ea56b45 (37976204741), 05a2823 (37976614283), e93585f (37976951312) and 9c23608 (37977293806) each finished green before the next merge. Main's run on ea56b45 was still running when #53's run had finished, so the merge waited for it. This reflect was pushed after main's run on ffdde55, 37977631025, passed.
- **Branches.** `docs/m4.3-3-decisions`, `feat/m4.3-3-socket`, `docs/m4.3-3-ledger`, `docs/m4.3-3-review-records`, `fix/m4.3-3-review-helpers`, `fix/m4.3-3-review-socket` and `docs/m4.3-3-review-ledger` were deleted, local and remote. No PR is open.

**M4.3 is complete on main, and with it M4:**
- the binding and the facade, held on the server's fake shell and on a real socket;
- a client that does not read aborted (0006);
- a receive's wait by `call/cc` (0005's amendment);
- the pong timed from the ping's queueing, measured (0001's amendment);
- every one of step 1's review's survivors killed.

`make test` green on main: twelve suites, 349 expected passes, every pin ok.

NEXT, by form ("A server slice next"): the server's `suspend!` by `call/cc` in chez-http-server, with a check that a coroutine's continuation is never invoked twice, released as v0.4.1, then pinned here in a PR of its own. Then M5, the Autobahn lane: pulling its image needs the owner's word.

---

**Before the server's v0.4.1 pin: S-PARK retired, S-LETGO at 16,000 bytes, and an allocation counted on a stack segment of its own (2026-10-09),** on the owner's "lets start the S-PARK reference PR", after the server's v0.4.1 (its #159 and #160, tagged on 520f70e). Branch `test/fit-server-v0.4.1`, cut from 43b18e7; one PR.
- **Measured first** (Darwin arm64, and Linux in Docker; the research record's last section, and probes in the scratch `ws-spark/`):
  - **S-PARK's reference**, a wait by `call/1cc` around `await`, held −338 to 334 B on v0.4.1, where 2,792 to 4,048 on v0.4.0: the server's full park makes it full too. A receive with `park!` by `call/1cc` held 453 to 490 B there, so no change to the binding reddens the check.
  - **Two more checks went red** when main's suites ran on v0.4.1: S-LETGO, at 2,832 to 2,952 B against 2,004, and the binding suite's R-DONE-ALLOC-BEHIND, at 64 B in 4 of 7 runs. Each passed with the server's drain one-shot again, and the done check with its park one-shot again too.
  - **S-LETGO's excess is not the message:** about 2.9 KB from 4,000 to 400,000 bytes, and 9.35 KB with ten connections. **The done check's 64 B is the counter's:** the same done counted 512 B at one depth and 576 B at the others, the binding's and the taker's alike.
- **DECIDED by form:**
  - **"Retire S-PARK (Recommended)"**, 0005's amendment. Weighed: replacing the reference only, with one held outside the scheduler, which no change to the binding reddens from v0.4.1.
  - **"Fix both checks here (Recommended)"**, decision 0007. Weighed: the server's drain one-shot again in a v0.4.2, which allocates about 3 KB more a waiting request; and finding the server's mechanism first.
- **Built:**
  - `tests/test-socket.sps`: S-PARK and its reference gone, five checks; S-LETGO at 16,000 bytes, one read of the server's 16,384-byte buffer, bound 8,004 B; `call/1cc` off its imports.
  - `tests/ws-testing.sls`: `least-counted` counts each call inside a `call/1cc`, on a stack segment of its own, not at three depths.
  - `park!`'s comment gives both servers' numbers; the code is unchanged.
- **Records:** 0005's amendment, 0007, the design's §8 and §9, the plan's M4.3 note, the research record's last section.
- **Tests first** (`m4-mutations.md`):
  - **Stage 0**, main's suites on v0.4.1: the socket suite at status 3, as predicted. Not predicted: S-LETGO and R-DONE-ALLOC-BEHIND red, which the second form decided.
  - **Stage 1**: twelve suites and 348 on each server, as predicted, and again once S-LETGO moved to 16,000 bytes. On Linux, twice on each.
- **Mutants:** 10 rows on each server.
  - **Run 1: 2 mismatches on each.** R-20 stayed green with S-LETGO at 40,000 bytes, a frame of three reads; S-LETGO moved to 16,000. R-26 reddened two more allocation checks, a prediction error.
  - **Run 2: 0 mismatches.** Every changed check has a killer by value. P-1CC survives, as 0005's amendment says.
- `make test` green before the commit (Darwin arm64): twelve suites, 348 expected passes, every pin ok. On v0.4.1, twelve suites and 348, on Darwin and on Linux.

NEXT: the PR; review and the closing ritual when the owner asks; then the pin to the server's v0.4.1 (520f70e) alone; then M5, the Autobahn lane, whose image needs the owner's word to pull.

**#57's review, as a stacked PR, on `fix/v0.4.1-fit-review` (2026-10-09):** a /code-review xhigh over #57 reported eight findings. On the owner's "fix all", all eight were fixed, three of them by form, each the recommended: "Record the gap" (finding 3), "Server plan's open list" (finding 4) and "A stacked PR on #57".
- **Measured first** (Darwin arm64; the research record's newest section; probes in the scratch `ws-spark/rv/`):
  - **The counter's premise was wrong.** On plain Chez, at 401 depths, no count moved, either way. Near the server's scheduler, #57's counter counted a v0.4.0 coroutine's wake as 65,968 B, a new stack segment, in every call (finding 5).
  - **The 64 B is the fake shell's.** A taker's write's done counted 512 B, then 576 and 576; the binding's, in the layouts that failed, 576 three times. The same counted inside a `call/1cc`, under a full `call/cc`, or neither, on both servers. A `guard` in the fake shell's `taker-call!` wraps both.
  - **The least of three fails when only one side's first call counts low;** the middle of three passed the binding suite in every run, on both servers. Written into the tree first as the least, at three depths inside a `call/1cc`, it failed 5 of 6 on v0.4.1: a helper procedure the shadow lacked.
- **Built:**
  - `tests/ws-testing.sls`: `middle-counted`, the middle of three counts made 100 frames apart, with no `call/1cc` (findings 2, 5, 6 and 8).
  - `tests/test-socket.sps`: `reading`, a transport that tells each read's length; S-LETGO stops at status 3 unless all five big frames came whole (finding 1); the header says what is not checked here, and why (finding 3).
- **Records:**
  - 0005's amendment, the gap;
  - 0007 renamed, "an allocation is counted as the middle of three counts", and amended;
  - the design's §8 and §9, the plan's M4.3 note, the research record;
  - the per-connection figure, about 620 B more than v0.4.0, not 720 (finding 7).
  - In chez-http-server, #161 adds what the full drain keeps to its plan's open list (finding 4).
- **Tests first** (`m4-mutations.md`): stage 1 failed once, a prediction error (above); after the change, twelve suites and 348 on v0.4.0, and on v0.4.1 three times; the binding suite 6 of 6 on each server.
- **Mutants:** 12 rows on each server, run 2's ten and two for the whole-read check. Run 3, 0 mismatches each, under the counter first written; run 4, 0 mismatches each, under the middle.
- **Linux** (Docker, libuv 1.48.0): `make test`, twelve suites and 348, twice on each server; the binding suite 6 of 6 on v0.4.1.
- `make test` green before the commit (Darwin arm64): twelve suites, 348 expected passes, every pin ok.

NEXT: the PRs, #57 and this one stacked on it; the closing ritual when the owner asks, bottom-up; then the pin to the server's v0.4.1 (520f70e) alone; then M5, the Autobahn lane, whose image needs the owner's word to pull.

---

MERGED to main on 2026-10-09, on the owner's "all green, do closing ritual": **the v0.4.1 fit and its review, as two stacked PRs** (the two entries above), bottom-up.
- **#57**, at 717b538, was squashed as c9b3e7e (tree 717b538's, parent 43b18e7). Its run, 38001010340, passed: twelve suites, 348 expected passes. It merged without `--delete-branch`, since #58 was based on it. Main's run on the squash, 38006065674, passed with the same counts before #58 merged.
- **#58** was retargeted to main and rebased from 717b538 onto c9b3e7e: 3bef5d1 became 2e35bd3, the tested tree, pushed with the lease. CI passed on both heads (38005793169 on 3bef5d1, 38006098548 on 2e35bd3), each twelve suites and 348. It merged as 851bff0 (tree 2e35bd3's, parent c9b3e7e). Main's run on the squash, 38006442242, passed with the same counts.
- **Branches.** Both deleted, local and remote; this checkout is on main, fast-forwarded. No PR is open.
- **Alongside**, in chez-http-server: #161, what the full drain keeps, on its plan's open list (aa7dc93).

`make test` green on main: twelve suites, 348 expected passes, every pin ok.

NEXT: the pin to the server's v0.4.1 (520f70e) alone, its every suite measured green on v0.4.1 already (#57, #58); then M5, the Autobahn lane, whose image needs the owner's word to pull.

---

**The server's v0.4.1, pinned alone (2026-10-09),** on the owner's "lets do the v0.4.1 pin in chez-websocket". Branch `chore/pin-server-v0.4.1`, cut from 413516f; one PR, one commit.
- **The pin:** chez-http-server moves from v0.4.0 (388ec43) to v0.4.1 (520f70e), whose park and drain are by `call/cc` (its decision 0025): a waiting coroutine holds about 3 KB less. Of the pins it carries, chez-libuv moves from v0.7.4 (27d84bb) to v0.8.0 (ad3bb47); chez-httparse 0b7058e, byte-machine c338a57, uriparse 5ecd88f and chez-srfi 7879b52 are unchanged.
- **What reaches here is chez-libuv v0.8.0's libuv floor,** 1.48 where it was 1.44. Its build passes a system libuv below the floor over for its own, which needs CMake, and its `config.sls` refuses one below it at load. CI's ubuntu-24.04 libuv is 1.48.0, the floor exactly.
  - The README says 1.48, and that chez-libuv builds its own below it, with CMake 3.10 or later; the Makefile's comment on `submodules` says the same.
  - global-constraints says 1.48, and CMake 3.10, libuv's own floor. The 3.26 it said until now is the siblings' preset floor, which this build never runs, as the server's global constraints say since its v0.4.1.
- **Fitted before the pin** (#57, #58): every suite passed on v0.4.1, on Darwin and on Linux, and design §9's measure at the pin was taken there.
- **Watched to fail:** with the gitlink moved and `SERVER_PIN` not, `make check-pins` answered the one predicted line, `PIN MISMATCH: vendor/chez-http-server at 520f70e…, expected 388ec43…`, with the five carried pins ok.
- `make test` green before the commit (Darwin arm64), three runs: twelve suites, 348 expected passes, each suite's count as main's on v0.4.0, every pin ok. The binding suite passed 6 of 6, 55 each. `make prod` green, its shim checked a prod build.

NEXT: the PR; the closing ritual when the owner asks; then M5, the Autobahn lane, whose image needs the owner's word to pull.

---

MERGED to main on 2026-10-09, on the owner's "ci is green, do closing ritual": **the server's v0.4.1 pin** (the entry above), #59.
- **#59**, at b3cc009, was squashed as 04506ff (tree b3cc009's, parent 413516f). Its run, 38007212232, passed on Linux: twelve suites, 348 expected passes, every pin ok, the server at 520f70e. Main's run on the squash, 38007369096, passed with the same counts.
- **Branch.** Deleted, local and remote; this checkout is on main, fast-forwarded. No PR is open.

`make test` green on main: twelve suites, 348 expected passes, every pin ok, the server at v0.4.1.

NEXT: M5, the Autobahn lane, when the owner asks; pulling its image needs the owner's word.

---

**M5, the Autobahn lane (2026-10-09),** on the owner's "let's start M5 in chez-websocket". Branch `feat/m5-autobahn`, cut from 7cc1d4a. Decision 0008, by forms, each the recommended.
- **The image, pulled on the owner's word** ("Here and in CI"): `crossbario/autobahn-testsuite:25.10.1`, still the digest 0022 recorded, linux/amd64 alone, 389 MB to download. A Sonnet agent sourced Autobahn and seven peers at tags; the [research record](../../.plans/research/2026-10-09-autobahn-lane.md) holds both and every measure.
- **Measured before the forms:**
  - On Linux (the echo server in a container), 16 full runs, each cap's alike. At 16 MiB, 13 runs: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL. At the default 1 MiB, 3 runs: 24 of the 291 FAILED, each closed 1009.
  - On macOS the cases reach the echo server through Docker Desktop, and 3 of 11 full runs stopped short. wstest exits 0 even then, and when cases fail.
  - Three cases vary, OK or NON-STRICT, with how the client's bytes fall into reads: 3.4, 4.1.5 and 4.2.5. Alone on Linux, NON-STRICT 12, 11 and 14 times in 30.
- **Forms:**
  - "16 MiB", the echo server's cap, the suite's largest message.
  - "Every PR and push", a CI job of its own.
  - "List what was measured": the three varying cases list both verdicts.
  - "Server slice after the lane", for a finding.
- **Found by the lane: a close lost to a reset** (design §9). A server that fails a client still sending closes its socket with the client's bytes unread, and the kernel resets the connection. On macOS a raw client never read the 1009, 100 of 100; on Linux it did, but 14 of 100 ended in a reset. The server's HTTP closes half-close and linger (its 0011); a taken stream's close does not. python-websockets and ws half-close and drop.
- **Landed:**
  - `(ws-autobahn)`: a JSON reader (RFC 8259), the ratchet's reader, and the gate, both ways. Its suite `tests/test-autobahn.sps` has 20 checks.
  - `tests/autobahn/`: `echo.sps`, `gate.sps`, `run.sh`, `fuzzingclient.json`, and the ratchet `verdicts.txt`, 301 lines written from a Linux run's index by a script of their own.
  - `make autobahn` runs the echo server in an environment of its own, the image by digest (`--network host` on Linux, `host.docker.internal` on macOS), and the gate.
  - CI: the setup both jobs need moved into `.github/actions/setup`; the `autobahn` job beside `linux` keeps the run's reports when it fails.
  - README: the status, and `make autobahn`.
- **A hazard found by a safety check:** `run.sh` began with `rm -rf "$OUT/config" "$OUT/reports"`, which an empty `OUT` would have turned on `/config`. It now removes only a stale `index.json`, and each variable it needs is checked (`:?`).
- **Mutants** (`m5-mutations.md`):
  - The gate's: 66 rows, 0 mismatches on run 4. Run 1 was void (a harness quoting error). Run 2 had 3 mismatches: 2 prediction errors, and J-6, whose gap vector was wrong. J-28 and R-11 were added as value killers.
  - The lane's: 6, each turning the gate red. L-1 and L-6 were prediction errors (7.5.1; 5.19 and 5.20); L-5's first try was void, stopped short on macOS.
- **Linux:** `make autobahn`'s pieces ran by hand, the gate on 16 full runs. **macOS:** `make autobahn` passed, 301 cases (23 s).
- `make test` green before the commit (Darwin arm64): thirteen suites, 368 expected passes, every pin ok.
- **Opened as stacked PRs** (form "Four stacked PRs"): #60 `docs/m5-1-decision`, #61 `test/m5-2-gate`, #62 `test/m5-3-lane`, #63 `docs/m5-4-ledger`. Each exact tree was proven in a detached scratch worktree: twelve suites and 348 for #60, thirteen and 368 for the rest, and `make autobahn` passing on #62's.
- **CI's first native runs of the lane** (runs 38016701245, #62, and 38016703127, #63), on ubuntu-24.04 amd64:
  - `make autobahn` took about 38 s: the pull, the 301 cases and the gate. The `autobahn` job took 62 and 64 s, its cached setup about 23 s.
  - Its gate said, both times: 301 cases as the ratchet holds them, 291 OK, 7 NON-STRICT, 3 INFORMATIONAL. So 3.4, 4.1.5 and 4.2.5 came out OK.
  - The `linux` job: thirteen suites, 368 expected passes. All four PRs' runs green.

NEXT: the closing ritual when the owner asks. Then the server slice: a taken stream's close lingers, its release, pinned here alone, and `none` measured again for 3.4, 4.1.5 and 4.2.5. Then M6, v0.1.0.

---

**S-SILENT's lower bounds by the loop's clock (2026-10-10),** on the owner's ask: CI's run 38051169931 (attempt 1, PR #63's docs-only tree) measured a ping met on time at 98 ms, where the check took 99 or later. Branch `test/s-silent-lower-bound`, cut from dc53b3b; one PR.
- **Found by measurement** ([the research record](../../.plans/research/2026-10-10-s-silent-clock.md)): the suite timed by Chez's clock, `CLOCK_MONOTONIC`, and the server arms and fires by libuv's.
  - On Linux libuv's is `CLOCK_MONOTONIC_COARSE` wherever that ticks every millisecond, as it does in the noble image. There `uv_now` ran 0.37 to 3.09 ms behind Chez's, and the lag varies.
  - The ping came as early as 98.888 ms in 1,000 runs at the suite's numbers. At 20/30 ms, 143 runs of 10,000 broke the old bounds; in one, a ping met on time read 15 ms for 20.
  - The wheel never fired early by its own clock, in 11,600 runs. On a fine loop clock, as on macOS, the old 99 was exact, so CI's 98 says its loop clock is coarse too (inferred).
- **Landed:** S-SILENT times the take-over and each write by `uv_now`, read without bringing it up to date. Its lower bounds are the limits themselves, 100 and 300, which the server's deadlines and the binding's order guarantee to the millisecond; the upper bounds stay 250 and 450. `now-ms` is gone. The suite's header says why.
- **Mutants** (`m4-mutations.md`, its last section): KS-1 to KS-4 again, each red by value; KS-4, a ping at 50 ms, reddens S-SILENT alone. Run 1's three mismatches were the new runner's name map; run 2, 0 mismatches on Darwin, and Linux the same.
- **A scope statement, SC-1:** a shell that arms a taker's deadline by a stale reading of its clock is green here. It was green by the suite's clock before, and is green in every server suite that runs here, so the server holds no check of it.
- **Seen in the server, not changed here:** its `tests/test-shell.sps` compares a hold on Chez's clock with the loop's and allows one millisecond. By the measures above, that is the same hazard.
- **Linux** (Docker, libuv 1.48.0): every suite, thirteen and 368; the socket suite 100 times, four at once, all green.
- **CI did not run:** GitHub Actions refused the jobs for billing, through October by the owner's word. Run 38053941404 ended with 0 steps on attempts 1 and 2. Stood in for:
  - **the `linux` job,** by an amd64 image as CI's: ubuntu 24.04, libuv1-dev 1.48.0, Chez 10.4.1 threaded (`ta6le`), dash, under emulation. Every suite passed, thirteen and 368, and the socket suite 100 times, four at once. There too libuv takes the coarse clock: `uv_now` ran 0.12 to 2.16 ms behind;
  - **the `autobahn` job,** by main's run on this branch's base, dc53b3b: 38051601592 passed both jobs, and nothing that job reads has changed.
- `make test` green before the commit (Darwin arm64): thirteen suites, 368 expected passes, every pin ok.

NEXT: the PR; the closing ritual when the owner asks, past the billing block on the owner's word. #64 and #65, M5's review, are open and add to this ledger too, so whichever merges second rebases. Then the server slice: a taken stream's close lingers.

---

MERGED to main on 2026-10-10, on the owner's "Do ritual": **S-SILENT's lower bounds by the loop's clock** (the entry above), #66.
- **#66**, at a60dc63, was squashed as 7e5a75f (tree a60dc63's, parent dc53b3b).
- **CI did not run** on its head (38053941404 on 39a6d91 and 38056687582 on a60dc63) or on main's squash (38057601100). Each job ended with 0 steps, the billing block, through October by the owner's word. It merged past that red check on the owner's word. The entry above records the stand-in: an amd64 image as CI's for the `linux` job, and main's run on dc53b3b for the `autobahn` job.
- **Branch.** Deleted, local and remote; main fast-forwarded to 7e5a75f.
- **Two server findings went to tasks of their own,** in chez-http-server: its held-shutdown check, timed on two clocks with 1 ms of slack; and a check that a taker's arm brings the clock up to date (SC-1).

`make test` green on main: thirteen suites, 368 expected passes, every pin ok.

NEXT: #64 and #65, M5's review, still open. #64's last run before the block, 38051609330, was red: "a run told to stop takes its echo server with it". Each rebases onto 7e5a75f, and their CI waits for November or a local stand-in. Then the server slice: a taken stream's close lingers.

---

**M5's review (2026-10-10),** on the owner's "fix all" after a /code-review (xhigh) over #60-#63 reported fourteen findings. Branch `fix/m5-review`, on #63. Decision 0008's amendment.
- **Forms, each the recommended:**
  - **"Container on Docker Desktop":** on macOS and Windows the echo server runs in a Linux container (`tests/autobahn/echo.Dockerfile`, `make echo-image`, `make docker-smoke`). Linux and CI keep the host network.
    - Measured on macOS: a first build of 242 s (226 s compiling Chez), 7 s after a change, 138 MB, and a warm run of 17 s. None of 26 container runs stopped short, where 3 of 11 had through Docker Desktop's forwarding.
  - **"Keep both building on a miss":** a `chez-cache-salt` dispatch input runs the setup action's miss path by hand.
- **Fixed:**
  - The ratchet lists whole verdicts, `" | "` between them, so a pairing never measured fails. 4.1.5 lists two; 3.4 and 4.2.5 three.
  - An empty index, wstest's `{}` when no connection opened (measured), is a run of no case.
  - The short-run hint counts the cases that did not run.
  - `make autobahn` checks the pins.
  - The host path takes any free port and reads it back.
  - A CRLF ratchet reads alike, and `.gitattributes` keeps scripts and the ratchet LF.
  - `gate-main` is gate.sps's body, every failure status 2.
  - `tests/test-autobahn-run.sps` holds `run.sh` with a stand-in for docker. It showed a trap that carried on after a signal: a signal now exits, and the exit stops the server.
  - The tally is plainer.
- **Watched to fail** (`m5-mutations.md`):
  - Test-first: the gate's suite stopped at load; stage 1 reddened exactly the 15 named; `run.sh`'s suite reddened all 7 on the old `run.sh`.
  - The gate's mutants, re-cut: 83 rows, 0 mismatches on the first run.
  - `run.sh`'s: 11 rows, 1 mismatch. RM-8 survived: the stop's wait cannot be seen, since the server stops before the shell's next command. Kept against the race.
  - The container path's: four one-offs on real Docker, all as named.
- **Re-gated:** every full run since M5 began, as predicted; all 180 flip-run verdicts listed.
- **make autobahn, macOS, container path:** 248 s from no image, gate passing; `make docker-smoke` 6 s.
- `make test` green before the commit (Darwin arm64): fourteen suites, 381 expected passes, every pin ok. `make check-help` passes.

- **Opened** as stacked #64 `fix/m5-review` and #65 `docs/m5-review-ledger` (form "Two stacked PRs").
- **CI's first runs: the `linux` job red** on all three, the `autobahn` job green on all three.
  - The red was `tests/test-autobahn-run.sps`'s "ends before it listens". On Ubuntu, sh is dash. An echo server that exits at once stays a zombie until its shell reaps it, and wait_listening, in a command substitution, is a subshell that cannot reap it. So kill -0 answered "alive", and the run waited out its 60 s.
  - Reproduced in the Linux container, 72 s, the one red. Fixed on #64 (`9e27973`): alive only when ps shows the server and not as a zombie. 9 of 9 under dash (9 s) and under macOS's sh.
  - `run.sh`'s mutants run again on the fix: as in run 1.
- **The cache-miss path proven** by a dispatch run with `chez-cache-salt=-m5-review-probe` (38049305608). Both jobs missed, built Chez from source and met the floor. `linux` saved the key; `autobahn`'s save lost the race and only warned ("Unable to reserve cache … another job may be creating this cache"), the job green.
- `make test` green before the commit (Darwin arm64): fourteen suites, 381 expected passes, every pin ok.

NEXT: CI on #64 and #65 again; the closing ritual when the owner asks, bottom-up from #60. Then the server slice for the lost close; then M6.

---

MERGED to main on 2026-10-10, on the owner's "ci is green, do closing ritual": **M5, the Autobahn lane, and its review**, six stacked PRs merged bottom-up (#60-#65).
- **#60** was squashed as b1d6943 (2da1190's tree, on 7cc1d4a). Its run was 38016697501; main's run on the squash, 38050710772, passed.
- **#61** as 0ce9848, rebased 4d61088 -> 127c313. Its runs, 38016698903 and 38050728164, passed, and main's, 38050923658.
- **#62** as 4642cfd, rebased 2070682 -> a717492. Its runs, 38016701245 and 38050934920, passed, and main's, 38051160948.
- **#63** as dc53b3b, rebased df31c6b -> 098fad5. Run 38051169931's first attempt failed S-SILENT once, on the docs-only tree: a ping measured at 98 ms against a floor of 99. The re-run passed, and main's, 38051601592. S-SILENT was then fixed in a session of its own, #66 (7e5a75f, reflect 018ed48): it is now timed by the loop's clock, since the flake was libuv's CLOCK_MONOTONIC_COARSE on Linux.
- **CI stopped: GitHub billing.** The probe run 38052164159 never started ("recent account payments have failed or your spending limit needs to be increased"). On the owner's word, the other session rebased #64 and #65 onto 018ed48. A range-diff showed their patches identical, and #65's added lines byte for byte the same.
- **#64** as 85fbe2e (17db252's tree, on 018ed48), and **#65** as 61be5e7 (rebased 12a0e6f -> 30a26e5; its tree, on 85fbe2e). They merged on local evidence, by form ("Merge on local evidence"), with CI blocked:
  - on 17db252, `make test`: fourteen suites, 381 expected passes, on macOS (this session) and amd64 Linux (the other);
  - the `run.sh` suite 9 of 9 under dash, on arm64 and amd64.
- **Open: R-TERM's one CI failure,** run 38051609330 on fd9f54d. It is unexplained: 0 of 80+ runs failed locally. The probe that would find its cause runs once CI is back; it is the branch `probe/r-term` (d58976d), kept.
- **Branches.** The six were deleted, local and remote; `probe/r-term` is kept. This checkout is on main, fast-forwarded. No PR is open.

`make test` green on main (61be5e7, Darwin arm64): fourteen suites, 381 expected passes, every pin ok. Main has had no CI run since dc53b3b: none can start while billing is blocked.

NEXT, when CI is back:
1. Main's run on 61be5e7.
2. The R-TERM probe, then its fix.
3. The chez-http-server slice for the lost close (design §9), its release pinned here alone, and `none` measured again for 3.4 and 4.2.5.
4. M6, v0.1.0.

---

**SC-1's record brought up to date (2026-10-11),** on the owner's ask, once chez-http-server #163 had merged as 5f97368. Branch `docs/sc-1-killed-by-server`, cut from 42d5c73. Records only.
- **What changed upstream.** #66 left SC-1, a taker's deadline armed by the loop's time not brought up to date, as a scope statement: no suite here or in the server saw it. The server's #163 adds a shell check that SC-1 reddens by value (the deadline `0` ms past the stale time, where the check wants at least 300), recorded in its `m8-mutations.md`.
- **Here.** `m4-mutations.md` gains a dated update under SC-1's note; the run's table is left as it was measured. SC-1 is still a scope statement in this repository: the socket suite times by the loop's clock, and the pin, v0.4.1 (520f70e), predates the server's check. No pin moves: #163 changed only the server's tests.
- `make test` green before the commit (Darwin arm64): fourteen suites, 381 expected passes, every pin ok. Nothing tested changed.

NEXT, unchanged from M5's reflect: main's run on 61be5e7 when CI is back (the block is intermittent: the server's #163 ran and passed on 2026-10-11, while main's runs there were still refused); the R-TERM probe, then its fix; the chez-http-server slice for the lost close; M6, v0.1.0.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **SC-1's record brought up to date** (the entry above), #67.
- **#67**, at 33cf87e, was squashed as 803ed6e (tree 76306f2, the tested head's; parent 42d5c73).
- **CI did not run** on its head: run 38141891555 ended with both jobs not started (0 steps, the payments annotation), the billing block. Records only; the entry's `make test` stood in. It merged past that red check on the owner's word.
- **Branch.** Deleted, local and remote; main fast-forwarded. The session's worktree was removed.

`make test` green on main: fourteen suites, 381 expected passes, every pin ok.

NEXT, unchanged: main's run on 61be5e7 when CI is back; the R-TERM probe, then its fix; the chez-http-server slice for the lost close; M6, v0.1.0.

---

**Before the server's v0.5.0 pin: D-OUTSIDE's client ends (2026-10-11),** on the owner's "let's pin chez-websocket to v0.5.0", after the server's v0.5.0 (its #172 and #173, tagged on 02ef95d). Branch `test/fit-server-v0.5.0`, cut from 2879eb0; the pin stacks on it, alone, as #59 followed #57 and #58.
- **Measured first** (Darwin arm64): main's suites on v0.5.0, the gitlink staged in a scratch worktree. Fourteen suites, the driver suite 14 of 15, every other suite's count main's on v0.4.1.
  - **The one red is D-OUTSIDE**, "the stream closed while the thunk waits", at `(() ())` where `((closed client-closed) ())`.
  - **It is the change v0.5.0 makes** (the server's decision 0026). A taken stream's close now lingers until the client ends, a read error or `CHEZ_HTTP_LINGER_TIMEOUT`, and so does its test fake's door. D-OUTSIDE closed the stream with the client still there, and read the log at once.
- **Built:** `tests/test-driver.sps`: D-OUTSIDE delivers the client's end after the close and before it settles, and its title says so. Its expected value is main's.
- **On both servers.** On v0.4.1 the client's end is inert: its fake reads nothing once the close is asked for, so the check is main's there. On v0.5.0 it is what closes the stream.
- **Mutants** (`m4-mutations.md`): 11 rows, 0 mismatches, each red set and its values named and hashed before the run.
  - M4.2's M-18, M-19 and M-20 redden D-OUTSIDE by value on both servers.
  - On v0.5.0, two more: the check without the client's end, and a fake that drops the end while the stream closes, each `(() ())`.
- **Records:** this entry and the mutation log. No CHANGELOG entry: a check's stimulus, not anything a user meets.
- `make test` green before the commit (Darwin arm64), three runs: fourteen suites, 381 expected passes, each suite's count main's, every pin ok. On v0.5.0, the same tree, three runs: fourteen suites and 381, each suite's count main's on v0.4.1.

NEXT: the PR, and the pin to the server's v0.5.0 (02ef95d) stacked on it, alone. Then `none` measured again for 3.4, 4.1.5 and 4.2.5.

---

**The server's v0.5.0, pinned alone (2026-10-11),** on the owner's "let's pin chez-websocket to v0.5.0". Branch `chore/pin-server-v0.5.0`, stacked on `test/fit-server-v0.5.0` (#68); one PR, one commit.
- **The pin:** chez-http-server moves from v0.4.1 (520f70e) to v0.5.0 (02ef95d). Its taken stream's close half-closes and lingers (its decision 0026): the slice this project's decision 0008 asked for in item 6, for the close design §9 found lost. Of the pins it carries, chez-libuv moves from v0.8.0 (ad3bb47) to v0.9.0 (3c4e7f0). chez-httparse 0b7058e, byte-machine c338a57, uriparse 5ecd88f and chez-srfi 7879b52 are unchanged.
- **What reaches here:**
  - **The binding's close lingers.** `close-stream!` arms the close timeout, its call an abort, then calls `transport-close!`. On v0.5.0 the stream reads on, dropping what the client sends, and once the writes are out it shuts its write side, so a client still sending reads the close frame, not a reset. The close timeout still bounds the writes. Once they are out, the server's linger bounds the rest, `CHEZ_HTTP_LINGER_TIMEOUT` (30 s), until the client closes; until then the stream counts toward the server's connection cap. The transport's close call, which the binding steps as the stream's end, comes once the client has closed.
  - **chez-libuv v0.9.0:** the libuv floor is still 1.48. Its shim gained two functions, so `make build` rebuilds it. A loop run short of C stack is refused as `&uv-stack-exhausted`.
  - **The test fake's door closes the same way.** D-OUTSIDE was fitted first (#68). Every other suite passed on v0.5.0 unchanged.
- **Watched to fail:** with the gitlink moved and `SERVER_PIN` not, `make check-pins` answered the one predicted line (named and hashed before the run), `PIN MISMATCH: vendor/chez-http-server at 02ef95d…, expected 520f70e…`, with the five carried pins ok, chez-libuv at 3c4e7f0.
- **Records:** the Makefile's pin and the README's `make submodules` line. Design §9, decision 0008's item 6 and the ratchet's note on `none` wait for `none` measured again.
- `make test` green before the commit (Darwin arm64), three runs: fourteen suites, 381 expected passes, each suite's count main's on v0.4.1, every pin ok. The binding suite passed 6 of 6, 55 each. `make prod` green, its shim checked a prod build.
- **CI is billing-blocked,** so Linux ran in containers, on this tree:
  - aarch64 (`chez-libuv-noble-scratch:10.4.1`, libuv 1.48.0): fourteen suites, 381, each suite's count main's;
  - x86_64 under emulation (`chez-websocket-ci-amd64:10.4.1`, libuv 1.48.0): fourteen suites, 381, each suite's count main's.

  The pins are checked on the host, since one image has no git.

NEXT: the PRs; the closing ritual when the owner asks, bottom-up, #68 then this. Then `none` measured again for 3.4, 4.1.5 and 4.2.5 on Linux, and design §9, decision 0008's item 6 and the ratchet's note brought up to date.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **the fit and the server's v0.5.0 pin, as two stacked PRs** (the two entries above), bottom-up.
- **#68, D-OUTSIDE's client ends:** b8e1ff9 squashed as 05cca1c (tree 625bd05, the tested head's; parent 2879eb0). It merged without `--delete-branch`, since #69 was based on it.
- **#69, the pin:** retargeted to main and rebased from b8e1ff9 onto 05cca1c, 7de17de becoming c83ea8e (tree 6f7e6ab, unchanged), pushed with the lease read from `ls-remote`. It squashed as 99d7cd9 (tree 6f7e6ab; parent 05cca1c), its gitlink 02ef95d.
- **CI.** Billing-blocked throughout. Every run ended with both jobs, `linux` and `autobahn`, not started (0 steps, the payments annotation): the PRs' 38154991308 (b8e1ff9) and 38155258780 (7de17de), the rebased head's 38156549518 (c83ea8e), and main's on each squash, 38156521949 (05cca1c) and 38156588688 (99d7cd9). The entries' local runs stood in: Darwin, and Linux aarch64 and x86_64 in containers, fourteen suites and 381 each. The two merged past the red check on the owner's word.
- **Branches.** Both deleted, local and remote, and the fit's worktree removed. This reflect is committed from the pin's worktree, detached at 99d7cd9. The main checkout is fast-forwarded after it, its submodules brought to the new pins. No PR is open.

`make test` green on main: fourteen suites, 381 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: `none` measured again for 3.4, 4.1.5 and 4.2.5 on Linux, each case alone, 30 runs, as M5 measured them; then design §9, decision 0008's item 6 and the ratchet's note brought up to date. When CI is back, main's latest run; the R-TERM probe, then its fix. M6, v0.1.0.

---

**The ratchet drops `none` for 3.4 and 4.2.5, measured on the server's v0.5.0 (2026-10-11),** on the owner's "let's re-measure none for 3.4, 4.1.5 and 4.2.5", after the v0.5.0 pin (#69). Branch `test/ratchet-drops-none`, cut from 96138ce; one PR.
- **Measured** (the research record's last section; scratch `ws-none/`), v0.4.1 (2879eb0's tree) the control, each cell's predictions named and hashed before it ran. The echo server in a Linux container on `ab-net`, the ten bad-frame cases alone, M5's flips.
  - **As M5 ran them**, 30 runs a server: no `none` on either, and NON-STRICT on 3.4, 4.1.5 and 4.2.5 only 1 and 4 times in 90, where M5 saw 37. Run so, the cases cannot tell the servers apart.
  - **The echo held to 0.25 CPU**: no change; a mostly idle server never spends its quota.
  - **The echo and a busy loop on one CPU** brought M5's rate back: 30 runs, then 150 in alternating blocks of 50. In all, 720 tries a server: v0.4.1 lost the 1002 once (3.4), v0.5.0 never.
  - **M5's raw clients**, a 4 MiB frame against a 1 MiB cap. On macOS v0.4.1 lost the close in 30 of 100 connections, every one ending in an error; v0.5.0 in none, every one ending cleanly. On Linux both read it in all 100, but 6 of v0.4.1's ended in a reset and none of v0.5.0's.
- **DECIDED by form: "Drop none (Recommended)".** 3.4 and 4.2.5 list `OK OK 1002 | NON-STRICT OK 1002`, the verdicts v0.5.0 was measured to give, as decision 0008's item 5 asks. Weighed: keeping `none` listed. As a check of the lost close the gate is weak, since on Linux even v0.4.1 lost the 1002 once in 720 tries; the server's shell suite holds the linger.
- **Watched to fail** (`m5-mutations.md`): the gate on a full run's index, one case's close code `null`. Refused for 3.4 and 4.2.5 on the new ratchet, passed on main's; refused for 4.1.5 on both. 7 rows, 0 mismatches. Three full `make autobahn` runs passed on the new ratchet.
- **Records:** the ratchet and its note; decision 0008's amendment of 2026-10-11 (item 6 done, `none` dropped); design §9's lost close done; the research record's new section.
- **Found on the way, not fixed here:** in `run.sh`'s container path, `wait_listening` reads the last run's `server.log` before `docker logs` rewrites it, so a later run's wait can end before the new container listens. A task was flagged for it.
- `make test` green before the commit (Darwin arm64): fourteen suites, 381 expected passes, every pin ok. Linux aarch64 in a container (`chez-libuv-noble-scratch:10.4.1`, dash): fourteen suites and 381, `run.sh`'s suite 9 of 9.

NEXT: the PR; the closing ritual when the owner asks. Then, when CI is back, main's latest run; the R-TERM probe, then its fix; M6, v0.1.0.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **the ratchet drops `none` for 3.4 and 4.2.5** (the entry above), #70.
- **#70**, at b640699, was squashed as ecbffc8 (tree 8538227, the tested head's; parent 96138ce).
- **CI.** Billing-blocked: its run, 38161334795, and main's on the squash, 38162015335, each ended with both jobs, `linux` and `autobahn`, not started (0 steps, the payments annotation). The entry's local runs stood in: `make test` on Darwin and in the Linux aarch64 container, fourteen suites and 381, and three full `make autobahn` runs. It merged past the red check on the owner's word.
- **Branch.** Deleted, local and remote. This reflect is committed from the PR's worktree, detached at ecbffc8, then removed; the main checkout is fast-forwarded after it. No PR is open.
- **The task flagged for `run.sh`'s container wait** runs in a session of its own, on the owner's word.

`make test` green on main: fourteen suites, 381 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: the `run.sh` fix's PR, from its own session. When CI is back, main's latest run; the R-TERM probe, then its fix. M6, v0.1.0.

---

**The container path's wait reads this run's log alone (2026-10-11),** on the owner's ask, the task #70 flagged. Branch `fix/autobahn-container-wait`, cut from 7d33b4a; one PR.
- **Found** during #70. On the container path, `make autobahn`'s default on macOS and Windows, `run.sh`'s `wait_listening` read `$out/server.log` before anything had fetched the new container's log, and nothing emptied it first.
  - On a fresh tree, the first read printed `grep: … No such file or directory`.
  - On every later run, the last run's log says `listening`, so it ended the wait at once.
  - Measured on real Docker, over the last run's log: main's wait polled 0 times and the fixed one 7. Only the fuzzing client's slower start, in its emulated container, had kept runs green.
- **Landed:**
  - `run.sh` empties the log before it starts the container. It empties the file rather than removing it, so the wait's first read finds one.
  - `tests/autobahn/fake/docker` plays the container path too. Its container's log says `listening` from its second read, and its fuzzing client passes only once a read has shown that.
  - `tests/test-autobahn-run.sps` gains three checks: R-CWAIT, R-CENDS and R-CFRESH. The host path's helpers keep their names and build the same commands (compared for all nine calls).
- **Watched to fail** (`m5-mutations.md`, its last section):
  - Test-first, on main's `run.sh`: the three new checks red as named, the nine old ones green.
  - 18 rows (RM-1 to RM-10 again, CW-1 to CW-7 and the baseline), 0 mismatches. RM-8 survives, as before.
  - Under dash in the Linux container, main's `run.sh` and the removed-log mutant (CW-2) redden the same checks by the same values.
- **Seen, not changed:** when the echo container's `docker run -d` fails, the network made for it is left, since the cleanup trap is set only after the container starts. Measured with an image that does not exist; the network was removed by hand. A task was flagged for it.
- **CI did not run:** GitHub Actions is billing-blocked through October, by the owner's word. Stood in for:
  - **the `linux` job,** by `make test` in `chez-libuv-noble-scratch:10.4.1` (Linux 6.12 aarch64, dash, libuv 1.48.0): fourteen suites and 384;
  - **the `autobahn` job,** which runs the host path, whose code is unchanged. Its checks pass under dash. The container path changed, and `make autobahn` on macOS passed twice, from a fresh tree and then over its log.
- `make test` green before the commit (Darwin arm64): fourteen suites, 384 expected passes, every pin ok.

NEXT: the PR; the closing ritual when the owner asks. Then the network left by a failed container start, from its task. When CI is back, main's latest run; the R-TERM probe, then its fix. M6, v0.1.0.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **the container path's wait reads this run's log alone** (the entry above), #71.
- **#71**, at 16cc5cc, was squashed as ebb5c1f (tree f7156bd, the tested head's; parent 7d33b4a).
- **CI.** Billing-blocked: its run, 38163493911, and main's on the squash, 38163636478, each ended with both jobs, `linux` and `autobahn`, not started (0 steps, the payments annotation). The entry's local runs stood in: `make test` on Darwin and in the Linux aarch64 container, fourteen suites and 384, and two `make autobahn` runs on the container path. It merged past the red check on the owner's word.
- **Branch.** Deleted, local and remote. This reflect is committed from the PR's worktree, detached at ebb5c1f, then removed; the main checkout is fast-forwarded after it. No PR is open.
- **The task flagged for the network a failed container start leaves** runs in a session of its own, on the owner's word. Its branch, `fix/autobahn-network-leak`, was cut from #71's head, 16cc5cc, whose tree the squash keeps.

`make test` green on main: fourteen suites, 384 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: the network-leak fix's PR, from its own session. When CI is back, main's latest run; the R-TERM probe, then its fix. M6, v0.1.0.

---

**The container path's network removed when its run ends early (2026-10-11),** on the owner's ask, the task #71 flagged. Branch `fix/autobahn-network-leak`, cut from #71's head (16cc5cc) while #71 was open, then moved onto main's fcbc598 once #71 was squashed as ebb5c1f, whose tree is 16cc5cc's; one PR.
- **Found** in #71. `run.sh`'s container branch made its network, started the container, and only then set its traps. When `docker run -d` failed, `run.sh` exited 2 and left the network. The owner measured it with an image that does not exist. A signal before the traps left the network too, and the container if it had started.
- **Landed:**
  - `run.sh` sets its traps as soon as `cleanup` is defined, right after the network is made and before `docker run -d`.
  - `tests/autobahn/fake/docker` names each network and container it makes in `FAKE_STATE/made`, and keeps a network in `FAKE_STATE/networks` until it is removed. It gains `FAKE_ECHO=fails` (made, cannot start, exit 127, the container left, as Docker 29.2.1 does) and `FAKE_ECHO=term`.
  - `tests/test-autobahn-run.sps` gains R-CFAIL and R-CTERM. Each reads what was made, by kind, and what of it is left.
- **Watched to fail** (`m5-mutations.md`, its last section):
  - Test-first, on #71's `run.sh`: the two new checks red as named, the 12 old ones green. The first run was red by the wrong value: the check read the state before the run (`append`'s arguments have no order). A `let` fixed it.
  - 24 rows (#71's 18 and NL-1 to NL-6), 0 mismatches. NL-4 (the INT and TERM traps after the start) survives on macOS, whose sh runs the EXIT trap on a fatal TERM; dash does not, and it reddens R-CTERM there. NL-6 (no INT trap) survives: no check sends INT. RM-8 survives, as before.
  - Under dash: #71's `run.sh`, NL-3 and NL-4 redden as named.
  - Real Docker: #71's `run.sh` left the network for a missing image, the network and a `Created` container for a missing entrypoint, and the network and a running container for a TERM during `docker run -d`. The fixed one left nothing in each.
- **Seen, not changed:** a signal while `docker network create` itself runs can still leave the network. Setting the traps above the create would close it, at the cost of a failed create removing a network of that name.
- **CI did not run:** GitHub Actions is billing-blocked through October, by the owner's word. Stood in for:
  - **the `linux` job,** by `make test` in `chez-libuv-noble-scratch:10.4.1` (Linux 6.12 aarch64, dash, libuv 1.48.0): fourteen suites and 386;
  - **the `autobahn` job,** which runs the host path, whose code is unchanged. Its checks pass under dash. The container path changed, and `make autobahn` on macOS passed twice, from a fresh tree and then over its log, with nothing left.
- `make test` green before the commit (Darwin arm64): fourteen suites, 386 expected passes, every pin ok.

NEXT: the PR; the closing ritual when the owner asks. When CI is back, main's latest run; the R-TERM probe, then its fix. M6, v0.1.0.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **the container path's network removed when its run ends early** (the entry above), #72.
- **#72**, at c548090, was squashed as 0298c48 (tree d950062, the tested head's; parent fcbc598).
- **CI.** Billing-blocked: its run, 38165077964, and main's on the squash, 38165234147, each ended with both jobs, `linux` and `autobahn`, not started (0 steps). The entry's local runs stood in: `make test` on Darwin and in the Linux aarch64 container, fourteen suites and 386, and two `make autobahn` runs on the container path. It merged past the red check on the owner's word.
- **Branch.** Deleted, local and remote. This reflect is committed from the PR's worktree, detached at 0298c48, then removed; the main checkout is fast-forwarded after it. No PR is open. Another session's M6.1 branch, `chore/release-0.1.0` (worktree `m6`), is cut from fcbc598 and has no PR yet.

`make test` green on main: fourteen suites, 386 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: M6, v0.1.0, from its own session. When CI is back, main's latest run; the R-TERM probe, then its fix.

---

**M6.1, the user docs (2026-10-11),** on the owner's "chez-websocket M6". Branch `docs/m6-1-user-docs`, cut from fcbc598, then rebased onto 270ce0e once #72 merged; the release stacks on it (by form, "Two stacked PRs": this +602, the release +147).
- **Forms, each the recommended:**
  - **"docs/ first":** v0.1.0 had no user docs. The README said how to build, and the API lived in the facade's header and the design's §1 and §7.
  - **"Re-measure on v0.5.0":** the README's "about 8 KB" an idle connection costs is M4.3's figure. At the v0.4.1 pin it measured 5,253 to 5,292 B at a bare `await`, 303 to 340 B more in a receive (design §9), and nothing has measured it on v0.5.0. The release measures it again.
  - **"Tag on local runs":** CI is billing-blocked through October, by the owner's word. As the server's v0.5.0 was tagged.
  - **"Release before them":** R-TERM's one CI failure and the network-leak fix are both in the Autobahn lane's `run.sh`, which no user loads.
- **Built:**
  - `docs/handlers.org`: the design's §1 echo example; the handshake's refusals; receive, send, close and the subprotocol; what each close sends and what `&websocket-closed` says; subprotocols and origins; limits for one handler; what it does not do.
  - `docs/configuration.org`: the eight `CHEZ_WS_` variables, their defaults, units, spelling and least values; the queue, quiet clients, slow readers and the close; the server's own variables, by link at v0.5.0.
  - README.org: "Using it", pointing at both. CHANGELOG.md: the docs under Unreleased. The plan's M6: the four forms.
- **Held by a check, not a comment:** `tests/test-docs.sps`, six checks. The configuration table's variables are the library's, in its order, and its defaults, read as an environment, are the library's in each variable's unit. Every name of the library's the pages write is one `(websocket)` exports. Every Scheme block reads. The handlers page's first program, `serve` captured, is played on the fake shell: RFC 6455's handshake to /echo answered 101 with §1.3's accept, a masked Hello echoed as §5.7's frame, the client's close 1000 answered 1000; and another path 404.
- **Tests first:** before the pages, status 2 at the first read, as named. On the first pages, 5 of 6: the echo check's stimulus sent the client's close in the Hello's read, so the binding answered the close before the procedure ran, and a send while the server's close is under way sends nothing. The close now comes in a read of its own.
- **Mutants** (`m6-mutations.md`, new): 16 and the baseline.
  - Run 1: 2 mismatches. M6-15's cut replaces every occurrence, and the runner's pre-flight asked for one. M6-11, the program's `(websocket)` import dropped, ended the suite in a harness error: Chez refuses an unbound identifier as the program is evaluated, and the program loaded outside any check. Fixed: each check loads and plays the program, a raise answering `(raised message)` in its place. My prediction had been DOC-ECHO alone; it became DOC-ECHO and DOC-404 before run 2.
  - Runs 2 and 3: 0 mismatches, and run 4, on the rebased tree, the pages' and the suite's blobs unchanged: 0. Every check has a killer by value.
  - **M6-14 survives, a scope statement:** the pages' prose and their tables of statuses and codes are the handshake's and the protocol's, held to the RFC by their own suites, and not seen here.
- `make test` green before the commit, on the rebased tree (Darwin arm64): fifteen suites, 392 expected passes, every pin ok; main's fourteen and 386, and the docs suite's 6. `make check-help` passes. Linux aarch64 in a container (`chez-libuv-noble-scratch:10.4.1`, dash, libuv 1.48.0), every suite as `make test` runs it, the pins checked on the host: fifteen suites and 392, each suite's count Darwin's.

NEXT: the release, stacked on this: the connection's cost measured on v0.5.0; CHANGELOG.md's Unreleased moved under `[0.1.0]`; the README's status; then the PRs, and at the closing ritual, the signed tag `v0.1.0` on the release's squash.

---

**M6.2, v0.1.0's release, on `chore/release-0.1.0` (2026-10-11),** on the owner's "chez-websocket M6". Stacked on `docs/m6-1-user-docs`, both on main's 270ce0e.
- **What it carries.** The `[0.1.0]` section was written from the milestone plan, the design, the decisions and this ledger, M0 to #72, and checked against the facade's exports and each library's header. The docs entry M6.1 put under Unreleased is in it.
- **The version:** 0.1.0, the plan's M6. No form: the first release.
- **The pins:** chez-http-server v0.5.0 (02ef95d), which brings chez-libuv v0.9.0 (3c4e7f0), chez-httparse v0.4.5 (0b7058e) with byte-machine v0.7.0 (c338a57), uriparse v0.6.2 (5ecd88f) and chez-srfi 7879b52.
- **Measured** (by form, "Re-measure on v0.5.0"; the research record's last section, by the probe `.plans/research/spike/ws-cost.sps`, committed by M6's review):
  - **A connection's cost,** by the server's method, five holds each, Darwin: an idle WebSocket in a receive 5,281 to 5,435 B, and 5,353 to 5,477 B after 10 echoes; the server's own idle connection 1,900 to 2,055 B. Measured first on 54da491's tree (#73's first commit, on fcbc598), then again on 270ce0e's once #72 had merged; the records give the second.
  - **`make autobahn`,** on the container path, twice: on 54da491's tree (#73's first commit, on fcbc598), 291 OK, 7 NON-STRICT and 3 INFORMATIONAL, gate passing (61 s); on this tree, 290, 8 and 3, case 3.4 NON-STRICT, one of the three the ratchet lists both ways, gate passing (56 s). No network or container left by either; `ab-net`, M5's of 2026-10-10, was there before.
- **Built:**
  - CHANGELOG.md: `[0.1.0] - 2026-10-11`, with an intro naming the pins, Added, and Measured; a fresh, empty Unreleased above it; the link references, `[0.1.0]` the tag's release page.
  - README.org's status: v0.1.0 the first release, pointing at the CHANGELOG; an idle connection about 5.3 KB, where it said about 8 KB.
  - Design §9 and the research record: the measure.
- **CI is billing-blocked,** so by the owner's form ("Tag on local runs") these stand in, on this branch's tree before this entry:
  - Darwin arm64, `make test`: fifteen suites, 392 expected passes, every pin ok;
  - Linux aarch64 (`chez-libuv-noble-scratch:10.4.1`, dash, libuv 1.48.0), every suite as `make test` runs it, the pins checked on the host: fifteen suites and 392;
  - Linux x86_64 under emulation (`chez-websocket-ci-amd64:10.4.1`, libuv 1.48.0), the same: fifteen suites and 392, in 98 s;
  - each suite's count alike on the three; and the two `make autobahn` runs above.
- **The tag.** After the merges, at the closing ritual: `v0.1.0` on the stack's last squash, annotated and signed (corrected by M6's second review: the release's squash until M6's review stacked on it, #75), as the server's are: "chez-websocket v0.1.0 — WebSocket for chez-http-server", its body pointing at CHANGELOG.md's `[0.1.0]`. Main's run is read once CI returns.
- `make test` green before the commit (Darwin arm64): fifteen suites, 392 expected passes, every pin ok. Nothing tested changed: CHANGELOG.md, README.org, the design, the research record and the ledger only.

NEXT: the PRs; the closing ritual for both, bottom-up, and the tag, when the owner asks. When CI is back, main's latest run; the R-TERM probe, then its fix.

---

**M6'S REVIEW (2026-10-11),** on the owner's "fix all" after a `/code-review` (xhigh) over #73 and #74 reported 14 findings. Branch `fix/m6-review`, stacked on `chore/release-0.1.0` (#74); one PR, by form ("One PR"). The tag now goes on this PR's squash, the stack's last.
- **The docs suite's holes** (the four most severe), each closed and watched to fail:
  - **A default that is not a number, or is in another unit, passed:** "off", "20 ms" and "16 s" read as unset, or as seconds. DOC-DEFAULTS now reads a cell only as digits then ` s` for a duration and digits alone for a size or a count (the design's §7), anything else `(unreadable row)`.
  - **Names outside five prefixes went unchecked**, `&websocket-closed` among them: DOC-NAMES now takes `websocket?`, `&websocket-…`, asked for its record type, and `handshake-settings…`. New, DOC-FIELDS: the fields handlers.org lists are the design's §7's, each one `websocket-limits-with` takes.
  - **The fragments were only read:** new, DOC-FRAGMENTS runs each where its words put it, in a handler when it names `request`, else in a WebSocket's procedure, the names it takes from around it given by the suite. The settings and limits fragments answer RFC 6455's handshake 101; the guard's echoes and shows `1000`.
- **The pages:** configuration.org's closing bullet said the connection is always cut off; now only a client that has not answered within the close timeout is, timed from when the close was asked for. handlers.org's limits example made its settings and limits at every request; now once, as its own advice says.
- **The rest:**
  - `#+begin_src` in any case, and a block never ended red;
  - a program's forms run as a top-level program's (R6RS §8.1);
  - a row of no cells, or with no last bar, read;
  - the suite refuses to run with a `CHEZ_WS_` variable set, as the binding suite does;
  - the first measures' tree is 54da491, not fcbc598 (the entries above and the research record, corrected in place);
  - the probe committed as `.plans/research/spike/ws-cost.sps` and `ws-hold.py`, its header saying how to run it, and cited;
  - `concat` and `copy` in `(ws-play)`, the binding suite's and the docs suite's; lines by `(ws-autobahn)`'s `text-lines`. The driver suite keeps its own, since it does not import `(ws-play)`. `values-of` stays in the docs suite: the limits suite imports nothing that has it;
  - the CHANGELOG's Added names the per-handler settings and limits.
- **The probe, as committed,** run again on this tree (Darwin, five holds each): 5,251 to 5,403 B in a receive, 5,381 to 5,511 B after 10 echoes, the server's own 1,809 to 2,054 B, overlapping the release's figures, which stand.
- **Watched to fail** (`m6-mutations.md`, its review section):
  - **The new suite:** M6-1 to M6-16 named again, M6-17 to M6-34 new; 0 mismatches. M6-30 to M6-32 are named green: a definition after `serve`, a row with no last bar, a bare `|` line. M6-33, a `CHEZ_WS_` variable set: status 2. M6-14 survives as before, a scope statement.
  - **#73's suite, the same new mutants:** the first run void, mine: `(ws-play)`'s new exports collide with its own definitions. With those taken out of the scratch copy, 0 mismatches. It passed every hole, and failed M6-30 to M6-32.
  - **The new suite on #74's pages,** before their fixes: 8 of 8, as named.
- `make test` green before the commit (Darwin arm64): fifteen suites, 394 expected passes, the docs suite's 8, every pin ok. `make check-help` passes. Linux aarch64 in a container (`chez-libuv-noble-scratch:10.4.1`, dash, libuv 1.48.0): fifteen suites and 394, each suite's count Darwin's. The CHANGELOG says 394.

NEXT: the PR; the closing ritual for #73, #74 and this, bottom-up, and the tag `v0.1.0` on this PR's squash, when the owner asks. When CI is back, main's latest run; the R-TERM probe, then its fix.

---

**M6'S SECOND REVIEW (2026-10-11),** on the owner's "fix the ones that matter" after a second `/code-review` (xhigh) over #75 reported 12 findings. On `fix/m6-review` (#75), a second commit.
- **Fixed, the five that matter:**
  - **The fragments are known by name, not guessed.** DOC-FRAGMENTS took a fragment's role from the word `request`, and held every other fragment to one fragment's echo and `1000`. Now each carries an org `#+name:`, and the suite's `fragment-plays` gives each its own play and result, from the page's words. A fragment the suite does not know, or one it knows that the page lost, is red. So the check cannot pass on an empty page either.
  - **The handler fragments are held to what they show,** not to a 101 alone. `chat-settings` must choose `chat.v2` of an offer of `chat.v1, chat.v2`, take the app's page and refuse another site's 403. `upload-limits` must take a frame announcing 2,000,000 bytes, which the default cap fails 1009.
  - **The tag:** the M6.2 entry's tag line now says the stack's last squash, corrected in place. #74's commit message said the same of its own squash; it is amended, its tree unchanged, and this branch moved onto it.
  - **The limits example** makes settings of its own, `(make-handshake-settings '())`, where it borrowed the chat example's subprotocols and origins.
  - **configuration.org's close:** whoever begins it, the client has the close timeout, counted from when the server's close was queued, to read what is left, and to answer if the server began it. The table's row says "finish a close".
- **Not fixed, by the owner's word:** the six others (first written as seven). Tabs or two spaces before a block's language; `(ws-play)`'s generic `copy` and `concat`; `(ws-autobahn)` imported for `text-lines`; `field?` reading `condition-who`; blocks read more than once; and DOC-NAMES's environment wider than its title.
- **Watched to fail** (`m6-mutations.md`, its second review's section): M6-1 to M6-34 named again and M6-35 to M6-42 new, 0 mismatches. On the first review's suite the eight new ones each passed, as named.
- `make test` green before the commit (Darwin arm64): fifteen suites, 394 expected passes, every pin ok. `make check-help` passes. Linux aarch64 in a container (`chez-libuv-noble-scratch:10.4.1`, dash, libuv 1.48.0): fifteen suites and 394, each suite's count Darwin's.

NEXT: the PRs; the closing ritual for #73, #74 and #75, bottom-up, and the tag `v0.1.0` on #75's squash, when the owner asks. When CI is back, main's latest run; the R-TERM probe, then its fix.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **M6, v0.1.0, as three stacked PRs** (the four entries above), bottom-up, and **the tag `v0.1.0`**.
- **#73, the user docs:** 1b9fe1d squashed as b7486b6 (tree ae60f9d, the tested head's; parent 270ce0e). It merged without deleting its branch, since #74 was based on it.
- **#74, the release:** retargeted to main and rebased from 1b9fe1d onto b7486b6, d46b08d becoming 99df52f (tree dd8c3d5, unchanged), pushed with the lease. It squashed as 68aafbd (tree dd8c3d5; parent b7486b6).
- **#75, M6's two reviews:** retargeted to main and rebased onto 68aafbd, 1a6a919 becoming 9c46561 (tree fe23180, unchanged), pushed with the lease. It squashed as 87bc9e6 (tree fe23180; parent 68aafbd), its message both commits'.
- **The tag:** `v0.1.0`, annotated and signed (tag object 6a641d4, EdDSA key D4D955D55C8853D7, a good signature), on 87bc9e6, the stack's last squash: "chez-websocket v0.1.0 — WebSocket for chez-http-server". Its body names CHANGELOG.md's `[0.1.0]`. Pushed; no GitHub release was made, as for the server's tags.
- **CI.** Billing-blocked: the PRs' last runs, 38169790136 (99df52f) and 38169816473 (9c46561), and main's on each squash, 38169778213 (b7486b6), 38169802989 (68aafbd) and 38169831729 (87bc9e6), each ended with both jobs, `linux` and `autobahn`, not started (0 steps). The entries' local runs stood in, by the owner's form ("Tag on local runs"): `make test` on Darwin, Linux aarch64 and Linux x86_64, and two `make autobahn` runs. They merged past the red check on the owner's word.
- **Branches.** All three deleted, local and remote. This reflect is committed from the `m6` worktree, detached at 87bc9e6, then removed. The main checkout is fast-forwarded after it. No PR is open.

**M6 is done, and with it the milestone plan:** v0.1.0 is the first release. The README's status names it.

**Reflect.**
- **The docs needed a check of their own.** The first docs suite passed pages that were wrong, as each review found. A default of "off" or "20 ms" passed. The condition type's name went unchecked, and the snippets were only parsed. Each fix was proved by mutants run against the suite before it: those mutants passed there and fail here.
- **A measure in a record goes stale with its pin.** The README's "about 8 KB" had stood since M4.3, through the v0.4.1 pin, which cut it to about 5.3 KB. The probe is now committed, so the next pin can measure it again.
- **Main moved under the stack** (#72, from another session) between the docs' first commit and the PRs. Rebasing first, and measuring again on the rebased tree, kept every count in the records true of a tree on main.

`make test` green on main (87bc9e6, Darwin arm64): fifteen suites, 394 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: when CI is back, main's latest run; the R-TERM probe, then its fix. The second review's seven findings left unfixed (its entry lists them). The next server release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps`.

---

**R-TERM's probe and fix (2026-10-11),** on the owner's "start the R-TERM probe". Branch `fix/r-term`, cut from 3637f8a.
- **CI could not run the probe.** Main's latest run, 38169940312, ended with both jobs not started, the billing block. So the probe ran in the local Linux containers instead, each with a pid 1 that never reaps, and found the cause. The measurements are in `m5-mutations.md`, its last section.
- **The cause.** On a Linux host, libuv 1.48 gives the echo server's loop an io_uring ring with a polling thread, `iou-sqp`. Docker's default seccomp forbids io_uring, so the containers never had that thread, and macOS has no io_uring.
  - At SIGTERM, the server's main thread exits first, and `ps` shows `Zl` while `iou-sqp` still runs. `echo_alive` read that as gone, but the shell could not reap the server yet.
  - On the TERM path, `run.sh` exits right after `echo_stop`. The server would then be left to the runner's init, and R-TERM's `kill -0` would sometimes come first: one of the three CI runs on that tree failed. That CI side is inferred, not observed: all CI showed is `(#t 0)` (corrected in place by the review below).
  - Measured: 0 of 400 runs under the default seccomp on aarch64, half of them under load, and 0 of 100 on x86_64. With io_uring allowed, 19 of 30; with the fix, 0 of 30.
- **The fix:** `echo_stop` waits for its server once `ps` shows it ended, so the shell reaps its own child.
- **The check, test-first.**
  - The fake docker's `term` mode holds the server lingering for 500 ms: stopped, and named in `lingers`. A new fake `ps` reads it as `Zl`.
  - R-TERM is now red on main's `run.sh` in every run, on macOS and under dash. Before, it could fail only on a Linux host with io_uring.
- **Watched to fail:** 7 rows on macOS, 0 mismatches, and the same seven under dash. RM-8, a survivor since M5's review, is killed as RT-2: the lingering server outlives the shell's next command.
- **Seen, not fixed:** R-TWO red in 3 of 50 suite runs under dash, each over the last run's logs.
  - The likely cause: the host path leaves emptying `server.log` to the server's own redirection, in the forked child. The shell's first `grep` can win that race.
  - Left for a change of its own.
- **`probe/r-term`** is kept, to confirm the cause on CI once CI is back (corrected in place by the review below).
- `make test` green before the commit (Darwin arm64): fifteen suites, 394 expected passes, every pin ok. On Linux aarch64 in a container with io_uring allowed (`chez-libuv-noble-scratch:10.4.1`, `--security-opt seccomp=unconfined`, dash, libuv 1.48.0): fifteen suites and 394, each suite's count Darwin's.

NEXT: the PR; the closing ritual when the owner asks. When CI is back, main's latest run. The host path's old-log race, in a change of its own. The second review's seven findings left unfixed. The next server release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps`.

---

**R-TERM's review (2026-10-11),** on the owner's "fix all" after a /code-review (xhigh) of #76 reported seven findings. On `fix/r-term`.
- **Fixed, all seven:**
  - **The stop is bounded again.** `echo_stop` polls until `ps` shows nothing, not even a zombie, which the shell reaps at the sleep's wait. The unbounded `wait` is gone, so "did not stop within 30 s" holds once more.
  - **The fake `ps`:**
    - It asks the `ps` on PATH after itself, not `/bin/ps`.
    - It takes the pid from `-p`, wherever that is.
    - It continues a lingering server the second time it is asked, counted in asks, not 500 ms of wall-clock time.
  - **The marker is named once,** `FAKE_LINGERS`, set by the suite for every lane.
  - **The records:** the probe section says which runs had the `ps` shim, and that CI's side of the cause is inferred. The R-TERM entry above is corrected in place.
  - **`probe/r-term` is kept,** with a step that lists the runner's threads and watches the server's exit (90c04fd). It will tell whether CI's runner has the `iou-sqp` thread.
- **A check of the fake `ps`,** R-FAKEPS: a stub `ps` after it, a lingering pid named by `-p` first, `("Zl" "T")`.
- **Watched to fail** (`m5-mutations.md`, "R-TERM's review"):
  - Test-first: R-FAKEPS red on the old fake. The new fakes on the PR head's `run.sh` hung in R-TERM until `timeout` killed it, which is the finding itself.
  - Mutants: 11 rows, 1 mismatch, RT-3, the prediction's: R-FAKEPS holds the fake's `Zl` too.
  - The PR head's form, RT-5, hangs. A server that is never continued, FP-3, is red at the 30 s cap.
  - Under dash with io_uring, all eleven matched macOS but RT-4, the real race there.
- `make test` green before the commit (Darwin arm64): fifteen suites, 395 expected passes, every pin ok. `make check-help` passes. On Linux aarch64 with io_uring allowed (`chez-libuv-noble-scratch:10.4.1`, `--security-opt seccomp=unconfined`, dash, libuv 1.48.0): fifteen suites and 395, each suite's count Darwin's.

NEXT: the PR's CI, when CI is back, and the closing ritual when the owner asks, `probe/r-term` kept. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause there. The host path's old-log race, in a change of its own. The second review's seven findings left unfixed. The next server release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps`.

---

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **R-TERM's probe and fix, and its review** (the two entries above), #76.
- **#76**, at adadde5, was squashed as 96f6285 (tree ced87cd, the tested head's; parent 3637f8a). Its message is all three commits'.
- **CI did not run.** The PR's runs, 38174218722 (e487b94), 38176190506 (e59f78e) and 38176289113 (adadde5), and the probe's, 38176038063 (90c04fd), each ended with every job not started (0 steps), the billing block. The entries' local runs stood in: macOS, and Linux aarch64 with io_uring allowed. It merged past the red check on the owner's word.
- **Branches.** `fix/r-term` was deleted, local and remote. `probe/r-term` (90c04fd) is kept for CI. This checkout is on main, fast-forwarded. #77, another session's, is open.

**Reflect.**
- **The stand-ins were not running the server CI runs.** Docker's default seccomp forbids io_uring, so in every Linux container here, M5's and M6's included, the echo server had no `iou-sqp` thread. CI's runner and any Linux host have one. The 80+ local runs could never see R-TERM fail. When a CI-only failure will not reproduce, ask first what the sandbox takes away.
- **A pid 1 that never reaps turned a race into a count.** With `sleep` as init, anything `run.sh` left behind stayed: 19 of 30, where CI's reaper made it one run in three.
- **The first fix trusted the fake it was tested with.** The `wait` relied on `ps` telling the truth about Z, and the review found it unbounded. The new fake was not executable at first, so a check passed without it. Now R-FAKEPS holds the fake `ps`, and the stop's 30 s cap is held by FP-3.

`make test` green on main (96f6285, Darwin arm64): fifteen suites, 395 expected passes, every pin ok.

NEXT: when CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI; then that branch can go. The host path's old-log race, from its task. The second review's seven findings left unfixed. The next server release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps`.

---

**S-LETGO's 2.9 KB, explained (2026-10-11),** on the owner's "do the chez-websocket docs PR", the server's form "A docs PR there, after (Recommended)". One docs branch, `docs/drain-retention-explained`, cut from main at 3637f8a in its own worktree, and rebased onto #76's squash and its reflect (0b90231) before the merge.
- **What changed upstream.** The server's plan §14 listed what its full drain keeps after a big read, from 0007's finding 4. It settled it by measurement (chez-http-server#178, merged as e5be01a): nothing is kept. The 2.9 KB was the heap falling between S-LETGO's two readings. Each wake's full capture uses up the thread's stack segment by the drain's depth, until Chez gives it a fresh one.
- **Measured here, on the pinned v0.5.0** (Darwin arm64), with the probe now committed as `.plans/research/spike/s-letgo-floor.sps`. It reads S-LETGO's difference and, beside it, the same for two 1-byte messages:
  - one connection, 4,000 and 16,000 bytes: 2,880 to 2,984 B, and 2,888 to 2,944 B for two 1-byte messages;
  - ten connections, 4,000 bytes: 8,016 to 9,456 B, and 8,544 to 9,536 B. Three readings near −55 KB came where a fresh segment was given.
- **Records corrected:**
  - decision 0007 (status, its "weighed" note, its consequence, and an amendment of 2026-10-11; its pointer names the research record's section);
  - the research record (a note under S-LETGO's table, and a section of its own);
  - the design doc's "measured before the v0.4.1 pin" (and its pointer to the v0.1.0 section, no longer the last);
  - the socket suite's oracle note.
- **Nothing else changes.** S-LETGO's bound, half the frame, 8,004 B, is above the fall. No check, export or behaviour changes. This binding wakes its receives with `#t`, so the server's fix (#178, a waiting coroutine kept what woke it) changes nothing it keeps. Its fifteen suites passed on the server's branch, 394.
- `make test` green before the commit (Darwin arm64): fifteen suites, 394 expected passes, every pin ok; `make check-help` passes. Rebased onto #76's squash and its reflect, 395, its R-TERM check among them, every pin ok.

NEXT: the PR; the closing ritual when the owner asks. When CI is back, main's latest run. The server's next release pinned here alone.

MERGED to main on 2026-10-11, on the owner's "do closing ritual": **S-LETGO's 2.9 KB, explained**, #77 (the entry above).
- **The rebases.** #76 merged (96f6285) as #77's merge was asked for, and the merge was refused for a conflict. Both entries had been appended to this ledger. #77 was rebased onto 96f6285, keeping both entries. Then #76's reflect landed (0b90231), and #77 was rebased onto that too. The five files besides the ledger were proved byte-identical to the reviewed head's (7aa4440). The ledger only gained lines, and `make test` passed on each rebased tree, 395. The final head, 32e6944, was pushed with the lease read from `ls-remote`.
- **The squash.** 32e6944 squashed as 05d6dbf, on 0b90231, with `--match-head-commit` on the full SHA. Its tree, 1b8186d, is the tested head's.
- **CI.** Billing-blocked. Each run's `linux` and `autobahn` jobs were not started (0 steps, the payments annotation): the PR's 38175693664 (7aa4440) and 38178529477 (32e6944), and main's 38178554139 on the squash. The Darwin runs stood in, as the PR body said. It merged past the red check on the owner's word.
- **Branches.** `docs/drain-retention-explained` was deleted on the remote by the merge, and locally once this reflect's worktree was detached at 05d6dbf. The worktree is removed after the push. No PR is open.

**Reflect.** Two sessions appended to this ledger at once. Each rebase kept both entries, and the files under review were proved unchanged by it. Re-read main, and the open PRs, right before the merge, not only before the PR.

`make test` green on main (05d6dbf, Darwin arm64): fifteen suites, 395 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: when CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The host path's old-log race, from its task. The second review's seven findings left unfixed. The server's next release (the wake-value fix, its decision 0027, the signal fix) pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps` and S-LETGO's floor by `.plans/research/spike/s-letgo-floor.sps`.

---

**The host path's old log (2026-10-11),** on the owner's task "first prove the mechanism … then fix the host path by emptying server.log in the parent before the server starts". Branch `fix/autobahn-host-log`, cut from 50017c4. The measurements are in `m5-mutations.md`, its last section.
- **The finding** (R-TERM's "Seen while measuring"): R-TWO red in 3 of 50 suite runs under dash, each over the last run's logs, with an empty `server.log` and "the echo server ended without stopping:".
- **Proved, not inferred.**
  - Forced: a copy of `run.sh` whose server child waits, before its own `>`, until the wait has read the log. Main's form failed as R-TWO did, the fuzzing client given the last run's port, 3 of 3 on macOS and 5 of 5 under dash. The fixed form passed every round.
  - The real race, main's `run.sh` unchanged: 8 runs at once in the io_uring container, each over its last log. 21 of 320 failed as R-TWO did. Each had read the old `listening` line: 4 were given the last run's port, and 17 no port, the child's `>` emptying the log between the wait's `grep` and its `sed`. With the fix, 0 of 320.
- **The fix:** `run.sh`'s prelude empties `server.log` before either path starts its server. The container path's own emptying is folded into it.
- **The checks, test-first.** No command `run.sh` calls runs between the fork and the child's `>`, so no fake on PATH can hold that window. The suite writes a held copy of `run.sh` instead.
  - In that copy, the background command's child names its pid in `FAKE_HELD` and stops itself before its redirections. The fake `ps` continues it the first time it is asked about it.
  - **R-HWAIT:** over a last run's log, a run passes. **R-HFRESH:** on a tree with no log yet, a run says only the gate's line.
  - Both are red on main's `run.sh` in every run, 4 of 4 on macOS and 3 of 3 under dash, by the values named.
- **Watched to fail:** run 1 on macOS, 34 rows, 1 mismatch, the prediction's.
  - HF-2 (`kill -0` for `kill -STOP`) was named to survive. But its `sh -c` still delays the child by one process start, enough to lose the race often. Run 2 measured it, red 2 of 2 in R-HWAIT and 1 of 2 in R-HFRESH. With no hold at all (HF-4), the checks stay green.
  - Survivors, scopes: HL-4 (emptied after the fork), HL-5 (a failed emptying not caught), NL-4 and NL-6 as before.
  - Under dash, eight rows as on macOS.
- `make test` green before the commit (Darwin arm64): fifteen suites, 397 expected passes, every pin ok. On Linux aarch64 with io_uring allowed (`chez-libuv-noble-scratch:10.4.1`, `--security-opt seccomp=unconfined`, dash, libuv 1.48.0): fifteen suites and 397, each suite's count Darwin's.

NEXT: the PR; the closing ritual when the owner asks. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The second review's seven findings left unfixed. The server's next release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps` and S-LETGO's floor by `.plans/research/spike/s-letgo-floor.sps`.

MERGED to main on 2026-10-11, on the owner's "Do ritual": **The host path's old log** (the entry above), #78.
- **#78**, at 7ea183d, was squashed as c79c866 (tree 41e9d1a, the tested head's; parent 50017c4), with `--match-head-commit` on the full SHA. Its message is the commit's.
- **CI did not run.** The PR's run, 38181338934 (7ea183d), ended with `linux` and `autobahn` not started (0 steps, the payments annotation). The entry's local runs stood in: macOS, and Linux aarch64 with io_uring allowed. It merged past the red check on the owner's word.
- **Branches.** `fix/autobahn-host-log` was deleted, local and remote. The main checkout is on main, fast-forwarded. This reflect is committed from the session's worktree, detached at c79c866. Its app branch, `claude/fervent-mccarthy-433c50`, is local only, with no commits of its own, and is left to the app. No PR is open.

**Reflect.**
- **Find the seam before choosing the fake.** Both ways the task offered to force the race assumed a fake could stand between the fork and the child's `>`. Nothing `run.sh` calls runs there, so the check holds a copy of `run.sh`, its one command wrapped. Asking first where a fake could stand saved building one that could never be red.
- **Load, not repetition, showed the race.** 0 of 60 runs in sequence or two at once, but 21 of 320 with 8 at once. 17 of the 21 were given no port at all, so a probe that watched only for the old port would have missed most of them.
- **A cut that looks neutral can be a measurement.** HF-2's `kill -0` kept one `sh -c` before the `>`, and that alone lost the race most of the time. The window is about one process start wide.

`make test` green on main (c79c866, Darwin arm64): fifteen suites, 397 expected passes, every pin ok, the server at v0.5.0 (02ef95d).

NEXT: when CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI; then that branch can go. The second review's seven findings left unfixed. The server's next release pinned here alone, with a connection's cost measured again by `.plans/research/spike/ws-cost.sps` and S-LETGO's floor by `.plans/research/spike/s-letgo-floor.sps`.

---

**The server's v0.6.0, pinned alone (2026-10-12),** on the owner's "start the v0.6.0 pin", picked over waiting for the release that carries chez-libuv v0.10.0: a suite or Autobahn that moved would then be the server's alone. Branch `chore/pin-server-v0.6.0`, cut from main at 1e416af in its own worktree; one PR, one commit.
- **The pin:** chez-http-server moves from v0.5.0 (02ef95d) to v0.6.0 (47c787d, the tag signed, a good signature). The pins it carries are v0.5.0's: chez-libuv 3c4e7f0 (v0.9.0), chez-httparse 0b7058e, byte-machine c338a57, uriparse 5ecd88f and chez-srfi 7879b52.
- **Measured first** (Darwin arm64): main's suites unchanged, the server's checkout at v0.6.0 and `SERVER_PIN` not, run with `make -o check-pins test`. Three runs: fifteen suites and 397, each suite's count main's on v0.5.0, the baseline run the same hour in this worktree. No fit was needed, unlike v0.5.0's (#68).
- **What reaches here** (the server's CHANGELOG `[0.6.0]`, read against `src/`):
  - **The close's writes are bounded by the server too** (its decision 0027). Once `transport-close!` is asked for, each write the close waits for has `CHEZ_HTTP_WRITE_TIMEOUT` (60 s), and the stream is aborted past it. `close-stream!` arms the close timeout (10 s) before it calls `transport-close!`, so with the defaults the binding's bound comes first, as 0027 says. The protocol asks for `close-stream` after a clean close, after a failure's close frame, and at the stream's end, so a client that reads nothing there is cut at the earlier of the two. CHANGELOG.md's Unreleased says so.
  - **A signal sent as `serve` logs `listening` drains it** (#174), where before it could end the process undrained.
  - **A taker's early bytes wait for its read-start** (#179). The binding starts reading in its take-over, before it steps the bytes read past the request, so it lost nothing before.
  - **A taker hears its client's end once** (#181), and **a waiting coroutine lets go of what woke it** (#178). The binding wakes its receives with `#t`.
  - **The fake shell keeps closer to the server.** A deadline passing, and `fake-shell-settle!`, now run the connection's scheduler; a write after the close is told `ECANCELED` on the next turn. The binding and driver suites passed on it unchanged.
- **Watched to fail:** with the gitlink moved and `SERVER_PIN` not, `make check-pins` answered the predicted lines (hashed before the run, 51f31c54): `PIN MISMATCH: vendor/chez-http-server at 47c787d…, expected 02ef95d…`, the five carried pins ok, exit 2.
- **Measured again, as v0.1.0's NEXT asked** (Darwin arm64; the research record's section "At the server's v0.6.0 pin"; v0.5.0 beside it the same hour):
  - a connection's cost, by `ws-cost.sps`: an idle WebSocket in a receive 5,330 to 5,397 B on v0.6.0, 5,353 to 5,367 B on v0.5.0. The README's "about 5.3 KB" stands.
  - S-LETGO's floor, by `s-letgo-floor.sps`: a big message, then a small one, reads as two small ones on both, 2,880 to 2,984 B at one connection on v0.6.0.
- **Autobahn** (`make autobahn`, the container path on Docker Desktop, the echo image rebuilt from this tree, its server's `serve.sls` v0.6.0's): two runs, each `301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`, exit 0.
- **Records:** the Makefile's pin; the README's `make submodules` line; `docs/configuration.org`'s link to the server's configuration page, now at v0.6.0; CHANGELOG.md's Unreleased; the design's "What a connection costs"; the research record's new section.
- `make prod` green: fifteen suites and 397 on the prod shim, each suite's count main's, and both check-prod runs a prod build.
- **CI is billing-blocked,** so Linux ran in containers on this tree, io_uring allowed (`--security-opt seccomp=unconfined`):
  - aarch64 (`chez-libuv-noble-scratch:10.4.1`, libuv 1.48.0): fifteen suites, 397, each suite's count Darwin's;
  - x86_64 under emulation (`chez-websocket-ci-amd64:10.4.1`, libuv 1.48.0): fifteen suites, 397, each suite's count Darwin's.

  The pins are checked on the host.
- **The chez-libuv v0.10.0 handoff** (from the chez-libuv session, 2026-10-12): it reaches here only through a server release that carries chez-http-server#185 (merged as f27633d). That pin moves alone too, and its counts, `make prod`, Autobahn, and any new chez-libuv condition go back to that session.
- `make test` green before the commit (Darwin arm64): fifteen suites, 397 expected passes, each suite's count main's on v0.5.0, every pin ok; `make check-help` passes.

NEXT: the PR; the closing ritual when the owner asks. Then the server's release that carries chez-libuv v0.10.0, pinned here alone and reported back to the chez-libuv session. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The second review's seven findings left unfixed.

MERGED to main on 2026-10-12, on the owner's "do closing ritual": **The server's v0.6.0, pinned alone** (the entry above), #79.
- **#79**, at 1e6867a, was squashed as e168cd6 (tree 99c078a, the tested head's; parent 1e416af), with `--match-head-commit` on the full SHA. Its message is the commit's.
- **CI did not run.** The PR's run, 38297020379 (1e6867a), and main's on the squash, 38297557590, each ended with `linux` and `autobahn` not started (0 steps, the payments annotation). The entry's local runs stood in: macOS, Autobahn twice, and Linux aarch64 and x86_64 with io_uring allowed. It merged past the red check on the owner's word.
- **Branches.** `chore/pin-server-v0.6.0` was deleted, local and remote. The main checkout is fast-forwarded, and `make submodules` brought its server checkout from 02ef95d to the new gitlink, 47c787d: a fast-forward alone leaves the old pin checked out (`git submodule status` marks it `+`). This reflect is committed from the pin's worktree, detached at e168cd6, which is removed after the push. No PR is open.

**Reflect.**
- **Measure the old pin beside the new, the same hour.** v0.5.0's range for the server's own connection read 1,808 to 1,970 B today and 1,900 to 2,055 B yesterday: a day's drift is as wide as any change the pin could make. Read beside a same-hour baseline, "nothing moved" is a comparison, not a reading against old numbers.
- **A pin's behaviour change reaches the docs only with a check.** The server's write bound on a close is real, but here it shows only past a close timeout set above 60 s. Tracing `close-stream`'s three paths showed where it applies, and no check here holds it, so it went to the CHANGELOG, not `docs/`.
- **Pinning alone keeps the next pin readable.** v0.6.0 moved no suite, no cost and no Autobahn verdict. Whatever moves at the next pin is chez-libuv v0.10.0's.

`make test` green on main (e168cd6, Darwin arm64): fifteen suites, 397 expected passes, each suite's count as before the pin, every pin ok, the server at v0.6.0 (47c787d).

NEXT: the server's release that carries chez-libuv v0.10.0 (chez-http-server#185, f27633d), pinned here alone and reported back to the chez-libuv session. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The second review's seven findings left unfixed.

---

**The second review's rest (2026-10-16),** on the owner's "fix the seven docs-suite findings": the six M6's second review left, its items 7 to 12, which the ledger counted as seven (corrected in place). Branch `fix/docs-suite-review`, cut from main at 6caf10b in its own worktree; one PR.
- **Fixed, all six** (`m6-mutations.md`, its section "The second review's rest"):
  - **A block's lines are read as org reads them.** A directive's words may have any spaces or tabs around and between them, in any case. A tab-indented block, or one written `#+begin_src  scheme`, was skipped, so a block that did not read passed DOC-READ.
  - **DOC-FIELDS holds each field to its own limit.** A name is a field when `websocket-limits-with` takes it and, set to 100,000, changes that field alone. It no longer reads the refusal's `condition-who`. A provenance guard refuses a value that is some field's default.
  - **DOC-NAMES asks `library-exports`** for `(websocket)`'s names, as its title says. `(rnrs)` exports no name its prefixes match, so no answer changes today.
  - **Each page is split once and each block read once**, its data kept in its record.
  - **`(ws-play)`'s `copy` and `concat` are `bv-slice` and `bv-concat`**, its header saying so.
  - **`text-lines` is `(ws-text)`'s**, with the `split` under it, a library of `(rnrs)` alone. The gate, `(ws-autobahn)`, imports it, and so do the docs, Autobahn and `run.sh` suites.
- **Watched to fail:** seven new mutants and a guard's, predicted on main's suite and on the fixed one, hashed before; 0 mismatches. On main, DR-1 to DR-3, DF-1 and DF-2 passed, and DR-4 and DR-5 were red on pages org reads as written. M6-1 to M6-42 again, on main's suite and on the fixed one, the runner rebuilt from this session's record (its mutants' sha256 `ffda1147`, as recorded): 0 mismatches.
- `make test` green before the commit (Darwin arm64): fifteen suites, 397 expected passes, each suite's count main's, every pin ok; `make check-help` passes. Linux aarch64 with io_uring allowed (`chez-libuv-noble-scratch:10.4.1`, dash, libuv 1.48.0): fifteen suites and 397, each suite's count Darwin's.

NEXT: the PR; the closing ritual when the owner asks. The server's release that carries chez-libuv v0.10.0 or v0.11.0, pinned here alone and reported back to the chez-libuv session. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI.

MERGED to main on 2026-10-16, on the owner's "do closing ritual": **The second review's rest** (the entry above), #80.
- **#80**, at 03c2e67, was squashed as 08d295e (tree 7dfbba0, the tested head's; parent 6caf10b), with `--match-head-commit` on the full SHA. Its message is the commit's.
- **CI did not run.** The PR's run, 38885401295 (03c2e67), and main's on the squash, 38916054854, each ended with `linux` and `autobahn` not started (0 steps). The entry's local runs stood in: macOS and Linux aarch64. It merged past the red check on the owner's word.
- **Branches.** `fix/docs-suite-review` was deleted, local and remote. The main checkout is fast-forwarded, its submodules at the gitlinks. This reflect is committed from the fix's worktree, detached at 08d295e, which is removed after the push. No PR is open.

**Reflect.**
- **A reader stricter than its format errs both ways.** The old block reader skipped blocks org reads, the holes the review named, and also went red on pages org reads as written: a tab-indented `#+end_src`, a tab after `#+name:` (DR-4, DR-5). Reading as org does closed both.
- **Count from the review's own report.** The ledger's "seven" came from a summary line; the review's findings, as reported, left six. The report is the record to count from.
- **A runner kept in a scratchpad does not last.** M6's mutation runner was gone from the scratchpad, rebuilt from this session's transcript, and trusted because its mutants hashed to the recorded `ffda1147`. A record of each mutant set's hash is what made the rebuild checkable.

`make test` green on main (08d295e, Darwin arm64): fifteen suites, 397 expected passes, each suite's count as before, every pin ok, the server at v0.6.0 (47c787d).

NEXT: the server's release that carries chez-libuv v0.10.0 or v0.11.0, pinned here alone and reported back to the chez-libuv session. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI.

---

**The server's v0.7.0, pinned (2026-10-16),** on the owner's "pin v0.7.0 in chez-websocket". Branch `chore/pin-server-v0.7.0`, cut from main at 9be5265 in its own worktree; one PR, one commit. Unlike v0.6.0's, it carries one check's rewrite beside the pin, by the server's form of 2026-10-16 ("Land it; fix ws's check at its next pin (Recommended)"): the check leaned on a fake the server has since made faithful, so no fit could pass on both pins and stay true.
- **The pin:** chez-http-server moves from v0.6.0 (47c787d) to v0.7.0 (a9f0ef5, the tag signed, a good signature). The pins it carries: chez-libuv afe79a5 (v0.11.0, from v0.9.0), chez-httparse 0b7058e, byte-machine c338a57, uriparse 5ecd88f and chez-srfi 7879b52.
- **Measured first** (Darwin arm64): main's suites unchanged, the server's checkout at v0.7.0 and `SERVER_PIN` not, run with `make -o check-pins test`. Three runs: fifteen suites, 396 of 397, each run the same one red, the binding's "a send waiting when the connection ends is woken at once, before the client reads"; main's baseline the same hour, on v0.6.0, 397.
- **What reaches here** (the server's CHANGELOG `[0.7.0]`, read against `src/` and `tests/`):
  - **The test fake keeps what a taker's client sends while the taker reads nothing**, its end too, and reads it on the turn after reading starts again (the server's #187). The binding stops reading past the high water, so a client's end then waited, where v0.6.0's fake told it at once. The server's libuv shell does the same: it reads nothing then (probed for #187, three runs).
  - **The test fake bounds a taker's close by the write timeout** (#188), as the server has since v0.6.0. No suite here moved for it.
  - **A waiting taker's thunk may end with no values** (#189). The binding's thunk runs the procedure and closes; no suite here moved.
  - **chez-libuv v0.11.0.** `src/` imports nothing of chez-libuv; the socket suite and the two probes import `(libuv)`, and none calls what v0.10.0 changed (`uv-kill!`, `uv-write*!`'s segment count, `addrinfo-chain->list`).
- **The check, rewritten to what the server does,** as two (`m6-mutations.md`, "At the server's v0.7.0 pin"): a send waiting when the client's end comes is not told it while reading is stopped; it goes on once the client reads down to the low water, the end read after it raising 1006 in the receive that follows (W-END); and, to a client that reads nothing, the write timeout ends it, not a millisecond before (W-END-TIMEOUT). Probed first on v0.7.0's fake, both ways. The end's arrival is now seen by a receive after the second send, which the old check did not have.
  - **Test first:** on the server's v0.6.0 tree both were red by value, the end told at once, as predicted; the suite's other 54 green.
  - **Mutants:** nine rows of the binding, BASE and eight, predictions hashed before the run (`d12650a9`), **0 mismatches**, each red by the value named. K-49, the end that wakes no send, is killed now by W-END-TIMEOUT, the write timeout's own check and C-SENDCLOSING.
  - **The fake's delivery, described again:** the driver suite's and the binding suite's headers, and the design's §8, said `fake-shell-deliver!` hands over an event "whatever the read state". Each now says an event given while the taker has stopped reading waits until it reads again, as the server's does.
- **Watched to fail:** with the gitlink moved and `SERVER_PIN` not, `make check-pins` answered the predicted lines (hashed before the run, cc82df1a): `PIN MISMATCH: vendor/chez-http-server at a9f0ef5…, expected 47c787d…`, the five carried pins ok, chez-libuv now afe79a5, exit 2.
- **Measured again** (Darwin arm64; the research record's section "At the server's v0.7.0 pin"; v0.6.0 beside it the same hour, from a copy of its tree):
  - a connection's cost, by `ws-cost.sps`: an idle WebSocket in a receive 5,332 to 5,344 B on v0.7.0, 5,179 to 5,477 B on v0.6.0. The README's "about 5.3 KB" stands.
  - S-LETGO's floor, by `s-letgo-floor.sps`: a big message, then a small one, reads as two small ones on both. One reading, −13,528 B on v0.7.0, is neither a stack segment's step nor seen again in three more runs of its setting on each pin; it is left out of the ranges, its cause not found.
- **Autobahn** (`make autobahn`, the container path on Docker Desktop, the echo image rebuilt from this tree, its server v0.7.0's): two runs, each `301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`, exit 0.
- **Records:** the Makefile's pin; the README's `make submodules` line; `docs/configuration.org`'s link to the server's configuration page, now at v0.7.0; CHANGELOG.md's Unreleased, v0.6.0's pin entry now v0.7.0's; the design's "What a connection costs" and §8; the research record's new section; `m6-mutations.md`'s new section.
- `make prod` green: fifteen suites and 398 on the prod shim, each suite's count Darwin's, and both check-prod runs a prod build.
- **CI is billing-blocked,** so Linux ran in containers on this tree, io_uring allowed (`--security-opt seccomp=unconfined`):
  - aarch64 (`chez-libuv-noble-scratch:10.4.1`, libuv 1.48.0): fifteen suites, 398, each suite's count Darwin's;
  - x86_64 under emulation (`chez-websocket-ci-amd64:10.4.1`, libuv 1.48.0): fifteen suites, 398, each suite's count Darwin's.

  The pins are checked on the host.
- **For the chez-libuv session:** chez-libuv v0.11.0 reaches here through the server's v0.7.0. Each suite's count, `make prod`, Autobahn, and the cost moved only where this entry says, and no chez-libuv condition was met. The report goes back to that session.
- `make test` green before the commit (Darwin arm64), three runs: fifteen suites, 398 expected passes, every pin ok; `make check-help` passes.

NEXT: the PR; the closing ritual when the owner asks. When CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI.

MERGED to main on 2026-10-16, on the owner's "Do closing ritual": **The server's v0.7.0, pinned** (the entry above), #81.
- **#81**, at df4307f, was squashed as 04a68ba (tree 12b902b, the tested head's; parent 9be5265; the gitlink a9f0ef5), with `--match-head-commit` on the full SHA. Its message is the commit's.
- **CI did not run.** The PR's run, 38940322362 (df4307f), and main's on the squash, 38951792929, each ended with `linux` and `autobahn` not started (0 steps, the payments annotation). The entry's local runs stood in: macOS three times, `make prod`, Autobahn twice, and Linux aarch64 and x86_64 with io_uring allowed. It merged past the red check on the owner's word.
- **Branches.** `chore/pin-server-v0.7.0` was deleted, local and remote. The main checkout is fast-forwarded; `make submodules` brought its server checkout from 47c787d to a9f0ef5, and chez-libuv under it to afe79a5, and `make build` relinked the shim; `make check-pins` reads every pin ok. This reflect is committed from the pin's worktree, detached at 04a68ba, which is removed after the push. No PR is open.
- **The chez-libuv session** (yuzu-libuv-issues-a) was sent the report its v0.10.0 handoff asked for: the counts, `make prod`, Autobahn, the cost, and that no chez-libuv condition was met.

**Reflect.**
- **A fake's fix can break a check that read the fake's slip as the server's rule.** W-END held a client's end waking a send while reading was stopped. The server never does that; only v0.6.0's fake did. A check against a fake holds the fake unless it is probed against the server too. The server's #187 probed its libuv shell first, which is what showed the check was wrong rather than the fake.
- **`fake-shell-settle!` is a client that reads everything.** The first probe of the write-timeout path settled the fake and saw the send go on, not time out. Settling delivers every later turn, each write the client reads. To keep a client that reads nothing, move the clock with `tick!` and deliver later turns only by name.
- **A reading that is not the known step gets its own re-run, not a guess.** S-LETGO's floor showed −13,528 B once, unlike the −55 KB and −61 KB steps of a fresh stack segment. Three more runs per pin did not show it again. It is recorded beside its re-runs, its cause not found, rather than explained.

`make test` green on main (04a68ba, Darwin arm64): fifteen suites, 398 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: when CI is back, main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release pinned here when one comes.

MERGED to main on 2026-10-16, on the owner's "do closing ritual": **Plan and timeline references dropped for public release**, #82. No slice entry came before it: the owner asked in one session for a sweep of the source, README.org and the reference docs, so that comments hold type and developer information alone.
- **What it changed.** Comments, test descriptions, README.org and CHANGELOG.md lost every pointer into `.plans/` and `.superpowers/`: milestones and steps, reviews, decision numbers and their amendments, "by form" answers, design sections, probe labels (R-TERM, R-TWO), research records, `global-constraints`, and dates. Where a pointer carried a rule, a reason or a number, that stays, stated as the current fact. README.org's Status became What it does, without its three `.plans` links. CHANGELOG.md kept its release and measurement dates and versions. RFC citations, type signatures and peer comparisons are unchanged. Outside comments, the only changed lines are test descriptions, docs prose and one Makefile error message.
- **#82**, at e999f48, was squashed as c2012ca (tree 3183d0c, the tested head's; parent 1e3bac3).
- **CI did not run.** The PR's run, 38955879544 (e999f48), and main's on the squash, 38958882255, each ended with `linux` and `autobahn` not started (the payments annotation). `make test` on e999f48 stood in. It merged past the red check on the owner's word ("Merge anyway").
- **Branches.** `docs/public-release-comments` was deleted, local and remote. The main checkout is fast-forwarded to c2012ca. No PR is open.

**Reflect.**
- **A citation in a comment carries a rule and its provenance; a public comment keeps only the rule.** Most "(0006)" and "(M4.3's review)" were provenance alone and dropped clean. The ones that carried history needed rewriting as the current fact: `park!`'s v0.4.0-to-v0.4.1 story, verdicts.txt's v0.4.1 resets, and the socket suite's heap ranges. Some of those numbers now stand without the server version they were measured on.
- **File-scoped sweeps miss a cross-file label; a final union search catches it.** Three agents swept disjoint files in parallel, each with its own pattern. `(global-constraints)` in ws-testing.sls fell outside every pattern and was caught only by the last repo-wide search over the union of patterns.
- **A wide prose change is checked by what changed outside comments.** Listing the diff's changed lines that are not comments showed only test descriptions, docs prose and one Makefile message, so no code moved.

`make test` green on e999f48, whose tree is c2012ca's (Darwin arm64): fifteen suites, 398 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: before going public, the owner decides on what is still private. README.org's Building and `.github/actions/setup/action.yml` both say the pins are private, all but chez-srfi. `.plans/`, `.superpowers/` and AGENTS.md's pointers to them are tracked. When CI is back: main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release is pinned here when one comes.

MERGED to main on 2026-10-16, on the owner's "Run the closing ritual for PR 83, merging past CI if billing still blocks it": **Only chez-http-server is private now**, #83. The owner said many of the pins are now public. `gh api` and unauthenticated requests agreed: chez-libuv, chez-httparse, uriparse and byte-machine are public, and chez-http-server and this repository are private.
- **What it changed.** README.org's Building says chez-http-server is private and the pins it carries are public. The setup action's comments say the same, and its missing-token error now asks for read access to chez-http-server alone. No behaviour changed: `SUBMODULES_READ_TOKEN` is still required, and the rewrite still sends the org's URLs through it, which reads the public pins as any token does.
- **#83**, at 0c03760, was squashed as cb122ea (tree 04ab77a, the tested head's; parent 0876908), with `--match-head-commit` on the full SHA.
- **CI did not run.** The PR's run, 38959618002 (0c03760), and main's on the squash, 38959853562, each ended with `linux` and `autobahn` not started (the payments annotation). `make test` on 0c03760 stood in, and it merged past the red check on the owner's word.
- **Branches.** `docs/public-deps` was deleted, local and remote. The main checkout is fast-forwarded to cb122ea. No PR is open.

**Reflect.**
- **A claim about who can read a repository is checked with and without credentials.** `gh api` reports a repository's visibility, but it runs as the owner, who reads everything. An unauthenticated request returning 404 for chez-http-server and 200 for the rest is what a stranger cloning the project sees.
- **Narrowing what a token is said to need is safe only where nothing is narrowed in fact.** The error message now names one repository, but the URL rewrite still covers the whole org. That holds because any token reads public repositories. Narrowing the rewrite itself to chez-http-server would change how clones are fetched, which CI cannot prove while billing blocks it, so the rewrite stays.

`make test` green on 0c03760, whose tree is cb122ea's (Darwin arm64): fifteen suites, 398 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: before going public, chez-http-server's own visibility, and whether `.plans/`, `.superpowers/` and AGENTS.md's pointers to them ship. When CI is back: main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release is pinned here when one comes.

MERGED to main on 2026-10-16, on the owner's "Run the closing ritual for PR 84, merging past CI if billing still blocks it": **README in chez-http-server's shape; design records out of archives**, #84. The owner asked for README.org to come closer to chez-http-server's format, though not to copy it, with the copyright and license links at the bottom. They also asked that `.plans/` and `.superpowers/` stay in the repository as design artifacts but be left out of releases.
- **What it changed.**
  - README.org is now "Chez WebSocket". It has Features as bold-lead bullets, a Quick start (the `/echo` server, run with `make run`), and Build and test with its prerequisites. Then come short Autobahn, Configuration and Handlers sections pointing into `docs/`, and License: © Kiyomi Computation Systems LLC, linked to kiyomicomputation.systems, and BSD 3-Clause, linked to LICENSE.
  - `.gitattributes` marks `/.plans` and `/.superpowers` `export-ignore`.
- **#84**, at bee5618, was squashed as 6baa7b4 (tree 61c9e2f, the tested head's; parent 40519fb), with `--match-head-commit` on the full SHA.
- **CI did not run.** The PR's run, 38960520431 (bee5618), and main's on the squash, 38960754149, each ended with `linux` and `autobahn` not started (the payments annotation). `make test` on bee5618 stood in, and it merged past the red check on the owner's word.
- **Branches.** `docs/readme-format` was deleted, local and remote. The main checkout is fast-forwarded to 6baa7b4. No PR is open.

**Reflect.**
- **A README's example is run, not read.** The docs suite holds `docs/`, not README.org. So the Quick start's program was extracted from the README itself and run with `make run`, and a raw-socket client got its `101` and its echo. The `websocat` line it suggests was not run, since no websocat is installed here.
- **`export-ignore` is read from the tree being archived.** Before the commit, only `git archive --worktree-attributes` could show the rule working. After the merge, a plain `git archive` of main lists no file under either directory.
- **`git check-attr` on a file inside an ignored directory says `unspecified`.** `git archive` checks the directory itself and skips it whole, which `git check-attr export-ignore .plans` reports as `set`. Check the directory, not a file in it.

`make test` green on bee5618, whose tree is 6baa7b4's (Darwin arm64): fifteen suites, 398 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: before going public, chez-http-server's own visibility. AGENTS.md still ships in archives, and the echo image's Docker context (`.dockerignore`) still takes `.plans/` and `.superpowers/`; neither was asked. When CI is back: main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release is pinned here when one comes.

MERGED to main on 2026-10-16, on the owner's "Yes, run the closing ritual on PR #85": **Examples: an echo, a chat room and a clock**, #85. The owner asked for an `examples/` folder of small, runnable servers, was offered six candidates, and picked three: echo with a page, chat, and a clock that pushes.
- **What it added.**
  - `examples/echo.sps`, `chat.sps` and `clock.sps`, each one program of 49 to 69 lines, run with `make run PROGRAM=examples/<name>.sps`, and each serving a page at `/` that opens its WebSocket from the page's own host. Echo sends each message back. Chat tells a newcomer how many are in the room (`here: 3`) and sends each message to every other client's WebSocket, passing over one that closed before it left the room. Clock sends `tick n` a second apart, reading under `with-deadline` between ticks, and closes with 1000 "stopped" on `stop`.
  - `tests/test-examples.sps`, ten checks: each program read with Chez's reader, `serve` captured, its handler played on the server's fake shell.
  - `examples/README.org`, an Examples section in README.org, `make help`'s `run` line naming `examples/echo.sps`, and a CHANGELOG entry under Unreleased.
- **#85**, at 6ee664b, was squashed as 392a181 (tree c5968f1, the tested head's; parent 805d699), with `--match-head-commit` on the full SHA.
- **CI did not run.** The PR's runs, 38963592637 (d6c0c2c) and 38965080082 (6ee664b), and main's on the squash, 38965960863, each ended with `linux` and `autobahn` not started (0 steps). `make test` on 6ee664b stood in, and each example was run with `make run` and driven from the in-app browser.
- **Branches.** `feat/examples` was deleted, local and remote, and its worktree, `.claude/worktrees/examples`, removed. The main checkout is fast-forwarded to 392a181. #86 (docs as Markdown) is open and still mergeable.

**Reflect.**
- **An example is tried the way its reader tries it.** The first push gave only echo a page. The owner opened clock in a browser and got the 404 meant for other paths. A browser is the client everyone has (websocat was not even installed here), so every example now answers `/` with a page, and one check holds all three to it.
- **What a program does to shared state is checked by making it visible.** A chat room that never shrinks behaves like a correct one until memory runs out. The newcomer's `here: N` made leaving observable, and the check that drops Bob counts two. `fake-shell-hold!` kept Bob's scheduler undrained, so his WebSocket closed before his procedure could leave. That is the only way the per-send guard shows: without it, Alice's procedure dies 1011 and Carol hears nothing.
- **Each check was watched red against a program wrong in its own way.** Thirteen mutations, each turning only the checks it should: a page opening the wrong socket or served off `/`, origins `'any`, another path 200, the sender told its own message, no leave, no per-send guard, the count without the newcomer, a deadline per message, `stop` just returning, and half-second ticks.
- **Two `make run`s started at once in a fresh worktree race on `git submodule update`**, and one fails on the submodule's config lock. Start servers one at a time. A worktree's pins clone in seconds with `--reference` to the main checkout's; `git worktree remove` needs `--force` once submodules are in it.

`make test` green on 6ee664b, whose tree is 392a181's (Darwin arm64): sixteen suites, 408 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: #86 (docs as Markdown). Before going public, chez-http-server's own visibility; AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`. When CI is back: main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release is pinned here when one comes.

MERGED to main on 2026-10-16, on the owner's "Run the closing ritual on PR #86": **The user docs as Markdown**, #86. The task was to rewrite `docs/` as Markdown, ready for a static site, laid out as chez-libuv's and chez-httparse's are, and to keep the docs suite holding it.
- **What it changed.**
  - `docs/` follows chez-libuv's layout: `README.md` is the home page (a taste, four ideas, Read next), then `installing.md`, `handlers.md`, `configuration.md`, `how-it-works.md`, `reference.md`, `testing.md` and `performance.md`. No front matter, a `#` title, `##` sections, `###` reference entries, and `scheme`/`sh`/`text` fences. `handlers.md` and `configuration.md` port the `.org` pages, which are deleted. chez-httparse keeps its home in `site/index.md` instead; this repository has no `site/`, so the home is in `docs/`.
  - A Scheme block is named on its fence, `scheme name=NAME`. chez-cmark-gfm's `markdown->sxml` keeps only the info string's first word (`class="language-scheme"`), and GitHub does too, so the name never renders. The other choice, an HTML comment, renders as `<!-- raw HTML omitted -->`.
  - `tests/test-docs.sps` reads `docs/*.md` as CommonMark with GitHub's tables, and every check it had is ported. New checks: Markdown alone in `docs/`; the home links every page; every relative link in `docs/`, and every `file:` link in README.org, exists; every fence names its language; every `make` target in an `sh` block is one `make help` lists; `reference.md` has exactly one entry per `(websocket)` export, each entry's kind and call form matching what Chez evaluates (arity masks, `[brackets]` optional); and every number on `performance.md` and `testing.md` is one that CHANGELOG.md, README.org or `verdicts.txt` records.
  - After #85 merged, the docs link the examples. `installing.md` runs `examples/echo.sps` and its page, `handlers.md` gained a "More examples" section, and Home's Read next lists `examples/`.
  - README.org and `tests/test-limits.sps` point at the `.md` pages. CHANGELOG has one Unreleased entry; the released 0.1.0 entry still names the `.org` pages, as it should.
- **#86**, at e71e3c8 (main merged in, with #85, cleanly), was squashed as f066010 (tree 009944c, the tested head's; parent 311814d), with `--match-head-commit` on the full SHA.
- **CI did not run.** The PR's runs, 38964377699 (2858e9c) and 38966319131 (e71e3c8), and main's on the squash, 38972262236, each ended with `linux` and `autobahn` not started (0 steps). `make test` on e71e3c8 stood in.
- **Branches.** `docs/markdown` was deleted, local and remote, and its worktree, `.claude/worktrees/docs-markdown`, removed. The main checkout is fast-forwarded to f066010.

**Reflect.**
- **A worktree comes first, before the branch.** This session briefly ran `git switch -c` in the shared checkout, saw that the examples session lived in a worktree of its own, and switched back to main within a minute, before editing anything. Its own worktree then took a `make build` (submodules cloned and the shim built) and nothing else.
- **A docs-to-records check keeps the measured pages from inventing.** Testing's table would have said 288 OK (301 less 7, 3 and 3). That is arithmetic, not a record, so the page says "every case not below" and quotes the two macOS runs CHANGELOG records instead.
- **Each check was watched red against Markdown that was wrong in its own way.** There were 25 mutations, each turning only its own checks red: rows swapped, a default or its unit changed, the delimiter row lost, a name misspelt, a field dropped, a fence left open, a block unreadable, renamed, given another language or unnamed, a reordered subprotocol list, the echo's path, README's echo answering 500, a page unlinked, a link to no file, a misspelt target, an invented number, a reference entry dropped, its arguments wrong, a value called a procedure, an entry for no export, README.org linking nothing, a non-Markdown file, and no program (provenance, status 3). A tilde fence with Scheme in capitals, a fence indented inside a list, and a double-backtick table cell stayed green.
- **Links to work not yet merged are drafted, checked, and held back.** With #85 still open, the example links were drafted and run against #85's four files, copied in and then removed. Without them, the link check named exactly the five new links.

`make test` green on e71e3c8, whose tree is f066010's (Darwin arm64): sixteen suites, 417 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: building the site itself (chez-libuv's `build-site.sps` and `site/`, over chez-cmark-gfm), when the owner wants it; the docs are ready for it. Before going public, chez-http-server's own visibility; AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`. When CI is back: main's latest run, and `probe/r-term`'s run to confirm R-TERM's cause on CI. The next server release is pinned here when one comes.

MERGED to main on 2026-10-23, on the owner's "Run the closing ritual for PR 87, then PR 88, then run the Pages workflow on main to publish the site": **CI without a read token** (#87) and **the docs site, published** (#88). The owner had made this repository public and fixed Actions billing. chez-http-server is public too: an unauthenticated request answers 200.
- **#87** removed the `SUBMODULES_READ_TOKEN` requirement: the setup action's `token` input, the step that required it, and the `insteadOf` rewrite. It also dropped the "private" notes from README.org and docs/installing.md. A fork's pull request, which GitHub gives no secrets, would otherwise have failed at the token check. A fresh clone ran `make submodules` with every git credential source off (no system or global config, no askpass) and got every pin. #87, at d13f441, was squashed as ca36525 (tree 4ce7e81, the tested head's; parent 17de7ff).
- **#88** ported chez-http-server's generator: `build-site.sps`, `site/*.sls`, `tests/site-unit.sps`, `tests/site-render-unit.sps`, `tests/site-check.sps`, `scripts/fetch-akku-lock` and its offline test.
  - `Akku.lock` is `akku lock`'s output for a development-only `Akku.manifest`. It pins chez-cmark-gfm 2.0.0 by sha256 `bb647e07…8305159`, the sum chez-http-server's lock records.
  - New make targets: `site-deps`, `site`, `check-site` and `check-site-deps`. CI's `linux` job runs the two checks, and the setup action installs apt's `cmark-gfm`.
  - `pages.yml` deploys on a `v*` tag or by hand, reading the Chez floor from ci.yml's env as the Makefile does.
  - Pages was switched on with `build_type=workflow` through the API.
  - #88, at 66791d0, was squashed as 9578778 (parent ca36525). Its tree, 786ec29, is the one tested locally: #88's branch merged onto ca36525 before the squash, with `make test` (sixteen suites, 417 expected passes), `make check-site` and `make check-help` green.
- **CI is back.** Main's dispatched run on 17de7ff, 40037321498, was green, the first since the billing failures. #87's PR run 40037730476 and #88's 40038872793 were green, and #88's run included the new Docs site step. Main's push run on 9578778, 40043193594, was green; the one on ca36525 was cancelled by the concurrency group.
- **Published.** The Pages run 40043210848 on 9578778 built and deployed. https://kiyomi-computation-systems.github.io/chez-websocket/ answers 200 with the wordmark, and so do `handlers.html` and `style.css`.
- **Branches.** `ci/no-read-token` and `docs/pages` were deleted, local and remote. The main checkout is fast-forwarded to 9578778. No PR is open.

**Reflect.**
- **A ported test can hold the source project's data, not its code.** site-render-unit's prev/next check builds its fixture from the real nav order. Ported unchanged, it failed for chez-http-server's page names, not for the generator. Pointing every test at this project's names first, and watching the five plus one fail, showed exactly what each library had to change.
- **The second of two dependent PRs is tested merged onto the first.** #88 calls the setup action without a token, which only works after #87. Testing `docs/pages` merged onto the squashed #87 before squashing #88 tested the tree main then got, 786ec29.
- **A value written once stays written once in a new workflow.** pages.yml reads the Chez floor from ci.yml instead of restating `10.4.1`, as the Makefile already does for the echo image.

NEXT: the owner can delete the now-unused `SUBMODULES_READ_TOKEN` secret. The Pages run warned on two things:
- `actions/checkout@v4` and `actions/cache/restore@v4` run on the deprecated Node 20; chez-libuv is on `checkout@v7`.
- The deploy job's `ubuntu-latest` moves to Ubuntu 26.

`probe/r-term`'s run, to confirm R-TERM's cause on CI, can go now that CI runs. AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`. The next `v*` tag republishes the site with links pinned to it.

MERGED to main on 2026-10-23, on the owner's "Yes, run the closing ritual on PR #89: squash merge, catch up main, delete the branch and worktree, reflect, then run the Pages workflow by hand and check its annotations": **the actions on Node 24, and the Pages deploy runner pinned** (#89).
- **Node 24.** Each bump was chosen by reading the tag's `action.yml` through `gh api`. Every old major runs `node20`; every new one runs `node24`.
  - `actions/checkout` v4 → v7, in ci.yml and pages.yml.
  - `actions/cache/restore` and `actions/cache/save` v4 → v6, in the setup action. Only the `uses:` lines changed; v6 keeps the `cache-hit` and `cache-primary-key` outputs the setup action reads.
  - `actions/upload-artifact` v4 → v7, in autobahn's failure step. The Pages run never reached it, but it was on Node 20 and would warn on a failed run.
- **The runner.** Pages' `deploy` job, the one job on `ubuntu-latest`, is on `ubuntu-24.04` like the rest.
- **#89**, at ef5c444 (one commit on 36ae37e), was squashed as 2bb6120.
- **CI.** The PR's run, 40046424762, was green on `linux` and `autobahn` with no annotations. Both jobs hit the Chez cache on the unchanged key `chez-Linux-ubuntu-24.04-X64-10.4.1-threads`. Main's push run on 2bb6120, 40046693229, was green with no annotations. `make test` and `actionlint` were green locally.
- **Pages, by hand.** Run 40046745214 on 2bb6120 built and deployed with no annotations on either job, and the site answers 200.
- **Branches.** `ci/node24` was deleted, local and remote, and its worktree, `.claude/worktrees/ci-node24`, removed. The main checkout is fast-forwarded to 2bb6120. No PR is open.

**Reflect.**
- **Before an empty result counts as a pass, the same check is shown to fail.** The check-runs annotations API returned nothing for the new runs. Read the same way, the old Pages run 40043210848 shows both warnings, the Node 20 one and the Ubuntu 26 one. So an empty list means the warnings are gone, not that the query missed them.
- **The deprecation covers every action on the old runtime, not only the ones the run named.** Pages printed checkout and cache/restore. Reading each `uses:` line across the workflows found cache/save and upload-artifact too, both on Node 20 but not run on a green Pages build.
- **`git worktree remove` refuses a worktree with submodules,** even a clean one. `--force` removed it once `git status` and `submodule foreach` both showed it clean and its one commit was squashed onto main.
- **Pages ran before the reflect, not after,** so this entry records the deployment rather than promising it.

NEXT: the owner can delete the now-unused `SUBMODULES_READ_TOKEN` secret. `probe/r-term`'s run, to confirm R-TERM's cause on CI, can go now that CI runs. AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`. The next `v*` tag republishes the site with links pinned to it.

MERGED to main on 2026-10-24, on the owner's "do closing ritual": **a security policy** (#90) and **the v0.2.0 release** (#91). The owner had asked to "protect main, turn on private vulnerability reporting with a SECURITY.md, tidy probe/r-term and the wiki, then prepare v0.2.0 in a PR".
- **Settings, on the owner's word, 2026-10-23.** Branch protection on main: pull requests required with no approvals, the `linux` and `autobahn` checks required (not strict), and no force pushes or deletion. Admins are not enforced, so reflects like this one still go straight to main, as a bypass. Private vulnerability reporting is on, and the wiki is off. Neither sibling repository protects its main.
- **#90** adds SECURITY.md after chez-libuv's. It covers the latest release only, takes reports through Security → Report a vulnerability, names what a client's bytes reach, and sends problems outside the upgrade to chez-http-server. #90, at 072fa26, was squashed as 5207eca (parent 1ca526e). Its run 40048794378 was green, and so was main's on 5207eca, 40091242369.
- **#91** moves Unreleased to `[0.2.0] - 2026-10-24`, which was dated 2026-10-23 until the day it merged. It also bumps Akku.manifest to 0.2.0, with the owner's synopsis "WebSocket (RFC 6455) support for chez-http-server R6RS". `akku lock` for the edited manifest writes the committed Akku.lock unchanged. `git diff v0.1.0 -- src/` changes no line outside a comment, so the release notes say the code is unchanged but for its comments. #91, at 21c903a, was squashed as 7639940 (parent 5207eca). Its head's run, 40091279192, was green, the first merge to wait on the new required checks. main's tree is #91's head plus SECURITY.md alone.
- **R-TERM's cause, confirmed on CI.** The probe's three steps ran on today's main as a throwaway branch, `probe/r-term-ci`, run 40048850479.
  - On the runner, `io_uring_disabled` is 0. The echo server has a `scheme` thread and an `iou-sqp-…` thread, and after SIGTERM `scheme` is `Z` while `iou-sqp` is still `R`, then the process exits 0. That is the zombie run.sh waits out.
  - The probe's term scenario had drifted: today's fake docker stops the server and needs `FAKE_LINGERS` and the fake ps to resume it, and the probe sets neither. Every try waited run.sh's 30 s, and the job was cancelled at its 25 minutes. The real suite sets both, and passes in every CI run.
  - `probe/r-term` and `probe/r-term-ci` are deleted, local and remote.
- **Branches.** `docs/security-policy` and `release/v0.2.0` were deleted, local and remote. The main checkout is fast-forwarded to 7639940. No PR is open.

**Reflect.**
- **Required checks turn a last-minute edit into a wait.** #91's date change made a new head, and the merge waited on its CI before it could land. A release PR's date is best set when its merge is ready, or left to the merge itself.
- **A stale probe answers the question it was built for, and little else.** Its first step, which reads only the kernel and the server, held up. Its second step called fakes that had changed since, so its failure said nothing about the library.
- **A file someone else edited is asked about, not committed.** An Akku.manifest change appeared on the release branch's checkout. It went into #91 only on the owner's word, and only after `akku lock` showed the lock unchanged.

`make test` green on 21c903a (Darwin arm64): sixteen suites, 417 expected passes, every pin ok, the server at v0.7.0 (a9f0ef5).

NEXT: tag 7639940 `v0.2.0` and push it, on the owner's word, which republishes the docs site with links pinned to v0.2.0. Then Akku, once chez-http-server is in its index. AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`.

RELEASED v0.2.0 on 2026-10-24, on the owner's "Tag 7639940 as v0.2.0, push the tag, and check the Pages run republishes the site".
- **The tag.** `v0.2.0` is an annotated tag on 7639940, signed as v0.1.0 is (`tag.gpgSign`; `git tag -v` reports a good signature). Its message follows v0.1.0's.
- **The first deploy was refused.** The tag's Pages run, 40092141094, built, but its deploy failed: "Tag "v0.2.0" is not allowed to deploy to github-pages due to environment protection rules." Switching Pages on had created the `github-pages` environment allowing the `main` branch alone. chez-libuv's allows `main` and the tag pattern `v*`, and the same `tag v*` policy was added here. The re-run of the failed job (attempt 2) deployed.
- **Published.** The site's links out to the repository (`docs`, `examples`, `tests/autobahn/echo.sps`, `tests/autobahn/verdicts.txt`) now name `blob/v0.2.0/`, and each answers 200 on GitHub.

**Reflect.**
- **Switching Pages on makes an environment that only the default branch may deploy.** A workflow that deploys on tags needs a tag policy too. The manual run from `main` had worked, so nothing failed until the first release.

NEXT: Akku, once chez-http-server is in its index. AGENTS.md still ships in archives, and the echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-24, on the owner's "Run the closing ritual for PR 92 once its CI is green": **AGENTS.md out of release archives and Akku's scan**, #92. The owner asked to use .gitattributes and/or the Akku files to keep AGENTS.md and the plan files out of archives.
- **What it changed.** `.gitattributes` marks `/AGENTS.md` `export-ignore` beside `/.plans` and `/.superpowers`, and `.akkuignore` names `AGENTS.md`. Akku's repository scanner (akku/lib/repo-scanner.scm) skips every dot-named entry and every name `.akkuignore` lists, files and directories alike, with no wildcards. So `.plans` and `.superpowers` were never in its scan.
- **#92**, at 0f66a6e, was squashed as f2cb39a (tree 5934a56, the tested head's; parent e090370). Its run 40092831977 was green. A plain `git archive` of main now lists no file under `AGENTS.md`, `.plans/` or `.superpowers/`.
- **Branches.** `chore/archive-dev-files` was deleted, local and remote. The main checkout is fast-forwarded to f2cb39a. No PR is open.

**Reflect.**
- **An archive's attributes come from the tree it is made from.** v0.2.0's tarball keeps AGENTS.md, and only a release from f2cb39a on leaves it out. Rules like these belong in place before the first public tag.

NEXT: Akku, once chez-http-server is in its index. The echo image's Docker context still takes `.plans/` and `.superpowers/`; it is a build context, not a release archive.

MERGED to main on 2026-10-24, on the owner's "Run the closing ritual for PR 93": **contributor docs**, #93. The owner had asked to "add CONTRIBUTING.md, a PR template and bug/feature issue templates adapted from chez-http-server's, then open a docs: PR".
- **What it added.** CONTRIBUTING.md follows chez-http-server's sections. Its checks are this repository's: `make test`, `check-pins`, `check-help`, `check-site-deps` and `check-site`, and `autobahn`. Its "When you change…" list covers a verdict that moves, the server pin (the submodule and `SERVER_PIN` together), Akku.manifest with Akku.lock, the Makefile, `docs/` and `examples/`. Its code rules name the pure libraries under `src/websocket/`, the binding and the facade. `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/` (bug report, feature request) follow it, and README.org gains Contributing and Security sections, as the server's has.
- **Left out.** The server's NOTICE check, its Akku pin rule and its Guix and Docker dev environments have no counterpart here.
- **#93**, at a17e919, was squashed as 771c4ef (tree b999ad7, the tested head's; parent baa3a91). Its run 40095029812 was green.
- **Branches.** `docs/contributing` was deleted, local and remote. The main checkout is fast-forwarded to 771c4ef. No PR is open.

**Reflect.**
- **An adapted rule is traced to the code before it is written.** Each of CONTRIBUTING.md's claims was read from the suite or target behind it. `tests/test-docs.sps` refuses a Scheme block it does not know, `tests/test-examples.sps` plays a fixed list, and `make test` runs `check-pins` first. A copied line would have promised a check this repository lacks.
- **Nothing holds CONTRIBUTING.md to the checkout.** Every `make` target and path it and the templates name was checked by hand, once. `tests/test-docs.sps` holds only `docs/*.md` to the Makefile's targets and the files a link names, so a renamed target leaves CONTRIBUTING.md stale with every suite green.

`make test` green on a17e919 (Darwin arm64), and `make check-help` and `make check-site` too.

NEXT: hold CONTRIBUTING.md and the templates to the Makefile's targets and the checkout's paths, as the docs suite holds docs/. Akku, once chez-http-server is in its index. The echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-24, on the owner's "all green do the roitual": **the contributor files held to the checkout**, #94. The owner had asked to "hold CONTRIBUTING.md and the GitHub templates to the Makefile's targets and the checkout's paths, as test-docs holds docs/, test first, in a test: PR".
- **What it changed.** `tests/test-docs.sps` reads CONTRIBUTING.md, the pull request template and each issue template (found by `directory-list`, so a new one is covered). Every make target they run, in a sh block or a `code` span, must be one the Makefile documents. Every file they name must be in the checkout: by a link, by a `code` span written as a path, or by a word of their prose that is a file's name. A provenance guard fails the suite (status 3) when the scan finds nothing. CONTRIBUTING.md's line on the docs suite says so.
- **Watched failing.** Six defects were planted at once: a target in a `code` span and one in the sh block, a link, a template's path, and a prose file name in each issue template. Both new tests listed all six. Stubbing `named-files`, then `run-targets`, to read nothing tripped the guard each time.
- **#94**, at f5881fc, was squashed as a7d57f4 (tree a46abe2, the tested head's; parent 44e53b5). Its run 40097102362 was green. The docs suite has 19 passes, up from 17.
- **Branches.** `test/contributing` was deleted, local and remote. The main checkout is fast-forwarded to a7d57f4. No PR is open.

**Reflect.**
- **The planted defects tested the checker too.** The first red run also listed `.sls`, a bare extension in "R6RS `.sls` files", as a missing file. A scan run only on good input would have shown no such misreading. A file name now needs a name before its extension.
- **Reading a path out of prose is a matter of what it refuses.** A path here is path characters alone, with a `/` or a file's extension. That refuses blanks, URLs, `<placeholder>`s and `fix:`. Prose words count only when they are a file's name, so "and/or" can't trip it.

`make test` green on f5881fc (Darwin arm64), with `make check-help` and `make check-site`.

NEXT: Akku, once chez-http-server is in its index. CONTRIBUTING.md links AGENTS.md, which archives leave out, so a release tarball's copy has that one dead link (chez-http-server's has the same). The echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-26, on the owner's "Yes: once PR 95's CI is green, run its closing ritual, then put the v0.9.0 pin on main from the stash and open its PR": **S-LETGO's heap read with nothing marked in place**, #95. Found while pinning the server's v0.9.0, on the owner's "Investigate first: find what the server holds briefly across the let-go check's readings on v0.9.0, then propose the fix before opening the PR", and landed on its own, by the owner's "fix first".
- **What went red.** With the server at v0.9.0, the socket suite's S-LETGO was red in 4 of 6 runs, and in 0 of 6 on v0.7.0 the same hour. Its three differences had one about 9 KB, a neighbour about −3.3 KB, and one at the 2.9 KB floor.
- **What it was.** Nothing kept: a copy of the suite reading Chez's object counts at each reading found live objects moving by the stack's floor alone and live bytevectors not at all. `bytes-allocated` less every live object's bytes moved 5.8 to 6.9 KB, one way and then back, every third reading, in 7 of 9 runs on v0.9.0, and 200 B at most on v0.7.0. Bisected over the server's history (`git bisect run`, four probe runs a step), the first commit with it is d73b437, the server's #236, which keeps the handler's coroutine on the request's notice and the connection on the notice. With `in-place-minimum-generation` above the oldest generation it moved 32 B at most in 5 of 5: dead objects in segments the collector marks in place.
- **The fix.** `footprint` collects with `in-place-minimum-generation` one above `(collect-maximum-generation)`; the suite's header says why, and decision 0007 has its amendment of 2026-10-26, the alternatives weighed in it. Green 10 of 10 on v0.9.0 and 8 of 8 on v0.7.0; R-20's kind (the binding keeping each read's bytevector until the next read) red on both, 18,816 to 18,992 B.
- **#95**, at 0aee4a5, was squashed as 26f3cb2 (tree 9d0a5b5, the tested head's; parent 91d58fc). Its run 40329080186 was green; its autobahn job took 8 m 3 s, where it has taken about 50 s.
- **Branches.** `test/let-go-in-place` was deleted, local and remote. The main checkout is fast-forwarded to 26f3cb2. No PR is open. The pin's change waits in `stash@{0}`, made on `chore/pin-server-v0.9.0`.

**Reflect.**
- **A heap total counts what the collector has not freed, not only what lives.** When a heap check moves with nothing kept behind it, split the heap by Chez's object counts first. The bytes no object owned named the kind of thing in one run, where the readings alone had looked like a kept read.
- **`git bisect run` leaves GIT_DIR set for its script.** A step that runs git in the superproject must unset git's local variables (`git rev-parse --local-env-vars`), or every step skips. The first bisect ran to its end that way and found nothing.
- **A server change that keeps nothing more can still move a heap reading.** The notice's new references grow nothing, and the swing came from where objects lie, not how many.

NEXT: the v0.9.0 pin's PR, from the stash: `SERVER_PIN`, the gitlink, `docs/installing.md` and `docs/configuration.md` at v0.9.0, CHANGELOG.md's Unreleased, and `docs/performance.md` and README.org at about 5.6 KB, measured on v0.9.0. Akku, once chez-http-server is in its index.

MERGED to main on 2026-10-26, on the owner's "do ritual": **the server's v0.9.0, pinned**, #96. The owner had asked to "bump the chez-http-server pin to it in a PR, with SERVER_PIN, the docs that name the tag, and a CHANGELOG entry".
- **The pin.** chez-http-server moves from v0.7.0 (a9f0ef5) to v0.9.0 (d928e41, the tag signed, a good signature). The pins it carries: chez-libuv afe79a5 (v0.11.0, as before), chez-httparse 52a62e5 (v0.5.0) with byte-machine c1f7791 (v0.8.0), uriparse 9416299 (v0.8.0) and chez-srfi 7879b52. The tag adds only its release commit to 9195305, which every suite and Autobahn had passed beforehand (`301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`).
- **Watched to fail:** with the gitlink moved and `SERVER_PIN` not, `make check-pins` named the server's mismatch, the five carried pins ok, exit 2.
- **Records:** the Makefile's pin; `docs/installing.md` at v0.9.0; `docs/configuration.md`'s link to the server's configuration page, now `docs/configuration.md` at v0.9.0 (the server's docs became Markdown in 0.8.0); CHANGELOG.md's Unreleased, the pin and the sixteen names `(http-server)` gains, which nothing here defines.
- **Measured again** (`ws-cost.sps`, Darwin arm64, v0.7.0 beside it the same hour): an idle WebSocket 5,463 to 5,680 B on v0.9.0, 5,314 to 5,429 B on v0.7.0; the server's own connection 2,079 to 2,246 B, 1,808 to 1,977 B. So about 5.6 KB, from 5.3 KB, the server's connection about 270 B bigger; `docs/performance.md` and README.org say so.
- **S-LETGO** went red on v0.9.0 until #95 (the entry above) read its heap with nothing marked in place. On this branch, over #95: `make test` 3 of 3, the socket suite 5 of 5 more.
- **#96**, at aa1c56d (two commits: the pin with its pages, then the records), was squashed as a0c57c0 (tree 5c76f56, the tested head's; parent 59d7171). Its run 40330916184 was green: autobahn 59 s, linux 6 m 22 s, where it has taken about a minute.
- **Branches.** `chore/pin-server-v0.9.0` was deleted, local and remote; the stash is empty. The main checkout is fast-forwarded to a0c57c0, the server at v0.9.0, every pin ok. No PR is open.

**Reflect.**
- **A pin measured first must be measured more than once.** The suites against the server's main passed in one run, and the let-go check then failed 4 of 6 on the branch. A suite with heap checks is run several times before a pin is called clean.
- **A line that names "the pin today" binds the bump to a measurement.** `docs/performance.md`'s did, and measuring found 270 B a connection that the server's CHANGELOG does not count as a cost.
- **"Tagged" is checked on the remote first.** The first request to pin v0.9.0 came while its release PR was still open, and no tag was there to pin.

NEXT: Akku, once chez-http-server is in its index (its 0.8.0 was submitted). Linux CI's 6 m 22 s, if it stays. CONTRIBUTING.md's AGENTS.md link is dead in a release archive; the echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-28, on the owner's "do ritual on 97": **`websocket-handshake`, the handshake for a host of its own**, #97. The owner had asked, from circuit, "lets do the websocket handshake": items 1 and 2 of circuit's slice 6 design, §6 "The change in chez-websocket", which the owner approved on 2026-10-27 (decision 0009).
- **The interface.** `websocket-handshake`, in the binding and through the facade, takes the method as a symbol, a reader of every line of a field, the request's host and the procedure, with optional settings and limits. It answers `handshake-accepted` (the 101's fields as string pairs, and the take-over, `Transport Bytevector -> Answer`) or `handshake-refused` (a status and its fields), read by six accessors. Its argument checks name it, before the reader is called. `websocket-accept` is built on it, its contract unchanged, and turns the fields into bytes itself, once a connection. `handshake-answer` answers string pairs, and `header` copies its strings.
- **The build** (Opus 5.5; 357,838 tokens, 34.7 minutes): the code, 11 binding rows (HB-*), the reference's seven entries and the handlers page's "Taking a WebSocket from another host". The brief said the door suite stays unchanged, which `websocket-accept`'s new conversion made impossible; on the session's word it now holds `websocket-accept`'s own answers on the fake shell, where it held `handshake-answer`'s. Its mutants, predictions hashed first (`6d72b377`): 5 mismatches, each a prediction's; H-26 survived, equivalent.
- **A read-only Opus review** (Opus 5.5; 161,158 tokens, 12.6 minutes) found, each fixed by the session:
  - the host argument untested: RV-12 (the `Host` field read instead), and the session's SV-1 and SV-2, survived every suite. Now HB-HOST, a host given apart from `Host`, and HB-HOST-ABS, an absolute-form target over the wire;
  - no row held that each answer's bytes are its own: RV-11 and SV-3 survived. Now D-OWN-BYTES spoils one 101's bytes and one refusal's;
  - a host that wraps the take-over and drops its answer writes the 101 and never runs the procedure (its probe). The reference and the handlers page say to answer what it answers;
  - two comments over-claimed: that every argument check of `websocket-accept` names it, and a handshake "for any host".
  The review's other ten mutants, and the session's SV-4 to SV-9, were killed by the build's suites.
- **Measured** (`ws-cost.sps`, Linux x86-64, main beside it): an idle WebSocket 5,513 to 5,679 B, 5,513 to 5,680 B on main; after 10 echoes 5,490 to 5,668 B, 5,465 to 5,635 B. Unchanged.
- **Where it ran:** Linux x86-64, Chez 10.4.1 threaded, in circuit's pinned Guix container with procps (`test-autobahn-run` needs `ps`). `make test` passed 16 suites, 433 rows (main 419), on the final tree and again before the commit; `make check-help`; `make check-pins` on the host. `check-site` (no cmark-gfm there) and Autobahn were left to CI.
- **#97**, at efdf0c3 (two commits: 6f86dfc, the code, tests and docs; efdf0c3, the records), was squashed as 4e39d7e (tree b427417, the tested head's; parent e4687af). Its run 40661773107 was green: autobahn 54 s (`301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`), linux 51 s, with `check-site` and 433 rows.
- **Branches.** `feat/host-neutral-handshake` was deleted, local and remote. The main checkout is fast-forwarded to 4e39d7e. No PR is open.
- **Traps:**
  - Chez 10.4.1 lets a program write over a library's string literal: `string-fill!` on a literal a library answered printed `xxxxxxx`. `header` copies.
  - `--libdirs` skips a missing directory silently. The review's mutant folders are source roots, with no `src/` inside, and a run naming `…/src` tested the real code.

**Reflect.**
- **An argument a field could stand in for is tested with a value apart from the field.** The builder's rows gave the host as `Host` gave it, so a handshake that read the field passed. The brief named the argument, not that test; circuit's 6c brief names it for `req-host`.
- **A conversion that moves takes its test of sharing with it.** Each answer's bytes were its own while `handshake-answer` made them; once `websocket-accept` made them, nothing held it until D-OWN-BYTES.
- **A contract a host can break silently is written where the host reads.** A dropped take-over answer hangs, with no error. Circuit's `TakeOver` type reads `-> Any` (its `src/circuit/response.sls:52`), and 6c makes it `-> Answer`.
- **A count is read from the whole output.** A rerun kept through `tail -25` lost the suite totals; CI's log gave them back.

NEXT: v0.3.0, a release PR (`release/v0.3.0`: Unreleased to `[0.3.0] - date`, and Akku.manifest), then the signed tag, on the owner's word; circuit's 6c pins it. Akku, once chez-http-server is in its index. CONTRIBUTING.md's AGENTS.md link is dead in a release archive; the echo image's Docker context still takes `.plans/` and `.superpowers/`. Linux CI took 51 s, so the 6 m 22 s didn't stay.

MERGED to main on 2026-10-28, on the owner's "do closing ritual on green": **the v0.3.0 release**, #98. The owner had asked "lets do the 0.3.0 release", then "update the changelog with 92 - 95".
- **#98** moves Unreleased to `[0.3.0] - 2026-10-28`, with a one-line summary and the compare links (`v0.2.0...v0.3.0`, and Unreleased from `v0.3.0`), and bumps Akku.manifest to 0.3.0. Akku.lock names no version of this package. Its second commit, on the owner's word, adds what #92 to #95 had left out of the CHANGELOG: under Added, the contributor docs (#93), held to the checkout (#94); under Changed, archives without AGENTS.md (#92); under Fixed, the let-go check on v0.9.0 (#95). Since v0.2.0 only #97 changes `src/`.
- **#98**, at 0f9783f (two commits: 89f9f89, the release; 0f9783f, the entries), was squashed as 577127d (tree 5b3a78d, the tested head's; parent 127a01c), merged on the day it is dated. Its run 40665464331 was green: autobahn 1 m 1 s (`301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`), linux 52 s, with `check-site` and 16 suites, 433 rows. Locally (Linux x86-64, circuit's Guix container) `make test` passed 433 rows on each commit, with `check-help`, and `check-pins` on the host.
- **Branches.** `release/v0.3.0` was deleted, local and remote. The main checkout is fast-forwarded to 577127d. No PR is open, and the remote has no `v0.3.0` tag.

**Reflect.**
- **A release's notes are read against every PR since the last tag.** #92 to #95 merged with no CHANGELOG entry, and the first draft of 0.3.0's notes followed the Unreleased section alone. `git log v0.2.0..main --first-parent` names each one.
- **A check watched straight after a push may not exist yet.** `gh pr checks --watch` exited 0 with both checks pending. Watching the head commit's own run (`gh run list --commit`) waits for it.

NEXT: tag 577127d `v0.3.0` and push it, on the owner's word, which republishes the docs site with links pinned to v0.3.0; then circuit's 6c pins it. Akku, once chez-http-server is in its index. CONTRIBUTING.md's links to AGENTS.md and `.plans/decisions/` are dead in a release archive, v0.3.0's among them; the echo image's Docker context still takes `.plans/` and `.superpowers/`.

RELEASED v0.3.0 on 2026-10-28, on the owner's "do it": push the ledger, then tag 577127d `v0.3.0`, push the tag, and check that the Pages run republishes the site.
- **The tag.** `v0.3.0` is an annotated tag on 577127d, signed with the Kiyomi releases key (`git tag -s`; `git tag -v` reports a good signature). Its message follows v0.2.0's.
- **Published.** The tag's Pages run, 40666101036, built and deployed on its first attempt, in 51 s. The site's eight pages link out to the repository seven times, each naming `blob/v0.3.0/`, and each answers 200 on GitHub. The reference and handlers pages carry `websocket-handshake`, and the handlers page has "Taking a WebSocket from another host". main's run on ad0d125, 40666058823, was green.

**Reflect.**
- **A deploy rule set at one release holds for the next.** v0.2.0's first deploy was refused until `github-pages` allowed `v*` tags; v0.3.0's deployed at once.

NEXT: circuit's 6c pins chez-websocket at v0.3.0. Akku, once chez-http-server is in its index. CONTRIBUTING.md's links to AGENTS.md and `.plans/decisions/` are dead in a release archive, v0.3.0's among them; the echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-28, on the owner's "Run the release chain": **`websocket-limits-from-environment` in the facade**, #99. Circuit's 6c found that an app there reads its settings from the ENV it gives `run-server`, which `environment-websocket-limits` never sees: that is read through `getenv` as the program starts. Asked from circuit, the owner chose "Release chez-websocket first", and that the app builds its limits from its own ENV and passes them in.
- **The change.** The facade exports `websocket-limits-from-environment : (String -> (U String #f)) -> WebsocketLimits`, which `(websocket limits)` defined already and `environment-websocket-limits` is made from, with `getenv`. `docs/reference.md` has its entry, and `docs/configuration.md` says a host with a lookup of its own passes it. CHANGELOG.md's Unreleased and the design's facade bullet name it.
- **The row.** One binding row, through the facade: a lookup's 4096 B and 4 s over the defaults, the queue's 16 kept, where the suite's own environment (checked empty) would give 1 MiB and 20 s; and a malformed value refused, naming the procedure and the variable, with a no-raise sentinel.
- **Watched to fail:** with the reference entry written and the export missing, the docs suite failed its two export rows, and the binding suite stopped at the unbound name.
- **Where it ran:** Linux x86-64, circuit's pinned Guix container with procps. `make test` passed 16 suites, 434 rows (main 433), with `check-help`, and `check-pins` on the host.
- **#99**, at ea3cbc2 (two commits: 567f58f, the export, docs and row; ea3cbc2, the records), was squashed as 07e0388 (tree b34be2b, the tested head's; parent 4a17082). Its run 40683925069 was green: autobahn 1 m 35 s (`301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`), linux 1 m 12 s, with `check-site` and 434 rows.
- **Branches.** `feat/limits-from-environment` was deleted, local and remote. The main checkout is fast-forwarded to 07e0388. No PR is open.

**Reflect.**
- **A value read at load answers the process, not a host.** `environment-websocket-limits` was the only way to the variables, and a host whose settings come through a procedure of its own had none until the procedure behind it was exported.
- **A host's first use is the facade's review.** Circuit's 6c was the first host apart from the server's handlers, and the gap showed only there.

NEXT: v0.4.0, a release PR (`release/v0.4.0`: Unreleased to `[0.4.0] - 2026-10-28`, and Akku.manifest), then the signed tag; circuit's 6c pins it. Akku, once chez-http-server is in its index. CONTRIBUTING.md's links to AGENTS.md and `.plans/decisions/` are dead in a release archive; the echo image's Docker context still takes `.plans/` and `.superpowers/`.

MERGED to main on 2026-10-28, on the owner's "Run the release chain": **the v0.4.0 release**, #100. The chain, asked from circuit's 6c: #99's ritual, this release PR and its ritual once green, then the signed tag, its push and the Pages check. The owner had chosen "v0.4.0" for it.
- **#100** moves Unreleased to `[0.4.0] - 2026-10-28`, with a one-line summary and the compare links (`v0.3.0...v0.4.0`, and Unreleased from `v0.4.0`), and bumps Akku.manifest to 0.4.0. Akku.lock names no version of this package. `git log v0.3.0..main --first-parent` names #99 and two ledger commits, so #99's entry is the release's whole. The minor version moves by semver's rule that new functionality bumps it, as 0.2.0 to 0.3.0 did: the reason the owner chose v0.4.0 on (corrected in place on 2026-10-29; this said a new facade export can clash with a program's own name, which was not the reason given). The server gitlink stays d928e41 (v0.9.0).
- **#100**, at 57d2bd1 (one commit), was squashed as 4456814 (tree 632f47c, the tested head's; parent fba6519), merged on the day it is dated. Its run 40696497257 was green: autobahn 56 s (`301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL`), linux 53 s, with `check-site` and 16 suites, 434 rows. Locally (Linux x86-64, circuit's Guix container) `make test` passed 434 rows, with `check-help`, and `check-pins` on the host.
- **Branches.** `release/v0.4.0` was deleted, local and remote. The main checkout is fast-forwarded to 4456814. No PR is open, and the remote has no `v0.4.0` tag.

**Reflect.**
- **A release asked in one word runs as the steps it was asked as.** "Run the release chain" answered a question that named four steps, and each ran in order, its check read before the next began.

NEXT: tag 4456814 `v0.4.0` and push it, which republishes the docs site with links pinned to v0.4.0; then circuit's 6c pins it. Akku, once chez-http-server is in its index. CONTRIBUTING.md's links to AGENTS.md and `.plans/decisions/` are dead in a release archive; the echo image's Docker context still takes `.plans/` and `.superpowers/`.

RELEASED v0.4.0 on 2026-10-28, on the owner's "Run the release chain": tag 4456814 `v0.4.0`, push the tag, and check that the Pages run republishes the site.
- **The tag.** `v0.4.0` (object accbffc) is an annotated tag on 4456814, signed with the Kiyomi releases key (`git tag -s`; `git tag -v` reports a good signature). Its message follows v0.3.0's.
- **Published.** The tag's Pages run, 40696817602, built and deployed on its first attempt, in 42 s. The site's eight pages link out to the repository nine times, at seven addresses, each naming `blob/v0.4.0/`. Five answer 200; the two that name a folder, `docs` and `examples`, answer 301 to `tree/v0.4.0/`, which answers 200. The reference page has `websocket-limits-from-environment`'s entry, and the configuration page names it. main's run on f330bbc, 40696783731, was green; the one on 4456814 was cancelled by it, as the workflow's concurrency does.

**Reflect.**
- **Only Akku.manifest names the version.** `git grep 0.3.0` outside CHANGELOG.md and the records found it alone, so a release PR is those two files.
- **A folder's `blob/` link answers 301.** It reaches `tree/` and 200; a check of the site's links follows redirects, or counts a 301 as a failure that isn't one.

NEXT: circuit's 6c pins chez-websocket at v0.4.0. Akku, once chez-http-server is in its index. CONTRIBUTING.md's links to AGENTS.md and `.plans/decisions/` are dead in a release archive, v0.4.0's among them; the echo image's Docker context still takes `.plans/` and `.superpowers/`.
