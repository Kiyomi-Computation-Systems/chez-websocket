# M2 — mutation log

Every check in M2 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M2.1, step 1 — the header

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The suite is `tests/test-frame.sps` as this step leaves it, 16
checks (blob 408b556). The library is `src/websocket/frame.sls` (blob fbe3456):
the header decoder, `frame-read-header!` and what it answers. M2.1 was built
whole, then cut in two steps. This one was proved in a scratch worktree of main
with its files laid in. A runner applied each mutant alone, compared the checks
that went red with the set named before the run, and left the tree as it was:
- a library mutant to a copy of the library, put first on the library path;
- a suite mutant to a copy of the suite, run in its place;
- the audit's mutant to a scratch copy of the tree.

### The oracles

- **RFC 6455's raw text.** §5.2's framing, §5.1's rule that a client masks every
  frame, §5.5's control frames, and §5.7's examples. A refusal's index is the
  first byte with which no frame a client may send begins.
- **The suite's own headers.** It builds them by §5.2. Unless its headers at the
  length forms' edges are the ones written out by hand, the suite stops with a
  provenance failure, exit 3.
- **Node's ws 7.5.10, a server's decoder** (Node 20.10.0), from a project's
  `node_modules` on this machine; nothing was downloaded. Two other projects
  carry it, with the same `receiver.js` (SHA-1 `42a9f03f`).
  - A shim of `(websocket frame)` logged every call the suite made: 3,441
    decoders.
  - ws was fed each decoder's bytes in the same pieces, as a server with no
    extension and no cap. Its answers were compared with ours at the level ws
    answers: whole messages, pings, pongs, closes and refusals.
  - A stream that begins with a continuation was fed to both after an empty
    binary frame, not final, so that ws had a message to continue.

  | decoders | what ws answered |
  |---|---|
  | 2,593 | the same: 132 with the same messages and control frames (each with an empty payload), 2,461 with nothing whole yet and nothing refused |
  | 49 | the same refusal, for the same reason, with 1002: 31 unmasked, 18 a control frame over 125 bytes |
  | 60 | the same refusal, for the same reason, with 1002, once given one byte more: 28 an unknown opcode, 26 a reserved bit, 6 a control frame not final |
  | 62 | nothing: ws accepts a length not in its shortest form |
  | 34 | 1009 where ours answers 1002, for a 64-bit length with its top bit set: ws caps a length at 2^53 − 1; 20 of them once given the rest of the length field |
  | 643 | 1009 for a length past 2^53 − 1, which ours reads and leaves to the protocol's cap |

  **No answer disagreed.** ws judges a header only once it holds two bytes, and a
  64-bit length once it holds all eight. Where both refused a stream fed a byte
  at a time, both refused at the same index: byte 1, for an unmasked frame (16)
  and a control frame over 125 bytes (12).

### The test-first runs

- **No library:** `Exception: library (websocket frame) not found`, exit 255.
- **A stub that decodes nothing:** all 16 checks red.

### The mutants

