# Performance

What a connection costs the server in memory, measured.

## An idle connection

| An idle connection                                                          | Heap             |
|:----------------------------------------------------------------------------|:-----------------|
| a WebSocket, its procedure waiting in `websocket-receive` after the `101`   | 5,281 to 5,435 B |
| the same, after 10 echoes                                                   | 5,353 to 5,477 B |
| the server's own connection, idle after a GET, for scale                    | 1,900 to 2,055 B |

So a WebSocket that is open and waiting costs the server about 5.3 KB, and
echoing messages does not make it grow. Its limits bound what a busy one can
make the server hold beyond that ([How it works](how-it-works.md)).

## How it was measured

By chez-http-server's own method: a Python child process holds the
connections open; the heap is read after two full collections; and a
connection's cost is the heap with 500 connections less the heap with 100,
over 400. Each row is five such holds.

Measured on an Apple M1 (8 cores), macOS 26, Chez Scheme 10.4.1
(`tarm64osx`) and libuv 1.52.1, against chez-http-server v0.5.0. On v0.7.0,
the pin today, a connection still costs about 5.3 KB.
