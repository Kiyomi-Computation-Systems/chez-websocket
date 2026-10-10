# M5 — mutation log

Every check in M5 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M5 — the Autobahn lane (decision 0008)

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09; the lane's runs also on Linux 6.12.76-linuxkit aarch64 in Docker
(Ubuntu 24.04, libuv 1.48.0, the prod shim), Autobahn under emulation. The gate is
`tests/ws-autobahn.sls` (blob 420378a), its suite `tests/test-autobahn.sps`, 20 checks
(blob effc39e); the ratchet `tests/autobahn/verdicts.txt` (blob 07d9715).

The gate's runner is M4's, pointed at this suite: each mutant alone, applied to a
copy of `(ws-autobahn)` put first on the library path, the checks that went red
compared with the set named before the run, the tree left as it was. A pre-flight
checks that every cut matches its text once and keeps its paren balance.

The lane's mutants run the whole lane: a copy of the tree with one edit, its echo
server on Linux in Docker (or, for `run.sh`, its own copy run from the tree on macOS),
Autobahn's 301 cases against it, and the tree's own gate on the run's index.

### The oracles

- **RFC 8259**: §6's number grammar, §7's escapes and its G clef, §13's examples.
- **Autobahn 25.10.1's index**, as `fuzzing.py` writes it and as the lane's runs wrote
  it: the agent, its cases sorted as strings, three spaces a level, null for a close
  code the server did not send (7.3.1's, copied into the suite's fixture).
- **Autobahn's verdicts** on Linux: the ratchet's 301 lines, written from a run's index
  by a script of their own, not by the gate.
- **chez-http-server's ratchet** (its decision 0008): both ways, a promotion a reviewed
  diff.

### The test-first runs

- **Before the library:** `Exception: library (ws-autobahn) not found`, exit 255, as
  named (hashed `185009ce`).
- **The first library** passed all 18 checks of that draft.
- **On real runs** (named before, but the command that would have hashed it failed to
  parse, so it reached disk only after: recorded unhashed). The 13 Linux runs at 16 MiB
  passed; a Linux run at 1 MiB failed on the 24 over-cap cases alone; a macOS run that
  stopped short failed on its 162 missing cases and 3.4, with the hint; a complete macOS
  run failed on 4.2.5 alone; a missing index was status 2. All as written.
- **The ratchet's alternatives** (by form, "List what was measured"), named and hashed
  before (`e8754bd0`): against the exact-only library, 20 checks, 9 green (7 JSON, 2
  index) and the 11 named red (2 ratchet, 8 gate, 1 harness), exit 1.

### Found by writing the mutants

- **Gaps, found drafting:** an object's separator (`{"a"x1}`), a high surrogate followed
  by something other than `\u`, a low half out of range, tab and CR as whitespace, an
  empty case field, a spec of two servers, a non-integer close code, and a behaviorClose
  that is not a string. Each became a vector before the first run.
- **One gap, found running:** J-6, an object's name not checked for its opening quote,
  survived run 2: the vector added for it, `{1"": 2}`, is refused anyway. `{x": 2}`
  reaches the guard; the mutant reads it as `{"": 2}`.
- **Value killers added after run 3:** J-NUM and R-PARSE went red only through raises.
  J-28 (numbers read exact) and R-11 (the ratchet in reverse) redden them by value.

### The runs

- **Run 1: void.** A harness error before any row ran: eleven cuts kept a `\"` the
  library's text does not have. Fixed, expectations unchanged.
- **Run 2: 64 rows, 3 mismatches.**
  - J-5 also reddened G-ORDER: that fixture's run starts with a NON-STRICT case, so
    reversed members turn its tally. A prediction error.
  - R-2 left R-REF green: every R-REF text is refused before the blank line the mutant
    chokes on. A prediction error.
  - J-6 survived: the gap above.
- **Run 3: 64 rows, 0 mismatches.**
- **Run 4: 66 rows (65 mutants and the baseline), 0 mismatches.** The table below.

### The gate's mutants (run 4)

