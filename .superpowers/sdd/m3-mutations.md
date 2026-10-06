# M3 — mutation log

Every check in M3 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M3.1, step 1 — the limits

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The library is `src/websocket/limits.sls` (blob 774b9d1), and the
suite `tests/test-limits.sps`, 14 checks (blob 5be87cb). M3.1 was built whole,
then cut in two steps by form. This one was proved in a scratch worktree of main
with its files laid in. A runner applied each mutant alone, compared the checks
that went red with the set named before the run, and left the tree as it was:
- a library mutant to a copy of the library, put first on the library path;
- the audit's mutant to a scratch copy of the tree.

Before each run, a pre-flight checked that every cut matched its text once.

### The oracles

- **The design's §7 table**: each variable, its default and its unit.
- **Decision 0001**: the 1 MiB cap, and the ping clock's 20 s and 20 s. **Its
  amendment of 2026-10-05**, by form: 16 messages queued, `CHEZ_WS_MAX_QUEUE`.
- **The server's conventions**, from its `(http-server limits)`: durations given
  in whole seconds and kept in ms, sizes in bytes, absent or empty the default,
  and a low water above the high water refused.
- **The bounds**, each field's least sensible value: a cap and a queue of 1,
  since reading stops once the queue holds a cap's worth; a pong timeout of 1 s,
  since one of 0 would pass as its ping went; 0 for the rest, an interval of 0
  turning pinging off (0001).

### The test-first runs

- **Before the library:** `Exception: library (websocket limits) not found`,
  exit 255.
- **A stub whose fields are all 0, and which reads and checks nothing:** 13 red,
  and 1 green, "make-websocket-limits makes what its arguments say", which L-32
  kills by value.
- **The first library run** passed all 14.

### The mutants

| key | check |
|---|---|
| L-DEF | the defaults: a 1 MiB cap, 16 messages queued, a ping after 20 s and its pong within 20 s, 10 s for a close, and the water marks at 256 KiB and 64 KiB |
| L-VARS | the variables, in the fields' order |
| L-EMPTY | an empty environment, and every variable empty, give the defaults |
| L-EACH | each variable moves its own field alone: sizes and counts in their unit, durations in whole seconds kept in ms |
| L-ALL | every variable at once |
| L-EDGE | each bound at its edge is accepted: a cap and a queue of 1, pinging off, a pong timeout of 1 s, a close timeout of 0, and both water marks at 0 |
| L-BELOW | below its bound, each is refused, naming its variable: a cap of 0, a queue of 0, a pong timeout of 0 |
| L-WATER | a low water above the high water is refused, whichever was set, naming the low water's variable; equal marks are accepted |
| L-MAL | a value not in ASCII digits alone is refused, naming its variable, for every variable |
| L-ZERO | leading zeros are digits too: 007 seconds is 7000 ms |
| L-MAKE | make-websocket-limits makes what its arguments say |
| L-MAKE-REF | make-websocket-limits refuses a field below its bound, or not an exact whole number, 16.0 among them, naming the field |
| L-WITH | websocket-limits-with replaces each field alone, by name |
| L-WITH-REF | websocket-limits-with refuses a name that is not a field, and a value make-websocket-limits refuses |

| # | mutation | red |
|---|----------|-----|
| B-0 | unmutated | none: step 1's tree unmutated, 14 passes |
| L-1 | the default cap one byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-2 | the default queue 17 messages | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-3 | the default ping interval 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-WITH |
| L-4 | the default pong timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-5 | the default close timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-6 | the default high water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-ZERO, L-WITH |
| L-7 | the default low water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-8 | CHEZ_WS_MAX_QUEUE misspelled | L-VARS, L-EACH, L-ALL, L-EDGE, L-BELOW, L-MAL |
| L-9 | a cap of 0 allowed | L-BELOW, L-MAKE-REF |
| L-10 | a queue of 0 allowed | L-BELOW, L-MAKE-REF, L-WITH-REF |
| L-11 | a pong timeout of 0 allowed | L-BELOW, L-MAKE-REF |
| L-12 | a ping interval of 0 refused | L-ALL, L-EDGE |
| L-13 | a close timeout of 0 refused | L-ALL, L-EDGE |
| L-14 | a high water of 0 refused | L-EDGE |
| L-15 | a low water of 0 refused | L-EDGE |
| L-16 | the ping interval read in ms | L-EACH, L-ZERO |
| L-17 | the pong timeout read in ms | L-EACH, L-ALL, L-EDGE |
| L-18 | the close timeout read in ms | L-EACH |
| L-19 | the cap read in KiB | L-EACH, L-ALL, L-EDGE |
| L-20 | a plus sign taken for a digit | L-MAL |
| L-21 | char-numeric? for a digit | L-MAL |
| L-22 | an empty value not the default | L-EMPTY |
| L-24 | a malformed value names itself, not its variable | L-MAL |
| L-25 | the environment's refusals name the field | L-BELOW, L-WATER |
| L-26 | no water check | L-WATER, L-MAKE-REF |
| L-27 | equal water marks refused | L-EDGE, L-WATER |
| L-28 | the water refusal names the high water first | L-WATER, L-MAKE-REF |
| L-29 | an inexact whole number accepted | L-MAKE-REF |
| L-30 | a non-number reaches exact? | L-MAKE-REF |
| L-31 | make-websocket-limits checks nothing | L-MAKE-REF, L-WITH-REF |
| L-32 | make-websocket-limits swaps the ping interval and timeout | L-MAKE, L-MAKE-REF, L-WITH |
| L-33 | websocket-limits-with takes any name | L-WITH-REF |
| L-34 | websocket-limits-with ignores its overrides | L-WITH, L-WITH-REF |
| A-1 | (websocket limits) imports (chezscheme) | the import audit's check of its library, alone |

Every red was by value, exit 1, with no harness error.

35 rows, each as named before the run, on this step's tree: 0 mismatches. The
first run, on the whole slice before it was cut, had one mismatch among these, a
prediction error: L-10, a queue of 0 allowed, reddens `websocket-limits-with`'s
refusal too, whose second row is a queue of 0. `make test` is green afterwards
on this step's tree: seven suites, 135 expected passes.

Every check has its killers, each at least one by value.

## M3.1, step 2 — the protocol

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The library is `src/websocket/protocol.sls` (blob 7ab40e3), and the
suite `tests/test-protocol.sps`, 46 checks (blob d64a9f6). The limits are step
1's. The runner was step 1's, with both suites run for every library mutant,
since the protocol reads its limits.

### The oracles

- **RFC 6455's raw text.** §5.4's fragments; §5.5's control frames; §5.5.1's close,
  answered with a close, its body empty or a two-byte code first; §5.5.2's ping,
  answered with a pong carrying its payload; §5.6's text in UTF-8; §5.7's
  examples; §7.1.4's clean close; §7.1.5 and §7.1.6, 1006 and an empty reason
  when no close came; §7.1.7's failing; §7.4.1's codes, read from the raw text:
  1000 to 1003 and 1007 to 1011 an endpoint may send, 1004 reserved, 1005, 1006
  and 1015 never set; §7.4.2's 3000 to 4999; §8.1, 1007.
- **RFC 3629 §4's grammar**, its rows at their edges and the index of each
  refusal, as M1.3's suite has them.
- **Decision 0001 and its amendment, and the design's §5.**
- **The suite's own frames.** It builds a client's frames by §5.2 and §5.3, and
  the server's by §5.2. Unless they are §5.7's bytes, the suite stops with a
  provenance failure, exit 3.
- **Chez's own sizes.** A message read in one frame should allocate what
  `make-bytevector` allocates for its bytes, and a fragmented one the doublings
  of its buffer, measured in the test.
