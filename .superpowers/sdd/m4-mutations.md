# M4 — mutation log

Every check in M4 was watched to fail: a single named mutation breaks the
asserted property, the check goes red, and the mutation is reverted. Recorded
per global-constraints ("a test is finished when it has been watched to fail").

## M4.1 — the handshake

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-06. The library is `src/websocket/handshake.sls` (blob 34e8f61), and the
suite `tests/test-handshake.sps`, 23 checks (blob 8bf2738).

The runner is M3's, pointed at this suite. It applies each mutant alone:
- a library mutant to a copy of the library, put first on the library path;
- the audit's mutant to a scratch copy of the tree.

It compares the checks that went red with the set named before the run, and leaves
the tree as it was. Before each run, a pre-flight checks that every cut matches its
text once and keeps its paren balance.

### The oracles

- **RFC 6455's example** (§1.3, §4.2.2): key `dGhlIHNhbXBsZSBub25jZQ==`, accept value
  `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`, and the subprotocol its server chose, chat.
- **The accept values of four other keys**, alike in three peers: Python 3.14's
  `hashlib` and `base64`, Node v20.10.0's `crypto`, and OpenSSL.
  - RFC 6455 §4.1's example key as printed, `AQIDBAUGBwgJCgsMDQ4PEC==`, gives
    `OfS0wDaT5NoxF2gqm7Zj2YtetzM=`;
  - the same bytes as erratum 3150 corrects the key gives
    `C/0nmHhBztSRGR1CwL6Tf4ZjwpY=`;
  - Chrome 152's two measured keys give `5U4UI4Mo7N9BGeXhuHaBN1/uENs=` and
    `w5g+AqJ3sLE19bigfXXLuee7fyI=`.
- **The base64 of 15, 17 and 24 bytes**: Python's `base64` and OpenSSL agreed.
- **Chrome 152's handshakes**, measured against a probe on the server: one from a page
  of the same origin, one from a page on localhost
  ([the research](../../.plans/research/2026-10-06-peer-handshakes.md)).
- **The design's §3, and decision 0003** by form.
- **The server's own rules** at v0.3.0: its `switch-fault` and `response-fault`.
- **The peers**, read from source: what each refuses and accepts (the research).
- **A real client.** Chrome 152 ran against a scratch probe that answered with the
  library, speaking superchat and chat, origins by default.
  - **A page of the same origin** opened, with `protocol` superchat, the handler's
    first preference among the two the client offered, and no extensions. The probe's
    close of 1000 then came clean.
  - **A page on localhost, to 127.0.0.1:** refused 403, for its origin; Chrome told an
    error and 1006.
  - **A page on localhost, to localhost:** opened.

### The test-first runs

- **Before the library:** `Exception: library (websocket handshake) not found`, exit
  255.
- **The first library run** passed all 21 checks of that draft. Writing the mutants
  then added P-TOKEN and the rows below, to 22 checks.
- **Decision 0003's checks**, named and hashed before the run (`32982d4`). Against the
  library before 0003 (426 for a version; no default for origins), exactly the three
  named went red: R-VERSION and R-ORDER, for the 426, and O-DEFAULT, whose call of four
  arguments raised. The other 20 stayed green, exit 1.

### Found by writing the mutants

Rows each written for a mutant the draft suite would have let pass:
- H-LISTS: an element with OWS after it (`websocket\t, h2c`, `Upgrade , close`), for L-5.
- R-UPGRADE:
  - `websocked`, a last character apart, for L-13 and L-14;
  - ` \t,h2c, \t`, untrimmed, its elements of OWS alone at either end, for L-8 and
    L-9.
- R-CONNECTION: `degrade`, the token's length, for L-13.
- S-LIST: `chat\t,v1`, for L-5.
- O-LIST: `HTTPS://ZOO.EXAMPLE`, a Z, for L-16.
- O-SAME:
  - `http//127.0.0.1:18741`, a scheme without its colon, for O-14;
  - `http://elsewhere.example/http://127.0.0.1:18741`, for O-12.
