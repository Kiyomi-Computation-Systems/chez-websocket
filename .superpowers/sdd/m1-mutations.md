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
  512 MiB, so a 32-bit field agrees with the 64-bit one below that. The library
  hashes 60 bytes, and a check would have to hash 512 MiB. That is the scope
  statement: the field is written as RFC 3174 §4 says, and nothing tests its
  top half.
- **No mutant reddens 63, 64 or 65 bytes alone.** The padded copy makes a block's
  end no special case here. The three hold an implementation that pads only its
  last block, as the plan asks.
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
still gets the accept value it computes. B-11 holds the choice.

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
