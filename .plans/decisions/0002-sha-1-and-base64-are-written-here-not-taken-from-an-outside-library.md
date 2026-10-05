# 0002: SHA-1 and base64 are written here, not taken from an outside library

Date: 2026-10-05
Status: accepted (user decision, 2026-10-05: "keep our own, record the decision", after
the survey below)
Brief: [the project brief](../2026-10-04-chez-websocket-project-brief.md)

## Context

The brief said neither SHA-1 nor base64 "exists in the server or its dependencies, so
this library writes both", and looked no further. After M1.1 had merged
`(websocket sha1)`, the owner asked whether a Chez base64 library already existed.
What exists, each read from its source on 2026-10-05:
- **Chez Scheme 10.4.1** exports nothing named base64, SHA-1 or digest from
  `(chezscheme)` (measured with `library-exports`).
- **The server's pins** carry neither. chez-srfi, at the commit the server pins and
  upstream, has SRFI 13 but not SRFI 207.
- **SRFI 207** (final) has `bytevector->base64` and `base64->bytevector`. Its decoder
  skips whitespace and takes unpadded input (its own examples), so it cannot refuse a
  malformed key alone, and no chez-srfi carries it.
- **Industria 2.3.0** (Akku; MIT; Gwen Weinholt; `gitlab.com/weinholt/industria` at
  v2.3.0) has `(industria base64)`, with `base64-encode` and `base64-decode`. It imports
  `(rnrs)` and `(srfi :13 strings)`, and the package depends on hashing, ip-address
  and struct-pack.
- **hashing 1.4.0** (Akku; MIT; the same author; `gitlab.com/weinholt/hashing` at
  v1.4.0; no dependencies) has `(hashing sha-1)`.

## Decision

Keep this library's own: `(websocket sha1)`, merged in M1.1, and `(websocket base64)`,
M1.2's.

## Why

- **The handshake needs two narrow operations:** the base64 of a 20-byte digest, and a
  check that a 24-character key is the base64 of 16 bytes. Each is a small library,
  held to its RFC's vectors and watched to fail like the rest.
- **Taking them from outside would cost more than it saves.** It would add a pin from a
  new host, GitLab, and a decision record for each (global-constraints). It would also
  loosen the purity rule, since `(industria base64)` imports SRFI 13. That is a
  cryptography collection vendored for one file.

## Consequences

- The brief's line now cites this record.
- A dependency added later still needs its own record.
