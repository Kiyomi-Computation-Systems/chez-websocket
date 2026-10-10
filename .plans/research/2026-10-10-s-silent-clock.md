# S-SILENT's 98 ms ping: two clocks

2026-10-10. Why S-SILENT measured a ping met on time at 98 ms on CI, and the bound that
follows from it.

**What happened.** CI's run 38051169931, attempt 1 (PR #63, a docs-only tree identical to one
that passed), job `linux`: `actual: (((ping "") (close 1011 "")) 98 within-the-timeout …)`. The
check took a ping at 99 ms or later; it had passed on every earlier CI run, about 25.

**Where.** Darwin 25.6.0 arm64 (Apple M1), Chez 10.4.1 `tarm64osx`, libuv 1.52.1. Linux
6.12.76-linuxkit aarch64 in Docker (image `chez-libuv-noble-scratch:10.4.1`: Ubuntu 24.04,
libuv 1.48.0, CI's), Chez 10.4.1. main at dc53b3b, the server pinned at v0.4.1 (520f70e).

## The two clocks, from their sources

- **The suite's:** `now-ms`, Chez's `(current-time 'time-monotonic)` in whole milliseconds.
  Chez 10.4.1 reads `clock_gettime(CLOCK_MONOTONIC)` (`c/stats.c:326-331`), less the
  process's start (`c/stats.c:372-378`, `587`).
- **The loop's:** `uv_now`, set by `uv__update_time` to `uv__hrtime(UV_CLOCK_FAST) / 1000000`
  (libuv 1.48.0, `src/unix/internal.h:381-385`).
  - On Linux, `UV_CLOCK_FAST` is `CLOCK_MONOTONIC_COARSE` whenever `clock_getres` says it
    ticks every millisecond or finer, and `CLOCK_MONOTONIC` otherwise
    (`src/unix/linux.c:1585-1619`).
  - On macOS it is `mach_continuous_time` (1.52.1, `src/unix/darwin.c:60-62`).
- **The server** arms a taker's deadline at `uv_now`, brought up to date, plus its
  milliseconds (`shell.sls`, `taker-deadline!`). Its wheel fires an entry at the first tick
  whose `uv_now` is at or past the entry's own deadline, never by its bucket (`wheel.sls`,
  `take-due!`).
- **The binding** writes the ping, then arms the pong (`protocol.sls`, `passed!`).

## Measured

**The loop's clock against `CLOCK_MONOTONIC`.** A C probe called `uv_update_time`, read
`uv_now`, then `clock_gettime`: 20,000 samples, each after a sleep of 37 to 436 µs.

| | `CLOCK_MONOTONIC_COARSE` | `uv_now` behind `CLOCK_MONOTONIC` |
|---|---|---|
| Linux | ticks every 1,000,000 ns, so libuv reads it | 0.37 to 3.09 ms; 96.5% 1 ms or more |
| macOS | none | a spread of 1.13 ms: the floor, and the read's own gap |

**S-SILENT's scenario, both clocks at once.** A probe built from the suite's helpers ran the
check's server and client again and again. It recorded at the take-over, at each arm and at
each write both Chez's clock to the nanosecond and `uv_now`, read without bringing it up to
date. The rows at 100/300 are the suite's numbers; 20/30 is a ping interval of 20 ms and a
timeout of 30, for many more runs. The tick stays the suite's 10 ms.

| | runs | loop ms, ping − take-over, least | loop ms, close − ping, least | true ms, take-over → ping, least | true ms, ping → close, least | old bounds broken |
|---|---|---|---|---|---|---|
| macOS, 100/300 | 300 | 100 | 300 | 99.385 | 299.618 | 0 |
| Linux, 100/300 | 300 | 100 | 300 | 99.046 | 299.117 | 0 |
| Linux, 100/300, four at once | 1,000 | 100 | 300 | 98.888 | 298.952 | 0 |
| Linux, 20/30, four at once | 10,000 | 20 | 30 | 14.681 | 28.416 | 143 |

- **The old bounds** are the suite's clock less one, 99 and 299 (19 and 29 at 20/30). At 20/30
  the ping read 18 ms 138 times, and 15 once.
- **The loop's clock fell further behind between the arm and the ping** by up to 0.91 ms on
  macOS and 1.77 ms on Linux run alone; four at once, by up to 6.33 ms. In that run the loop's
  clock moved 21 ms while `CLOCK_MONOTONIC` moved 14.7.
- **The suite's two whole-millisecond stamps** cost −0.99 to +0.99 ms against the true
  interval.

## Where the 2 ms came from

- **Not the wheel firing a tick early:** in the loop's own clock, no deadline was met before
  it in any of the 11,600 runs.
- **Not the suite's clock alone:** it reads `CLOCK_MONOTONIC`, to the nanosecond on Linux and
  the microsecond on macOS.
- **The two clocks apart.** Each stamp of the suite's is cut to the millisecond, up to 1 ms
  between the two. And `uv_now` lags `CLOCK_MONOTONIC` by an amount that varies: it is cut to
  the millisecond as the deadline is armed, and on Linux it is the coarse clock, whose lag is
  not bounded by its 1 ms tick.
- **On a fine loop clock the old 99 was exact.** The arm is at `floor(t_arm) + 100`, so the
  ping comes more than 99 ms after the take-over, and two whole-millisecond stamps of that
  differ by more than 98, so by 99 or more. A 98 on CI therefore says CI's loop clock is
  coarse, as linuxkit's is. That is inferred; CI's kernel was not measured.

## The bound

**Time by the loop's clock.** Read it at the take-over without bringing it up to date, and at
each write. Then:
- the take-over's reading is at or before the arm's, since the cached time never steps back;
- the ping is written at the first tick at or past the arm's reading plus 100;
- the pong is armed after the ping's write, so its reading is at or after the ping's.

So the ping comes at 100 ms or later, and the close 300 ms or later after it, to the
millisecond, whichever clock libuv reads. The probes held it in all 11,600 runs, the
check's own measure. The upper bounds, 250 and 450, are unchanged.

**What the loop's clock cannot see.** A shell that arms a taker's deadline by a time not
brought up to date (SC-1, `m4-mutations.md`) leaves S-SILENT green. It left the suite's clock
green before, 6 runs of 6. It also leaves the server's suites green: its shell suite (204
passes on Darwin, 199 on Linux), and every one of its 51 that runs here (1,951 passes on
Darwin, as many as without it).