- O-HOST: `http://` to an empty host, as coder and gorilla compare it, for O-11.
- P-TOKEN, a check of its own: a subprotocol of every kind of tchar and each range's
  ends, and a character beside each range, for A-10 to A-22.

The library changed with them:
- **`past-scheme` matches `://` in one comparison** where it took three characters,
  each a conjunct no row told apart.
- **`origin-accepted?` is a `cond`**, so a mutant can change what `any` answers
  without falling through to a list (O-15).
- **S-4 chooses the handler's first** subprotocol when none matches. Before it,
  S-NONE's only killers raised.

### The form

Two questions, both measured first (decision 0003):
- **What a handler that names no origins checks**: "Same host", the recommended.
- **What a wrong version is refused with**: "400 with 13", the recommended; the
  design's 426 cannot carry what RFC 9110 has a 426 carry, through the server.

### The mutants

| key | check |
|---|---|
| H-RFC | RFC 6455's example handshake, the handler speaking chat: a 101 with Upgrade: websocket, the example's accept value and chat, and nothing more |
| H-CHROME | Chrome 152's handshakes, as measured: accepted with the accept values three peers computed, and no answer to its permessage-deflate offer |
| H-KEYBITS | a key whose last digit sets bits past its data, as RFC 6455 §4.1 prints its example, is accepted, and the accept value is of the key as sent |
| H-LISTS | Upgrade and Connection are lists, read without regard to case: Upgrade: WebSocket, Connection: keep-alive, Upgrade, and OWS and empty elements around them |
| R-METHOD | a method other than GET is refused 400, for its method |
| R-UPGRADE | an Upgrade missing, empty, or not listing websocket is refused 400, for its upgrade |
| R-CONNECTION | a Connection missing, empty, or not listing upgrade is refused 400, for its connection |
| R-VERSION | a Sec-WebSocket-Version missing, or not 13, is refused 400 with Sec-WebSocket-Version: 13, for its version (0003) |
| R-KEY | a Sec-WebSocket-Key missing, not base64, or the base64 of other than sixteen bytes is refused 400, for its key |
| R-ORDER | the checks are made in the design's order, the first that fails answering: method, Upgrade, Connection, Sec-WebSocket-Version, Sec-WebSocket-Key, Origin |
| S-PICK | the handler's first subprotocol the client offered is chosen, in the handler's order, not the client's, and the 101 names it |
| S-NONE | when none matches, the client offers none, or the handler speaks none, none is chosen, the 101 names none, and the handshake succeeds |
| S-LIST | the client's offer is a list: OWS around elements, and empty elements, are passed over |
| S-EXACT | a subprotocol is offered only as a whole element, case and all: Chat, chatty, xchat, cha and "chat" are not chat |
| O-DEFAULT | a handler that names no origins gets same-host (0003): Chrome's page of the same origin is accepted, its page on localhost refused 403, and a request with no Origin accepted |
| O-ABSENT | a request with no Origin, which is not a browser's, is accepted whatever the handler lists |
| O-ANY | any accepts every Origin: another host's, and null |
| O-LIST | a listed origin is accepted without regard to ASCII case; one not listed, or a part or extension of one, is refused 403, for its origin |
| O-SAME | same-host accepts an Origin whose host and port are the request's, without regard to case or scheme, as Chrome's page of the same origin; another host, another port, a path, null, or no scheme is refused 403 |
| O-HOST | same-host compares the host the request names, letters without regard to case, an empty one too, as coder and gorilla do, and refuses RFC 6455's own example, whose Origin names another host; a list may hold same-host beside origins |
| P-TOKEN | a subprotocol the handler speaks is a token: one holding every kind of tchar, and each range's ends, is chosen; one with a character beside a range, a separator, DEL or a character past ASCII is refused, naming handshake-answer |
| P-API | handshake-answer refuses arguments outside its contract, naming itself: a method not a symbol, a reader not a procedure, a host not a string, a subprotocol not a token, origins neither any nor a list of origins and same-host, and a field read as neither a string nor #f |
| H-SERVER | every answer is one the server writes: a 101's fields pass its switch-fault against the request's, and a refusal's its response-fault |

