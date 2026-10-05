# M1 — mutation log

Every check in M1 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M1.1 — SHA-1

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-05.
Each mutant ran its suite alone on the Makefile's library path. A runner applied
it, compared the checks that went red with the set named before the run, and
restored the tree. Under each SHA-1 mutant it also hashed every vector outside
the suite, to tell a wrong digest from a raise: every one answered a digest.

### The oracles

- **RFC 3174 §7.3's four results** and **RFC 6455 §4.2.2's example digest** come
  from the RFCs' text. A fetch that summarized RFC 3174 garbled TEST3's digest
  (`3C CD 4C DA` for `3C D4 C4 DA`), so each was read from the raw text, then
  checked against the two peers below.
- **The six padding edges** are two peers' digests, which agreed: Perl's
  Digest::SHA 6.02 (`shasum -a 1`) and OpenSSL 3.6.3 (`openssl dgst -sha1`, and
  Python 3.14.5's `hashlib`, which is OpenSSL's here). Byte i of each input is
  i × 37 mod 256.

  ```
  perl -e 'print map { chr($_ * 37 % 256) } 0..N-1' | shasum -a 1
  python3 -c 'import hashlib; print(hashlib.sha1(bytes(i * 37 % 256 for i in range(N))).hexdigest())'
  ```

  | bytes | digest |
  |---|---|
  | 0 | da39a3ee5e6b4b0d3255bfef95601890afd80709 |
  | 55 | c5c6c6489395b389610c07e696a74908840d5be1 |
  | 56 | 9f28a611cdc197211cc44d24deac7fc4e8c52d46 |
  | 63 | 1aad096920c502124f20d608cbd152a49cc94a03 |
  | 64 | 8c378cc64f4bcf0b8279f405ccbf0a0a571e97f2 |
  | 65 | da051c9640eac8ca7925201d97f9a91d2abf6de0 |

### The allocation check's number

The check asserts that hashing ten blocks more allocates 640 bytes more. That is
704 − 64, the padded sizes of 640 bytes and of none (RFC 3174 §4). Its premise
was measured before it was written:
- **A hash allocates three things:** its padded copy, its schedule of 80 words
  and its digest. For the 60-byte key and GUID that is 832 bytes (144 + 656 +
  32), and for a million bytes 1,000,768. Each is its contents and a header,
  rounded up to 16 bytes.
- **The first version also allocated 5,888 bytes a block.** That was 11,776
  more for the 60-byte input's two blocks.
- **Chez 10.4.1 allocates for a call with four or more arguments.** Measured
  over 100,000 calls each:

  | call | bytes per call |
  |---|---|
  | `+` of 4 | 32 |
  | `+` of 5 | 48 |
  | `bitwise-xor` or `bitwise-ior` of 4 | 32 |
  | any of these of 2 or 3 | 0 |

  The schedule's xor of four (64 a block, 2,048 bytes) and the step's sum of
  five (80 a block, 3,840 bytes) make the 5,888. Both are now nested calls of
  three.

The check was stable over 30 runs, and green under `make prod`.

### The mutants

| # | mutation | red |
|---|----------|-----|
| M1-1 | the padded size takes len + 9: a block too many at 55 mod 64 | 55 bytes, alone |
| M1-2 | the padded size takes len + 7: a block too few at 56 mod 64 | 56 bytes, and TEST2 (56 bytes) |
| M1-3 | the length field counts bytes, not bits | every vector but 0 bytes |
| M1-4 | the length field little-endian | every vector but 0 bytes |
| M1-5 | the padding's 1 bit at the byte's other end (`#x01`) | every vector |
| M1-6 | the padding's first byte one place late | every vector |
| M1-7 | the message's words read little-endian | every vector |
| M1-8 | the schedule without its rotation: SHA-0 | every vector |
| M1-9 | the schedule reads W(t−13) for W(t−14) | every vector |
| M1-10 | steps 0–19 lose the NOT: (B AND C) OR (B AND D) | every vector |
| M1-11 | steps 40–59 take parity, not majority | every vector |
| M1-12 | the first function ends a step early (t < 19) | every vector |
| M1-13 | K for steps 40–59 one off: `8F1BBCDD` | every vector |
| M1-14 | H0 one off: `67452300` | every vector |
| M1-15 | a rotation's mask keeps one bit too few | every vector |
| M1-16 | 79 steps, not 80 | every vector |
| M1-17 | a step's sum not masked to 32 bits | every vector |
| M1-18 | H0 not added back after a block | every vector |
| M1-19 | only the first block is hashed | the eight inputs of two blocks or more; TEST1, 0 and 55 bytes stay green |
| M1-20 | the digest's first word little-endian | every vector |
| M1-21 | a step's sum as one `+` of five arguments | the allocation check, alone |
| M1-22 | the schedule's xor as one call of four arguments | the allocation check, alone |
| M1-23 | a rotation shifts before it masks (bignums at 2^60) | the allocation check, alone |
| M1-24 | the length field written as 32 bits | none: survives (a scope statement, below) |
| MI-1 | `sha1.sls` imports `(chezscheme)` too | the audit's check for `sha1.sls` |
| MI-2 | … `(http-server)` too | the same |
| MI-3 | … `(websocket private binding)` too | the same |
| MI-4 | … the facade, `(websocket)`, too | the same |
| MI-5 | … `(only (chezscheme) format)` too | the same |
| MI-6 | … `(rnrs)` wrapped, as `(only (rnrs) car)` | the same |
| MI-7 | `src/` holds no library | exit 2, no assertion ran |
| MI-8 | a `.sls` under `src/` that is not a library | the audit's check for that file; `sha1.sls`'s stays green |

