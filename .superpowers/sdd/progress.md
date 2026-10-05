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
