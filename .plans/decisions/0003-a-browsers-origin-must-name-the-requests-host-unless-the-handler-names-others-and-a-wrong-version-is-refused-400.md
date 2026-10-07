# 0003: A browser's Origin must name the request's host, unless the handler names others; a wrong version is refused 400

Date: 2026-10-06
Status: accepted (user decision, 2026-10-06, by form, M4.1: "Same host" and "400 with
13", each the recommended). Amended 2026-10-06 on the owner's word (M4.1's review):
"compare with X-Forwarded-Proto", the recommended.
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

## Amendment of 2026-10-06 (M4.1's review): the scheme, when a proxy names it

M4.1's review found that `same-host` compares only an Origin's host and port. A browser
leaves a default port out of both `Origin` and `Host`. So a page on
`http://app.example.com` passes for `wss://app.example.com`, though http on port 80 and
https on port 443 are different origins. coder and gorilla compare the same way
(gorilla `server.go:98`, coder `accept.go:239`, at the tags of
[the research](../research/2026-10-06-peer-handshakes.md)). coder holds the scheme only
for an origin pattern that holds `://` (`accept.go:244-246`).

**Who can use it, and what they get.** Behind Caddy, no real page lives on the http
side: Caddy redirects port 80 to https. It sends no HSTS unless told to, though, so a
network attacker can answer the browser's plain-http request with a page of their
own. That page's socket comes from the user's browser, and no CORS rule covers a
WebSocket: the page reads and sends what it likes. It is the user's session only
where the browser sends the session cookie across schemes:
- **Chrome** counts http and https of one host as different sites (since 89), and a
  cookie with no `SameSite` as `Lax` (since 85). So it sends only `SameSite=None`
  cookies there (Chrome's platform status).
- **Firefox and Safari:** Chrome's status page records Firefox's position as positive
  and Safari's as no signal. Not measured here.

**The server can tell.** Caddy writes `X-Forwarded-Proto`, `https` when its client used
TLS and `http` otherwise. It replaces any value a client sent, unless that client is a
trusted proxy (`modules/caddyhttp/reverseproxy/reverseproxy.go:997-1009` at v2.11.7;
its docs' `reverse_proxy.md:505-508`). A browser cannot set the field on a WebSocket
handshake.

**Decided on the owner's word**, "compare with X-Forwarded-Proto", after these facts and
a measured prototype:
- When the request's `X-Forwarded-Proto` is `http` or `https`, without regard to ASCII
  case, `same-host` also needs the Origin's scheme to be that one.
- Any other value is not compared, and neither is no value: as before, and as coder and
  gorilla compare.
- A listed origin, compared whole, and `any` are not held to it.

**Why no value is not a refusal:**
- **With no proxy**, the server speaks plain HTTP, and a browser will not let an https
  page open `ws://`. Measured in Chrome 152: from an https page, `ws://example.com`
  threw a `SecurityError`, and sockets to `ws://127.0.0.1` and `ws://localhost` never
  reached the server. So no scheme can mismatch.
- **Behind a TLS proxy that sends no value**, either guess is worse than none:
  - taking it for `http` refuses every real https page, while the attacker's http
    page still passes;
  - taking it for `https` refuses a server's own pages wherever no proxy stands in
    front.

Weighed and not taken: **"Keep host-only"**, coder's and gorilla's way, with docs
advising HSTS and an exact https origin.

**Consequences:**
- **Behind Caddy**, which always writes the field, a page on the http side of the site's
  own host is refused 403.
- **Behind a TLS proxy that sends no `X-Forwarded-Proto`**, the gap stays as it was.
  There, the proxy can send it (nginx: `proxy_set_header X-Forwarded-Proto $scheme;`),
  HSTS can keep browsers off plain http, or the handler can list its exact https
  origin.
- **If something in front of Caddy ends TLS and talks plain HTTP to Caddy**, Caddy writes
  `http`, and the site's https pages are refused 403 until Caddy's `trusted_proxies`
  names that hop.
- **The check only ever refuses more** than M4.1's: with no value it is the same.