Every red was exit 1 with no harness error, and MI-7's was exit 2, as named
before the run. All were reverted, and `make test` is green afterwards: three
suites, 17 expected passes, every pin ok.

Notes:
- **M1-24 survives by construction.** A length in bits passes 32 bits only at
  512 MiB, so a 32-bit field agrees with the 64-bit one below that. This note
  first said that nothing else of the field went untested; M1.1's review (below)
  found these inputs set only bits 3 to 10, 12, 17 and 19 to 22 of it, so a field
  cut to 23 bits survived as well. The review added an input that sets every bit
  from 3 to 24. Bits 25 to 63, which only inputs of 4 MiB and more set, are the
  scope statement.
- **No mutant reddens 63, 64 or 65 bytes alone.** The padded copy makes a block's
  end no special case here. For an implementation that pads only its last block,
  the three hold its block ends with at most one whole block before them: no
  input has whole blocks followed by a tail of 2 to 63 bytes (M1.1's review).
- **The audit reads, it does not load.** MI-3 and MI-4 name libraries that do not
  exist yet, and the audit refuses them all the same. MI-6 is refused by design:
  an import must name its library plainly.

## M1.2 — base64

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-05.
The runner was M1.1's: each mutant named its red set before the run, the tree
was restored after it, and every input was decoded and encoded again outside
the suite, to tell a wrong answer from a raise.

### The oracles

- **RFC 4648 §10's seven vectors**, from the RFC's raw text.
- **The alphabet's 48 bytes**, whose base64 is §4's Table 1 in order. Three peers
  agreed: Python 3.14.5's `base64` (CPython's binascii), Perl's MIME::Base64 3.16
  and OpenSSL 3.6.3 (`openssl base64 -d`).
- **RFC 6455's keys.**
  - §1.3's example decodes to `the sample nonce`, from the same three peers.
  - §4.1 prints `AQIDBAUGBwgJCgsMDQ4PEC==` for the bytes 1 to 16. Its erratum 3150
    (verified 2012) corrects it to `…PEA==`, since the printed `C` sets bits a
    conforming encoder leaves clear (RFC 4648 §3.5). The three peers encode the
    bytes as the erratum does, and decode the printed key to them.
- **The accept value**, `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`, from RFC 6455 §4.2.2.

### A decode accepts a last digit's set bits

The plan names three refusals: a wrong length, a character outside the alphabet,
and padding anywhere but the end. It does not say what to do with a last digit
whose unused bits are set. RFC 4648 §3.5 lets a decoder refuse such input ("MAY"),
and RFC 6455 does not ask it to. So the decode accepts it, as the plan reads. Four
of the five peers accept RFC 6455 §4.1's printed key:
- **websockets 17.2** decodes with `base64.b64decode(key, validate=True)`, which
  Python 3.14.5 answers with the sixteen bytes (measured);
- **ws 8.22.0** matches `/^[+/0-9A-Za-z]{22}==$/`, true for it in Node 20.10.0
  (measured);
- **coder v1.8.15 and gorilla v1.5.3** decode with Go's `base64.StdEncoding`. Go's
  documentation says only its `Strict` mode requires the bits to be zero.
- **tungstenite v0.30.0 refuses it.** It decodes with `data_encoding::BASE64`, and
  data-encoding's documentation says it checks trailing bits by default.

The accept value hashes the key as sent, so a client whose encoder set the bits
still gets the accept value it computes. B-11 holds the choice for a last digit
before two "=". This note first said B-11 held the choice. M1.2's review (below)
found that nothing held it before one "=": a decode that refused set bits there
passed every check. The review added "Zm/=", and BR-8 holds it.