- **Node's ws 7.5.10, a server's receiver** (Node 20.10.0, the same copy as M2's;
  `receiver.js` SHA-1 `42a9f03f`). A shim of `(websocket protocol)` logged every
  connection the suite made, each read it stepped, and what each step answered.
  The suite ran through it, its allocation check red, since the shim allocates.
  ws was fed each connection's reads in the same pieces, as a server with that
  connection's cap (`maxPayload`). Its answers were compared with ours: the
  messages, the pongs (ws's pings), a client's close, and a failure's code.

  | connections | what ws answered |
  |---|---|
  | 527 | the same |
  | 18 | a text failed 1007 by ours at the byte that showed it, and by ws only at its message's end, or not yet where the message had not ended: ws checks a text whole (receiver.js `dataMessage`) |
  | 3 | a close of 1012, 1013 or 1014, which ours fails 1002 and ws accepts: ws's `isValidStatusCode` takes 1000 to 1014 but 1004 to 1006. RFC 6455 §7.4.1 defines no 1012 to 1014; IANA's registry added them later. The design keeps §7.4.1's list. |
  | 1 | a length not in its shortest form, which ours refuses and ws reads (M2.1) |
  | 1 | a 64-bit length with its top bit set: ours 1002, ws 1009 (M2.1) |
  | 13 | no read: sends, and events refused |

  **No answer disagreed.** The queue's stops and starts have no counterpart in
  ws, which reads on; they are held to 0001 and its amendment.

### The test-first runs

- **Before the library:** `Exception: library (websocket protocol) not found`,
  exit 255.
- **A stub whose step answers nothing and refuses nothing:** 45 red, and 1
  green, "the bytes a step reads are left as they were", which M-82 kills by
  value. Run again on the final suite, it reddens the same.
- **The first library run** passed all 44 checks the suite then had. The rest
  came after, for gaps found while writing the mutants (below). Each new check
  was watched to fail under its mutants.

### Lines no check could tell apart, taken out before the run

Writing the mutants found six lines no check could tell from their absence. Each
was shown redundant, and taken out:
- A new message's reset of `held` to 0, and of the UTF-8 state to its start:
  `deliver!` leaves `held` at 0, and a text ends whole or the connection fails.
- `end!`'s clearing of `message`, `buffer` and `waiting`: after the end, nothing
  reads them. M3.2's ends will need `waiting` let go, and bring their own check.
- `taken!`'s first test of the phase: `waiting` is never set once the connection
  has ended, and the second test of the phase stands.

### Gaps found by writing the mutants, and their checks

- **What a connection keeps.** A delivered message's bytevector, and a read once
  its bytes are read, must not be kept: a connection lives as long as its
  WebSocket, idle or not. A guardian holds both now (M-39, M-77, M-59).
- **A fragmented message's buffer doubles.** A buffer that grew by each
  fragment alone would copy the message once a fragment: one-byte fragments to
  1 MiB would copy about 2^39 bytes on the server's one loop. The allocation
  check holds the doublings (M-46, M-47).
- **A take while reading answers nothing** (M-74).
- **An event of the wrong shape** is refused naming ws-step (M-78, M-79).
- **Two connections' control frames read in turns** (M-85, a control buffer
  shared by all).
- **A take after the end, with reading stopped** (M-76).
- **The refusal helper.** A mutant that stopped refusing made the step return two
  values where the helper took one, so its checks went red only through a raise.
  The helper now answers `accepted` for any return, and every check has a killer
  by value.

### The mutants

Step 1's 35 rows ran again on this tree, both suites run, and with them this
step's 89: the protocol's 88 and the audit's. Where the limits reach the
protocol, a row's red set takes in the protocol's checks too: L-1 (the default
cap), L-2 (the default queue) and L-34 (`websocket-limits-with` ignoring its
overrides). The keys are step 1's and these:

| key | check |
|---|---|
| P-HELLO | RFC 6455's masked Hello is delivered whole, as text: its UTF-8 bytes |
| P-ONE | a message in one frame, text or binary, at each length form's edges, is delivered whole |
| P-FRAG57 | §5.7's fragmented Hello, masked, is delivered whole once its final frame comes, and not before |
| P-FRAGS | a fragmented message is delivered whole, of its first frame's kind, whatever its fragments: empty ones, one byte each, and the length forms' edges |
| P-B2B | messages back to back, with control frames alone and between fragments, read whole, a byte at a time, and cut at every point |
| P-PAIRS | a fragmented message with a ping between, cut at every pair of points |
| P-CONT | a continuation with no message begun fails 1002, at its header: first, or after a message has ended, final or not |
| P-UNFIN | a text or binary frame while a message is unfinished fails 1002, at its header |
| P-PING | a ping is answered at once with a pong carrying its payload: §5.7's Hello, and 0, 1 and 125 bytes |
| P-PONG | a pong is answered with nothing, alone or between fragments: §5.7's masked pong |
| P-PINGMID | a ping between a message's fragments is answered before the message is delivered |
| P-CAP | a message of the cap's bytes is delivered; a frame one byte past it fails 1009 at its header, before its payload comes |
| P-CAPFRAG | fragments that take a message past the cap fail 1009 at that fragment's header; up to it, the message is delivered; control frames between them do not count |
| P-CAPDEF | the default cap, 1 MiB: 1,048,576 bytes are delivered, and reading stops with a cap's worth queued; a frame announcing 1,048,577 fails 1009 at its header |
| P-CAPMAX | a frame announcing 2^63 - 1 bytes fails 1009 at its header |
| P-UTF8OK | every row of RFC 3629 §4 at its edges, as text, is delivered; and U+FEFF first is delivered with it |
| P-UTF8AT | a byte no character can go on with fails 1007 at once, at the step that brings it, though the message has not ended |
| P-UTF8SPLIT | a character split between fragments is whole: € and U+10FFFF, split at every byte |
| P-UTF8END | a text message that ends mid-character fails 1007 at its final frame's end |
| P-BIN | binary is not checked: bytes no text may hold are delivered |
| P-REFUSE | each refusal of the frame decoder fails 1002, its reason logged |
| P-AFTER | after failing, nothing more is read: the rest of the read answers nothing |
| P-CLOSE | a close is answered with a close of its code and the stream closed, and the code and reason are told, cleanly: each code an endpoint may send |
| P-CLOSE123 | a close of a code alone, and of a reason of 123 bytes, the most a close holds, told whole |
| P-CLOSE0 | an empty close is answered with an empty close, and 1005 is told |
| P-CLOSE1 | a close of one byte fails 1002 |
| P-CODE | a close with a code an endpoint may not send fails 1002 |
| P-REASON | a close whose reason is not UTF-8 fails 1007: a byte no character goes on with, or a reason ending mid-character |
| P-CLOSEMID | a close between a message's fragments: the message unfinished is not delivered, and nothing after the close is read, a ping among it (§5.5.2) |
| P-SEND | a send writes its message as one frame: text in UTF-8 from its string, as §5.7's Hello; binary as given, as §5.7's 256-byte and 64 KiB messages |
| P-SEND2 | U+FEFF first is sent with it, and an empty text and an empty binary are frames of no payload |
| P-SENDMID | a send between a message's fragments leaves the message whole |
| P-SENDAPI | a send of another kind, or a payload not of its kind, or after the connection has ended, is an assertion naming ws-step |
| P-QBYTES | reading stops once a cap's worth is queued, and starts again once a take brings the queue under it; under the cap, it goes on, and a take answers nothing |
| P-QSTAY | a take that leaves a cap's worth queued leaves reading stopped |
| P-QCOUNT | by default, reading stops at 16 queued messages, and starts again once one is taken; at 15 it goes on |
| P-QWAIT | once reading stops, the rest of the read waits, and is read a message a take, before reading starts again |
| P-QREAD | what waits is read as it would have been: a ping answered at the take that reads it, a frame the read cut off finished by the next read |
| P-QEND | what waits may end the connection at the take that reads it, and then reading does not start: a refusal, a close |
| P-TAKEN | after the connection has ended, a take answers nothing, though reading had stopped |
| P-QAPI | a take of more than is queued, or with nothing queued, or a read while reading is stopped or after the connection has ended, is an assertion naming ws-step |
| P-API | an event outside the vocabulary or of the wrong shape, or a read outside its bytevector, is an assertion naming ws-step; limits that are not, naming make-ws-state |
| P-PURE | the bytes a step reads are left as they were, read at once or after waiting |
| P-ALLOC | a message in one frame is read into the bytevector it is delivered in, and one in fragments into a buffer that doubles up to the cap, allocating nothing a fragment |
| P-KEEP | a connection keeps no message once it is delivered, and no read once its bytes are read |
| P-TWO | two connections at once are each their own: their messages and their control frames read in turns |