| id | mutation | red |
|---|---|---|
| BASE | no edit | none |
| J-1 | whitespace without tab | J-LIT |
| J-2 | whitespace without CR | J-LIT |
| J-3 | expect takes any character | J-REF |
| J-4 | an empty object not seen | J-LIT, I-AGENT, I-REF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-HARNESS |
| J-5 | members in reverse | J-OBJ, J-ARR, I-AGENT, G-ORDER |
| J-6 | a member's name not checked for its quote | J-REF |
| J-7 | elements in reverse | J-OBJ, J-ARR |
| J-8 | control characters in a string | J-REF |
| J-9 | no \/ escape | J-ESC |
| J-10 | \b as tab | J-ESC |
| J-11 | \n as CR | J-ESC |
| J-12 | a pair without its #x10000 | J-ESC |
| J-13 | a high surrogate's \u not checked | J-REF |
| J-14 | a low surrogate's range not checked | J-REF |
| J-15 | a lone low surrogate taken | J-REF |
| J-16 | lowercase hex misread | J-ESC |
| J-17 | uppercase hex misread | J-ESC, J-REF |
| J-18 | a leading zero takes digits | J-REF |
| J-19 | a fraction of no digits | J-REF |
| J-20 | an exponent's + not read | J-NUM |
| J-21 | E not an exponent | J-NUM |
| J-22 | no minus | J-ARR, J-NUM |
| J-23 | false read as true | J-OBJ, J-LIT |
| J-24 | null read as nil | J-LIT, I-AGENT, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CLOSE, G-MISSING |
| J-25 | trailing text taken | J-REF |
| J-26 | the end told as a character | G-HARNESS |
| J-27 | the index told one late | J-WHERE, G-HARNESS |
| J-28 | numbers read exact | J-ARR, J-NUM |
| R-1 | comment lines read | R-PARSE, R-REF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-HARNESS |
| R-2 | blank lines read | R-PARSE, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-HARNESS |
| R-3 | four fields or more | R-REF |
| R-4 | an empty field taken | R-REF |
| R-5 | an empty alternative taken | R-REF |
| R-6 | the first code alternative alone checked | R-REF |
| R-7 | a code of letters | R-REF |
| R-8 | none not a code | R-PARSE, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-HARNESS |
| R-9 | a case twice taken | R-REF |
| R-10 | skipped lines not counted | R-REF |
| R-11 | the ratchet in reverse | R-PARSE, G-CHANGED, G-EMPTY |
| S-1 | a spec of servers past one | G-HARNESS |
| S-2 | a server with no agent | G-HARNESS |
| I-1 | the agent not looked for | I-REF, G-HARNESS |
| I-2 | other agents taken | I-REF |
| I-3 | cases as an array | I-REF |
| I-4 | a case that is a number | I-REF |
| I-5 | no behavior taken | I-REF |
| I-6 | a behaviorClose number taken | I-REF |
| I-7 | null read as null | I-AGENT, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CLOSE, G-MISSING |
| I-8 | a code any number | I-REF |
| G-1 | behavior not compared | G-ALTFAIL, G-CHANGED |
| G-2 | behaviorClose not compared | G-ALTFAIL, G-CLOSE |
| G-3 | the code not compared | G-ALTFAIL, G-CHANGED |
| G-4 | a missing case not told | G-MISSING, G-EMPTY |
| G-5 | a case only the run has not told | G-MISSING |
| G-6 | the ratchet tallied | G-PASS, G-ORDER, G-ALT |
| G-7 | the tally's order turned | G-PASS, G-ORDER, G-ALT |
| G-8 | an empty ratchet gated | G-HARNESS |
| G-9 | the hint never said | G-MISSING, G-EMPTY |
| G-10 | the hint always said | G-ALTFAIL, G-CHANGED, G-CLOSE |
| G-11 | one differences | G-ALTFAIL, G-CLOSE |
| G-12 | a difference passes | G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY |
| G-13 | a harness error is 1 | G-HARNESS |
| G-14 | nothing caught while reading | G-HARNESS |
| G-15 | a pass is 1 | G-PASS, G-ORDER, G-ALT |
| G-16 | cases compared in order | G-ORDER, G-MISSING, G-EMPTY |

Every check is reddened by value by at least one row: J-OBJ by J-5, J-ARR by J-7,
J-LIT by J-23, J-ESC by J-10, J-NUM by J-28, J-REF by J-3, J-WHERE by J-27, R-PARSE
by R-11, R-REF by R-3, I-AGENT by J-5, I-REF by I-2, G-PASS by G-15, G-ORDER by G-16,
G-ALT by G-7, G-ALTFAIL by G-1, G-CHANGED by G-3, G-CLOSE by G-2, G-MISSING by G-5,
G-EMPTY by G-4, G-HARNESS by G-13.

### The lane's mutants

Named and hashed before the run (`5f33e698`); the gate's status, and the cases it named.

| id | mutation | named | the gate |
|---|---|---|---|
| L-1 | `utf8.sls`: the ED row takes A0-BF, so surrogates pass | 6.3.1, 6.3.2, 6.20.1-7, 6.21.1-8 (17) | 1; those and 7.5.1 (18) |
| L-2 | `frame.sls`: reserved bits never refused | 3.1-3.7 | 1; exactly |
| L-3 | `protocol.sls`: a client's close code not checked | 7.9.1-9, 7.13.1, 7.13.2 | 1; exactly |
| L-4 | `echo.sps`: text sent back as binary | 1.1.1-8 among them, 1.2.x not | 1; 118, as named |
| L-5 | `run.sh`: the 16 MiB cap not set | the 24 over 1 MiB, FAILED with 1009 or none | 1; exactly (second try) |
| L-6 | `protocol.sls`: a ping answered with a ping | 2.1-2.4, 2.6, 2.9-2.11, 5.6-5.8 | 1; those and 5.19, 5.20 |

- **L-1 and L-6: prediction errors.** 7.5.1's close reason holds a surrogate; 5.19 and
  5.20 put pings between fragments.
- **L-5's first try: void.** On macOS the run stopped short at 6.20.4, a connection to
  the echo server timing out, before 9.*; the gate was red for that, not the cap. Its
  second try ran whole.
