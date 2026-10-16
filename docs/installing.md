# Installing

chez-websocket is a set of R6RS libraries on top of chez-http-server. You
build its dependencies once with `make build`, then run your program with
the library path that build assembles.

## What you need

- **Chez Scheme 10.4.1 or newer, threaded.** Threaded is Chez's default
  build. The examples call the binary `chez`.
- **libuv 1.48 or newer**, where `pkg-config` can see it: `brew install libuv`
  on macOS, `apt install libuv1-dev` on Ubuntu 24.04 or newer. With none, or
  an older one such as Debian 12's 1.44, the build makes its own copy, which
  needs CMake 3.10 or newer.
- **A C compiler, `make` and `git`.**
- **Docker**, only for `make autobahn` ([Testing](testing.md)).

## Build it

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-websocket.git
cd chez-websocket
make build
make test
```

`make build` clones the pinned dependencies, builds the small C library under
chez-libuv, and assembles one library path. `make test` runs every suite
under `tests/`; it ends with `ALL SUITES PASSED`.

`make help` lists every other target.

## The pinned server

The one dependency, chez-http-server, is a git submodule under `vendor/`,
pinned at a release tag, v0.7.0. It carries its own pins: chez-libuv,
chez-httparse, uriparse, and chez-srfi for the tests. You don't install any
of them yourself: `make build` clones what the build needs.

chez-http-server is private for now; the pins it carries are public.

To check every checkout sits at its pin:

```sh
make check-pins
```

## Run a program

Save the echo from [Home](README.md) as `echo.sps`, then:

```sh
make run PROGRAM=echo.sps
```

Connect a client, such as `websocat ws://127.0.0.1:8080/echo`: each line you
send comes back. Stop the server with Ctrl-C.

`make dev` starts a REPL with the same library path.
