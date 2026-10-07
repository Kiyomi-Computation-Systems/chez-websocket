# Peers' opening handshakes, read from source, and the handshake measured (2026-10-06)

The evidence for [decision 0003](../decisions/0003-a-browsers-origin-must-name-the-requests-host-unless-the-handler-names-others-and-a-wrong-version-is-refused-400.md)
and the design's §3, for M4.1. A Sonnet agent read each file through `gh api
contents?ref=TAG`, saving it and counting lines from the saved copy, and a script
checked each of its 362 quotes against the copies. Nothing was cloned, installed or
run. I measured the rest against the server.

| peer | tag | commit |
|---|---|---|
| Python websockets | 17.2 | a1664f4c5a7c71bf5391ad0c3c518e431f6261fb |
| gorilla/websocket | v1.5.3 | ce903f6d1d961af3a8602f2842c8b1c3fca58c4d |
| coder/websocket | v1.8.15 | 9c8faadccd1b679e811a79ce506f8a10237251ad |
| tungstenite-rs | v0.30.0 | 7f4aeaf0944992c5664c8fb8e0d54577c7e18020 |
| ws | 8.22.0 | 297202cdae9b0590629821373b3b679c407f3431 |
| autobahn-testsuite | v25.10.1 | 6ed6f439dc7ed0d7432fe2cf7481b110905ecc5c |
| autobahn-python, as the testsuite pins it | v0.10.9 | cf10233bec6d2e3b2cd4ce14a50ac7f43180617b |
| Caddy | v2.11.7 | 72dd0fb067f6d7826c7f79907670ba4a713bfe37 |

Paths: websockets' under `src/websockets/`; the others' from the repository root.

## The checks, in order, and their answers

| peer | order, first to last | the answers |
|---|---|---|
| websockets | method, HTTP version, Connection, Upgrade, Key, Version, Origin, subprotocol | 405 with `Allow: GET`; 505; 426 with `Upgrade: websocket` for Connection and Upgrade; 400 for the rest; 403 for Origin (server.py:262-312, :156-216) |
| gorilla | Connection, Upgrade, method, Version, Origin, Key | 400; 405; 403 for Origin; `Sec-Websocket-Version: 13` on every error (server.go:128-157, :82) |
| coder | HTTP version, Connection, Upgrade, method, Version, Key, Origin | 426 with `Connection: Upgrade` and `Upgrade: websocket`; 405; 400 with `Sec-WebSocket-Version: 13` for Version; 400; 403 (accept.go:185-221, :123) |
| tungstenite | method, HTTP version, Connection, Upgrade, Version, Key | no response written: an error is returned (src/handshake/server.rs:38-98, :261-284) |
| ws | method, Upgrade, Key, Version, subprotocol | 405; 400; 400 with `Sec-WebSocket-Version: 13, 8` for Version; Origin is the application's callback, 401 by default (lib/websocket-server.js:251-353); Connection is not checked |

No peer answers a version with 426. websockets' 400 for a version carries no
`Sec-WebSocket-Version` (server.py:308).

## Fields the client may repeat

- **Upgrade and Connection** are read as token lists over every line by websockets,
  gorilla and coder (websockets wants one Upgrade token alone, server.py:284); by
  tungstenite from the first line; ws compares Upgrade whole after Node joins the
  lines.
- **The version** must be `13` exactly in websockets, coder (first line) and
  tungstenite (first line); gorilla takes a list holding 13 on any line
  (server.go:140); ws takes 13 or 8 (lib/websocket-server.js:269).
- **The key** must decode to 16 bytes everywhere (ws by a regex of 22 characters and
  `==`, lib/websocket-server.js:16). Two lines are refused by websockets
  (server.py:292), coder (accept.go:215) and ws (Node joins them); gorilla and
  tungstenite take the first.

## Origin, by default

| peer | default | how |
|---|---|---|
| websockets | none | a list given: the value equal to a listed string or matching a regex; no Origin accepted only if `None` is listed (server.py:339-344) |
| gorilla | the request's host | no Origin accepted; else the URL's host, with its port, equal to the request's `Host` without regard to ASCII case; else 403 (server.go:90-98) |
| coder | the request's host | the same, then its `OriginPatterns` (accept.go:229-257) |
| tungstenite | none | the application's callback |
| ws | none | the application's `verifyClient` (doc/ws.md:126) |

## Subprotocols

| peer | whose order | compared | no match |
|---|---|---|---|
| websockets | the server's | exactly | 400 (server.py:497-512) |
| gorilla | the server's | exactly (server.go:106) | no header, success |
| coder | the server's | without regard to case, the client's spelling sent back (accept.go:268-271) | no header, success |
| tungstenite | the callback's | — | — |
| ws | the client's first, unless a callback chooses (lib/websocket-server.js:406) | — | no header, success |

Only websockets checks the names an application gives, as tokens, in its `serve`
(asyncio/server.py:667, headers.py:481). Its `serve` also answers `permessage-deflate`
by default (asyncio/server.py:494); gorilla, coder and ws ignore
`Sec-WebSocket-Extensions` unless compression is turned on, and tungstenite's server
has no extensions.

## Autobahn's fuzzing client

Its request (autobahn/websocket/protocol.py:3901-3976): `GET`, `Host` as host and port
always, `Upgrade: WebSocket`, `Connection: Upgrade`, a key of 16 random bytes and
`Sec-WebSocket-Version: 13`. It sends `Origin` and `Sec-WebSocket-Protocol` only when
the spec names them (autobahntestsuite/fuzzing.py:1266-1268), and the default spec
names neither. Only cases 12 and 13 offer `permessage-deflate`.

## Caddy's reverse proxy

- **`Host` and `Origin` reach a plaintext upstream unchanged.** Its docs list three
  exceptions, the `X-Forwarded-` fields (the website's
  `src/docs/markdown/caddyfile/directives/reverse_proxy.md:502-506`, master branch,
  not a tag). Its transport injects no `Host` without TLS
  (modules/caddyhttp/reverseproxy/httptransport.go:632-634).
- **Since 2.11.0, an HTTPS upstream gets the upstream's `Host`.**
- **A WebSocket's `Connection` and `Upgrade` are rewritten**, to `Upgrade` and the
  client's first Upgrade value lowercased (reverseproxy.go:860-883, :1651).
- **WebSockets are closed on a config reload**, by default.

## Measured (Darwin 25.6.0 arm64, chez-http-server v0.3.0)

- **Chrome 152** opened WebSockets to a probe on the server. From a page on
  `http://127.0.0.1:18741` it sent:
  - `Origin: http://127.0.0.1:18741` and `Host: 127.0.0.1:18741`;
  - `Upgrade: websocket` and `Connection: Upgrade`;
  - `Sec-WebSocket-Protocol: chat, superchat` (one line);
  - `Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits`.

  From a page on `http://localhost:18741` it sent `Origin: http://localhost:18741` to
  the same server.
