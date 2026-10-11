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

## M5's review (2026-10-10)

The /code-review (xhigh) of #60-#63 reported fourteen findings; "fix all", with two forms
(decision 0008's amendment). Platform as above; the gate is `tests/ws-autobahn.sls` (blob
805737b), its suite `tests/test-autobahn.sps`, 24 checks (blob 447d325); `run.sh` (blob
d51e3de) and its suite `tests/test-autobahn-run.sps`, 9 checks (blob adde458).

### The test-first runs

- **Before the fixes**, named and hashed (`fc3ed607`): the gate's suite stopped at load,
  `attempt to reference unbound identifier text-lines`, exit 255.
- **Stage 1** (`045a773f`): the old library, `text-lines` stubbed as the suite's old splitter
  and `gate-main` raising. 24 checks: the 9 named green (7 JSON, 2 index), the other 15 red,
  exactly.
- **`run.sh`'s suite on the old `run.sh`** (`153213c8`): all 7 checks of that draft red, as
  named, each on `PORT: parameter null or not set`.
- **Re-gated with the whole-verdict ratchet** (`0a5e1b14`): all 180 flip-run verdicts listed;
  the 13 Linux runs at 16 MiB and the 3 complete macOS ones passed; the 2 that stopped short
  failed with the counted hint; the 1 MiB run failed on its 24.

### Found by writing the mutants

- **A redundant guard:** `(pair? (cdr more))` after a `|` changed no outcome, since the next
  verdict's length check refuses the same lines with the same message. Taken out.
- **Two gaps in `run.sh`'s suite:** a fixed port passes every check but two runs at once, and
  the cleanup trap mattered only to a run that ends early with its server alive. R-TWO and
  R-TERM were added for them. The second showed the trap carried on after a signal; it now
  exits, and the exit stops the server.
- **The tally rewritten twice:** first as a fold that was no plainer, then on `unique`.

### The gate's mutants

Run 1: 83 rows (82 mutants and the baseline), 0 mismatches (specs hashed `8b776301`). The JSON
rows keep their cuts, re-predicted for the changed checks; the rest are cut anew.