| # | mutation | red |
|---|----------|-----|
| D-0 | none: the library as it is | none: 16 passes |
| D-1 | a reserved bit not checked | the reserved-bit refusals, alone |
| D-2 | RSV1 alone checked | the same |
| D-3 | an unknown opcode not checked | the unknown-opcode refusals, alone |
| D-4 | opcode 0xB taken for a pong | the same |
| D-5 | a control frame not final not checked | the not-final refusals, alone |
| D-6 | a close not taken for a control frame | the not-final and over-125 refusals, and the refusals split |
| D-7 | an unmasked frame not checked | §5.7's unmasked frames, the unmasked refusals, the refusals split, and a refusal's finality, through a raise |
| D-8 | a control frame's length not checked | the over-125 refusals, and the refusals split |
| D-9 | a control frame of 126 bytes let through | the same |
| D-10 | a control frame of 125 bytes refused | the four header checks (below) |
| D-11 | 126 read as a 7-bit length | the four header checks, the length forms' edges, the 16-bit refusals, and the refusals split |
| D-12 | 127 read as a 16-bit length | the four header checks, the length forms' edges, the 64-bit and top-bit refusals, and the refusals split |
| D-13 | a 7-bit length read in six bits | the four header checks, and the length forms' edges |
| D-14 | a 16-bit length under 126 not checked | the 16-bit refusals, and the refusals split |
| D-15 | a 16-bit 126 refused | the four header checks, and the length forms' edges |
| D-16 | a 16-bit 125 let through | the 16-bit refusals, and the refusals split |
| D-17 | a 16-bit length's first byte weighed 128 | the four header checks, and the length forms' edges |
| D-18 | a 64-bit length's top bit not checked | the top-bit refusals, and the refusals split |
| D-19 | a 64-bit length's first byte of 0x7F refused | the four header checks, and the length forms' edges |
| D-20 | the top bit looked for in the second byte | the four header checks, the length forms' edges, the top-bit refusals, and the refusals split |
| D-21 | a 64-bit length under 65,536 not checked | the 64-bit refusals, and the refusals split |
| D-22 | a 64-bit length under 65,536 checked a byte late | the same |
| D-23 | a 64-bit length's sixth byte checked alone | the four header checks: 2^32's sixth length byte is zero |
| D-24 | a 64-bit length's bytes weighed 255 | the four header checks, and the length forms' edges |
| D-25 | a 64-bit length summed with fixnum operations | the same, through a raise: 2^63 − 1 overflows |
| D-26 | a 64-bit length under 65,536 refused as top-bit | the 64-bit refusals, and the refusals split |
| D-28 | a header whole after three key bytes | the four header checks, and the length forms' edges |
| D-35 | a header read with a payload unfinished | none: survives this step (below) |
| D-37 | a header read's range not checked | the same |
| D-39 | a refusal not final | a refusal's finality, alone |
| D-40 | a refusal's code 1007 | all eleven refusal checks |
| D-47 | a refusal answered at the index of the byte before it | the same |
| D-41 | FIN read from the sixth bit | the four header checks, and the length forms' edges |
| D-42 | a ping read as a pong, and a pong as a ping | the four header checks |
| T-2 | the suite writes a 16-bit length least significant byte first | the provenance check: exit 3, no check run |
| MI-11 | `frame.sls` imports `(chezscheme)` too | the audit's check for `frame.sls` |

"The four header checks" are every kind of header at each length form's edges,
and a header split at every byte, at every pair of bytes, and with an empty piece
inside. They go red together under every mutant that reddens one of them. "All
eleven refusal checks" are §5.7's unmasked frames, the eight kinds, the refusals
split, and a refusal's finality.

37 rows, each as named before the run. Every red was exit 1 with no harness
error, but T-2's provenance failure, exit 3. Every suite was green afterwards on
this step's tree: six suites, 95 expected passes.

Notes:
- **D-35 and D-37 survive this step.** Each mutates one of a header read's
  assertions: a read while a payload is unfinished, and a range outside its
  bytevector. The checks that redden them, reads out of turn and ranges, come
  with the payload read in step 2, and both are red there.
