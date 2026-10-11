# The python child of ws-cost.sps (beside it): see that file for how to run.
# Holds n connections to the server at 127.0.0.1:port, then says "ready" and
# waits for its stdin to close.  Mode "ws": each a WebSocket, RFC 6455 §1.3's
# handshake, then r echoes of a masked 2-byte text, each read back.  Mode
# "http": each a GET answered 200 "ok", kept alive.
import socket, sys
mode, port, n, r = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
def until(s, end):
    buf = b""
    while not buf.endswith(end):
        c = s.recv(1)
        if not c: raise SystemExit("closed early")
        buf += c
    return buf
def exactly(s, k):
    buf = b""
    while len(buf) < k:
        c = s.recv(k - len(buf))
        if not c: raise SystemExit("closed early")
        buf += c
    return buf
socks = []
for i in range(n):
    s = socket.create_connection(("127.0.0.1", port))
    if mode == "ws":
        s.sendall(b"GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
        head = until(s, b"\r\n\r\n")
        if not head.startswith(b"HTTP/1.1 101"): raise SystemExit("not 101: %r" % head[:40])
        key = bytes([0x37, 0xFA, 0x21, 0x3D])
        frame = bytes([0x81, 0x82]) + key + bytes(b ^ key[j % 4] for j, b in enumerate(b"hi"))
        for _ in range(r):
            s.sendall(frame)
            if exactly(s, 4) != b"\x81\x02hi": raise SystemExit("bad echo")
    else:
        s.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        head = until(s, b"\r\n\r\n")
        if not head.startswith(b"HTTP/1.1 200"): raise SystemExit("not 200")
        exactly(s, 2)
    socks.append(s)
sys.stdout.write("ready\n"); sys.stdout.flush()
sys.stdin.read()
for s in socks: s.close()