| # | mutation | red |
|---|----------|-----|
| B-0 | unmutated | none: the unmutated tree, 60 passes |
| L-1 | the default cap one byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH, P-CAPDEF |
| L-2 | the default queue 17 messages | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH, P-QCOUNT |
| L-3 | the default ping interval 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-WITH |
| L-4 | the default pong timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-5 | the default close timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-6 | the default high water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-ZERO, L-WITH |
| L-7 | the default low water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-ZERO, L-WITH |
| L-8 | CHEZ_WS_MAX_QUEUE misspelled | L-VARS, L-EACH, L-ALL, L-EDGE, L-BELOW, L-MAL |
| L-9 | a cap of 0 allowed | L-BELOW, L-MAKE-REF |
| L-10 | a queue of 0 allowed | L-BELOW, L-MAKE-REF, L-WITH-REF |
| L-11 | a pong timeout of 0 allowed | L-BELOW, L-MAKE-REF |
| L-12 | a ping interval of 0 refused | L-ALL, L-EDGE |
| L-13 | a close timeout of 0 refused | L-ALL, L-EDGE |
| L-14 | a high water of 0 refused | L-EDGE |
| L-15 | a low water of 0 refused | L-EDGE |
| L-16 | the ping interval read in ms | L-EACH, L-ZERO |
| L-17 | the pong timeout read in ms | L-EACH, L-ALL, L-EDGE |
| L-18 | the close timeout read in ms | L-EACH |
| L-19 | the cap read in KiB | L-EACH, L-ALL, L-EDGE |
| L-20 | a plus sign taken for a digit | L-MAL |
| L-21 | char-numeric? for a digit | L-MAL |
| L-22 | an empty value not the default | L-EMPTY |
| L-24 | a malformed value names itself, not its variable | L-MAL |
| L-25 | the environment's refusals name the field | L-BELOW, L-WATER |
| L-26 | no water check | L-WATER, L-MAKE-REF |
| L-27 | equal water marks refused | L-EDGE, L-WATER |
| L-28 | the water refusal names the high water first | L-WATER, L-MAKE-REF |
| L-29 | an inexact whole number accepted | L-MAKE-REF |
| L-30 | a non-number reaches exact? | L-MAKE-REF |
| L-31 | make-websocket-limits checks nothing | L-MAKE-REF, L-WITH-REF |
| L-32 | make-websocket-limits swaps the ping interval and timeout | L-MAKE, L-MAKE-REF, L-WITH |
| L-33 | websocket-limits-with takes any name | L-WITH-REF |
| L-34 | websocket-limits-with ignores its overrides | L-WITH, L-WITH-REF, P-CAP, P-CAPFRAG, P-AFTER, P-QBYTES, P-QSTAY, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI, P-ALLOC |
| A-1 | (websocket limits) imports (chezscheme) | the import audit's check of its library, alone |
| A-2 | (websocket protocol) imports (chezscheme) | the import audit's check of its library, alone |
| M-1 | make-ws-state takes anything for limits | P-API |
| M-2 | the end does not end the connection | *P-CONT*, *P-UNFIN*, *P-AFTER*, P-CLOSEMID, P-SENDAPI, P-QEND, P-TAKEN, P-QAPI |
| M-3 | the end's actions in the reverse order | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE, P-CLOSE123, P-CLOSE0, P-CLOSE1, P-CODE, P-REASON, P-CLOSEMID, P-QEND, P-TAKEN |
| M-4 | a failing close's code little-endian | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-5 | a failure told 1000 | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-6 | a failure told clean | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-7 | a failure logged without why | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-8 | a failure leaves the stream open | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-9 | 1000 not sendable | P-CLOSE, P-CLOSE123, P-REASON, P-QEND, P-TAKEN |
| M-10 | 999 sendable | P-CODE |
| M-11 | 1003 not sendable | P-CLOSE |
| M-12 | 1004 sendable | P-CODE |
| M-13 | 1007 not sendable | P-CLOSE |
| M-14 | 1006 sendable | P-CODE |
| M-15 | 1011 not sendable | P-CLOSE |
| M-16 | 1012 sendable | P-CODE |
| M-17 | 3000 not sendable | P-CLOSE |
| M-18 | 2999 sendable | P-CODE |
| M-19 | 4999 not sendable | P-CLOSE |
| M-20 | 5000 sendable | P-CODE |
| M-21 | an empty close told 1000 | P-CLOSE0 |
| M-22 | an empty close answered with 1000 | P-CLOSE0 |
| M-23 | a close of one byte read as a code | P-CLOSE1 |
| M-24 | a close's code not checked | P-CODE |
| M-25 | a close's reason not checked | P-REASON |
| M-26 | a close's reason may end mid-character | P-REASON |
| M-27 | a close echoed with its reason | P-CLOSE, P-CLOSE123 |
| M-28 | a close's reason told from its code on | P-CLOSE, P-CLOSE123 |
| M-29 | a close with a code told unclean | P-CLOSE, P-CLOSE123, P-CLOSEMID, P-QEND, P-TAKEN |
| M-30 | a ping not answered | P-B2B, P-PAIRS, P-PING, P-PINGMID, P-CAPFRAG, P-QREAD, P-TWO |
| M-31 | a pong answered with a pong | P-B2B, P-PONG |
| M-32 | a pong without its ping's payload | P-B2B, P-PAIRS, P-PING, P-PINGMID, P-CAPFRAG, P-QREAD, P-TWO |
| M-33 | a cap's worth queued does not stop reading | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES |
| M-34 | max-queue messages queued do not stop reading | P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI |
| M-35 | no byte bound on the queue | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES, P-QSTAY |
| M-36 | no count bound on the queue | P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI |
| M-37 | a message always copied at its delivery | P-ALLOC |
| M-38 | a message delivered in its whole buffer | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-PONG, P-UTF8SPLIT, P-SENDMID |
| M-39 | a delivered message kept | P-KEEP |
| M-40 | a message's bytes not queued | P-CAP, P-CAPFRAG, P-CAPDEF, *P-QBYTES*, *P-QSTAY*, *P-QWAIT*, *P-QREAD*, *P-QEND*, *P-TAKEN*, *P-PURE*, *P-KEEP* |
| M-41 | a message not counted | *P-QBYTES*, *P-QSTAY*, *P-QCOUNT*, *P-QWAIT*, *P-QREAD*, *P-QEND*, *P-TAKEN*, P-QAPI, *P-PURE*, *P-KEEP* |
| M-42 | read-stop not answered | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES, P-QSTAY, P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN |
| M-43 | reading not marked stopped | P-QBYTES, P-QSTAY, P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI, *P-PURE*, P-KEEP |
| M-44 | every data frame ends its message | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-UNFIN, P-PONG, P-PINGMID, P-CAPFRAG, P-UTF8SPLIT, P-UTF8END, P-CLOSEMID, P-SENDMID, P-ALLOC |
| M-45 | a text may end mid-character | P-UTF8END |
| M-46 | the buffer grows by what it needs alone | P-ALLOC |
| M-47 | the buffer grows past the cap | P-ALLOC |
| M-48 | the buffer forgets what it held as it grows (filled) | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-PONG, P-PINGMID, P-CAPFRAG, P-UTF8SPLIT, P-SENDMID |
| M-49 | a control frame's count not begun again | P-B2B |
| M-50 | a continuation needs no message | *P-CONT* |
| M-51 | a continuation's cap not checked | *P-CAPFRAG* |
| M-52 | fragments may not reach the cap | P-CAPFRAG, P-ALLOC |
| M-53 | a continuation's cap checked on its own length | *P-CAPFRAG* |
| M-54 | a message begun before the last ended | *P-UNFIN* |
| M-55 | a first frame's cap not checked | P-CAP, P-CAPDEF, *P-CAPMAX*, P-AFTER |
| M-56 | a message may not reach the cap | P-CAP, P-CAPDEF, P-ALLOC |
| M-57 | a first frame's buffer a byte too big | P-ALLOC |
| M-58 | reading goes on past a full queue | P-QWAIT, P-QREAD, P-QEND, P-TAKEN |
| M-59 | what waits is kept from the read's start | P-QWAIT, *P-QREAD*, P-QEND, P-TAKEN, P-KEEP |
| M-60 | a refusal's reason not logged | P-REFUSE, P-AFTER, P-QEND |
| M-61 | a control payload always read into its start | P-B2B, P-TWO |
| M-62 | a text's bytes checked from the buffer's start | P-UTF8AT, P-UTF8SPLIT, P-UTF8END |
| M-63 | binary checked as UTF-8 | P-ONE, P-FRAGS, P-CAP, P-CAPFRAG, P-CAPDEF, P-BIN, *P-QBYTES*, *P-QSTAY*, P-ALLOC, *P-KEEP* |
| M-64 | a read's range not checked | P-API |
| M-65 | a read after the end allowed | P-QAPI |
| M-66 | a read while stopped allowed | P-QAPI |
| M-67 | a send after the end allowed | P-SENDAPI |
| M-68 | text sent as binary | P-SEND, P-SEND2 |
| M-69 | text sent in Latin-1 | *P-SEND2* |
| M-70 | any kind of bytevector sent as binary | P-SENDAPI |
| M-71 | a text's payload not checked for a string | P-SENDAPI |
| M-72 | a take with nothing queued | P-QAPI |
| M-73 | a take of more than is queued | P-QAPI |
| M-74 | a take while reading answers read-start | P-QBYTES |
| M-75 | read-start though what waits fills the queue again | P-QWAIT |
| M-76 | read-start after the connection ended | P-QEND, P-TAKEN |
| M-77 | what waits not let go before it is read | P-QWAIT, P-KEEP |
| M-78 | an event not a pair reaches car | P-API |
| M-79 | an event's shape not checked | P-API |
| M-80 | an unknown event answered with nothing | P-API |
| M-81 | the control buffer a byte short | *P-PING*, *P-CAPFRAG*, *P-CLOSE123* |
| M-82 | the read's payload unmasked in place | P-PURE, P-KEEP |
| M-83 | a fragmented message of its last frame's kind | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-PONG, P-CAPFRAG, P-UTF8SPLIT, P-UTF8END, P-SENDMID |
| M-84 | every message delivered as binary | P-HELLO, P-ONE, P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-CONT, P-PONG, P-CAPFRAG, P-UTF8OK, P-UTF8SPLIT, P-SENDMID, P-QCOUNT, P-QREAD, P-TWO |
| M-85 | one control buffer for every connection | P-TWO |
| M-86 | a send forgets the message begun | P-SENDMID |
| M-87 | binary sent as text | P-SEND, P-SEND2, P-SENDMID |
| M-88 | UTF-8 failed only at the message's end | P-UTF8AT |