- **Fields split over lines**, sent raw to a handler that answers a switch:
  - The server opens its door to `Connection: keep-alive` and `Connection: Upgrade` on
    two lines, and to `Upgrade: h2c` and `Upgrade: websocket` on two lines.
  - Its `request-header` reads only the first line of each: `keep-alive`, and `h2c`.
  - Of two `Sec-WebSocket-Protocol` lines, it reads the first; of two
    `Sec-WebSocket-Key` lines, the first.
- **A handler's 426:**
  - with `Connection: upgrade`, it is answered 500 (`invalid-response
    connection-field`);
  - with `Upgrade: websocket` alone, it goes out with `Connection: close` to an upgrade
    request, and with no `Connection` to a plain GET.

## For M4.1's review: the scheme

- **coder and gorilla compare no scheme.** gorilla's `checkSameOrigin` ends
  `return equalASCIIFold(u.Host, r.Host)` (server.go:98). coder's `authenticateOrigin`
  accepts `strings.EqualFold(r.Host, u.Host)` (accept.go:239), and holds the scheme only
  for an `OriginPatterns` entry with `://` in it (accept.go:244-246).
- **Caddy v2.11.7 and the scheme:**
  - **It writes `X-Forwarded-Proto` itself**: `https` when its client used TLS, `http`
    otherwise. A client's value counts only from a trusted proxy, and `Set` replaces
    it (reverseproxy.go:997-1009; docs `reverse_proxy.md:505-508`).
  - **It redirects HTTP to HTTPS** by default (the website's `automatic-https.md:46`).
    Neither that page nor `autohttps.go` mentions HSTS.
- **Chrome's platform status**, read 2026-10-06:
  - "Schemeful same-site" (5096179480133632), enabled by default in Chrome 89: http
    and https of one host are different sites. Firefox's position: positive; Safari:
    no signal.
  - "Cookies default to SameSite=Lax" (5088147346030592), enabled by default in Chrome
    85. Firefox: in development; Safari: no signal.
- **Chrome 152 from an https page (chromestatus.com), measured:**
  - `new WebSocket("ws://example.com/")` threw `SecurityError`: "An insecure WebSocket
    connection may not be initiated from a page loaded over HTTPS."
  - Sockets to `ws://127.0.0.1:18744` and `ws://localhost:18744` were made, then
    failed, and the probe there logged no request.
- **The server reads no `X-Forwarded-` field:** none of its `src/` names one, at v0.3.0.

## Not found, and caveats

- Go's `Header.Get` (the first line) and Node's joining of lines were read at Go 1.27.1
  and Node v24.21.0, which the peers do not pin.
- How ws coerces a version, and how Go parses `url.Parse("null")`, follow from the
  languages' rules. Neither was run.
