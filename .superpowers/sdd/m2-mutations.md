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