A key in italics went red through a raise. Every other red was by value, exit 1,
with no harness error.

124 rows, each as named before the run, on this step's tree: 0 mismatches. The
specs were hashed before each run (`specs.py`, SHA-256 `c9040933…` for the first,
`2f62a15a…` for the last). `make test` is green afterwards: eight suites, 182
expected passes, every pin ok.

Notes:
- **The first run had 11 mismatches, all prediction errors.** Each was an extra
  red, a check that rightly failed and that I had not named. None survived:
  - L-10 reddens `websocket-limits-with`'s refusal too: its second row is a queue
    of 0.
  - M-9 reddens the reason's check: its frames carry code 1000.
  - M-30 and M-32 redden the two connections' check, whose frames now include
    pings.
  - M-38, M-44, M-48, M-83 and M-84 redden the pong's check: its second row is a
    fragmented text with a pong between.
  - M-43 reddens the bytes left as they were: its second take finds nothing
    queued.
  - M-82 reddens what a connection keeps, which compares the read's bytes too.

  With the sets named again, the run on the final blobs had 0 mismatches.
- **Every check has its killers, and each one at least one by value.** Thirteen
  mutants still redden some check through a raise, such as a take refused
  because a message went uncounted (M-40, M-41).
- **No mutant survives.** M3.1 has no scope statement.

## M3.1's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The owner's `/code-review high` of #16 and #17 found nine things,
and all nine are fixed, on the owner's "fix all". The blobs: `limits.sls`
cdf3ec3, `protocol.sls` 132c307, `frame.sls` 1f004d2; `test-limits.sps`
16c37e2, 15 checks; `test-protocol.sps` 5aae609, 48 checks; `test-frame.sps`
b6c0444, 42 checks. The runner was step 2's, with three suites run for every
mutant, since `(websocket frame)` changed too.

### The findings and their fixes

| # | finding | fixed |
|---|---|---|
| 1 | a frame's buffer allocated at its announced length, at its header | a message's buffer grows as its bytes arrive (below) |
| 2 | limits with no upper bound: a bignum of ms passed, which `transport-deadline!` refuses | each value a fixnum at most, refused at the reading, naming the variable |
| 3 | guards no check or mutant held: a take's fixnum and sign, a read's start and end | rows for each, and Q-1 to Q-5 |
| 4 | an ended connection keeping its unfinished message | `end!` lets go of it, checked on the live heap |
| 5 | "five lines" where six were listed | six, in step 2's records |
| 6 | the record's predicate and accessors with no signature comment | a comment at the record type |
| 7 | the water check finding its marks by position | by name, `named` |
| 8 | `control-kind?` repeating `(websocket frame)`'s `control?` | `frame-control?`, exported, with its check |
| 9 | `field-values` building accessors each call | the table carries each field's accessor |

**Finding 1, measured.** A prototype of each fix was run against #17's library
(Darwin arm64):

| | #17 | grow as it arrives | 16 KiB up front, then grow |
|---|---|---|---|
| a 14-byte header announcing 1 MiB, alone | 1,048,576 B | 0 B | 16,384 B |
| 1 MiB in one frame, in reads of 16 KiB | 1,049,088 B, 1.98 ms | 2,080,912 B, 1.99 ms | 2,081,376 B |
| 1 MiB in one frame, in one read | 1,049,088 B | 1,049,088 B | 1,065,488 B |

Growing as it arrives does as well as or better than the floor in every case,
so there was nothing to put to a form. Plain doubling, capped at the message's
end, first measured 3,129,056 B: a doubling landed just under the end
(1,048,128 B), then grew again. So in a message's last frame, once a doubling
would reach half its end, the buffer takes the whole end. It is then never
more than four times what has arrived. The step's time is the same within
noise.

### The test-first runs

The review's suites against #17's libraries:
- **the frame suite** stops at once: `attempt to reference unbound identifier
  frame-control?`, exit 255;
- **the limits suite**: 14 passes, and the fixnum check red;
- **the protocol suite**: 46 passes, and red the growth check, `(1048576
  1048592)` for `(0 2080416)`, and the ended connection's, `(kept 1000448)`.

The rows for finding 3, the non-pair override and the non-default base pass
there: the code held them already, and no check did. Their mutants show it:
Q-1 to Q-5 and L-35, cut on #17's libraries, pass #17's suites with every
check green, and each fails its check here. L-37 cuts the review's new table.

### The oracles