### The mutants

| # | mutation | red |
|---|----------|-----|
| B-1 | the table swaps `+` and `/` | the alphabet's encode, and the accept value |
| B-2 | the table's `q` is a `Q` | the alphabet's encode, alone |
| B-3 | one byte left: its third digit written, not padded | `f`, `foob` and the bytes 1 to 16, encoded |
| B-4 | two bytes left: their fourth digit written, not padded | `fo`, `fooba` and the accept value, encoded |
| B-5 | the encode's loop runs one group past the end | `""`, `foo`, `foobar` and the alphabet, encoded: each reads past its end and raises |
| B-6 | the decode's length check dropped | the wrong-length refusal, alone (`Z` decodes to nothing; `Zg=` raises) |
| B-7 | a character outside the alphabet decodes as 0 | the alphabet, padding and three-padding refusals |
| B-8 | the decode takes the URL alphabet's `-` and `_` too | the alphabet refusal, alone |
| B-9 | three padding characters counted as padding | the three-padding refusal, alone (`Z===` leaves no room for its byte and raises) |
| B-10 | `=` inside the data decodes as 0 | the padding and three-padding refusals |
| B-11 | a last digit's unused bits must be zero | RFC 6455's client example, as printed, alone |
| B-12 | the decode's size ignores the padding | the six padded decodes |
| B-13 | the decode's second byte shifted by 7, not 8 | every decode of two bytes or more |
| B-14 | a lowercase letter's value one low | every decode but the empty one |
| B-15 | the encode's second digit shifted by 13, not 12 | every encode but the empty one |
| B-16 | the empty string refused | `""` decoded, alone |
| MI-9 | `base64.sls` imports `(chezscheme)` too | the audit's check for `base64.sls` |

Every red was exit 1 with no harness error, as named before the run. All were
reverted, and `make test` is green afterwards: four suites, 42 expected passes,
every pin ok.

Notes:
- **A stub passes five checks.** Against an encode that answered `""` and a decode
  that refused everything, 19 checks failed and 5 passed: the empty encode and
  the four refusals. A decode that refuses everything passes every refusal, so
  each refusal's red comes from a lenient mutant here (B-6 to B-10), and the
  empty encode's from B-5.
- **B-5, B-6 and B-9 redden partly through a raise.** `decoded` answers a byte
  list or `refused`, never `#f`, so a raise cannot pass for a refusal (SRFI-64
  turns a raise into `#f`).

## M1.3 — UTF-8

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-05.
This section holds the suite as it stands after M1.3's review (below), 28 checks.
The runner was M1.2's. Each mutant had the checks it would redden named before
the run, with a set marked "maybe" where I was unsure. The tree was restored
after each run.

### The oracles

- **RFC 3629 §4's grammar**, from the RFC's raw text: each row's first and last
  code point, and each refusal's index, the first byte at which no row can go on.
  Python 3.14.5 encoded each row's edge code points to the bytes the checks use.
- **RFC 3629 §7's four examples**, from its raw text, and §3's surrogate pair for
  U+233B4, `ED A1 8C ED BE B4`.
- **Two incremental decoders**: Python 3.14.5's `codecs` UTF-8 decoder, and Node
  20.10.0's `TextDecoder` with `fatal` and `stream`. Every case of every check went
  through both, a byte at a time and in the check's own pieces: rows, refusals,
  after an "A", splits, pairs of splits, empty pieces, §7's text and the one-call
  check. The cases were read from the test's own tables with Chez's reader.
  Python's per-piece wholeness comes from its buffered bytes. Node's comes from a
  replay of the pieces with a final flush.
  - **Node agreed with every case of every check.**
  - **Python agreed with all but the surrogate cases** (`ED` followed by `A0`–`BF`).
    It refuses those one byte later than the grammar, which allows only `80`–`9F`
    after `ED`. The checks hold the grammar's index.
- **The boundaries in §7's text** (0, 1, 4, 6, 7, 10, 13, 16, 19, 22, 25, 28, 32)
  are Python's character lengths.

### The mutants

U-1 to U-21 are M1.3's own, re-cut on the reviewed library. MI-10 is the import
audit's, which M1.3 first named U-22. R-1 to R-21 come from the review.

