# Peer WebSocket servers' defaults, read from source (2026-10-04)

The evidence for [decision 0001](../decisions/0001-messages-are-whole-and-capped-at-1-mib-and-the-server-reads-on-and-pings-a-quiet-client.md)
and the design. What five servers do **by default**, each fact read in the source at
the tag named. The files were read through `gh api contents?ref=TAG`; nothing was
cloned or installed. Four of the citations were checked again by hand against the
fetched files: websockets' timeouts, `max_size`, `max_queue` and `write_limit`;
coder's read limit; tungstenite's two sizes; ws's `maxPayload` and close timeout.

| peer | tag | commit |
|---|---|---|
| Python websockets | 17.2 | a1664f4c5a7c71bf5391ad0c3c518e431f6261fb |
| coder/websocket | v1.8.15 | 9c8faadccd1b679e811a79ce506f8a10237251ad |
| gorilla/websocket | v1.5.3 | ce903f6d1d961af3a8602f2842c8b1c3fca58c4d |
| tungstenite-rs | v0.30.0 | 7f4aeaf0944992c5664c8fb8e0d54577c7e18020 |
| tokio-tungstenite | v0.30.0 | 4994a078037a18a9347b8cf49291a5031d63d9e0 |
| ws | 8.22.0 | 297202cdae9b0590629821373b3b679c407f3431 |

Paths: websockets' under `src/websockets/`; the others' from the repository root.
websockets' asyncio and sync servers agree unless a row says otherwise.

## The largest message

| peer | default | what happens past it | source |
|---|---|---|---|
| websockets | 1 MiB (`max_size = 2**20`); no separate frame limit | close 1009, checked at each frame's header against what the message has left | asyncio/server.py:517; protocol.py:584-606 |
| coder | 32,768 bytes (`defaultReadLimit`) | close 1009, as the application reads | read.go:107, 526-530 |
| gorilla | none (`readLimit` 0 unless `SetReadLimit`) | if set: close 1009, checked at each data frame's header | conn.go:915-927, 1109-1114 |
| tungstenite | 64 MiB a message, 16 MiB a frame | an error returned, no close frame | src/protocol/mod.rs:101-102, 784-791 |
| ws | 100 MiB (`maxPayload`) | close 1009, checked at each data frame's header | lib/websocket-server.js:74; lib/receiver.js:438-453 |

## Keepalive

| peer | default | source |
|---|---|---|
| websockets | a ping every 20 s; no pong within 20 s closes with 1011 | asyncio/server.py:513-514; asyncio/connection.py:836-843 |
| coder | none; `Conn.Ping` on demand | conn.go:216-231 |
| gorilla | none; the application runs its own ticker | doc.go:98-101 |
| tungstenite | none: no timer anywhere in `src/` | src/ (searched whole) |
| ws | none; the README shows a ping loop of the application's | README.md:452-491 |

## Reading while the application is busy, and pings received

| peer | default | source |
|---|---|---|
| websockets | reads on into a queue of 16 frames (`max_queue`), then pauses reading; a ping is answered by the core at once | asyncio/server.py:518; protocol.py:690-694 |
| coder | pings answered only while a read is in progress | read.go:316-323 |
| gorilla | pings answered only while the application reads | conn.go:1146-1171 |
| tungstenite | the pong is queued and written on the next read, write or flush | src/protocol/mod.rs:281-292 |
| ws | reads on, events emitted; pongs automatic (`autoPong`) | lib/websocket-server.js:71 |

## The read API

| peer | the main read | a read of pieces | source |
|---|---|---|---|
| websockets | `recv()`, a whole message | `recv_streaming()`, fragments | asyncio/connection.py:250-317, 328-394 |
| coder | `Read`, the whole message | `Reader`, an `io.Reader` over one message | read.go:35-49 |
| gorilla | `ReadMessage`, all its bytes | `NextReader`, an `io.Reader` over one message | conn.go:1089-1099 |
| tungstenite | `read()`, a reassembled message | raw frames only through `FrameSocket` | src/protocol/mod.rs:259-261 |
| ws | the `'message'` event, reassembled | binary fragments with `binaryType = 'fragments'` | lib/receiver.js:577-644 |

## UTF-8 in text messages

| peer | default | source |
|---|---|---|
| websockets | checked when `recv` decodes the whole message (per fragment in `recv_streaming`); 1007 | asyncio/messages.py:161-186; protocol.py:621-623 |
| coder | not checked (its Autobahn run excludes the UTF-8 cases) | autobahn_test.go:26-34 |
| gorilla | not checked for text; a close reason's is, 1002 | doc.go:80-81; conn.go:960-968 |
| tungstenite | checked incrementally per fragment; an error returned, no close frame | src/protocol/message.rs:8-77 |
| ws | checked at the message's end; 1007 | lib/receiver.js:616-630 |

## The closing handshake's timeout

| peer | default | source |
|---|---|---|
| websockets | 10 s (`close_timeout`), for the client's close and the TCP close together | asyncio/server.py:515 |
| coder | 5 s to write the close, then 5 s for the client's | close.go:86-91, 115-120 |
| gorilla | none; `Close()` closes TCP without a close frame | conn.go:342-346 |
| tungstenite | none | src/ (no timers) |
| ws | 30 s (`closeTimeout`), then the socket is destroyed | lib/constants.js:10 |

## Sending

| peer | default | source |
|---|---|---|
| websockets | `send()` waits while more than `write_limit`, 32 KiB, is unsent | asyncio/server.py:519; asyncio/connection.py:1049-1078 |
| coder | `Write` returns once the frame is flushed to the socket | write.go:43-49, 103-115 |
| gorilla | a blocking write, no queue | conn.go:379-403 |
| tungstenite | `write_buffer_size` 128 KiB, `max_write_buffer_size` unlimited | src/protocol/mod.rs:58-77 |
| ws | `send()` does not wait; `bufferedAmount` is exposed | lib/sender.js:563-572 |

## Origin (for M4)

| peer | default | source |
|---|---|---|
| websockets | not checked; a list of allowed origins (exact or regex) answers 403 | server.py:316-349 |
| coder | the Origin's host must equal the request's Host; absent is allowed; else 403 | accept.go:228-264 |
| gorilla | the same as coder (`checkSameOrigin`) | server.go:88-99; util.go:176-198 |
| tungstenite | not checked; the application's handshake callback decides | src/handshake/server.rs:167-209 |
| ws | not checked; `verifyClient` decides (401 by default) | lib/websocket-server.js:326-354 |

## Subprotocols

| peer | default | source |
|---|---|---|
| websockets | the server's list, in its order: the first the client offered; none matching is 400 | server.py:432-514 |
| coder | the server's list, in its order; none matching sends no header and succeeds | accept.go:266-276 |
| gorilla | the server's list, in its order; none matching sends no header and succeeds | server.go:101-115 |
| tungstenite | none; the application sets the header | src/handshake/server.rs:167-209 |
| ws | the client's first, unless a callback chooses | lib/websocket-server.js:282-293 |

## Not found, or inferred

- tungstenite sending no close frame on an error is inferred from the absence of
  any write path in `src/protocol/mod.rs`, not from its documentation.
- websockets' low-water mark for `write_limit` is asyncio's own default, not read.
- The server-side read timeouts of coder, gorilla and ws belong to Go's `net/http`
  and Node's `http.Server`, which were not read.
- websockets' trio implementation was not read.