- **The transport's contract**: `transport-deadline!` takes a fixnum of ms
  (`(fixnum? ms)`, chez-http-server's `transport.sls`). Chez's own
  `(greatest-fixnum)` sets the edge.
- **Chez's own sizes** for the growth check. The test works out the sizes by
  the rule the library's comment states: double, or take what has arrived if
  more, and take the end once a doubling would reach half of it.
- **The live heap** for what an ended connection keeps: a footprint is the live
  heap holding it, every generation collected, less the live heap once it is
  let go. The first such measure frees about 87 KB that loading left, so one
  round warms up. Then a new connection measures 48 to 432 B, and an ended one
  432 B, or 1,000,432 B with the release taken out. Half the fragment's
  1,000,000 bytes tells them apart.
- **ws 7.5.10**, fed every connection of the review's suite: 582. 542 answered
  the same and 17 read nothing. The rest are ws's own, as in step 2: 18 judge
  UTF-8 at a message's end, 3 accept 1012 to 1014, and 2 are M2.1's length
  rules. No answer disagreed.

### The mutants

The keys are step 1's and step 2's, with four new: L-FIX, "a value is a fixnum
at most…"; P-GROW, "a message's buffer grows as its bytes arrive…"; P-ENDKEEP,
"once the connection has ended, it keeps no unfinished message"; and FC,
`frame-control?`'s check in the frame suite. M3.1's rows were re-cut where the
review changed their code. M-57 is withdrawn: a first buffer one byte bigger is
now outgrown at once. G-5 cuts the eager buffer instead.

| # | mutation | red |
|---|----------|-----|
| B-0 | unmutated | none: the tree unmutated, 105 passes |
| L-1 | the default cap one byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-ZERO, L-WITH, P-CAPDEF |
| L-2 | the default queue 17 messages | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-ZERO, L-WITH, P-QCOUNT |
| L-3 | the default ping interval 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-WITH |
| L-4 | the default pong timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-ZERO, L-WITH |
| L-5 | the default close timeout 1 ms more | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-ZERO, L-WITH |
| L-6 | the default high water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-FIX, L-ZERO, L-WITH |
| L-7 | the default low water a byte less | L-DEF, L-EMPTY, L-EACH, L-EDGE, L-WATER, L-FIX, L-ZERO, L-WITH |
| L-8 | CHEZ_WS_MAX_QUEUE misspelled | L-VARS, L-EACH, L-ALL, L-EDGE, L-BELOW, L-MAL, L-FIX |
| L-9 | a cap of 0 allowed | L-BELOW, L-MAKE-REF |
| L-10 | a queue of 0 allowed | L-BELOW, L-MAKE-REF, L-WITH-REF |
| L-11 | a pong timeout of 0 allowed | L-BELOW, L-MAKE-REF |
| L-12 | a ping interval of 0 refused | L-ALL, L-EDGE |
| L-13 | a close timeout of 0 refused | L-ALL, L-EDGE |
| L-14 | a high water of 0 refused | L-EDGE |
| L-15 | a low water of 0 refused | L-EDGE |
| L-16 | the ping interval read in ms | L-EACH, L-FIX, L-ZERO |
| L-17 | the pong timeout read in ms | L-EACH, L-ALL, L-EDGE, L-FIX |
| L-18 | the close timeout read in ms | L-EACH, L-FIX |
| L-19 | the cap read in KiB | L-EACH, L-ALL, L-EDGE, L-FIX |
| L-20 | a plus sign taken for a digit | L-MAL |
| L-21 | char-numeric? for a digit | L-MAL |
| L-22 | an empty value not the default | L-EMPTY |
| L-24 | a malformed value names itself, not its variable | L-MAL |
| L-25 | the environment's refusals name the field | L-BELOW, L-WATER, L-FIX |
| L-26 | no water check | L-WATER, L-MAKE-REF |
| L-27 | equal water marks refused | L-EDGE, L-WATER, L-FIX |
| L-28 | the water refusal names the high water first | L-WATER, L-MAKE-REF |
| L-29 | any integer taken for a fixnum | L-FIX, L-MAKE-REF |
| L-30 | the bound before the review: any exact integer | L-FIX |
| L-31 | make-websocket-limits checks nothing | L-FIX, L-MAKE-REF, L-WITH-REF |
| L-32 | make-websocket-limits swaps the ping interval and timeout | L-MAKE, L-MAKE-REF, L-WITH |
| L-33 | websocket-limits-with takes any name | L-WITH-REF |
| L-34 | websocket-limits-with ignores its overrides | L-WITH, L-WITH-REF, P-CAP, P-CAPFRAG, P-AFTER, P-QBYTES, P-QSTAY, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI, P-ALLOC, P-GROW |
| L-35 | an override not checked for a pair | L-WITH-REF |
| L-37 | the ping interval's and timeout's accessors swapped in the table | L-WITH |
| A-1 | (websocket limits) imports (chezscheme) | the import audit's check of its library, alone |
| A-2 | (websocket protocol) imports (chezscheme) | the import audit's check of its library, alone |
| M-1 | make-ws-state takes anything for limits | P-API |
| M-2 | the end does not end the connection | *P-CONT*, *P-UNFIN*, *P-AFTER*, *P-CLOSEMID*, P-SENDAPI, P-QEND, P-TAKEN, P-QAPI |
| M-3 | the end's actions in the reverse order | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE, P-CLOSE123, P-CLOSE0, P-CLOSE1, P-CODE, P-REASON, P-CLOSEMID, P-QEND, P-TAKEN |
| M-4 | a failing close's code little-endian | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-5 | a failure told 1000 | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-6 | a failure told clean | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-7 | a failure logged without why | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-8 | a failure leaves the stream open | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND |
| M-9 | 1000 not sendable | P-CLOSE, P-CLOSE123, P-REASON, P-QEND, P-TAKEN |
| M-10 | 999 sendable | P-CODE |
| M-11 | 1003 not sendable | P-CLOSE |
| M-12 | 1004 sendable | P-CODE |
| M-13 | 1007 not sendable | P-CLOSE |
| M-14 | 1006 sendable | P-CODE |
| M-15 | 1011 not sendable | P-CLOSE |
| M-16 | 1012 sendable | P-CODE |
| M-17 | 3000 not sendable | P-CLOSE |
| M-18 | 2999 sendable | P-CODE |
| M-19 | 4999 not sendable | P-CLOSE |
| M-20 | 5000 sendable | P-CODE |
| M-21 | an empty close told 1000 | P-CLOSE0 |
| M-22 | an empty close answered with 1000 | P-CLOSE0 |
| M-23 | a close of one byte read as a code | P-CLOSE1 |
| M-24 | a close's code not checked | P-CODE |
| M-25 | a close's reason not checked | P-REASON |
| M-26 | a close's reason may end mid-character | P-REASON |
| M-27 | a close echoed with its reason | P-CLOSE, P-CLOSE123 |
| M-28 | a close's reason told from its code on | P-CLOSE, P-CLOSE123 |
| M-29 | a close with a code told unclean | P-CLOSE, P-CLOSE123, P-CLOSEMID, P-QEND, P-TAKEN |
| M-30 | a ping not answered | P-B2B, P-PAIRS, P-PING, P-PINGMID, P-CAPFRAG, P-QREAD, P-TWO |
| M-31 | a pong answered with a pong | P-B2B, P-PONG |
| M-32 | a pong without its ping's payload | P-B2B, P-PAIRS, P-PING, P-PINGMID, P-CAPFRAG, P-QREAD, P-TWO |
| M-33 | a cap's worth queued does not stop reading | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES |
| M-34 | max-queue messages queued do not stop reading | P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI |
| M-35 | no byte bound on the queue | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES, P-QSTAY |
| M-36 | no count bound on the queue | P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI |
| M-37 | a message always copied at its delivery | P-ALLOC, P-GROW |
| M-38 | a message delivered in its whole buffer | P-FRAGS |
| M-39 | a delivered message kept | P-KEEP |
| M-40 | a message's bytes not queued | P-CAP, P-CAPFRAG, P-CAPDEF, *P-QBYTES*, *P-QSTAY*, *P-QWAIT*, *P-QREAD*, *P-QEND*, *P-TAKEN*, *P-PURE*, *P-KEEP* |
| M-41 | a message not counted | *P-QBYTES*, *P-QSTAY*, *P-QCOUNT*, *P-QWAIT*, *P-QREAD*, *P-QEND*, *P-TAKEN*, P-QAPI, *P-PURE*, *P-KEEP* |
| M-42 | read-stop not answered | P-CAP, P-CAPFRAG, P-CAPDEF, P-QBYTES, P-QSTAY, P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN |
| M-43 | reading not marked stopped | P-QBYTES, P-QSTAY, P-QCOUNT, P-QWAIT, P-QREAD, P-QEND, P-TAKEN, P-QAPI, *P-PURE*, P-KEEP |
| M-44 | every data frame ends its message | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-UNFIN, P-PONG, P-PINGMID, P-CAPFRAG, P-UTF8SPLIT, P-UTF8END, P-CLOSEMID, P-SENDMID, P-ALLOC |
| M-45 | a text may end mid-character | P-UTF8END |
| M-46 | the buffer grows by what it needs alone | P-ALLOC, P-GROW |
| M-47 | the buffer grows past the cap before a message's last frame | P-ALLOC |
| M-48 | the buffer forgets what it held as it grows (filled) | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-PONG, P-PINGMID, P-CAPFRAG, P-UTF8SPLIT, P-SENDMID, P-QREAD |
| M-49 | a control frame's count not begun again | P-B2B |
| M-50 | a continuation needs no message | *P-CONT* |
| M-51 | a continuation's cap not checked | P-CAPFRAG |
| M-52 | fragments may not reach the cap | P-CAPFRAG, P-ALLOC |
| M-53 | a continuation's cap checked on its own length | P-CAPFRAG |
| M-54 | a message begun before the last ended | *P-UNFIN* |
| M-55 | a first frame's cap not checked | P-CAP, P-CAPDEF, P-CAPMAX, P-AFTER |
| M-56 | a message may not reach the cap | P-CAP, P-CAPDEF, P-ALLOC |
| M-58 | reading goes on past a full queue | P-QWAIT, P-QREAD, P-QEND, P-TAKEN |
| M-59 | what waits is kept from the read's start | P-QWAIT, *P-QREAD*, P-QEND, P-TAKEN, P-KEEP |
| M-60 | a refusal's reason not logged | P-REFUSE, P-AFTER, P-QEND |
| M-61 | a control payload always read into its start | P-B2B, P-TWO |
| M-62 | a text's bytes checked from the buffer's start | P-UTF8AT, P-UTF8SPLIT, P-UTF8END |
| M-63 | binary checked as UTF-8 | P-ONE, P-FRAGS, P-CAP, P-CAPFRAG, P-CAPDEF, P-BIN, *P-QBYTES*, *P-QSTAY*, P-ALLOC, *P-GROW*, *P-KEEP*, *P-ENDKEEP* |
| M-64 | a read's range not checked | P-API |
| M-65 | a read after the end allowed | P-QAPI |
| M-66 | a read while stopped allowed | P-QAPI |
| M-67 | a send after the end allowed | P-SENDAPI |
| M-68 | text sent as binary | P-SEND, P-SEND2 |
| M-69 | text sent in Latin-1 | *P-SEND2* |
| M-70 | any kind of bytevector sent as binary | P-SENDAPI |
| M-71 | a text's payload not checked for a string | P-SENDAPI |
| M-72 | a take with nothing queued | P-QAPI |
| M-73 | a take of more than is queued | P-QAPI |
| M-74 | a take while reading answers read-start | P-QBYTES |
| M-75 | read-start though what waits fills the queue again | P-QWAIT |
| M-76 | read-start after the connection ended | P-QEND, P-TAKEN |
| M-77 | what waits not let go before it is read | P-QWAIT, P-KEEP |
| M-78 | an event not a pair reaches car | P-API |
| M-79 | an event's shape not checked | P-API |
| M-80 | an unknown event answered with nothing | P-API |
| M-81 | the control buffer a byte short | *P-PING*, *P-CAPFRAG*, *P-CLOSE123* |
| M-82 | the read's payload unmasked in place | P-PURE, P-KEEP |
| M-83 | a fragmented message of its last frame's kind | P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-PONG, P-CAPFRAG, P-UTF8SPLIT, P-UTF8END, P-SENDMID |
| M-84 | every message delivered as binary | P-HELLO, P-ONE, P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-CONT, P-PONG, P-CAPFRAG, P-UTF8OK, P-UTF8SPLIT, P-SENDMID, P-QCOUNT, P-QREAD, P-TWO |
| M-85 | one control buffer for every connection | P-TWO |
| M-86 | a send forgets the message begun | P-SENDMID |
| M-87 | binary sent as text | P-SEND, P-SEND2, P-SENDMID |
| M-88 | UTF-8 failed only at the message's end | P-UTF8AT |
| G-1 | plain doubling, capped at the message's end | P-GROW |
| G-3 | the whole end at a last frame's first byte | P-GROW |
| G-5 | a first frame's buffer at its announced length, as before the review | P-GROW |
| G-7 | room for the rest of the read, not of the frame | P-ALLOC |
| S-9 | the buffer grows at every piece | P-ALLOC, P-GROW |
| E-1 | the end keeps an unfinished message | P-ENDKEEP |
| Q-1 | a take's count not checked for a fixnum | P-QAPI |
| Q-2 | a negative take | P-QAPI |
| Q-3 | a read's start not checked for a fixnum | P-API |
| Q-4 | a read's end not checked for a fixnum | P-API |
| Q-5 | a negative start | P-API |
| S-1 | a delivery does not end the message | P-ONE, P-B2B, *P-CONT*, P-QBYTES, *P-QSTAY*, P-QCOUNT, *P-QWAIT*, *P-QREAD*, *P-TAKEN*, *P-PURE* |
| S-2 | a delivery keeps its count of bytes held | *P-ONE*, *P-B2B*, *P-QBYTES*, *P-QSTAY*, *P-QWAIT*, *P-QREAD*, *P-TAKEN*, *P-PURE*, *P-KEEP* |
| S-3 | a control frame of no payload not answered | P-B2B, P-PING, P-CLOSE0, P-SENDAPI |
| S-4 | a continuation of no payload never ends | P-FRAGS, P-UTF8SPLIT, P-UTF8END |
| S-5 | a first frame of no payload never ends | P-ONE, P-B2B, *P-QCOUNT*, P-ALLOC, P-GROW |
| S-6 | every message begun as binary | P-HELLO, P-ONE, P-FRAG57, P-FRAGS, P-B2B, P-PAIRS, P-CONT, P-PONG, P-CAPFRAG, P-UTF8OK, P-UTF8AT, P-UTF8SPLIT, P-UTF8END, P-AFTER, P-SENDMID, P-QCOUNT, P-QREAD, P-TWO |
| S-7 | the reading goes on past the end | *P-CONT*, *P-UNFIN*, *P-AFTER*, *P-CLOSEMID* |
| S-8 | a binary message's end checked as UTF-8 (equivalent: a binary's checker state is always whole) | none: survives, an equivalent mutant (below) |
| F-1 | frame-control? leaves out a close | FC, *P-CLOSE*, *P-CLOSE123*, *P-CLOSE1*, *P-CODE*, *P-REASON*, P-CLOSEMID, *P-QEND*, *P-TAKEN* |