| id | mutation | red |
|---|---|---|
| BASE | no edit | none |
| J-1 | whitespace without tab | J-LIT |
| J-2 | whitespace without CR | J-LIT |
| J-3 | expect takes any character | J-REF |
| J-4 | an empty object not seen | J-LIT, I-AGENT, I-REF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN, G-HARNESS, G-MAIN |
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
| J-24 | null read as nil | J-LIT, I-AGENT, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CLOSE, G-MISSING, G-MAIN |
| J-25 | trailing text taken | J-REF |
| J-26 | the end told as a character | G-HARNESS |
| J-27 | the index told one late | J-WHERE, G-HARNESS, G-MAIN |
| J-28 | numbers read exact | J-ARR, J-NUM |
| R-1 | comment lines read | R-PARSE, R-CRLF, R-REF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN, G-HARNESS, G-MAIN |
| R-2 | blank lines read | R-PARSE, R-CRLF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN, G-HARNESS, G-MAIN |
| R-3 | a CR kept | T-LINES, R-CRLF |
| R-4 | a line after the last LF | T-LINES, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN, G-HARNESS, G-MAIN |
| R-5 | an empty case taken | R-REF |
| R-6 | a verdict of two fields | R-REF |
| R-7 | an empty field in a verdict | R-REF |
| R-8 | a verdict's code unchecked | R-REF |
| R-9 | any separator | R-REF |
| R-10 | a verdict listed twice taken | R-REF |
| R-11 | a case twice taken | R-REF |
| R-12 | none not a code | R-PARSE, R-CRLF, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN, G-HARNESS, G-MAIN |
| R-13 | a code of letters | R-REF |
| R-14 | skipped lines not counted | R-REF |
| R-15 | the ratchet in reverse | R-PARSE, R-CRLF, G-CHANGED, G-EMPTY, G-NOCONN |
| R-16 | unique keeps last occurrences | G-PASS, G-ALT, G-MAIN |
| S-1 | a spec of servers past one | G-HARNESS |
| S-2 | a server with no agent | G-HARNESS |
| I-0 | an empty index read as of agents | G-NOCONN |
| I-1 | the agent not looked for | I-REF, G-HARNESS |
| I-2 | other agents taken | I-REF |
| I-3 | cases as an array | I-REF |
| I-4 | a case that is a number | I-REF |
| I-5 | no behavior taken | I-REF |
| I-6 | a behaviorClose number taken | I-REF |
| I-7 | null read as null | I-AGENT, G-PASS, G-ORDER, G-ALT, G-ALTFAIL, G-CLOSE, G-MISSING, G-MAIN |
| I-8 | a code any number | I-REF |
| G-1 | every verdict held | G-ALTFAIL, G-CHANGED, G-CLOSE |
| G-2 | fields held apart | G-ALTFAIL |
| G-3 | the first verdict alone held | G-ALT |
| G-4 | a missing case not told | G-MISSING, G-EMPTY, G-NOCONN |
| G-5 | a case only the run has not told | G-MISSING |
| G-6 | the ratchet tallied | G-PASS, G-ORDER, G-ALT, G-MAIN |
| G-7 | each behavior counted as the whole run | G-PASS, G-ORDER, G-ALT, G-MAIN |
| G-8 | an empty ratchet gated | G-HARNESS |
| G-9 | the hint never said | G-MISSING, G-EMPTY, G-NOCONN |
| G-10 | the hint always said | G-ALTFAIL, G-CHANGED, G-CLOSE |
| G-11 | the hint counts the ratchet | G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING |
| G-12 | one cases | G-MISSING |
| G-11b | one differences | G-ALTFAIL, G-CLOSE |
| G-13 | a difference passes | G-ALTFAIL, G-CHANGED, G-CLOSE, G-MISSING, G-EMPTY, G-NOCONN |
| G-14 | a harness error is 1 | G-HARNESS, G-MAIN |
| G-15 | nothing caught while reading | G-HARNESS, G-MAIN |
| G-16 | a pass is 1 | G-PASS, G-ORDER, G-ALT, G-MAIN |
| G-17 | cases compared in order | G-ORDER, G-MISSING, G-EMPTY, G-NOCONN |
| G-18 | verdicts joined by | | G-ALTFAIL, G-EMPTY, G-NOCONN |
| M-1 | any count of paths | G-MAIN |
| M-2 | an unreadable path read | G-MAIN |
| M-3 | the spec and ratchet swapped | G-MAIN |
| M-4 | only an &error caught | G-MAIN |
| M-5 | the raise's message not said | G-MAIN |
| M-6 | a raise is 1 | G-MAIN |
| M-7 | a wrong count is 1 | G-MAIN |
| M-8 | an unreadable path is 1 | G-MAIN |

New checks and their killers by value: T-LINES by R-3, R-CRLF by R-3, R-PARSE by R-15,
R-REF by R-5, G-ALT by G-3, G-ALTFAIL by G-2, G-NOCONN by I-0, G-MAIN by M-7.

### `run.sh`'s mutants

Run 1: 11 rows (10 mutants and the baseline), 1 mismatch (specs hashed `1f5a54a2`). Each on a
scratch copy of `src/` and `tests/`, the suite run there.

| id | mutation | named | the suite |
|---|---|---|---|
| BASE | no edit | none | as named |
| RM-1 | the last run's index kept | R-STALE | as named |
| RM-2 | the caller's environment inherited | R-ENV | as named |
| RM-3 | no stopped check | R-KILL | as named |
| RM-4 | a dead server waited for | R-NOSTART | as named |
| RM-5 | docker's status not read | R-DOCKER | as named |
| RM-6 | the URL at a fixed port | R-PASS, R-ENV, R-TWO | as named |
| RM-7 | the server at a fixed port | R-TWO | as named |
| RM-8 | the stop not waited for | R-PASS, R-PID, R-ENV, R-STALE, R-TWO, R-TERM, R-DOCKER | none, survived |
| RM-9 | no traps on the host | R-TERM | as named |
| RM-10 | no pid recorded | R-PID, R-KILL, R-TERM | as named |

- **RM-8 survived:** with the stop's wait taken out, every check stayed green. The server
  stops and says `stopped` before the shell reaches its next command, so no run of the
  suite's can see the wait. It matters for a server slow to drain, such as one with a
  connection open, which a lane run never leaves. Kept, since without it the `stopped`
  check races the server.

### The container path

On macOS, with real Docker: copies of `run.sh` run from the tree with make's environment,
named and hashed before (`db5768e3`). All four as named.
- **The baseline:** status 0 in 17 s, nothing left.
- **CM-1, no cleanup trap:** status 0, and one container and one network left.
- **CM-3, the logs read before the stop:** status 2, "ended without stopping".
- **CM-2, a dead container waited for:** status 2 after 60 s, "did not listen within 60 s".
  The real `run.sh` on the same image, `ubuntu:24.04`, says "ended before it listened".


