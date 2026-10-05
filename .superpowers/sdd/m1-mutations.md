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
