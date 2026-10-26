# Performance

What a connection costs the server in memory, measured.

## An idle connection

| An idle connection                                                          | Heap             |
|:----------------------------------------------------------------------------|:-----------------|
| a WebSocket, its procedure waiting in `websocket-receive` after the `101`   | 5,463 to 5,680 B |
| the same, after 10 echoes                                                   | 5,608 to 5,613 B |
| the server's own connection, idle after a GET, for scale                    | 2,079 to 2,246 B |

So a WebSocket that is open and waiting costs the server about 5.6 KB, and
echoing messages does not make it grow. Its limits bound what a busy one can
make the server hold beyond that ([How it works](how-it-works.md)).

## How it was measured

By chez-http-server's own method: a Python child process holds the
connections open; the heap is read after two full collections; and a
connection's cost is the heap with 500 connections less the heap with 100,
over 400. Each row is five such holds.

Measured on an Apple M1 (8 cores), macOS 26, Chez Scheme 10.4.1
(`tarm64osx`) and libuv 1.52.1, against chez-http-server v0.9.0, the pin
today. On v0.7.0, measured the same hour, a WebSocket cost about 5.3 KB:
the server's own connection grew by about 270 B in v0.9.0, and a
WebSocket's with it.