| # | mutation | red |
|---|----------|-----|
| B-0 | the library as written | none: the library unmutated, 23 passes |
| A-1 | a method that is not a symbol is not refused | P-API |
| A-2 | a reader that is not a procedure is not refused | P-API |
| A-3 | a host that is not a string is not refused | P-API |
| A-4 | subprotocols that are not a list reach for-all | P-API |
| A-5 | subprotocols are not checked as tokens | P-TOKEN, P-API |
| A-6 | token? takes a symbol to string-length | P-API |
| A-7 | an empty subprotocol is a token | P-API |
| A-8 | a token's characters are not checked | P-TOKEN, P-API |
| A-9 | tchar's lower letters start at b | H-RFC, R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, P-TOKEN, H-SERVER |
| A-10 | tchar's lower letters end at y | P-TOKEN |
| A-11 | tchar's capitals start at B | P-TOKEN |
| A-12 | tchar's capitals end at Y | P-TOKEN |
| A-13 | tchar's digits start at 1 | P-TOKEN |
| A-14 | tchar's digits end at 8 | P-TOKEN |
| A-15 | tchar's lower letters run on to { | P-TOKEN |
| A-16 | tchar's capitals start at @ | P-TOKEN |
| A-17 | tchar's capitals run on to [ | P-TOKEN |
| A-18 | tchar's digits start at / | P-TOKEN |
| A-19 | tchar's digits run on to : | P-TOKEN |
| A-20 | tchar lacks ! | P-TOKEN |
| A-21 | tchar lacks ~ | P-TOKEN |
| A-22 | tchar takes a comma | P-TOKEN, P-API |
| A-23 | origins any is refused | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, S-PICK, S-NONE, S-LIST, S-EXACT, O-ABSENT, O-ANY, P-TOKEN, H-SERVER |
| A-24 | origins that are not a list reach for-all | P-API |
| A-25 | origins' elements are not checked | P-API |
| A-26 | same-host is not an origin | O-DEFAULT, O-ABSENT, O-SAME, O-HOST |
| A-27 | a listed origin string is refused | R-ORDER, O-ABSENT, O-LIST, O-HOST |
| A-28 | a field's value is not checked | P-API |
| C-1 | the method is not checked | R-METHOD, R-ORDER |
| C-2 | the method must be get, in lower case | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-HOST, P-TOKEN, P-API |
| C-3 | Upgrade is not checked | R-UPGRADE, R-ORDER, P-API, H-SERVER |
| C-4 | Upgrade's websocket is compared with case | H-LISTS |
| C-5 | Upgrade is compared whole, not as a list | H-LISTS |
| C-6 | Connection is not checked | R-CONNECTION, R-ORDER |
| C-7 | Connection's upgrade is compared with case | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-HOST, P-TOKEN |
| C-8 | Connection is compared whole, not as a list | H-LISTS |
| C-9 | the version is not checked | R-VERSION, R-ORDER |
| C-10 | the version may be a list holding 13 | R-VERSION |
| C-11 | the version is read as a number | R-VERSION |
| C-12 | a wrong version is refused 426, the design's first answer | R-VERSION, R-ORDER |
| C-13 | a wrong version is refused with no field | R-VERSION |
| C-14 | the key is not checked | R-KEY, R-ORDER |
| C-16 | a key is the base64 of sixteen bytes or more | R-KEY |
| C-17 | a missing key reaches the decoder | R-KEY |
| C-18 | a key that is not base64 reaches bytevector-length | R-KEY, R-ORDER, H-SERVER |
| C-19 | the Origin is not checked | R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-HOST |
| C-20 | an Origin refused is answered 400 | R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-HOST |
| O-1 | a request with no Origin is refused | O-DEFAULT, O-ABSENT |
| O-2 | any is judged as a list | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, P-TOKEN, H-SERVER |
| O-15 | any accepts only the request's own host | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, P-TOKEN |
| O-3 | a listed origin is compared with case | O-LIST |
| O-4 | an Origin is accepted when a listed origin begins it | O-LIST |
| O-5 | same-host accepts nothing | O-DEFAULT, O-SAME, O-HOST |
| O-6 | same-host accepts everything | O-DEFAULT, O-SAME, O-HOST |
| O-7 | same-host is read as a listed origin | O-DEFAULT, O-SAME, O-HOST |
| O-8 | an Origin with no scheme is compared whole with the host | O-SAME |
| O-9 | the host is compared with case | O-HOST |
| O-10 | an Origin is accepted when the host begins what follows its scheme | O-SAME |
| O-11 | past-scheme misses a :// that ends the origin | O-HOST |
| O-12 | past-scheme finds the last :// | O-SAME |
| O-13 | past-scheme ends at :/ | O-DEFAULT, O-SAME, O-HOST |
| O-14 | past-scheme ends at //, the colon unasked | O-SAME, O-HOST |
| L-1 | an absent field reaches has-element? | R-UPGRADE, R-CONNECTION |
| L-2 | the empty last element is passed over (equivalent: no token is empty) | none (equivalent) |
| L-3 | after a comma, the next character is skipped | H-LISTS, S-LIST |
| L-4 | OWS before an element is kept | H-LISTS, S-PICK, S-LIST |
| L-5 | OWS after an element is kept | H-LISTS, S-LIST |
| L-6 | elements are separated by semicolons | H-RFC, H-LISTS, S-PICK, S-LIST |
| L-7 | find-comma runs past the end | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-HOST, P-TOKEN, H-SERVER |
| L-8 | skip-ows runs past the end | R-UPGRADE, R-CONNECTION, S-NONE |
| L-9 | back-ows runs past the start | H-LISTS, R-UPGRADE, R-CONNECTION, S-NONE, S-LIST |
| L-10 | HTAB is not OWS | H-LISTS, S-LIST |
| L-11 | SP is not OWS | H-LISTS, S-PICK |
| L-12 | range=? does not compare lengths | R-UPGRADE, R-CONNECTION, S-NONE, S-EXACT, O-LIST, O-SAME, O-HOST |
| L-13 | range=? does not compare characters | R-UPGRADE, R-CONNECTION, S-EXACT, O-DEFAULT, O-LIST, O-SAME, O-HOST |
| L-14 | range=? leaves the last character unread | R-UPGRADE, O-LIST, O-SAME, O-HOST |
| L-15 | A is not folded | H-LISTS, O-LIST, O-HOST |
| L-16 | Z is not folded | O-LIST |
| L-17 | capitals fold one short | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-HOST, P-TOKEN |
| S-1 | an absent offer reaches has-element? | S-NONE |
| S-2 | subprotocols are compared without regard to case | S-EXACT |
| S-4 | when the offer names none of them, the handler's first is chosen | S-NONE, S-EXACT |
| S-3 | the handler's last preference wins | S-PICK |
| F-1 | the 101 never names the subprotocol | H-RFC, S-PICK, S-LIST, P-TOKEN |
| F-2 | the 101's Upgrade is WebSocket | H-RFC, H-CHROME |
| F-3 | the accept field is named Sec-Websocket-Accept | H-RFC, H-CHROME, H-KEYBITS |
| F-4 | the accept value is of the key re-encoded | H-KEYBITS |
| F-5 | the GUID ends in 2 | H-RFC, H-CHROME, H-KEYBITS |
| F-6 | the 426 names version 8, 13 | R-VERSION |
| F-7 | a refusal carries Content-Length: 0 | R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, H-SERVER |
| F-8 | a refusal names no check | R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-HOST |
| R-1 | the method is checked after Upgrade | R-ORDER |
| R-2 | Connection is checked before Upgrade | R-ORDER, P-API |
| R-3 | the version is checked before Connection | R-ORDER |
| C-15 | a key is any 24 characters | R-KEY |
| R-4 | the key is checked after the Origin | R-ORDER |
| R-5 | the version is checked after the key | R-ORDER |
| AUD-1 | (websocket handshake) imports (chezscheme) | the import audit's check of its library, alone |
| D-1 | a handler that names no origins gets any | O-DEFAULT |
| D-2 | a handler that names no origins gets none | O-DEFAULT |
| D-3 | origins given are dropped for the default | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, O-LIST, O-HOST, P-TOKEN, P-API |