| # | mutation | red |
|---|----------|-----|
| U-1 | UTF8-1 ends at `7E` | its row, and the after-"A" check |
| U-2 | UTF8-2 starts at `C1`, an overlong lead | the no-lead and overlong refusals, after "A" |
| U-3 | UTF8-2 ends at `DE` | its row, the tail refusal, after "A", the refusal split, the character split, the empty piece |
| U-4 | `E0`'s first tail from `9F`: an overlong accepted | the tail and overlong refusals, after "A", the refusal split, the empty piece |
| U-5 | the `E1` row ends at `EB` | 9: its row, §7's examples, after "A", the three character splits, the two text checks, the allocation check |
| U-6 | `ED`'s first tail to `A0`: U+D800 accepted | the tail and surrogate refusals, after "A", the refusal split, the empty piece, the one-call check |
| U-7 | the `EE` row is `EF` alone | 7: its row, the tail refusal, after "A", the refusal split, the three character splits |
| U-8 | `F0`'s first tail from `8F`: an overlong accepted | the tail and overlong refusals, after "A", the refusal split, the empty piece |
| U-9 | the `F1` row ends at `F2` | 7: its row, the tail refusal, after "A", the refusal split, the three character splits |
| U-10 | `F4`'s first tail to `90`: U+110000 accepted | the tail and past-U+10FFFF refusals, after "A", the refusal split, the empty piece |
| U-11 | `F4` starts no character | 9: its row, the tail and past-U+10FFFF refusals, the unfinished check, after "A", the refusal split, the three character splits |
| U-12 | a later tail takes any byte from `80` | the tail refusal, after "A", the refusal split, the empty piece |
| U-13 | a two-byte lead needs no tail | 13 |
| U-14 | whole while one byte is still needed | 9: the unfinished check, the refusal split, the three character splits, the two text checks, the range, the one-call check |
| U-15 | a feed reads from 0, not from `start` | 20 |
| U-16 | a feed reads to the bytevector's end, not to `end` | 24 |
| U-17 | a feed starts from `utf8-start`, not the state it is given | 19 |
| U-18 | UTF8-2's tail starts at `81` | its row, after "A", the character split, the empty piece |
| U-19 | a later tail ends at `BE` | 16 |
| U-20 | `need` ors four arguments, its last twice | none: survives, an equivalent mutant (below) |
| U-21 | a state's count read by dividing, `(floor (/ s 65536))` | the allocation check, alone |
| MI-10 | `utf8.sls` imports `(chezscheme)` too | the audit's check for `utf8.sls` |
| R-1 | `EE`/`EF`'s first tail from `7F` | the tail refusal, after "A", the refusal split, the empty piece |
| R-2 | `EE`/`EF`'s first tail to `C0` | the same four |
| R-3 | `F1`–`F3`'s first tail to `C0` | the same four |
| R-4 | past a piece's first byte, `E0`–`F4` leads classed by length only | after "A", and the one-call check |
| R-5 | past a piece's first byte, `E0` and `F1`–`F4` refused | after "A", alone |
| R-6 | a piece of two or more bytes entered mid-character: its first byte unchecked | the refusal split, the empty piece |
| R-7 | a piece entered mid-character: its later bytes unchecked | the same two |
| R-8 | a piece entered mid-character: a refusal past its first byte answers the state before it | the same two |
| R-9 | a piece entered and left mid-character answers the state it was given | 13: the seven three- and four-byte rows, §7's examples, the unfinished check, after "A", the pair split, the byte-at-a-time text, the allocation check |
| R-10 | an empty piece widens an unfinished state's range to `80`..`BF` | the empty piece, alone |
| R-11 | an empty piece adds one to an unfinished state's count | the empty piece, alone |
| R-12 | no range assertion | the range assertion check, alone |
| R-13 | the range assertion does not bound `end` | the range assertion check, alone |
| R-14 | `utf8-whole?` compares with `=`, raising on `#f` | the one-call check, alone, through a raise |
| R-15 | a feed given `#f` steps it, raising | the one-call check, alone, through a raise |
| R-16 | a feed allocates a cell per call | the allocation check, alone |
| R-17 | U-21's division, and `E1`–`EC` refused: the mebibyte refused at byte 1 | 12, the allocation check among them |
| R-18 | `E0`'s first tail from `A1` | 6: its row, the unfinished check, after "A", the three character splits |
| R-19 | `ED`'s first tail to `9E` | 5: its row, after "A", the three character splits |
| R-20 | `F0`'s first tail from `91` | 6: its row, the unfinished check, after "A", the three character splits |
| R-21 | `F4`'s first tail to `8E` | 6: its row, the unfinished check, after "A", the three character splits |

Every red was exit 1 with no harness error, and every red set matched the one
named before the run, with nothing in a "maybe" set red. All were reverted. `make
test` is green afterwards: five suites, 71 expected passes, every pin ok.

