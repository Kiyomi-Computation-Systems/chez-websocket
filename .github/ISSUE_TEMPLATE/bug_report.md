---
name: Bug report
about: Something broke or behaved unexpectedly
labels: bug
---

<!-- A suspected vulnerability? Don't file it here: SECURITY.md says how to
report it privately. A problem in the HTTP server underneath, outside the
WebSocket upgrade, belongs to chez-http-server's issues; if you are not sure
which, file it here. -->

**Environment**

- OS and architecture (e.g. macOS 15 arm64, Ubuntu 24.04 x86_64):
- Chez Scheme version (`chez --version`):
- libuv version (`pkg-config --modversion libuv`, or "built by chez-libuv"):
- chez-websocket version or commit:
- `make check-pins` output:
- The client (a browser and its version, or a library and its version):

**What happened**

**What you expected**

**How to reproduce it**

Ideally a small handler and the client that shows it: a `websocat` command,
a page's script, or the frames' bytes. A program runs with
`make run PROGRAM=repro.sps`.

**Does `make test` pass on your machine?**