**The runs**, each red set named before the run and hashed:
- **The first**, before 0003 (`c0ebf63`): 99 rows, 98 mutants and the baseline. Two
  mismatches, both prediction errors:
  - O-14's `//` kept the loop's three-character bound, so an Origin ending in `://`
    falls past it, and O-HOST went red too.
  - L-14 leaves the last character unread, so an empty range reads past its end, and
    O-HOST raised.
- **The second**, on 0003's library (`9c29011`): 102 rows, the two red sets as found,
  C-12 turned to "refused 426", and D-1 to D-3 for the default. 0 mismatches.
- **The last**, on this record's blobs, the same specs: 102 rows, 101 mutants and the
  baseline, 0 mismatches.

L-2, `fx<?` for `fx<=?` in `has-element?`, is equivalent and stays green. It passes
over the empty element after a last comma, and no token is empty: the handler's names
are checked as tokens, and `websocket` and `upgrade` are not empty.

In 24 rows a check went red through a raise: A-9 to A-14, A-20, A-21, A-23, A-26,
A-27, C-14, C-17, C-18, O-2, O-7, L-1, L-7, L-8, L-9, L-12, L-14, S-1 and F-3. Every
such check has a killer by value too.

Every check has killers, at least one of them by value:

| check | killers by value |
|---|---|
| H-RFC | C-2, C-7, D-3, F-1, F-2, F-3, F-5, L-6, L-17, O-15 |
| H-CHROME | C-2, C-7, D-3, F-2, F-3, F-5, L-17, O-15 |
| H-KEYBITS | C-2, C-7, D-3, F-4, F-5, L-17, O-15 |
| H-LISTS | C-2, C-4, C-5, C-7, C-8, D-3, L-3, L-4, L-5, L-6, L-10, L-11, L-15, L-17, O-15 |
| R-METHOD | C-1, F-7, F-8 |
| R-UPGRADE | C-2, C-3, F-7, F-8, L-13, L-14 |
| R-CONNECTION | C-2, C-6, F-7, F-8, L-13 |
| R-VERSION | C-2, C-7, C-9, C-10, C-11, C-12, C-13, F-6, F-7, F-8, L-17 |
| R-KEY | C-2, C-7, C-15, C-16, F-7, F-8, L-17 |
| R-ORDER | C-1, C-2, C-3, C-6, C-7, C-9, C-12, C-14, C-19, C-20, F-8, L-17, R-1, R-2, R-3, R-4, R-5 |
| S-PICK | C-2, C-7, D-3, F-1, L-4, L-6, L-11, L-17, O-15, S-3 |
| S-NONE | C-2, C-7, D-3, L-12, L-17, O-15, S-4 |
| S-LIST | C-2, C-7, D-3, F-1, L-3, L-4, L-5, L-6, L-10, L-17, O-15 |
| S-EXACT | C-2, C-7, D-3, L-13, L-17, O-15, S-2, S-4 |
| O-DEFAULT | C-2, C-7, C-19, C-20, D-1, D-2, F-8, L-13, L-17, O-1, O-5, O-6, O-13 |
| O-ABSENT | C-2, C-7, L-17, O-1 |
| O-ANY | C-2, C-7, D-3, L-17, O-15 |
| O-LIST | C-2, C-7, C-19, C-20, D-3, F-8, L-13, L-14, L-15, L-16, L-17, O-3, O-4 |
| O-SAME | C-2, C-7, C-19, C-20, F-8, L-13, L-14, L-17, O-5, O-6, O-8, O-10, O-12, O-13, O-14 |
| O-HOST | C-2, C-7, C-19, C-20, D-3, F-8, L-12, L-13, L-15, L-17, O-5, O-6, O-9, O-11, O-13, O-14 |
| P-TOKEN | A-5, A-8, A-15, A-16, A-17, A-18, A-19, A-22, C-2, C-7, D-3, F-1, L-17, O-15 |
| P-API | A-1, A-2, A-3, A-4, A-5, A-6, A-7, A-8, A-22, A-24, A-25, A-28, C-2, C-3, D-3, R-2 |
| H-SERVER | C-3, F-7 |