**Which reds come through a raise.** SRFI-64 turns a raise inside a check into
`#f`. No check's actual value can be `#f` here, so a failing check whose actual
value is `#f` raised. A copy of `(ws-testing)`, kept outside the repository,
printed each one. It was shown first on a probe of one check that raises and one
that mismatches. Across all 43 mutants, only R-14 and R-15 redden through a raise,
both the one-call check, whose property is that the API does not raise. Every
other red is a compared value.

Notes:
- **M1.3's first run had four mismatches,** named before it.
  - U-3, U-13 and U-19 each reddened one check more than I had named: a check's
    inputs held the byte they changed. They were prediction errors.
  - U-20 survived as first written, `hi 0`, and again as `hi hi`. Chez's
    optimizer inlines `need`, whose ranges are constants at every call, and folds
    them: `expand/optimize` shows `(need 2 #xA0 #xBF)` as the constant 172223. So
    no four-argument call is left to allocate: the mutant is equivalent.
- **M1.3's review** (a code review of PR #7) found mutants the first suite missed:
  - widened first tails for `EE`/`EF` and `F1`–`F3`;
  - leads classed by their place in a piece;
  - refusals split across pieces, and pieces entered and left mid-character;
  - an empty piece that widened or extended an unfinished state;
  - a per-call allocation, cancelled by a baseline that was itself a feed;
  - an allocating feed refused early, whose 0 a failure could produce.

  Each is one of R-1 to R-17 above. Under each, the first suite's check of that
  property stayed green. It also found that the `E0`, `ED` and `F0` rows had no
  mutant of their own: R-18 to R-21 are theirs, and `F4`'s.
- **The byte-at-a-time check no longer reddens through a raise.** In the first
  suite it fed a refusal back into the library, which raised under five mutants.
  Now a refusal ends the feeding in the test's helper, and the library answers
  `#f` for `#f`.
- **A stub passed eleven of the first suite's checks**: the nine rows, §7's
  examples and the allocation check. Each has its own mutant above.

## M1.1's review — SHA-1

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-05.
A code review of the merged SHA-1 code (53fa639, PR #4) reported 15 findings. All
were in the suite, the records and the import audit; the library's digests were
right. Each mutant below ran its suite with the mutated library or harness first on
the library path, a copy kept outside the repository, and each audit mutant ran in
a scratch copy of the tree. Every red set was named before the run.

### What changed

- **The library** works its words with R6RS's fixnum operations and rotates with
  `fxrotate-bit-field`. A 60-byte hash went from 4,384 to 2,789 ns, and a mebibyte
  from 33.8 to 21.2 ms (three alternating runs, each the least of seven trials).
  It allocates the same.
- **`tests/test-sha1.sps`** has 16 checks: four new, and one replaced.
  - 4 MiB less a byte, whose length in bits sets every bit of the length field
    from 3 to 24. Its digest, `4cb28b705337e4487cc93d13c3e69882120b0750`, is three
    peers', which agreed: Python 3.14.5's `hashlib`, OpenSSL 3.6.3 and Perl's
    Digest::SHA 6.02.
  - Two digests held at once, the message left as it was, and a hash run inside
    another from a timer interrupt.
  - What a hash allocates, at 0, 55, 56, 64, 640 and 128,000 bytes. It must equal
    what the test allocates for RFC 3174's three objects: the padded message (§4),
    the 80-word schedule (§6.1) and the 20-byte digest. This replaces M1.1's
    ten-block slope, which a cost paid once a call cancelled.
- **`(ws-testing)`** exports the measure both suites now share, `allocated`:
  - the least of three counts, each made from its own depth of the stack, 100
    frames apart;
  - less an empty thunk's count, since a reading allocates 160 bytes of its own;
  - after a check of the counter: a bytevector 1,024 bytes longer must count
    1,024 bytes more.

  A failed check's line is now followed by what it expected and what it got, and
  a harness error names what was raised.
- **The import audit** reads every form in a file, and every extension Chez looks
  for a library under. It passes over names that begin with ".", and refuses
  `(rnrs eval)`.

### Why three depths

A count also takes in a new stack segment, about 64 KiB, when the measured call's
stack reaches past the end of the current one. That happens from some depths
only, and at every call from them. The probe ran M1.1's check (ten blocks against
one) k frames deeper, for each k from 0:

| library | measure | depths that read other than 640 |
|---|---|---|
| main's | M1.1's: one count | 75 of 40,001, reading 66,416 or 66,544 |
| main's | three counts, all from one depth | 15 of 9,001 |
| main's | three counts, from depths 100 frames apart | 0 of 40,001 |
| this branch's | the same | 0 of 40,001 |

The review had proposed three counts from one depth, which the second row refuses.