- **The mutants are the whole slice's, on this step's tree.** Each red set here
  is the one named for the whole suite (step 2's table), narrowed to this step's
  sixteen checks. The mutants of the payload read are step 2's alone.
- **Every check has its killers.** Each of the 16 went red under at least one
  mutant. Only D-7's finality red and D-25's header reds are through a raise;
  those checks also go red by value, under D-39 and D-13.

## M2.1, step 2 — the payload

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The suite is `tests/test-frame.sps` as M2.1 ends it, 30 checks
(blob ba760b4). The library (blob 5f866cf) adds `frame-read-payload!`, which
unmasks a payload into a destination the caller gives it. The runner was step
1's.

### What this step changed in the suite

- `in-pieces` reads a payload with `frame-read-payload!`, where step 1 ended the
  feeding at its first byte, and `merged` joins a frame's payload pieces into
  one. So each of step 1's checks runs through changed helpers, and every mutant
  of both steps ran again here, on this step's tree.
- The provenance check holds the suite's masked frames to §5.7's bytes too.
- 14 checks are new: §5.7's masked text and pong, the refusals after a frame,
  the six payload checks, the API's four, the bytes left as they were, two
  decoders, and the allocation check.

### The oracles

- **RFC 6455's raw text.** §5.2's framing, §5.3's masking, §5.1's rule that a
  client masks every frame, §5.5's control frames, and §5.7's examples. A
  refusal's index is the first byte with which no frame a client may send
  begins.
- **The suite's own frames.** It builds them by §5.2 and §5.3, and they are
  checked against the RFC before any check runs. Unless its masked text and pong
  are §5.7's bytes, and its headers at the length forms' edges are the ones
  written out by hand, the suite stops with a provenance failure, exit 3.
- **Node's ws 7.5.10, a server's decoder** (Node 20.10.0), from a project's
  `node_modules` on this machine; nothing was downloaded. Two other projects
  carry it, with the same `receiver.js` (SHA-1 `42a9f03f`).
  - A shim of `(websocket frame)` logged every call the suite made: 4,034
    decoders, with the allocation check left out, since the shim allocates.
  - ws was fed each decoder's bytes in the same pieces, as a server with no
    extension and no cap. Its answers were compared with ours at the level ws
    answers: whole messages, pings, pongs, closes and refusals.
  - ws unmasks in place, so each piece was copied before it was fed.
  - A stream that begins with a continuation was fed to both after an empty
    binary frame, not final, so that ws had a message to continue.

  | decoders | what ws answered |
  |---|---|
  | 3,128 | the same: 662 with the same messages and control frames, 2,466 with nothing whole yet and nothing refused |
  | 62 | the same refusal, for the same reason, with 1002: 38 unmasked, 24 a control frame over 125 bytes |
  | 90 | the same refusal, for the same reason, with 1002, once given one byte more: 42 an unknown opcode, 39 a reserved bit, 9 a control frame not final |
  | 67 | nothing: ws accepts a length not in its shortest form |
  | 37 | 1009 where ours answers 1002, for a 64-bit length with its top bit set: ws caps a length at 2^53 − 1; 21 of them once given the rest of the length field |
  | 643 | 1009 for a length past 2^53 − 1, which ours reads and leaves to the protocol's cap |
  | 2 | 1002 for a continuation with no message begun, a message's rule and so the protocol's, before the frame's fault ours refuses |
  | 5 | none: API checks whose call raised before it was logged |

  **No answer disagreed.** ws judges a header only once it holds two bytes, and a
  64-bit length once it holds all eight. Where both refused a stream fed a byte
  at a time, both refused at the same index: byte 1, for an unmasked frame (16)
  and a control frame over 125 bytes (12).

### The test-first runs

- **Step 1's library:** `Exception: attempt to reference unbound identifier
  frame-read-payload!`, exit 255.
- **Step 1's library with a payload read that reads nothing:** step 1's 16
  checks green, and all 14 new ones red. The bytes left as they were go red only
  because the read goes nowhere; D-43 and W-4 redden that check by value.

### The mutants

| # | mutation | red |
|---|----------|-----|
| D-0 | none: the library as it is | none: 30 passes |
| D-1 | a reserved bit not checked | the reserved-bit refusals, and the refusals after a frame |
| D-2 | RSV1 alone checked | the same |
| D-3 | an unknown opcode not checked | the unknown-opcode refusals, and the refusals after a frame |
| D-4 | opcode 0xB taken for a pong | the same |
| D-5 | a control frame not final not checked | the not-final refusals, and the refusals after a frame |
| D-6 | a close not taken for a control frame | the not-final and over-125 refusals, the refusals split and after a frame |
| D-7 | an unmasked frame not checked | §5.7's unmasked frames, the unmasked refusals, the refusals split and after a frame, and a refusal's finality, through a raise |
| D-8 | a control frame's length not checked | the over-125 refusals, the refusals split and after a frame |
| D-9 | a control frame of 126 bytes let through | the same |
| D-10 | a control frame of 125 bytes refused | the four header checks (below) |
| D-11 | 126 read as a 7-bit length | the four header checks, the length forms' edges, the 16-bit refusals, the refusals split and after a frame, frames back to back both ways, §5.7's long messages, and the allocation check |
| D-12 | 127 read as a 16-bit length | the four header checks, the length forms' edges, the 64-bit and top-bit refusals, the refusals split and after a frame, §5.7's long messages, and the allocation check |
| D-13 | a 7-bit length read in six bits | the four header checks, and the length forms' edges |
| D-14 | a 16-bit length under 126 not checked | the 16-bit refusals, the refusals split and after a frame |
| D-15 | a 16-bit 126 refused | the four header checks, the length forms' edges, frames back to back both ways, and the allocation check |
| D-16 | a 16-bit 125 let through | the 16-bit refusals, the refusals split and after a frame |
| D-17 | a 16-bit length's first byte weighed 128 | the four header checks, the length forms' edges, and §5.7's long messages |
| D-18 | a 64-bit length's top bit not checked | the top-bit refusals, the refusals split and after a frame |
| D-19 | a 64-bit length's first byte of 0x7F refused | the four header checks, and the length forms' edges |
| D-20 | the top bit looked for in the second byte | the four header checks, the length forms' edges, the top-bit refusals, the refusals split and after a frame |
| D-21 | a 64-bit length under 65,536 not checked | the 64-bit refusals, the refusals split and after a frame |
| D-22 | a 64-bit length under 65,536 checked a byte late | the same |
| D-23 | a 64-bit length's sixth byte checked alone | the four header checks: 2^32's sixth length byte is zero |
| D-24 | a 64-bit length's bytes weighed 255 | the four header checks, the length forms' edges, §5.7's long messages, and the allocation check |
| D-25 | a 64-bit length summed with fixnum operations | the four header checks, and the length forms' edges, through a raise: 2^63 − 1 overflows |
| D-26 | a 64-bit length under 65,536 refused as top-bit | the 64-bit refusals, the refusals split and after a frame |
| D-27 | the key's bytes stored a place off | §5.7's masked frames, the refusals after a frame, every payload check, a destination without room, two decoders, and the allocation check |
| D-28 | a header whole after three key bytes | the same, and the four header checks and the length forms' edges |
| D-29 | the key's place not reset at a header | frames back to back both ways, and the allocation check |
| D-30 | the key's place not carried from a read to the next | the payloads split and a byte at a time, frames back to back both ways, §5.7's long messages, two decoders, and the allocation check |
| D-31 | a payload's bytes left not counted down | §5.7's masked frames, the refusals after a frame, the payloads split and a byte at a time, frames back to back both ways, §5.7's long messages, reads out of turn, and the allocation check |
| D-32 | a payload read takes all the bytes given | the refusals after a frame, frames back to back, §5.7's long messages, the bytes left as they were, and the allocation check, the last four through a raise |
| D-33 | a destination's room not checked | a destination without room, alone |
| D-34 | a negative place taken | the same |
| D-35 | a header read with a payload unfinished | reads out of turn, alone |
| D-36 | a payload read with none left | the same |
| D-37 | a header read's range not checked | ranges, alone |
| D-38 | a payload read's range not checked | the same |
| D-39 | a refusal not final | a refusal's finality, alone |
| D-40 | a refusal's code 1007 | all twelve refusal checks |
| D-47 | a refusal answered at the index of the byte before it | the same |
| D-41 | FIN read from the sixth bit | §5.7's masked frames, the four header checks, the length forms' edges, the refusals after a frame, the payloads split and a byte at a time, frames back to back both ways, §5.7's long messages, and two decoders |
| D-42 | a ping read as a pong, and a pong as a ping | §5.7's masked frames, the four header checks, frames back to back both ways, and two decoders |
| D-43 | the bytes after the last whole word unmasked in place, then copied | the bytes left as they were, a destination without room, and the allocation check |
| D-44 | one key for every decoder | two decoders, alone |
| D-45 | a payload read copies its key | the allocation check, alone |
| D-46 | a payload byte unmasked through a list of the key | the same |
| W-1 | the key word's second byte weighed 512 | §5.7's masked frames, the refusals after a frame, the payloads split, a destination's place, frames back to back, §5.7's long messages, a destination without room, and the allocation check |
| W-2 | the key word not turned to the payload's offset | the payloads split, frames back to back, and §5.7's long messages |
| W-3 | words read and written most significant byte first | as W-1 |
| W-4 | words unmasked in place, then copied | the bytes left as they were, a destination without room, and the allocation check |
| W-5 | no word path: every byte one at a time | none: survives, the scope statement (below) |
| T-1 | the suite masks with the key a place off | the provenance check: exit 3, no check run |
| T-2 | the suite writes a 16-bit length least significant byte first | the same |
| MI-11 | `frame.sls` imports `(chezscheme)` too | the audit's check for `frame.sls` |

"The four header checks" are every kind of header at each length form's edges,
and a header split at every byte, at every pair of bytes, and with an empty piece
inside. They go red together under every mutant that reddens one of them. "All
twelve refusal checks" are §5.7's unmasked frames, the eight kinds, the refusals
split and after a frame, and a refusal's finality.

56 rows, each as named before the run. Every red was exit 1 with no harness
error, but T-1 and T-2's provenance failures, exit 3. `make test` is green
afterwards: six suites, 109 expected passes, every pin ok.

Notes:
- **The first run had one mismatch, a prediction error.** D-32's set left out
  "the bytes a decoder reads are left as they were". The mutant reads the rest of
  the stream as one payload: 209 bytes, where that check gives a destination of
  200, so the room's assertion raises. With it named, the run matched.
- **D-35 and D-37, which survive step 1, are red here**, under reads out of turn
  and ranges.
- **The first runs were on the library before its word path.** The word path
  came after them (below), and every mutant ran again on the new library: D-43
  and D-46 now reach only the bytes after the last whole word, D-45's cut was
  made again for its `let*`, and W-1 to W-5 are the word path's own.
- **W-5 survives by design.** Without the word path, every byte is unmasked one
  at a time, and the answers are the same. The checks hold what a read answers,
  not how fast. The speed is measured, not checked.
- **Every check has its killers.** Each of the 30 went red under at least one
  mutant whose red set was named before the run. The provenance check went red
  under T-1 and T-2, and the audit's check for `frame.sls` under MI-11. Only D-7's
  finality red, D-25's header reds and D-32's four are through a raise; each of
  those checks also goes red by value under another mutant.

### The word path

A payload is unmasked four bytes at a time: read as one little-endian word, xored
with the key turned to the payload's offset, and written back. Chez 10.4.1
compiles `bytevector-u32-ref`, `bytevector-u32-native-ref` and
`bytevector-u32-set!` as calls out of line (`$assembly-output`), and still the
word path was the fastest of three shapes. Each figure is the mean of two runs,
each the mean of four timed runs after a warm-up:

| unmasking | 1 MiB in one piece | 100,000 frames of 5 bytes | 64 KiB a byte a piece |
|---|---|---|---|
| a byte at a time | 4.64 ns a byte | 61.0 ns a frame | 15.7 ns a byte |
| a byte at a time, four to a turn | 3.04 | 60.0 | 16.7 |
| a word at a time, the key word built at every read | 1.86 | 55.5 | 21.2 |
| a word at a time, the key word built only for a read of a whole word (kept) | 1.85 | 55.8 | 16.7 |

A frame's header costs about the same in all four. A read of fewer than four
bytes builds no key word, so a payload fed a byte at a time costs 16.7 ns a byte,
where building the word at every read cost 21.2.

## M2.2 — the encoder

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The suite is `tests/test-frame.sps`, 40 checks (blob 61e6285). The
library (blob 52e0afc) adds `frame-encode`, which makes a server's frame whole in
a bytevector of its own. The runner was M2.1's, with the 10 new checks named.

### What this step changed

- **The library.** `frame-encode`, and `check-range`, which the decoder's reads
  share: it now checks for a bytevector and two fixnums first, so anything but a
  range of a bytevector is an assertion naming the caller. Before, a string was
  refused by `bytevector-length`, and an index of `0.0` passed, to be refused by
  a fixnum operation.
- **The suite.** It builds a server's unmasked headers by §5.2 too, and the
  provenance check holds them to §5.7's unmasked frames and to the edges written
  out by hand. 10 checks are new: §5.7's frames, the edges, every kind at each
  edge, the decode of each encode, a range, three refusals, the payload left as
  it was, and the allocation check.
- **The decode of each encode** runs the decoder, so M2.1's mutants ran again
  here, their red sets named anew.

### The oracles

- **RFC 6455's raw text.** §5.7's unmasked frames a server sends: "Hello" as text
  (`81 05 48 65 6c 6c 6f`) and as a ping (`89 05 …`), and the headers of the
  256-byte and 64 KiB binary messages (`82 7E 01 00`, `82 7F 00 00 00 00 00 01 00
  00`). §5.2's length forms, §5.1's rule that a server masks no frame, and §5.5's
  125 bytes for a control frame.
- **The suite's own frames**, held to those before any check runs, or the suite
  stops with a provenance failure, exit 3. To decode an encode, the suite masks
  it first, with its own masking, which the same check holds to §5.7's: the
  decoder refuses an unmasked frame (§5.1).
- **Chez's own sizes.** An encode should allocate what `make-bytevector`
  allocates for the frame's length, as base64's check does for its string.
- **Node's ws 7.5.10, a server's encoder** (Node 20.10.0, the same copy as
  M2.1's; `sender.js` SHA-1 `0d370839`). A shim of `(websocket frame)` logged
  every `frame-encode` the suite made, the allocation check left out, since the
  shim allocates: 81 encodes, 32 different kinds and payloads, of 0, 1, 5, 12,
  125, 126, 127, 256, 65,535 and 65,536 bytes. ws's `Sender.frame` was given each
  kind and payload, final, unmasked, without extension.

  | calls | what ws answered |
  |---|---|
  | 81 | the same bytes |
  | 4 | a control frame over 125 bytes, which ours refuses: ws's `Sender` refuses it too, `ping` and `pong` with "The data size must not be greater than 125 bytes", `close` with "The message must not be greater than 123 bytes" for its reason; at 125 bytes it sends all three, headers `89 7d`, `8a 7d` and `88 7d` |
  | 4 | a kind ours refuses (a continuation, `reserved`, `#f`, 1): ws's methods take no kind |
  | 7 | a range or payload ours refuses: no counterpart |

  **No answer disagreed.** ws writes a 64-bit length as four zero bytes and 32
  bits (`writeUInt32BE(0, 2)`, then the length at 6), which no payload a test
  can hold tells apart from ours (E-18).

### The test-first runs

- **M2.1's library:** `Exception: attempt to reference unbound identifier
  frame-encode`, exit 255.
- **A stub that answers an empty bytevector and refuses nothing:** 31 passes and
  9 red, as named before the run. The decoder's 30 stay green, and so does "an
  encode leaves its payload's bytevector as it was", since a stub writes nothing;
  E-21 and E-23 redden it by value.
- **The first library run** had the allocation check red from a suite bug: its
  expected side built the frame's list inside the measured thunk. With the
  length taken outside it, the library passed all 40, and the stub, run again,
  reddened the same 9.

### The mutants

M2.1's 55 mutants and its baseline ran again on this tree, each with the red set
M2.1, step 2 records, but for these:
- **D-0**, the baseline: 40 passes.
- **The decode of each encode** is red too under D-10, D-11, D-12, D-13, D-15,
  D-17, D-24, D-27, D-28, D-31, D-41, D-42, W-1 and W-3: each misreads a frame
  the encoder makes.
- **D-6** reddens the control frames refused too: `control?` is the encoder's as
  well.
- **D-9 and D-10** were cut again: `(fx>? n 125)` is in the encoder too, so
  their cut takes the decoder's clause around it.

| # | mutation | red |
|---|----------|-----|
| E-1 | a text frame's opcode a binary frame's | §5.7's frames, every kind, the decode, and a range |
| E-2 | a ping's opcode a pong's | §5.7's frames, every kind, and the decode |
| E-3 | a close's opcode a ping's | every kind, and the decode |
| E-4 | a binary frame's opcode a text frame's | §5.7's frames, the edges, every kind, the decode, and a range |
| E-5 | a pong's opcode a ping's | every kind, and the decode |
| E-6 | a continuation encoded, with opcode 0 | the kinds refused, alone |
| E-7 | any other kind encoded as binary | the same |
| E-8 | FIN clear | §5.7's frames, the edges, every kind, the decode, and a range |
| E-9 | RSV1 set | the same |
| E-10 | the mask bit set with a 7-bit length | §5.7's frames, the edges, every kind, and a range |
| E-11 | the mask bit set with a 16-bit length | §5.7's frames, the edges, and every kind |
| E-12 | 126 in 7 bits | the edges, every kind, and the decode |
| E-13 | 125 in 16 bits | the same |
| E-14 | 65,536 in 16 bits | §5.7's frames, the edges, every kind, the decode, the payload left as it was, and the allocation check, through a raise: the 16-bit write refuses 65,536 |
| E-15 | 65,535 in 64 bits | the edges, every kind, the decode, and the allocation check |
| E-16 | a 16-bit length least significant byte first | §5.7's frames, the edges, every kind, and the decode |
| E-17 | a 64-bit length least significant byte first | the same |
| E-18 | a 64-bit length as ws writes it, four zero bytes and 32 bits | none: survives, the scope statement (below) |
| E-19 | a 64-bit length announced as 16-bit | §5.7's frames, the edges, every kind, and the decode |
| E-20 | the payload copied from the bytevector's start, not the range's | a range, alone |
| E-21 | the copy's two bytevectors swapped | §5.7's frames, every kind, the decode, a range, and the payload left as it was |
| E-22 | the payload's length taken as the range's end | a range, alone, through a raise |
| E-23 | the payload cleared once copied | a range, and the payload left as it was |
| E-24 | a control frame's length not checked | the control frames refused, alone |
| E-25 | a control frame of 126 bytes encoded | the same |
| E-26 | a control frame of 125 bytes refused | every kind, the decode, the payload left as it was, and the allocation check, through a raise |
| E-27 | the encoder's range not checked | the ranges refused, alone |
| E-28 | a bytevector not checked for | the same |
| E-29 | a start not checked for a fixnum | the same |
| E-30 | a negative start taken | the ranges refused, and the decoder's ranges |
| E-31 | a start after the end taken | the same |
| E-32 | an end past the bytevector taken | the same |
| E-33 | the frame allocated twice | the allocation check, alone |
| E-34 | the whole bytevector's payload copied before it is encoded | the same |
| T-3 | the suite writes an unmasked 16-bit length least significant byte first | the provenance check: exit 3, no check run |
| T-4 | the suite sets the mask bit in an unmasked header | the same |
| T-5 | the suite's unmasked 126, written by hand, least significant byte first | the same |

"§5.7's frames" is the check of §5.7's unmasked frames, byte for byte; "the
edges", the length forms at their edges, unmasked; "every kind", every kind a
server sends at each length form's edges; "the decode", a decode of each encode,
masked first; and "a range", a payload from a range of its bytevector. "The
ranges refused" is the encoder's check, and "the decoder's ranges" M2.1's.

93 rows, each as named before the run, on the blobs above: 0 mismatches. Every
red was exit 1 with no harness error, but the five provenance failures, exit 3.
`make test` is green afterwards: six suites, 119 expected passes, every pin ok.

Notes:
- **The first run had one mismatch, an equivalent mutant.** E-34 was first cut
  as `(apply frame-encode (list …))`, and stayed green: Chez's optimizer makes
  that the direct call (`expand/optimize` shows it), so it allocated nothing.
  Cut again as a copy of the payload, it reddened the allocation check alone. The
  rows were then run again on the final blobs, after a change to comments only.
- **E-18 survives by design.** A 64-bit length's first four bytes are zero for
  every payload under 2^32 bytes, and no test holds 4 GiB. ws writes them so.
- **The decode's own masking hides a set mask bit** (E-10, E-11): it sets that
  bit itself. The byte checks catch both.
- **E-12 and E-13 change a frame's size by two bytes**, and Chez allocates both
  sizes alike, in 144 bytes, so the allocation check stays green. Their header
  bytes catch them.
- **Every check has its killers.** Each of the 10 new checks went red under at
  least one mutant whose red set was named before the run, and each by value:
  through a raise are only E-14's six, E-22's and E-26's four. The decoder's
  ranges have three killers more, E-30 to E-32, and the provenance check three,
  T-3 to T-5.

## M2.2's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-05. The owner's `/code-review high` on #14 found ten things, all fixed on
the owner's "fix all", on a branch stacked on #14. The suite is 41 checks (blob
cf6181f), and the library blob 80b9faa. The runner was M2.2's, with the checks'
new names.

### The findings and their fixes

| # | finding | fix |
|---|---------|-----|
| 1 | `check-range`'s `(fixnum? end)` was held by no check | both range checks pass a non-fixnum end; the decoder's passes a non-fixnum start and a string too |
| 2 | a close of one byte was encoded, though a close's body is empty or begins with its two-byte code (§5.5.1) | refused, as an assertion naming `frame-encode`, by a new check; the suite encodes a close of two bytes where it encoded one of one |
| 3 | the allocation check measured no range | it measures each frame again from a range, with bytes before and after it |
| 4 | `opcode` held a second copy of `kinds` | the opcode is found in `kinds`, the one table |
| 5 | E-21's reds rested on bytes the frame never wrote | cut again with the frame filled with zeros first |
| 6 | the suite's encoder tables repeated `kinds` and `data-lengths` | derived from them |
| 7 | the allocation check built each frame's list to count it | its size comes from its header's length and its payload's |
| 8 | the README said the codec writes the server's frames | it builds them |
| 9 | the 125-byte limit was written twice | `control-max`, which the decoder and the encoder read; cp0 folds it (`expand/optimize` shows `(fx>? n 125)`) |
| 10 | the length's form was decided twice | once: the second byte's seven bits and how many bytes of length follow, written with `bytevector-uint-set!`, which allocates nothing on fixnums (probed: 0 B over 100,000 calls of 2 and 8 bytes) |

### The test-first runs

- **The review's suite against #14's library:** 40 passes and 1 red, the close of
  one byte, as named before the run.
- **The gaps of findings 1 and 3, as mutants of #14's library.** E-45 (the end
  not checked for a fixnum) and E-46 (a range's payload copied out first) were
  green under #14's suite, 40 passes each. Under the review's, E-45 reddened both
  range checks, and E-46 the allocation check. Each also reddened the close of
  one byte, which that library encodes.
- **With the fixes:** 41 passes.

### The oracles

ws 7.5.10 again, through the shim: 99 calls, 81 encodes and 18 refusals of ours.
All 81 are the same bytes as ws's, 32 different kinds and payloads, of 0, 1, 2,
5, 12, 125, 126, 127, 256, 65,535 and 65,536 bytes. Of the refusals:
- 4 are the control frames over 125 bytes, which ws's `Sender` refuses too.
- 2 are the closes of one byte. ws's `Sender.close` writes a two-byte code before
  any reason, or nothing (`sender.js`, lines 110 to 130), so it never sends one.
- 4 are kinds and 8 are ranges or payloads, with no counterpart.

### The mutants

99 rows, each red set named before the run, on the blobs above: 0 mismatches,
on the first run. A check of every cut, made before the run, found D-8's stale:
its 125 is `control-max` now. It was cut again before any row ran.

M2.1's rows are as M2.2 records them, but for these:
- **D-8, D-9 and D-10** are cut on `control-max`.
- **D-42** no longer reddens the decode of each encode. The table is one, so a
  ping written as a pong is read as a ping again. §5.7's frames and every kind
  go red instead.

Of M2.2's rows, E-1 to E-5 are retired with the `case` they cut, and E-17 is
merged into E-16: the length is one write now. E-6, E-7, E-10 to E-16, E-18,
E-19, E-21 and E-23 to E-26 are cut again on the review's code, each with the
same fault. E-22 now reddens the close of one byte and the allocation check too:
its payload runs past a range's bytevector. These are new:

| # | mutation | red |
|---|----------|-----|
| E-35 | text and binary swapped in the one table | §5.7's masked frames, the four header checks, the length forms' edges, the refusals after a frame, the payloads split and fed a byte at a time, frames back to back both ways, §5.7's long messages, two decoders; and §5.7's frames, the edges, every kind and a range. Not the decode, whose round trip agrees |
| E-36 | the search stops before the pong | every kind, the decode, the payload left as it was, and the allocation check, through a raise |
| E-37 | a 16-bit length announced as 64-bit | §5.7's frames, the edges, every kind, and the decode |
| E-38 | a 16-bit length written in eight bytes | the same, and the allocation check |
| E-39 | the control limit 126, read and written | the over-125 refusals, the refusals split and after a frame, and the control frames refused |
| E-40 | the control limit 124, read and written | the four header checks, every kind, the decode, the payload left as it was, and the allocation check |
| E-41 | a close of one byte encoded | the close of one byte, alone |
| E-42 | a close of two bytes refused, and of one encoded | the close of one byte, every kind, the decode, the payload left as it was, and the allocation check |
| E-43 | an empty close refused too | every kind, the decode, the payload left as it was, and the allocation check, through a raise |
| E-44 | a ping or a pong of one byte refused too | the same |
| E-45 | an end not checked for a fixnum | the decoder's ranges, and the ranges refused |
| E-46 | a range's payload copied out first | the allocation check, alone |

Notes:
- **E-18 still survives by design**, cut on `bytevector-uint-set!`: four zero
  bytes and 32 bits, as ws writes a 64-bit length.
- **Every check has its killers, and each goes red by value under one.** The
  close of one byte has three: E-22, E-41 and E-42. Through a raise are E-14's
  six, E-22's range and allocation, and the four of E-26, E-36, E-40, E-42, E-43
  and E-44 each; every one of those checks also goes red by value under another.
