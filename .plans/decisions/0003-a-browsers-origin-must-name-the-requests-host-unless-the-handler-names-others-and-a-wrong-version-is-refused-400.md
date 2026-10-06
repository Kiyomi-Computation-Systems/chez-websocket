# 0003: A browser's Origin must name the request's host, unless the handler names others; a wrong version is refused 400

Date: 2026-10-06
Status: accepted (user decision, 2026-10-06, by form, M4.1: "Same host" and "400 with
13", each the recommended)
Design: [the design](../2026-10-04-chez-websocket-design.md) §3

## Context

chez-http-server's decision 0022 left `Origin` to M4, and the design's §3 named 426 for
a wrong `Sec-WebSocket-Version`. Building `(websocket handshake)` in M4.1 measured both.
The peers were read from source at their tags
([the survey](../research/2026-10-06-peer-handshakes.md)); Chrome was measured against
the server.

**Origin.** A browser sends `Origin` on every WebSocket handshake, with the site's
cookies. So a page on another site can open a WebSocket as the logged-in user, unless
the server checks (RFC 6455 §10.2: such a server SHOULD, answering 403).
- **Chrome 152, measured** against a probe on the server (Darwin arm64): a page on
  `http://127.0.0.1:18741` sent `Origin: http://127.0.0.1:18741` with
  `Host: 127.0.0.1:18741`; a page on `http://localhost:18741` sent
  `Origin: http://localhost:18741` to the same server.
- **Clients that are not browsers send none by default**: Autobahn's fuzzing client
  (autobahn 0.10.9, as the testsuite's v25.10.1 pins it) sends `Origin` only when its
  spec names one. And such a client may send any `Origin` it likes.
- **Caddy 2.11.7** passes `Host` and `Origin` unchanged to a plaintext upstream (its
  documentation, and its transport's source): the owner's deployment.
- **Peers' defaults:** coder and gorilla accept no Origin, or one whose host and port
  equal the request's `Host`, without regard to case, and answer others 403; a list
  or a callback widens it. websockets, tungstenite and ws check nothing unless the
  application lists origins or gives a callback.

**The version.** RFC 6455 §4.2.2 says to answer an unknown version with an error
"(such as 426 Upgrade Required)" and `Sec-WebSocket-Version`, and §4.4's own example
is a 400. RFC 9110 §15.5.22 has a 426 carry `Upgrade`, and §7.8 has a sender of
`Upgrade` put `upgrade` in `Connection`. The server lets a handler's response say only
`Connection: close`. Measured through the server: a 426 with `Connection: upgrade` is
a fault it answers 500 (`invalid-response connection-field`), and a 426 with `Upgrade`
alone goes out with `Connection: close` to an upgrade request, and with no `Connection`
to a plain GET. No peer answers a version with 426: gorilla and coder answer 400 with
`Sec-WebSocket-Version: 13`, ws 400 with `13, 8`, and websockets 400 with no field.

## Decision

By form, the recommended answer to each of two questions:

1. **"Same host"**: a handler that names no origins accepts a request with no `Origin`,
   or one whose host and port, past its scheme's `://`, are the request's host, letters
   without regard to case, and refuses others 403: coder's and gorilla's way. A handler
   may name `any`, or a list of origins, compared without regard to ASCII case, that may
   hold `same-host`. A request with no `Origin` is accepted whatever the handler names.
2. **"400 with 13"**: a missing or wrong `Sec-WebSocket-Version` is refused 400, with
   `Sec-WebSocket-Version: 13`, as RFC 6455 §4.4's example and gorilla and coder answer.

Weighed and not taken:
- **"No check"**, websockets', ws' and tungstenite's default: a page on any site could
  open a WebSocket with the user's cookies unless the handler listed origins.
- **"426 as designed"**: it breaks RFC 9110 §15.5.22's MUST.
- **"426 with Upgrade"**: it goes out without `upgrade` in `Connection`, so it breaks
  §7.8's MUST.

## Consequences

- **A page on another host or port is refused 403** unless the handler names it, a
  development server on another port among them (`http://localhost:5173`). So is
  RFC 6455's own example, whose `Origin` (`http://example.com`) names another host than
  its `Host` (`server.example.com`).
- **Behind Caddy, a site's own pages are accepted**, since `Host` and `Origin` reach the
  server unchanged. A `Host` rewritten on the way (`header_up Host`, or an HTTPS
  upstream, for which Caddy 2.11 sets it to the upstream's) refuses them.
- **Autobahn is accepted**: its fuzzing client sends no `Origin`.
- **A browser cannot be made to send another site's `Origin`**, and a client that is not
  a browser can send any, so the check holds browsers alone, as RFC 6455 §10.2 says.
- **The design's §3** says 400 for the version.