### On Linux's sh (after CI's first runs)

CI's `linux` job reddened R-NOSTART, and no other check. Ubuntu's sh is dash: an echo server
that exits at once stays a zombie until its shell reaps it, which wait_listening's command
substitution cannot do, and kill -0 answers for a zombie. Reproduced in the Linux container
on #64's first head (`5dcef89`), named and hashed before (`da330889`): R-NOSTART red after
72 s, the 60 s wait, and the other 8 green. That old liveness check is the fix's mutant. With
the server alive only when ps shows it and not as a zombie (`2160a781`): 9 of 9 under dash
in 9 s, and under macOS's sh. `run.sh`'s 11 rows run again on the fix: as in run 1, RM-8 the
one survivor.

## The ratchet drops `none` (2026-10-11)

After the server's v0.5.0 pin (#69), by form ("Drop none"; decision 0008's amendment of
2026-10-11). Darwin 25.6.0 arm64, Docker Desktop 29.2.1. The measures are the research
record's last section; scratch `ws-none/`.
- **The change:** `tests/autobahn/verdicts.txt` lists 3.4 and 4.2.5 as `OK OK 1002 | NON-STRICT
  OK 1002`, without `NON-STRICT OK none`, and its note says why.
- **The oracle:** the gate itself, `tests/autobahn/gate.sps`, on lane run 2's `index.json`:
  301 cases, every one as the ratchet holds it, the echo server at v0.5.0. Each row turns one
  case's verdict to `NON-STRICT OK null` and runs the gate against the new ratchet or main's.
  Each row's status and line were named and hashed before the run (`c00c7d2c`).

| Row | Index | Ratchet | Status, as named |
|---|---|---|---|
| G-0 | as run | new | 0 |
| G-1 | 3.4 `null` | new | 1: "3.4: ratchet OK OK 1002 \| NON-STRICT OK 1002, run NON-STRICT OK none" |
| G-2 | 3.4 `null` | main's | 0 |
| G-3 | 4.2.5 `null` | new | 1: the same line for 4.2.5 |
| G-4 | 4.2.5 `null` | main's | 0 |
| G-5 | 4.1.5 `null` | new | 1: the same line for 4.1.5 |
| G-6 | 4.1.5 `null` | main's | 1: the same line; 4.1.5 never listed `none` |

- **One run, 7 rows, 0 mismatches.** The ratchet's edit is what refuses a lost 1002 in 3.4
  and 4.2.5; 4.1.5 refused it already.
- **The lane on the new ratchet:** three full `make autobahn` runs, each status 0, every
  case as held.
- **The measures' predictions,** named and hashed before each cell (`ws-none/predict.txt`).
  Two were wrong, both for v0.4.1: a CPU quota of 0.25 did not raise NON-STRICT, since a
  mostly idle server never spends it; and 150 contended runs gave no `none`, where at least 2
  were named. The raw probes' v0.4.1 row on macOS read the close 70 times in 100, where at
  most a few were named (M5: 0). Each v0.5.0 prediction held.

## The container path's wait (2026-10-11)

Found during #70 and fixed in a PR of its own. Darwin 25.6.0 arm64 with macOS's sh, and Linux
aarch64 in `chez-libuv-noble-scratch:10.4.1` with dash. `run.sh` is blob cecc148 (main's
a339895), the fake 5377f84 (641873c), the suite 12 checks, a14ce59 (adde458). Scratch
`ab-wait/`.
- **The finding:** on the container path, `wait_listening` read `$out/server.log` before its
  first `echo_alive`, and on that path only `echo_alive` and `echo_stop` write the file.
  Nothing emptied it first.
  - On a fresh tree, the first read printed `grep: …/server.log: No such file or directory`.
  - On every later tree, the last run's log says `listening 0.0.0.0 9001`, so it ended the
    wait at once, before the new container listened.
- **The fix:** `run.sh` empties the log before it starts the container. Emptied rather than
  removed, the wait's first read finds a file. The host path truncates the log as it starts
  the server, as before.