### The mutants

"The 14 digest checks" are the twelve vectors, the two held digests and the
nested hash.

| # | mutation | red |
|---|----------|-----|
| M1-1 | the padded size takes len + 9 | 55 bytes, and the allocation check |
| M1-2 | the padded size takes len + 7 | TEST2, 56 bytes, the held digests, the allocation check |
| M1-3 | the length field counts bytes, not bits | the 14 digest checks but 0 bytes |
| M1-4 | the length field little-endian | the same 13 |
| M1-5 to M1-16 | the padding's bit, its place, the words' order, the schedule's rotation and its W(t−14), each function, K, H0, the rotation's field one bit short, 79 steps | each, the 14 digest checks |
| M1-17 | a step's sum not masked to 32 bits | all 16, through a raise: `fx+` overflows |
| M1-18 | H0 not added back after a block | the 14 digest checks |
| M1-19 | only the first block is hashed | the 11 digest checks of two blocks or more |
| M1-20 | the digest's first word little-endian | the 14 digest checks |
| M1-21 | a step's sum as one generic `+` of five | the allocation check, alone |
| M1-22 | the schedule's xor as one generic `bitwise-xor` of four | the allocation check, alone |
| M1-23 | a rotation by the generic `bitwise-rotate-bit-field` | the allocation check, alone |
| M1-24 | the length field written as 32 bits | none: survives (M1.1's note, corrected) |
| P-1 | a digest buffer shared by every call | the held digests, the allocation check |
| P-2 | a schedule shared by every call | the nested hash, the allocation check |
| P-3 | a hash zeroes its message after copying it | the message check, alone |
| A-1 | a four-argument `+` in `pad` | the allocation check, alone |
| A-2 | the digest built through a list | the allocation check, alone |
| A-3 | a 64 KiB scratch buffer a hash | the allocation check, alone |
| A-4 | a block loop that keeps a frame a block | the allocation check, alone: 391,104 bytes at 128,000, for 128,768 |
| L-23 | the length field masked to 23 bits | 4 MiB, alone |
| L-24 | the length field masked to 24 bits | 4 MiB, alone |
| LB-3 to LB-31 | bit k of the length field stuck at 0 | k = 3 to 24: 4 MiB, and each check whose input sets bit k; for 11, 13 to 16, 18, 23 and 24, 4 MiB alone. k = 25 to 31: none, the scope statement |
| W-1 | the five block-end sums unmasked, so a hash raises | all 16, through a raise, exit 1 |
| C-1 | a dead counter | the SHA-1 suite: exit 2, its allocation check's expected value raising "the counter does not count a 1,024-byte bytevector"; the UTF-8 suite: its allocation check, through a raise |
| C-2 | a dead counter, left unchecked | none, in either suite: why the counter is checked |
| C-3 | an empty thunk's count not taken off | the UTF-8 suite's allocation check, reading 160 for 0; the SHA-1 suite's cancels |
| C-4 | one count, from one depth | none: survives at the suite's own depth (the probe above) |
| C-5 | three counts, all from one depth | none: survives at the suite's own depth (the probe above) |
| MI-1 to MI-10 | M1.1's to M1.3's import mutants | each, as recorded: its file's check; MI-7, exit 2 |
| IA-1 | a form after `sha1.sls`'s library | the audit's check for `sha1.sls` |
| IA-2 | an impure `sha1.ss` beside `sha1.sls` | the audit's check for `sha1.ss`, which it now reads |
| IA-3 | `sha1.sls` imports `(rnrs eval)` too | the audit's check for `sha1.sls` |
| IA-4 | an editor's lock file, `.#sha1.sls`, a dangling link | none: passed over, as it should be |
| U-1 to U-21, R-1 to R-21 | M1.3's, against the shared measure | each, as recorded in M1.3's table; U-20 survives |

Every red was exit 1 with no harness error, but C-1's exit 2 and MI-7's, as named
before the run. A failed check now prints its actual value, and a raise shows as
`#f`: only M1-17, W-1, C-1 (UTF-8), R-14 and R-15 redden through one. `make test`
is green afterwards: five suites, 75 expected passes, every pin ok.

Notes:
- **The first run had one mismatch**, named before it, and it ran against three
  counts from one depth. M1-17 was predicted to redden the 14 digest checks, as
  under M1.1's generic arithmetic, where an unmasked sum grew a bignum. Under
  fixnum operations it overflows within a block and `fx+` raises, as the header
  says it would, so all 16 checks go red. It was a prediction error. Every other
  red set matched. After the change to three depths, all 127 matched, M1-17 with
  its corrected set.
- **C-2, C-4 and C-5 survive by design.** C-2 shows what the counter's check is
  for. C-4 and C-5 measure at a depth the suite is not near a segment's end at,
  and the probe shows the depths that are.
- **The nested hash needs no thread.** A timer interrupt 500 ticks into TEST4's
  eleven blocks hashes "abc" from inside it. Under P-2 the outer digest comes out
  `30fb65e6…`, and the check also holds that the interrupt came before the outer
  hash returned.

## M1.2's review — base64

Platform: Darwin arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-05.
A code review of the merged base64 code (cbf2a7d, PR #6) reported six findings.
The library's answers were right. Two findings were gaps in the suite that
mutants passed through: the edges of the decode's character ranges, and a set
last digit before one "=". Four were in the library: the alphabet written twice,
generic operations called out of line, an encode through a string port, and
short-group tests run on every group. Each mutant below ran the suite with the
mutated library first on the library path, a copy kept outside the repository.
MI-9 ran the audit in a scratch copy of the tree. Every red set was named before
the run.

### What changed

- **The library.**
  - The decode's values are `digits` read the other way: a 128-entry table built
    from the string when the library loads. The alphabet is written once.
  - A group is put together with `fx*` by powers of two and `fxior`, and split
    with `fxarithmetic-shift-right` and `fxand`. In Chez 10.4.1's assembly, the
    generic shifts and `fxarithmetic-shift-left` are calls, and `fx*` by a
    constant is inline, with an overflow test.
  - The encode writes into a string of its known length, filled with "=".
  - Whole groups come first, then the one short group, if any.
  - It imports `(rnrs mutable-strings)` for `string-set!`, which `(rnrs)` leaves
    out. The audit allows it, as it does any `(rnrs ...)` but `eval`.

  An encode of a 20-byte digest went from 216 to 87 ns, and a decode of a key
  from 222 to 126 ns. At 3,000 bytes, an encode went from 26.8 to 11.6 µs and a
  decode from 36.0 to 21.5 µs. Each is the lower of two alternating runs, and
  each run the least of seven trials.
- **`tests/test-base64.sps`** has 27 checks, three of them new.
  - Each character beside a run of the alphabet in ASCII is refused: `*`, `,`,
    `.`, `:`, `@`, `[`, `` ` `` and `{`. So are DEL and U+0080, either side of
    ASCII's end. The runs are `+`, `/` to `9`, `A` to `Z` and `a` to `z`.
  - "Zm/=" decodes to "fo", whose last digit sets both of its unused bits. The
    bytes are three peers': Python 3.14.5's `base64` with `validate=True`, Perl's
    MIME::Base64 3.16 and OpenSSL 3.6.3.
  - What each allocates: encodes of 0, 1, 2, 3, 16, 20, 48 and 3,000 bytes, and
    decodes of strings of as many bytes. Each must equal what the test allocates
    for the string or bytevector of RFC 4648 §4's length.

### The mutants

Test-first, against main's library, with the review's suite:

| # | mutation | red |
|---|----------|-----|
| BR-0 | none: main's library as it is | the allocation check, alone: the encode's string port |
| BR-1 | the capitals' run starts at `@` | the edge check, through a raise (`@` takes −1), and the allocation check |
| BR-2 | the capitals' run ends at `[` | the edge check, and the allocation check |
| BR-3 | the small letters' run starts at `` ` `` | the same |
| BR-4 | the small letters' run ends at `{` | the same |
| BR-5 | the numerals' run ends at `:` | the same |
| BR-6 | the numerals' run starts at `/` | the alphabet's decode, "Zm/=", and the allocation check |
| BR-7 | a last digit's unused bits must be zero before one "=" | "Zm/=", and the allocation check |

Against the review's library:

| # | mutation | red |
|---|----------|-----|
| B-1 | the table swaps `+` and `/` | the alphabet both ways, and the accept value |
| B-2 | the table's `q` is a `Q` | the alphabet both ways, both RFC 6455 keys, and the allocation check |
| B-3 | one byte left: its third digit written, not padded | `f`, `foob` and the bytes 1 to 16, encoded |
| B-4 | two bytes left: their fourth digit written, not padded | `fo`, `fooba` and the accept value, encoded |
| B-5 | the encode's loop runs one group past its whole ones | every encode, and the allocation check, through a raise |
| B-6 | the decode's length check dropped | the wrong-length refusal, alone, through a raise |
| B-7 | a character outside the alphabet decodes as 0 | the alphabet, edge, padding and three-padding refusals |
| B-8 | the decode takes the URL alphabet's `-` and `_` too | the alphabet refusal, alone |
| B-9 | three padding characters counted as padding | the three-padding refusal, alone, through a raise |
| B-10 | `=` decodes as 0 | the padding and three-padding refusals |
| B-11 | a last digit's unused bits must be zero before two "=" | RFC 6455's client example, as printed, alone |
| B-12 | the decode's size ignores the padding | the seven padded decodes |
| B-13 | a whole group's second byte shifted by 7, not 8 | the seven decodes with a whole group |
| B-13b | a short group's second byte shifted by 7, not 8 | the three decodes that end in one "=" |
| B-14 | every digit's value one high | every decode but the empty one |
| B-15 | a whole group's second digit shifted by 13, not 12 | the seven encodes with a whole group |
| B-15b | a short group's second digit shifted by 13, not 12 | five of the six encodes with a short group (below) |
| B-16 | the empty string refused | `""` decoded, alone |
| MI-9 | `base64.sls` imports `(chezscheme)` too | the audit's check for `base64.sls` |
| BR-8 | a last digit's unused bits must be zero before one "=" | "Zm/=", alone |
| BR-9 | the ASCII test lets U+0080 through | the edge check, alone, through a raise |
| BR-10 | the table one short, DEL past its end | the edge check, alone, through a raise |
| BR-11 | no ASCII test before the table | the alphabet and edge refusals, through a raise |
| BR-12 | the encode's string handed back through a string port | the allocation check, alone |
| BR-13a | a decode's whole group ors its four values with `bitwise-ior` | none: equivalent (below) |
| BR-13 | a decode's whole group put together with the generic shifts and one four-argument `bitwise-ior` | the allocation check, alone |
| BR-14a | an encode's whole group ors its three values with `bitwise-ior` | none: equivalent (below) |
| BR-14 | an encode's whole group put together with the generic shifts and one three-argument `bitwise-ior` | none: survives, the scope statement (below) |
| BR-15 | the decode table built at every lookup | the allocation check, alone |
| BR-16 | the decode's whole groups take a padded last group too | the seven padded decodes, and the allocation check, through a raise |
| BR-17 | a padded last group not decoded | the seven padded decodes |
| BR-18 | a short last group not encoded | the six encodes with a short group |
| BR-19 | the encode's whole groups stop a group early | the seven encodes with a whole group |
| BR-20 | the encode's string not filled with "=" | the six encodes with a short group |
| BR-21 | a padded last group always reads its third digit | the four decodes that end in two "=", and the allocation check, through a raise |
| BR-22 | the encode's string has no room for a short last group | the six encodes with a short group, and the allocation check, through a raise |

M1.2's B-1 to B-16 and MI-9 are re-cut for the new library. B-13 and B-15 are
split in two, since a whole group and a short one now have their own code. B-14
was a range's offset, and is now a value in the table. Every red was exit 1 with
no harness error, as named before the run: 44 runs, 8 against main's library and
36 against the review's. `make test` is green afterwards: five suites, 78
expected passes, every pin ok.

Notes:
- **The first runs had eight mismatches, from two prediction errors.**
  - Main's library fails the allocation check unmutated (BR-0), so every
    test-first mutant reddens it too. The first run's sets left it out, so all
    seven mismatched. With it named, all eight matched.
  - BR-13 was first cut as BR-13a and predicted red. A four-argument
    `bitwise-ior` allocates 32 bytes a call when Chez cannot type its
    arguments. Here Chez's type pass knew three of them came from `fx*`, tested
    the fourth with `fixnum?`, and compiled `fxior`, which allocates nothing
    (`expand/optimize`). BR-13 is the re-cut, with the generic shifts, whose
    results it cannot type. BR-14a is equivalent the same way, since all three
    of its arguments are known.

  After the re-cuts, all 44 matched.
- **The suite missed these before the review.** BR-1 to BR-5 and BR-7 redden
  only checks the review added, so M1.2's suite passed them. The review ran four
  of them (BR-1, BR-2, BR-4 and BR-5) and BR-7 against it. The sixth edge, BR-6,
  was held already: `/` is in the alphabet, and decodes as 51 under it.
- **The decode allocated only its bytes already.** On main's library, the
  allocation check's decode half matched. The red was the encode's port: an
  encode of nothing allocated 160 bytes, for 0, and one of 3,000 bytes 33,008,
  for 16,016.
- **B-15b leaves the bytes 1 to 16 green.** Their last byte, 16, gives the same
  second digit shifted by 12 or by 13.
- **BR-14 survives by design.** The generic shifts and a three-argument
  `bitwise-ior` are calls, but they allocate nothing. The checks hold what a
  call allocates, not whether it runs inline. The speed above is measured, not
  checked.
