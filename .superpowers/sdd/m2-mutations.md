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