- **The checks:** `tests/autobahn/fake/docker` now plays the container path too, as
  `FAKE_ECHO` says, with its state under `FAKE_STATE`. Its container's log says `listening`
  from its second read. On the container's network, its fuzzing client passes only once a
  read of that log has shown the container listening. Each check runs in a tree of its own:
  - **R-CWAIT:** a run waits until its own container listens, and passes, though the last
    run's log says it did.
  - **R-CENDS:** a container that ends before it listens is a harness error, "ended before
    it listened", and no fuzzing client runs, though the last run's log says it listened.
  - **R-CFRESH:** a run on a tree with no log yet says nothing but the gate's line.

### The test-first run

The new suite and fake on main's `run.sh`, named and hashed before (`bebc3ad3`): exit 1, the
nine old checks green, the three new red as named:
- **R-CWAIT** `(1 #f)`: the wait ended at once, and the fuzzing client found no container seen
  listening. The gate failed it as a run of no case.
- **R-CENDS** `(2 #f #t)`: the run went on to the fuzzing client, which wrote its index, and
  ended "without stopping".
- **R-CFRESH:** the gate's line came after `grep: …/fresh/server.log: No such file or
  directory`.

### The mutants

Run 1: 18 rows (17 mutants and the baseline), 0 mismatches (specs hashed `2f44f90b`). The
runner is M5's review's: each mutant gets a scratch copy of `src/` and `tests/`, and the suite
runs there.
- RM-1 to RM-10 ran again, re-predicted for the new suite.
- RM-4 now also reddens the container's checks, since on that path `echo_alive` is what
  fetches the log.
- RM-8 was named as the survivor it was.

| id | mutation | named | the suite |
|---|---|---|---|
| BASE | no edit | none | as named |
| RM-1 | the last run's index kept | R-STALE | as named |
| RM-2 | the caller's environment inherited | R-ENV | as named |
| RM-3 | no stopped check | R-KILL | as named |
| RM-4 | a dead server waited for | R-NOSTART, R-CWAIT, R-CENDS, R-CFRESH | as named |
| RM-5 | docker's status not read | R-DOCKER | as named |
| RM-6 | the URL at a fixed port | R-PASS, R-ENV, R-TWO | as named |
| RM-7 | the server at a fixed port | R-TWO | as named |
| RM-8 | the stop not waited for | none | as named, survived |
| RM-9 | no traps on the host | R-TERM | as named |
| RM-10 | no pid recorded | R-PID, R-KILL, R-TERM | as named |
| CW-1 | the last run's log kept | R-CWAIT, R-CENDS, R-CFRESH | as named |
| CW-2 | the log removed, not emptied | R-CFRESH | as named |
| CW-3 | the URL at the host's address | R-CWAIT, R-CFRESH | as named |
| CW-4 | the fuzzing client on the host's network | R-CWAIT, R-CFRESH | as named |
| CW-5 | the container's log read before its stop | R-CWAIT, R-CFRESH | as named |
| CW-6 | a dead container waited for | R-CENDS | as named |
| CW-7 | the wait never fetches the container's log | R-CWAIT, R-CFRESH | as named |

New checks and their killers, by value:
- **R-CWAIT** by CW-1 `(1 #f)`.
- **R-CENDS** by CW-1 `(2 #f #t)`, and by CW-6 `(2 #f #f)` after the 60 s wait.
- **R-CFRESH** by CW-2, the only one of the fix's own mutants to redden it, with its `grep:`
  line. So it holds the choice to empty the file, not remove it.

The host path's helpers keep their names and build the same commands, and RM-1 to RM-10 redden
what they did. No report has a harness error.

### Under dash

In the Linux container, the suite ran on three `run.sh` variants, named and hashed before
(`d0659a6c`), each as named:
- **BASE:** 12 passes.
- **CW-1, main's `run.sh`:** 9 passes. The three new checks were red by the same values as on
  macOS.
- **CW-2:** 11 passes, with R-CFRESH alone red.

### On real Docker

Docker Desktop 29.2.1, with `make autobahn`'s environment, named and hashed before
(`b532dd78`). Each run started over the log the last run left:
- **Main's `run.sh`,** instrumented to count the wait's polls: `wait: 0 polls`, status 0.
- **The fixed `run.sh`,** instrumented the same way: `wait: 7 polls`, status 0.

So main's wait never waited. Runs stayed green only because the fuzzing client's emulated
container starts more slowly than the echo server listens.

Two `make autobahn` runs, the first from a fresh tree and the second over its log: status 0
each, no `grep:` line, and no container or network left.
