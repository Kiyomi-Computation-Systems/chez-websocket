# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release (see [CHANGELOG.md](CHANGELOG.md)) | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository. Do not open a
public issue.

You can expect an acknowledgement within 7 days.

This library reads bytes from any client that connects: reports touching
what a client can send are especially welcome. That means the opening
handshake, the frame decoder, UTF-8 checking, the closing handshake, and
the limits that bound memory and time (message size, the queue, unsent
bytes, the ping and close timeouts). Please include your platform, Chez
version, `make check-pins` output, and the bytes or client that shows the
problem.

A problem in the HTTP server underneath, outside the WebSocket upgrade,
belongs to
[chez-http-server](https://github.com/Kiyomi-Computation-Systems/chez-http-server/security);
if you are not sure which, report it here.
