# Testing

`make test` runs every suite under `tests/`. Each part is held to answers
that come from somewhere else, not only to its own:

- **Standards:** RFC 3174's SHA-1 vectors, RFC 4648's base64 vectors,
  RFC 3629's UTF-8 grammar, and RFC 6455's examples and rules.
- **Real clients:** Chrome's handshakes.
- **Other code:** values computed alike by Python, Node, Perl, OpenSSL and
  ws.
- **These pages:** every Scheme block here runs, and the variables, defaults
  and names are checked against the library.

## Autobahn|Testsuite

[Autobahn|Testsuite](https://github.com/crossbario/autobahn-testsuite) is
the standard WebSocket conformance suite. Its fuzzing client attacks a
server with good and bad traffic, case by case, and grades each answer.

```sh
make autobahn
```

This runs the client in Docker against
[tests/autobahn/echo.sps](../tests/autobahn/echo.sps), an echo server built
from the library. It fails if any case's verdict differs from
[tests/autobahn/verdicts.txt](../tests/autobahn/verdicts.txt), better or
worse. On macOS and Windows the echo server runs in a Linux container beside
the client; `make echo-image` builds it.

## The results

301 cases, all but compression's (12.x and 13.x; there is no 11.x), against
the echo server at a 16 MiB cap, the largest message the cases send. **None
fails.**

| Verdict                    | Cases                                         |
|:---------------------------|:----------------------------------------------|
| OK                         | every case not below                          |
| NON-STRICT                 | 3.2, 3.3, 4.1.3, 4.1.4, 4.2.3, 4.2.4 and 5.15 |
| OK or NON-STRICT, by run   | 3.4, 4.1.5 and 4.2.5                          |
| INFORMATIONAL              | 7.1.6, 7.13.1 and 7.13.2, as the cases say    |

- **NON-STRICT** cases send a message and then a bad frame, back to back.
  The server reads both at once and closes with `1002` before it has echoed
  the message; the strict verdict wants the echo first. python-websockets
  gets the same verdict.
- **OK or NON-STRICT** cases send the same a few bytes at a time. Which
  verdict a run gets depends on how the bytes fall into reads, so
  `verdicts.txt` lists both.

Two runs on macOS gave 291 OK, 7 NON-STRICT and 3 INFORMATIONAL; then 290, 8
and 3, with case 3.4 NON-STRICT.