A key in italics went red through a raise. Every other red was by value, exit 1,
with no harness error.

145 rows, each as named before the run, on the blobs above: 0 mismatches
(`specs.py`, SHA-256 `e267fe0a…` for the first run, `1d6a44a6…` for the last).

**M2's 98 frame mutants and their baseline ran again on this tree,** since the
frame suite gained a check. Each kept its recorded red set. D-6, `control?`
leaving out a close, reddens `frame-control?`'s check too, as named before the
run: 99 rows, 0 mismatches.

Notes:
- **The first run had four mismatches.**
  - **E-1 survived.** The ended connection's check, as first written, compared
    the live heap holding an ended connection with the heap holding a new one,
    measured apart, and allowed less than the fragment's 1,000,000 bytes more.
    The heap moved by about 87 KB between the two, so a kept buffer showed only
    913,336 bytes. The check now measures each connection's footprint, back to
    back, after a warm-up, against half the fragment. E-1 reddens it at
    1,000,240 bytes.
  - Three prediction errors, each an extra red or one fewer. M-63 reddens the
    ended connection's check too: a binary checked as UTF-8 ends the connection
    in its first step, and the check's second read is refused. S-1 leaves
    P-KEEP green: the waiting read fails before it can be kept. S-3 reddens a
    send after the end: an empty close left unanswered leaves the connection
    open.
- **S-8 survives, an equivalent mutant.** It checks a binary's end as UTF-8. A
  binary never feeds the checker, whose state is whole whenever a message
  ends.
- **Every check has its killers, each at least one by value.** Fifteen mutants
  still redden some check through a raise.

## M3.2, step 1 — the server's close, and closes crossing

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05.

The blobs:
- `protocol.sls` 00559db, and `test-protocol.sps` 1fc97be, 59 checks;
- unchanged from M3.1's review: `limits.sls` cdf3ec3, `frame.sls` 1f004d2,
  `test-limits.sps` 16c37e2 and `test-frame.sps` b6c0444.

The runner is M3.1's review's, run on a named tree, three suites a mutant.

### The form, and what it was measured on

