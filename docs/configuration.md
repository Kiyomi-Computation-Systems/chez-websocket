# Configuration

Every limit has a default, and an environment variable to change it, as the
server's `CHEZ_HTTP_` variables do. They are read once, when your program
starts, so a bad value stops it there, naming the variable.

| Variable                    | Default | What it sets                                                           |
|:----------------------------|:--------|:-----------------------------------------------------------------------|
| `CHEZ_WS_MAX_MESSAGE_BYTES` | 1048576 | the largest message, in bytes; a bigger one closes with `1009`         |
| `CHEZ_WS_MAX_QUEUE`         | 16      | messages waiting for `websocket-receive` before reading stops          |
| `CHEZ_WS_PING_INTERVAL`     | 20 s    | quiet time before the server pings; `0` turns pinging off              |
| `CHEZ_WS_PING_TIMEOUT`      | 20 s    | time for the client's pong; past it, the connection closes with `1011` |
| `CHEZ_WS_CLOSE_TIMEOUT`     | 10 s    | time for the client to finish a close; past it, cut off                |
| `CHEZ_WS_WRITE_HIGH_WATER`  | 262144  | bytes unsent before a send waits and reading stops                     |
| `CHEZ_WS_WRITE_LOW_WATER`   | 65536   | bytes unsent when both go on again                                     |
| `CHEZ_WS_WRITE_TIMEOUT`     | 60 s    | time a client past the high water has for each write; past it, cut off |

- **Units.** Times are whole seconds. Sizes are bytes.
- **Spelling.** A value is the digits `0` to `9` and nothing else: `-1`, `+5`,
  `1e3` and `2.5` are refused, and so is a space. Unset or empty keeps the
  default.
- **Least values.** `1` for the message size, the queue, and the ping, close
  and write timeouts. `0` for the ping interval and the two waters. The low
  water may not be above the high water.

For example, to take messages up to 16 MiB and ping every 30 s:

```sh
CHEZ_WS_MAX_MESSAGE_BYTES=16777216 CHEZ_WS_PING_INTERVAL=30 make run PROGRAM=echo.sps
```

## What the limits do

- **The queue.** While your procedure is busy, the server reads on and keeps
  whole messages for it. It stops reading once `CHEZ_WS_MAX_QUEUE` messages,
  or `CHEZ_WS_MAX_MESSAGE_BYTES` bytes of them, are waiting, and starts again
  as you receive them.
- **Quiet clients.** Anything the client sends counts as not quiet. A client
  that sends nothing for 20 s is pinged, and if no pong comes in 20 s more,
  the connection closes with `1011`.
- **Slow readers.** A client that reads slowly falls behind. Past the high
  water, sends wait and the server stops reading from it, until the client
  has read down to the low water. A client past the high water that takes
  longer than the write timeout over a write is cut off.
- **Closing.** Whoever begins a close, the client then has the close timeout,
  counted from when the server's close was queued, to read what is left, and
  to answer the server's close if the server began it. A client that has not
  is cut off; one that has closes cleanly.

## In your program

`environment-websocket-limits` is what was read. To give one handler other
limits, see [Handlers](handlers.md).

A host that reads its settings through a procedure of its own, rather than
the process's environment, builds limits from it with
`(websocket-limits-from-environment lookup)`, and hands them to
`websocket-handshake` or `websocket-accept`.

The server's own variables still apply: where it listens, how many
connections it takes, and how long a closed connection lingers for the
client (`CHEZ_HTTP_LINGER_TIMEOUT`). See chez-http-server's
[configuration](https://github.com/Kiyomi-Computation-Systems/chez-http-server/blob/v0.10.0/docs/configuration.md).
