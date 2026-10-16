# How it works

The library has two halves: a **pure core** that knows the rules of
RFC 6455, and a **binding** that runs those rules over chez-http-server's
connection.

## The pure core

Each library below imports only `(rnrs)` and the others. None of them reads a
clock or touches a socket. They take what happened and give back what to do,
so a test can feed them bytes and check the answer exactly.

| Library                 | What it does                                                        |
|:------------------------|:--------------------------------------------------------------------|
| `(websocket sha1)`      | SHA-1, for the handshake's accept key                               |
| `(websocket base64)`    | base64, for the same key                                            |
| `(websocket utf8)`      | checks text is UTF-8, byte by byte, as it arrives                   |
| `(websocket frame)`     | reads a client's frames, in pieces of any size; writes the server's |
| `(websocket protocol)`  | one connection's rules: messages, pings, the limits, closing        |
| `(websocket handshake)` | checks the opening request, and makes the `101`'s fields            |
| `(websocket limits)`    | the limits, and reading them from the environment's strings         |

The heart is the protocol's step. It takes the connection's state and one
event, and returns the new state and a list of actions:

```text
   state + event
         │
         ▼
       step        no clock, no I/O
         │
         ▼
  new state + actions
```

- **Events:** bytes arrived; your procedure sent a message, closed, or took
  a message; a write finished; the timer went off; the connection ended.
- **Actions:** write these bytes; deliver this message; stop or start
  reading; set or cancel the timer; close or cut off the connection; the
  connection has ended, and here is how.

Time is not read, it is told: the step asks for a timer by kind (ping, pong,
close or write) and is told when it goes off.
[tests/test-imports.sps](../tests/test-imports.sps) holds each library to its
imports.

## The binding

The binding, `(websocket private binding)`, is the only part that does I/O.
`websocket-accept` checks the handshake with the core. Once the server has
sent the `101`, the binding takes the connection over: it feeds each read to
the step, and does what the step says, in order, using the server's
transport for writes, timers and pausing reads. Your procedure runs on a
coroutine the server gives it. When it waits in `websocket-receive` or
`websocket-send!`, the binding parks it, and wakes it when the step delivers
a message or the client catches up.

## Flow control, in plain words

Data moves both ways, and each way has a brake.

- **Coming in.** The server keeps reading while your procedure is busy, and
  queues whole messages for it. When the queue is full
  (`CHEZ_WS_MAX_QUEUE` messages, or `CHEZ_WS_MAX_MESSAGE_BYTES` bytes of
  them), it stops reading. The client's data then waits in the network, and
  TCP slows the client down. Each message you receive makes room, and reading
  starts again.
- **Going out.** Each send is written at once. If the client reads slowly,
  bytes pile up unsent. Past the high water (`CHEZ_WS_WRITE_HIGH_WATER`),
  your sends wait and the server stops reading from that client too. When the
  client has read down to the low water (`CHEZ_WS_WRITE_LOW_WATER`), both go
  on. A client that stays stuck longer than the write timeout is cut off.

So however many coroutines send to one slow client, the server holds at most
a high water's worth of bytes for it, plus the frame that passed it.

## The ping clock, in plain words

Each connection has one timer.

1. Whenever the client sends anything, the timer restarts at the ping
   interval.
2. If the client stays quiet that long, the server sends a ping and gives it
   the ping timeout to send something back.
3. If nothing comes, the connection closes with `1011`.

The clock stops while reading is stopped, since a pong the server does not
read is not the client's fault. Once the server begins a close, the timer is
the close timeout instead. The numbers are on
[Configuration](configuration.md).