"Deliver as before", the recommended (0001's second amendment). Two prototypes of
the core, the step as built, and one that drops data messages once the server's
close is sent and reads what waits at once:

| probe | delivered as before | dropped |
|---|---|---|
| default limits: 16 messages queued, then a 17th and the client's close waiting; the server's close | the client's close unread | the client's 1000 told, cleanly, at once |
| two messages after the server's close, then the client's close | 2 delivered | 0 delivered |
| `protocol.sls`, against M3.1's | +82/-22 | +97/-23 |

The form said 16 messages were queued. The first probe had run with a queue of 2.
It was run again at 16 after the answer, with the same outcome.

The PR shape was decided by form too: "Three stacked PRs", the recommended, one a
bullet of the plan's. Each step's library and tests against the step below:
- step 1: +96/-45 and +141/-2;
- step 2: +21/-6 and +48;
- step 3: +18/-1 and +33.

### The oracles

- **RFC 6455's raw text**:
  - §5.5: a control frame's payload is at most 125 bytes, so a close's reason is
    at most 123.
  - §5.5.1: a close received is answered unless one was sent. Once a close has gone
    each way, the stream closes at once. Two closes may cross.
  - §5.5.2: a ping is answered unless a close has been received.
  - §7.1.2: a close is sent with its code and reason.
  - §7.1.5 and §7.1.6: the code and reason told are the first close received's.
  - §7.1.7: failing sends a close, so a second is never sent.
  - §7.4.1: 1005, 1006 and 1015 are never set in a close.
- **The design's §5**: the events, the actions, and the close deadline named by its
  kind.
- **The form.**
- **websockets 17.2** (a1664f4), read through `gh api`. It answers pings while
  closing (`protocol.py`, `send_pong`, `recv_frame`), and queues data frames in any
  state (`asyncio/connection.py:740-749`). Its queue pauses reading past its high
  water whatever the state (`asyncio/messages.py:266-289`).
- **ws 7.5.10**, from a local checkout. A logging shim of the library recorded every
  connection the suite made, 651, and a script replayed each one into ws's
  WebSocket as a server's, on a fake socket:
  - each read was pushed in the same pieces;
  - a close went in as `ws.close(code, reason)`;
  - the fake socket was closed by its client once ws ended it, as a client's TCP
    close answers a server's.

  Compared: the messages, the pongs and closes written, a failure's code, and the
  code and reason told. 578 answered the same and 35 stepped nothing. The rest, each
  in a named category:

  | count | category |
  |---|---|
  | 18 | ws judges UTF-8 only at a message's end (M3.1) |
  | 14 | ws echoes a close's reason too; ours its code alone (M3.1) |
  | 3 | ws accepts 1012 to 1014 (M3.1) |
  | 2 | M2.1's length forms |
  | 1 | ws answers no ping once its close is sent: `pong()` refuses while closing |

  Of the 50 connections that step a close, 49 answered the same, and the other
  is the ping. No answer disagreed.

### The test-first runs

The step's suite against M3.1's library (132c307): 48 passes, and the 11 new checks
red, each through an event M3.1 did not have.

### The mutants

The new checks' keys:

| key | check |
|---|---|
| C-SEND | the server's close is written with its code and reason, and arms the close deadline… |
| C-123 | a close's reason of 123 bytes, the most a close holds past its code (§5.5), is sent whole… |
| C-REF | a close the server may not send is an assertion naming ws-step, open, closing or ended… |
| C-CROSS | closes crossing (§5.5.1, §7.1.5)… read whole, a byte at a time, and cut at every point |
| C-ANSWER | the client's close answering the server's is told, its code or 1005 for none… |
| C-BADCLOSE | a client's close after the server's that fails its checks fails with no second close… |
| C-FAIL | failing after the server's close writes no second close (§7.1.7)… |
| C-AFTER | after the server's close, a ping is answered… and messages are delivered as before (by form)… |
| C-ENDED1 | once the connection has ended, a close answers nothing… |
| C-API1 | a send once the server's close is sent is an assertion naming ws-step… a close of the wrong shape |
| C-STOP | the server's close while reading is stopped leaves it stopped (by form)… |

**The runs.** The predictions were first named for the whole slice, on its tree:
185 rows, 0 mismatches. It ran again, 0 mismatches each time, after three changes:
- the checks were split one to a bullet;
- the end's shape check gained the rows an end must pass (step 3);
- the retention check came to answer `kept` (step 2).

On this step's tree, 174 rows, 0 mismatches. They are:
- **M3.1's review's 145.**
  - Re-cut where this step rewrote their lines: M-2, M-3, M-8, M-21, M-22, M-27,
    M-65, M-67, M-75, M-76, M-85, M-86 and S-7, each breaking the same property as
    before.
  - E-1 now cuts `end!`'s release of the message alone.
  - M-5, M-6 and M-29 are named for what they now break: 1006 is told by one
    procedure wherever no close came, and an empty close is told by the same
    `clean` as one with a code.
- **This step's 29**, C-1 to C-40 less the eleven whose lines are steps 2's and 3's.

**M3.1's rows whose red sets grew**, by this step's checks. M-29 also reddens M3.1's
P-CLOSE0, since an empty close is told by the same `clean` now. The other 91 rows of
the review's table are red as there.

| # | mutation | red besides |
|---|---|---|
| L-34 | websocket-limits-with ignores its overrides | C-FAIL, C-STOP |
| M-2 | the end does not end the connection | C-FAIL, C-ENDED1, C-STOP |
| M-3 | the end's actions in the reverse order | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-ENDED1, C-STOP |
| M-4 | a failing close's code little-endian | C-ENDED1 |
| M-5 | 1000 told where no close came | C-BADCLOSE, C-FAIL, C-ENDED1 |
| M-6 | told clean where no close came | C-BADCLOSE, C-FAIL, C-ENDED1 |
| M-7 | a failure logged without why | C-BADCLOSE, C-FAIL, C-ENDED1 |
| M-8 | a failure leaves the stream open | C-BADCLOSE, C-FAIL, C-ENDED1 |
| M-9 | 1000 not sendable | C-SEND, C-123, C-REF, C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-AFTER, C-ENDED1, C-API1, C-STOP |
| M-10 | 999 sendable | C-REF |
| M-11 | 1003 not sendable | C-SEND |
| M-12 | 1004 sendable | C-REF |
| M-13 | 1007 not sendable | C-SEND |
| M-14 | 1006 sendable | C-REF |
| M-15 | 1011 not sendable | C-SEND |
| M-16 | 1012 sendable | C-REF |
| M-17 | 3000 not sendable | C-SEND |
| M-18 | 2999 sendable | C-REF |
| M-19 | 4999 not sendable | C-SEND, C-ANSWER |
| M-20 | 5000 sendable | C-REF |
| M-21 | an empty close told 1000 | C-ANSWER |
| M-23 | a close of one byte read as a code | C-BADCLOSE |
| M-24 | a close's code not checked | C-BADCLOSE |
| M-25 | a close's reason not checked | C-BADCLOSE |
| M-28 | a close's reason told from its code on | C-CROSS, C-ANSWER |
| M-29 | a client's close told unclean, an empty one among them | P-CLOSE0, C-CROSS, C-ANSWER, C-ENDED1, C-STOP |
| M-30 | a ping not answered | C-AFTER |
| M-32 | a pong without its ping's payload | C-AFTER |
| M-34 | max-queue messages queued do not stop reading | C-STOP |
| M-36 | no count bound on the queue | C-STOP |
| M-40 | a message's bytes not queued | C-STOP |
| M-41 | a message not counted | C-STOP |
| M-42 | read-stop not answered | C-STOP |
| M-43 | reading not marked stopped | C-STOP |
| M-44 | every data frame ends its message | C-AFTER |
| M-48 | the buffer forgets what it held as it grows (filled) | C-AFTER |
| M-50 | a continuation needs no message | C-FAIL |
| M-55 | a first frame's cap not checked | C-FAIL |
| M-58 | reading goes on past a full queue | C-STOP |
| M-59 | what waits is kept from the read's start | C-STOP |
| M-60 | a refusal's reason not logged | C-FAIL, C-ENDED1 |
| M-61 | a control payload always read into its start | C-CROSS |
| M-67 | a send after the end allowed (now: or once a close is sent) | C-API1 |
| M-75 | read-start though what waits fills the queue again | C-STOP |
| M-76 | read-start after the connection ended | C-STOP |
| M-79 | an event's shape not checked | C-API1 |
| M-83 | a fragmented message of its last frame's kind | C-AFTER |
| M-84 | every message delivered as binary | C-AFTER |
| S-1 | a delivery does not end the message | C-AFTER, C-STOP |
| S-2 | a delivery keeps its count of bytes held | C-AFTER, C-STOP |
| S-3 | a control frame of no payload not answered | C-ANSWER |
| S-6 | every message begun as binary | C-FAIL, C-AFTER |
| S-7 | the reading goes on past the end | C-FAIL |
| F-1 | frame-control? leaves out a close | C-CROSS, C-ANSWER, C-BADCLOSE, C-ENDED1, C-STOP |

**This step's own:**

| # | mutation | red |
|---|---|---|
| C-1 | the end disarms nothing | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-STOP |
| C-2 | the end disarms, armed or not | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE, P-CLOSE123, P-CLOSE0, P-CLOSE1, P-CODE, P-REASON, P-CLOSEMID, P-QEND, P-TAKEN, C-ENDED1 |
| C-3 | the deadline kept armed past the end | none: equivalent here |
| C-5 | a new connection's deadline armed | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE, P-CLOSE123, P-CLOSE0, P-CLOSE1, P-CODE, P-REASON, P-CLOSEMID, P-QEND, P-TAKEN, C-ENDED1 |
| C-6 | failing after the server's close writes a second close | C-BADCLOSE, C-FAIL |
| C-7 | failing never writes a close | P-CONT, P-UNFIN, P-CAP, P-CAPFRAG, P-CAPDEF, P-CAPMAX, P-UTF8AT, P-UTF8END, P-REFUSE, P-AFTER, P-CLOSE1, P-CODE, P-REASON, P-QEND, C-ENDED1 |
| C-8 | the client's close after the server's answered with a close | C-CROSS, C-ANSWER, C-STOP |
| C-9 | a client's close never answered | P-CLOSE, P-CLOSE123, P-CLOSE0, P-CLOSEMID, P-QEND, P-TAKEN, C-ENDED1 |
| C-10 | nothing read once the server's close is sent | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-AFTER, C-STOP |
| C-11 | a read refused once the server's close is sent | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-AFTER |
| C-12 | a send allowed once the server's close is sent | C-API1 |
| C-13 | reading not started again once the server's close is sent | C-STOP |
| C-14 | a close's code not checked for a fixnum | C-REF |
| C-15 | a close's code not checked | C-REF |
| C-16 | a close's reason not checked for a string | C-REF |
| C-17 | a close's reason of 124 bytes let through | C-REF |
| C-18 | a close's reason of 123 bytes refused | C-123, C-REF |
| C-19 | the server's close's code little-endian | C-SEND, C-123, C-CROSS, C-ANSWER, C-AFTER, C-ENDED1, C-STOP |
| C-20 | the server's close's reason not written | C-SEND, C-123, C-ANSWER |
| C-21 | the server's close's reason in Latin-1 | C-123 |
| C-22 | a close once one is sent written again | C-ENDED1 |
| C-23 | a close after the end written | C-ENDED1 |
| C-24 | the server's close leaves the connection open | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-ENDED1, C-API1, C-STOP |
| C-25 | the server's close arms no deadline in its state | C-CROSS, C-ANSWER, C-BADCLOSE, C-FAIL, C-STOP |
| C-26 | the arm left out of the server's close's actions | C-SEND, C-123, C-CROSS, C-ANSWER, C-AFTER, C-ENDED1, C-STOP |
| C-27 | the deadline armed named ping | C-SEND, C-123, C-CROSS, C-ANSWER, C-AFTER, C-ENDED1, C-STOP |
| C-36 | a close of the wrong shape | C-API1 |
| C-39 | a ping not answered once the server's close is sent (ws 7.5.10's way) | C-AFTER |
| C-40 | messages dropped once the server's close is sent (the form's other answer) | C-AFTER, C-STOP |

