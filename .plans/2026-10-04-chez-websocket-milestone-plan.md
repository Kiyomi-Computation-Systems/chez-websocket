# chez-websocket — the milestone plan (SDD rung 3)

Date: 2026-10-04
Design: [the design](2026-10-04-chez-websocket-design.md)

Each milestone is one or more slices. Each slice is built test-first, with every
check watched to fail against a named mutant, recorded in its milestone's mutation
log. A slice goes up as one PR. A slice over ~400 lines goes up as stacked PRs,
split by layers green on their own. A milestone ends with its exit: the records, the
README's status, and the reflect in the ledger.

## M0 — the skeleton (#2)

The pin of chez-http-server v0.3.0 and the pins it carries, the Makefile, Linux CI,
and the door suite.

## M1 — the primitives

- **M1.1 SHA-1** `(websocket sha1)`, `sha1 : Bytevector -> Bytevector` (20 bytes).
  - Vectors: RFC 3174's four test cases, and RFC 6455 §4.2.2's digest of its example
    key and GUID.
  - Inputs of 0, 55, 56, 63, 64 and 65 bytes, where the padding changes blocks.
  - `make check-imports` starts here.
- **M1.2 base64** `(websocket base64)`: encode, and decode for a key's check.
  - RFC 4648 §10's seven vectors, both ways.
  - A decode refuses a wrong length, a character outside the alphabet, and padding
    anywhere but the end.
  - Then the accept value of RFC 6455's example: `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`.
- **M1.3 UTF-8** `(websocket utf8)`: an incremental checker whose state carries
  across pieces.
  - Every row of RFC 3629 §4's grammar, at its edges.
  - Overlongs, surrogates (U+D800–U+DFFF) and code points past U+10FFFF refused.
  - A character split across pieces at every byte, and a piece ending mid-character
    told apart from one ending on a whole character.

## M2 — the frame codec

- **M2.1 decode** `(websocket frame)`:
  - headers whole, and split at every byte;
  - the three length forms at their edges: 125, 126, 65535 and 65536;
  - unmasking at every payload offset;
  - each refusal of design §4 with its 1002;
  - RFC 6455 §5.7's examples.
- **M2.2 encode**: the server's frames, unmasked and in shortest form. §5.7's unmasked
  examples, byte for byte, and a decode of each encode.

## M3 — the protocol

- **M3.1 messages and limits** `(websocket protocol)`, `(websocket limits)`:
  - whole and fragmented messages, text and binary;
  - control frames between fragments;
  - the cap at its edge, failing 1009 before any payload is held;
  - UTF-8 failing 1007 at the first bad byte;
  - reading on: the queue up to a cap, or 16 messages (0001's amendment),
    `read-stop`, then `read-start` on `taken`;
  - the limits read from an environment's strings, malformed values refused;
  - a client's close, answered, its code and reason checked, 1005 told: moved here
    from M3.2 by form on 2026-10-05, since the bytes M3.1 reads can carry one.
- **M3.2 the closing handshake**:
  - a close sent, and closes crossing; a message that comes after the server's close
    delivered as before, by form on 2026-10-05;
  - the close timeout, by its deadline's kind;
  - the stream's end, 1006 told; 1005 and 1006 never sent.
- **M3.3 the ping clock**:
  - a quiet client pinged when `ping` passes, and failed 1011 when `pong` passes;
  - any bytes received re-arm it;
  - it is stopped while reading is.

  Then the protocol's mutation sweep.

## M4 — the handshake and the binding

- **M4.1 the handshake** `(websocket handshake)`:
  - design §3's checks and answers: the pure library is given the method and the
    header fields, so its tests need no server; the facade reads them off the request;
  - subprotocols;
  - `Origin`, decided by form here (0022): the request's own host by default, and a
    wrong version refused 400 (0003).
- **M4.2 the binding's test driver**: the server's fake shell, or a door change in the
  server (design §8), decided by form. Decided (0004): the server's fake shell, and a
  door change too, `transport-abort!` and `request-header-values` (the server's
  v0.4.0, pinned here). `tests/test-driver.sps` holds what the binding needs of the
  fake, through the pin.
- **M4.3 the binding** `(websocket private binding)` and the facade, in three steps
  (2026-10-09): 1, the binding and the facade on the fake shell; 2, a client that does
  not read, with the send side's bound by form; 3, the real socket and the measures.
  Step 2's form (0006): reading stops past the high water, with a write timeout of its
  own, `CHEZ_WS_WRITE_TIMEOUT`, 60 s. Its review's forms (0006's amendment): the close
  timed from queueing, as peers time it, and at least 1 s; a send that waits before
  it writes too; a frame written in pieces of 64 KiB.
  - receive, send, close and backpressure;
  - a text message that begins with U+FEFF delivered with it, since Chez's decoders
    drop it;
  - the server's drain and the stream's close;
  - a client that does not read closed with `transport-abort!` (0004);
  - a real-socket suite on `127.0.0.1:0`;
  - a connection's cost, measured beside the server's own, measured again at the pin
    (design §9);
  - a client silent after the 101, pinged at the ping interval and failed with 1011 a
    timeout later, so a binding that never arms `ws-deadline`'s deadline fails it
    (M3.3's review);
  - when the pong's time starts, measured with a throttled reader (design §9);
  - the send side's bound for a client that sends and does not read, by form
    (design §9): decided in step 2 (0006);
  - a field split over lines: the facade reads every line, `request-header-values`
    joined with commas (0004; design §9; M4.1).

## M5 — the Autobahn lane

Pulling `crossbario/autobahn-testsuite:25.10.1`, pinned by digest and linux/amd64
only, needs the owner's word first.
- Its fuzzing client runs in Linux CI against an echo server built from this library.
- The gate parses `index.json`, and a ratchet holds every case's verdict.
- 301 cases: all but 12.x and 13.x, which are compression's.
- A local run on the arm64 development machine needs emulation.

## M6 — v0.1.0

The CHANGELOG's first release, the README's status, and the tag.
