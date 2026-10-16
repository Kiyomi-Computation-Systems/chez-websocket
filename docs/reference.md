# API reference

Every name `(websocket)` exports, one entry each. A handler's program imports
it beside `(http-server)`. For explanation and examples, read
[Handlers](handlers.md) and [Configuration](configuration.md) first.

## Conventions

**Reading a signature.** `(websocket-send! ws message) -> Void` takes two
arguments and returns nothing useful; the `->` is notation, not Scheme.
Arguments in `[brackets]` may be left out, from the right. A line like
`default-websocket-limits : WebsocketLimits` describes a value, not a
procedure.

**Types.** `Nat` is a non-negative exact integer. `Request` is the request a
chez-http-server handler is given, and `Answer` what it returns. `WebSocket`,
`HandshakeSettings` and `WebsocketLimits` are records you read only through
the names below.

**Mistakes raise.** A wrong argument, such as a send of a number or a close
code the server may not send, is an assertion violation naming the
procedure. The end of a connection is not a mistake: it is
`&websocket-closed`.

## Taking a WebSocket

### `websocket-accept` (procedure)

`(websocket-accept request procedure [settings [limits]]) -> Answer`

Checks `request` is a WebSocket handshake. If it is, the answer is a `101`,
and `procedure` then runs with the WebSocket on a coroutine of its own. If it
is not, the answer is the refusal, `400` or `403`, and `procedure` never runs.
`settings` defaults to `(make-handshake-settings '())`; `limits` to
`environment-websocket-limits`.

**Details:** [Handlers](handlers.md)

### `websocket?` (predicate)

`(websocket? object) -> Boolean`

Whether `object` is a WebSocket.

### `websocket-subprotocol` (procedure)

`(websocket-subprotocol ws) -> (U String #f)`

The subprotocol the handshake chose, or `#f` for none.

**Details:** [Handlers](handlers.md)

## Reading and writing

### `websocket-receive` (procedure)

`(websocket-receive ws) -> (U String Bytevector)`

Waits for the next message: a string for text, a bytevector for binary. A
second receive while one waits is refused. Once the connection has closed,
it gives the messages still waiting, then raises `&websocket-closed`.

**Details:** [Handlers](handlers.md)

### `websocket-send!` (procedure)

`(websocket-send! ws message) -> Void`

Sends a string as text, or a bytevector as binary. Waits while the client is
behind. Raises `&websocket-closed` once the connection has closed.

**Details:** [Handlers](handlers.md)

### `websocket-close!` (procedure)

`(websocket-close! ws [code [reason]]) -> Void`

Starts closing with `code`, `1000` if left out, and `reason`, `""` if left
out, and returns; the close finishes on its own. Does nothing once a close
was sent or the connection has closed.

**Details:** [Handlers](handlers.md)

## The end of a connection

### `&websocket-closed` (condition type)

Raised by `websocket-receive` and `websocket-send!` once the connection has
closed. It says how it closed.

**Details:** [Handlers](handlers.md)

### `websocket-closed?` (predicate)

`(websocket-closed? object) -> Boolean`

Whether `object` is a `&websocket-closed`.

### `websocket-closed-code` (procedure)

`(websocket-closed-code e) -> Nat`

The client's close code; `1005` if its close had none; `1006` if no close
came.

### `websocket-closed-reason` (procedure)

`(websocket-closed-reason e) -> String`

The client's close reason, or `""`.

### `websocket-closed-clean?` (procedure)

`(websocket-closed-clean? e) -> Boolean`

Whether a close went each way.

## Settings

### `make-handshake-settings` (procedure)

`(make-handshake-settings subprotocols [origins]) -> HandshakeSettings`

`subprotocols` is a list of names, in your order of preference. `origins` is
`'any`, or a list of origin strings and `same-host`; left out, it is
`'(same-host)`. A bad name is refused here, so make settings once, as your
program starts.

**Details:** [Handlers](handlers.md)

### `handshake-settings?` (predicate)

`(handshake-settings? object) -> Boolean`

Whether `object` is a handler's settings.

## Limits

Inside the library, times are in milliseconds and sizes in bytes.

### `environment-websocket-limits` (value)

`environment-websocket-limits : WebsocketLimits`

The defaults, with each `CHEZ_WS_` variable your environment sets applied
over them, read once as your program starts.

**Details:** [Configuration](configuration.md)

### `default-websocket-limits` (value)

`default-websocket-limits : WebsocketLimits`

The defaults, whatever the environment says.

**Details:** [Configuration](configuration.md)

### `websocket-limits-with` (procedure)

`(websocket-limits-with limits changes) -> WebsocketLimits`

`limits` with some fields changed. `changes` is a list of
`(field . value)` pairs, each field named as in `make-websocket-limits`.

**Details:** [Handlers](handlers.md)

### `make-websocket-limits` (procedure)

`(make-websocket-limits max-message-bytes max-queue ping-interval-ms
ping-timeout-ms close-timeout-ms write-high-water write-low-water
write-timeout-ms) -> WebsocketLimits`

Limits of these values. A value below its least, or a low water above the
high water, is refused.

**Details:** [Configuration](configuration.md)

### `websocket-limits?` (predicate)

`(websocket-limits? object) -> Boolean`

Whether `object` is a set of limits.

### `websocket-limits-max-message-bytes` (procedure)

`(websocket-limits-max-message-bytes limits) -> Nat`

The largest message, in bytes.

### `websocket-limits-max-queue` (procedure)

`(websocket-limits-max-queue limits) -> Nat`

The messages that may wait for a receive before reading stops.

### `websocket-limits-ping-interval-ms` (procedure)

`(websocket-limits-ping-interval-ms limits) -> Nat`

The quiet time before a ping; `0` for no pings.

### `websocket-limits-ping-timeout-ms` (procedure)

`(websocket-limits-ping-timeout-ms limits) -> Nat`

The time for a pong.

### `websocket-limits-close-timeout-ms` (procedure)

`(websocket-limits-close-timeout-ms limits) -> Nat`

The time for the client to finish a close.

### `websocket-limits-write-high-water` (procedure)

`(websocket-limits-write-high-water limits) -> Nat`

The bytes unsent before a send waits and reading stops.

### `websocket-limits-write-low-water` (procedure)

`(websocket-limits-write-low-water limits) -> Nat`

The bytes unsent when both go on again.

### `websocket-limits-write-timeout-ms` (procedure)

`(websocket-limits-write-timeout-ms limits) -> Nat`

The time a client past the high water has for each write.
