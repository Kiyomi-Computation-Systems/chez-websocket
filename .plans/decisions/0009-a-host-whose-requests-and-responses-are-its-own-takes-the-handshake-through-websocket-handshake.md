# 0009: A host whose requests and responses are its own takes the handshake through websocket-handshake

Date: 2026-10-28
Status: accepted (user decision, 2026-10-27: the owner approved circuit's slice 6 design,
whose §6 "The change in chez-websocket" asks for it; circuit's design §15.16 records the
approval).
Design: [the design](../2026-10-04-chez-websocket-design.md) §3 and §6

## Context

circuit is a Ring-like layer on chez-http-server. Its requests and responses are its own
records, and an adapter maps them onto the server's. Its slice 6c gives its apps
WebSockets, through this library.

`websocket-accept` needs the server's request, and answers the server's own types:
`switch-protocols` around the take-over, or `make-response` for a refusal. A host with
types of its own could only reach past them to the server's request, or copy the
handshake. The handshake's decision was already pure, in `(websocket handshake)`, but its
take-over is the binding's, and private.

## Decision

1. **`websocket-handshake`**, in the binding and through the facade, takes what a host
   reads of the request: the method as a symbol, a reader of every line of a field, the
   request's host, the procedure, and the settings and limits as `websocket-accept` takes
   them. It answers one of two records:
   - **accepted:** the 101's fields as string pairs, and the take-over, `Transport
     Bytevector -> Answer`, which the host hands the server's `switch-protocols` through
     its own 101, and whose answer it answers;
   - **refused:** the status and its fields as string pairs, answered with no body.

   The fields are each answer's own. The lines of a field are joined there, and the
   argument checks are there, naming it, before the reader is called.
2. **`handshake-answer` answers string pairs**, not bytevector pairs. It is not in the
   facade, and nothing documents it.
3. **`websocket-accept` is built on it,** its contract unchanged: it reads the server's
   request, and turns the fields into bytes itself, once a connection.
4. **All the WebSocket logic stays here.** A host's side is only a mapping onto its own
   types.

The refusal record carries no reason. `handshake-answer` still names the check that
failed, and a field for it can be added later without breaking a host.

## Consequences

- circuit's `(circuit websocket)` maps the answer onto `make-upgrade-res` and `make-res`,
  and imports `(websocket)`, not `(http-server)`.
- The take-over still runs on the server's transport and answers its `awaiting`: the
  procedure is neutral to a host's request and response types, not to the server.
- A host that wraps the take-over must answer what it answers: wrapped and its answer
  dropped, the 101 is written and the procedure never runs (the review's probe; the
  reference says so).
- The door suite now holds `websocket-accept`'s own answers to the server's checks, run on
  the fake shell, where it held `handshake-answer`'s.
- The release with it is v0.3.0, on the server's v0.9.0, which circuit pins.
