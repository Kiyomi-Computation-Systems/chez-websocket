# Contributing to chez-websocket

Thanks for helping. A **small fix**, such as a typo, a doc fix, or a bug with a
test that shows it, needs only the checks below. **Bigger work**, such as a new
export, a new limit, a new dependency, or a change to what the library accepts
from a client or sends back, starts as an issue, so the design is agreed
before the code is written. What the library accepts and refuses is held to
RFC 6455 and to Autobahn|Testsuite's verdicts, so changing it is a design
decision, not a fix.

## Setup

You need Chez Scheme 10.4.1 or newer (threaded), libuv 1.48 or newer, a C
compiler, `make` and `git`. [docs/installing.md](docs/installing.md) has the
details. Docker is needed only for `make autobahn`, and the cmark-gfm library
(`brew install cmark-gfm`, `apt install cmark-gfm`) only for the docs site.

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-websocket.git
cd chez-websocket
make test
```

`make test` clones the pinned server and builds what it needs first.
`make help` lists every target.

## The checks

CI runs these on every pull request, on Linux. Keep them green:

- `make test`: every suite passes (`ALL SUITES PASSED`). Among them, the
  docs suite runs the Scheme blocks in `docs/` and holds the names,
  defaults, targets and links the pages give to the library and the
  checkout; the examples suite plays each program in `examples/`; and the
  import audit holds each pure library to its imports.
- `make check-pins`: the server sits at its pin, and each pin it carries
  where the server records it. `make test` runs it first.
- `make check-help`: every target has a description in `make help`.
- `make check-site-deps` and `make check-site`: the docs site builds, and
  every link and anchor in it resolves.
- `make autobahn`: Autobahn|Testsuite's fuzzing client runs its cases
  against `tests/autobahn/echo.sps`, and each verdict matches
  `tests/autobahn/verdicts.txt`. It needs Docker.

## When you change…

- **What the library accepts, refuses or sends:** run `make autobahn`. It
  fails when a case's verdict moves, better or worse, so a change that moves
  one updates `tests/autobahn/verdicts.txt` and says why in the pull request.
- **The server pin:** chez-http-server is the one submodule, pinned at a
  release tag, and the pins it carries come with it. Move the submodule and
  `SERVER_PIN` in the Makefile together, on a commit of their own, with the
  pages that name the tag. `make check-pins` fails until the two agree.
- **`Akku.manifest`:** it names the docs site's one dependency,
  chez-cmark-gfm. Commit `Akku.lock` with it (`akku lock` writes it):
  `make site-deps` downloads the archive the lock names and checks its
  sha256.
- **The Makefile:** give each new target a `## ` description, so
  `make help` lists it.
- **`docs/`:** it is for people using the library. Keep it short and plain.
  A new page goes in `docs/` and in `site/pages.sls`, the nav's order;
  `make check-site` fails until both name it. A Scheme block in a page is
  run by `tests/test-docs.sps`, which fails on a block it does not know, so
  a new block gets its entry there.
- **`examples/`:** each example serves a page at `/` that opens its
  WebSocket, so a browser can try it. `tests/test-examples.sps` plays each
  one, and a new example gets its cases there.

## Code

- Libraries are R6RS `.sls` files under `src/`, and each holds its own code:
  no shared include files.
- **Functional core, imperative shell.** The RFC 6455 rules go in the pure
  libraries under `src/websocket/`, which take bytes and return actions, and
  import only `(rnrs ...)` and each other. The binding over chez-http-server's
  transport is `src/websocket/private/binding.sls`, and `src/websocket.sls`
  is the library a handler imports. `make check-imports`, a suite
  `make test` also runs, fails when a pure library imports anything else.
- Each export has a comment giving its type, Typed Racket style:
  `;; frame-fin? : FrameDecoder -> Boolean`.
- R6RS forbids assigning an exported variable, so reach mutable state through
  procedures.
- The library runs on macOS and Linux, on x86-64 and arm64. Keep code
  portable to Windows too, which chez-libuv does not support yet. CI runs
  Linux only, so say in the pull request where you tested.
- Comments and docs say what the code does and why, in the present tense.
  They don't cite issues, pull requests, plans or dates; that history belongs
  in commits and CHANGELOG.md.

## Tests

- Write the test first, and watch it fail before you make it pass. A test
  that passes whether the code is right or wrong is worse than none.
- A change in behavior comes with a test that fails without it.
- A suite is `tests/test-<name>.sps`, written with SRFI-64, and runs through
  `run-suite` from `(ws-testing)`, which exits with the status `make test`
  reads. `make test TESTS=tests/test-<name>.sps` runs just that suite.
- Hold the code to an answer from outside it where there is one: an RFC's
  examples, a real client's bytes, or a value another implementation
  computes. [docs/testing.md](docs/testing.md) lists the ones in use.
- Test what the code does, never what a comment says.

## Pull requests

- Commit messages and PR titles follow
  [Conventional Commits](https://www.conventionalcommits.org): `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Name branches `feat/<slug>`, `fix/<slug>`, `docs/<slug>` and so on.
- Pull requests are squash-merged, so the PR title becomes the commit's.
- A change users can see gets an entry under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).

## How the project is developed

Feature work starts as a design in `.plans/`, and each lasting decision gets
a numbered record in `.plans/decisions/`. [AGENTS.md](AGENTS.md) holds the
project's rules in full. Following them is encouraged for features, not
demanded of small fixes.

## Security

Don't open a public issue for a suspected vulnerability.
[SECURITY.md](SECURITY.md) says how to report it privately.
