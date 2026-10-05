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
