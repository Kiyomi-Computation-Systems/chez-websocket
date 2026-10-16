# chez-websocket

WebSocket (RFC 6455) for
[chez-http-server](https://github.com/Kiyomi-Computation-Systems/chez-http-server),
the HTTP/1.1 server for Chez Scheme.

A WebSocket is a connection that stays open after one HTTP request, so the
browser and the server can each send messages whenever they like.
chez-websocket lets a chez-http-server handler take that request and talk on
the connection: wait for a message, send one, close.

⚠️ **It is for servers.** There is no client, and no compression.

💡 These pages are Markdown in the repository's [docs](../docs) directory.

## A taste

An echo server: whatever a client sends to `/echo` comes back.

```scheme name=echo
(import (rnrs) (http-server) (websocket))

(serve
 (lambda (request)
   (if (string=? (request-path request) "/echo")
       (websocket-accept request
         (lambda (ws)                              ; runs once the handshake is done
           (let loop ()
             (websocket-send! ws (websocket-receive ws))
             (loop))))
       (make-response 404 #f '() (string->utf8 "not found\n")))))
```

## Four ideas to keep in mind

- **Your procedure waits; the server does not.** `websocket-receive` waits
  for the next message on a coroutine of its own, so other connections go on.
- **Messages arrive whole.** A string for text, a bytevector for binary,
  however the client split it up.
- **Everything has a limit.** Message size, waiting messages, unsent bytes
  and timeouts each have a default, and an environment variable to change it.
- **The end is a condition.** Once the connection has closed, a receive or a
  send raises `&websocket-closed`, which says how it closed.

## Read next

- [Installing](installing.md): what you need, `make build`, and running a
  program.
- [Handlers](handlers.md): taking a WebSocket, reading, writing, closing,
  subprotocols, origins and limits for one handler.
- [Examples](../examples): an echo, a chat room and a clock, each with a page
  to try it from a browser.
- [Configuration](configuration.md): the `CHEZ_WS_` variables.
- [How it works](how-it-works.md): a pure core, and a binding over the
  server.
- [API reference](reference.md): every exported name, one entry each.
- [Testing](testing.md): what checks the library, and the Autobahn results.
- [Performance](performance.md): what a connection costs, measured.