C-3 is equivalent on this tree: nothing reads the deadline after the end until step
2's passing, which kills it. Every check, 15 in the limits suite and 59 in the
protocol suite, has a killer that reddens it by value.

## M3.2, step 2 — the close timeout

The blobs: `protocol.sls` 4f944ea, and `test-protocol.sps` d98df8d, 63 checks; the
rest as step 1's.

### The oracles

- **The design's §5**: a close not answered in time closes the stream anyway, by its
  deadline's kind. websockets' `close_timeout`, 10 s (the peer survey).
- **RFC 6455 §7.1.5**: with no close received, the code is 1006.
- **ws 7.5.10**, as in step 1, its close timer fired as ws's own does
  (`socket.destroy`): 660 connections. 584 answered the same and 36 stepped
  nothing. 2 are "ours waits for a take; ws reads on", since ws has no queue. The
  rest are the categories of step 1. No answer disagreed.

### The test-first runs

The step's suite against step 1's library (00559db): 59 passes, and the 4 new
checks red.

### Found while writing the mutants

- **C-38**, the deadline's shape unchecked, would have survived the first form of
  the check, its red set named while writing it. The row stepped `(deadline-passed
  now)` on an open connection, which no deadline had armed, so it was refused for
  that reason too. Before the first run, the row was moved to step it while the
  close's deadline is armed, and C-38 reddens it.
- **C-4**, the end keeping the read that waits, reddened the retention check
  through its #f, which prints as a raise does. The check now answers `kept`, so C-4
  reddens it by value.

### The mutants

The new checks' keys:

| key | check |
|---|---|
| C-TIMEOUT | the close timeout (design §5)… a close after it answers nothing |
| C-API2 | a deadline passing with none armed is an assertion naming ws-step… one of the wrong shape while one is armed |
| C-STALL | by default, with 16 messages queued and none taken, the client's close waits behind them until the close timeout… |
| C-KEEPWAIT2 | once the close timeout has ended the connection, it keeps no read that waited for the queue |

On this step's tree, 179 rows, 0 mismatches. They are step 1's 174, E-1 re-cut back
to M3.1's two lines with the read that waits, and this step's 5, whose lines step 1
did not have.

**Rows whose red sets grew** by this step's checks. The other 148 are red as in step
1:

| # | mutation | red besides |
|---|---|---|
| L-2 | the default queue 17 messages | C-STALL |
| M-3 | the end's actions in the reverse order | C-TIMEOUT, C-STALL |
| M-5 | 1000 told where no close came | C-TIMEOUT, C-STALL |
| M-6 | told clean where no close came | C-TIMEOUT, C-STALL |
| M-9 | 1000 not sendable | C-TIMEOUT, C-API2, C-STALL, C-KEEPWAIT2 |
| M-34 | max-queue messages queued do not stop reading | C-STALL |
| M-36 | no count bound on the queue | C-STALL |
| M-41 | a message not counted | C-STALL |
| M-42 | read-stop not answered | C-STALL |
| M-44 | every data frame ends its message | C-TIMEOUT |
| M-58 | reading goes on past a full queue | C-STALL |
| M-79 | an event's shape not checked | C-API2 |
| M-82 | the read's payload unmasked in place | C-KEEPWAIT2 |
| S-1 | a delivery does not end the message | C-STALL |
| S-2 | a delivery keeps its count of bytes held | C-STALL |
| S-3 | a control frame of no payload not answered | C-API2 |
| C-2 | the end disarms, armed or not | C-TIMEOUT, C-STALL |
| C-3 | the deadline kept armed past the end | C-API2 |
| C-5 | a new connection's deadline armed | C-API2 |
| C-10 | nothing read once the server's close is sent | C-API2 |
| C-11 | a read refused once the server's close is sent | C-API2 |
| C-19 | the server's close's code little-endian | C-TIMEOUT, C-STALL |
| C-23 | a close after the end written | C-TIMEOUT |
| C-25 | the server's close arms no deadline in its state | C-TIMEOUT, C-API2, C-STALL, C-KEEPWAIT2 |
| C-26 | the arm left out of the server's close's actions | C-TIMEOUT, C-STALL |
| C-27 | the deadline armed named ping | C-TIMEOUT, C-STALL |

**This step's own:**

| # | mutation | red |
|---|---|---|
| C-4 | the end keeps a read that waits | C-KEEPWAIT2 |
| C-33 | a deadline passing with none armed ends the connection | C-API2 |
| C-34 | the passed deadline disarmed again | C-TIMEOUT, C-STALL |
| C-35 | the close timeout leaves the stream open | C-TIMEOUT, C-STALL |
| C-38 | a deadline of the wrong shape | C-API2 |

Every check, 15 in the limits suite and 63 in the protocol suite, has a killer that
reddens it by value.
