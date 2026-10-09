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

## M4.1's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-06. The library is `src/websocket/handshake.sls` (blob cc49751). The suites:
- `tests/test-handshake.sps`, 26 checks (blob ffadc1d);
- `tests/test-door.sps`, 5 checks (blob f7f8666).

The review, `/code-review` at high effort over #27 to #29, reported six findings.
- **The scheme:** discussed with the owner, and decided on their word: "compare with
  X-Forwarded-Proto" (0003's amendment).
- **The other five:** "fix the rest".

The runner is M4.1's, now running the door suite too.

### The findings and their fixes

| # | finding | fix |
|---|---|---|
| 1 | `same-host` ignores the Origin's scheme | when the request's `X-Forwarded-Proto` names `http` or `https`, the Origin's scheme must be it (0003's amendment) |
| 2 | an empty `Origin` is refused, unchecked and undecided | kept as built, gorilla's way, and recorded: it names no host (RFC 6454 §7.1); rows in O-SAME, O-LIST and O-ANY |
| 3 | the design's §9 said a split `Sec-WebSocket-Protocol` is refused | it is not: its later offers are missed, and the 101 goes without them |
| 4 | the answers hand out shared mutable bytevectors | each answer's fields, and its subprotocol's string, are made for it (H-FRESH) |
| 5 | the handshake's suite imports the server's internal serializer | the check moves to the door suite, D-SERVER; the handshake's suite needs no server, as the plan says |
| 6 | a handler's settings are checked at every handshake | `make-handshake-settings` checks them once, where they are made, and keeps copies (P-SETTINGS, P-KEEP); `handshake-answer` takes the settings |

### The oracles

- **Decision 0003's amendment** and the research's section for the review:
  - coder's and gorilla's source;
  - Caddy's `X-Forwarded-Proto` and its HTTPS redirect, from its source and docs at
    v2.11.7;
  - Chrome's platform status on schemeful same-site and on `SameSite=Lax` by default.
- **Chrome 152, measured:** an https page cannot open `ws://`.
- **The rows of O-SCHEME** follow from 0003's amendment. The prototype the owner saw
  ran the same table.

### The test-first runs

- **The review's suites against #29's library**, named and hashed before the run
  (`3a9ccdc`): both stopped at load, exit 255, `make-handshake-settings` unbound.
- **Against stage 1**, the settings API alone, named and hashed (`678dc43`). Exactly the
  four named went red, each for the reason named, with the other 22 and the door's 5
  green:
  - O-SCHEME accepted every scheme;
  - P-API's `X-Forwarded-Proto` row raised nothing;
  - H-FRESH read the spoiled shared bytes back, and lost its subprotocol to the
    settings' shared string;
  - P-KEEP chose `superchat` through the handler's list.
- **The fixes** then passed all 26 and 5.

### The gap run

X-9, "an empty Origin is taken as none", cut on #29's library (34e8f61), against #29's
suite (8bf2738), named and hashed before the run (`4119acd`): green, 23 passes, beside a
baseline row that passed too. The review's suite reddens X-9 (O-LIST, O-SAME). The
review's other gaps are #29's library itself, which #29's suite and CI passed:
- a scheme never compared;
- shared bytevectors;
- no settings to check once.

### The mutants

The new and changed checks:

| key | check |
|---|---|
| O-SCHEME | same-host holds the Origin's scheme to X-Forwarded-Proto when that names http or https, without regard to case; any other value, or none, is not compared; a listed origin and any are not held to it (0003's amendment) |
| P-SETTINGS | make-handshake-settings refuses settings outside its contract, naming itself: subprotocols not a list of tokens, and origins neither any nor a list of origins and same-host |
| P-API | handshake-answer refuses arguments outside its contract, naming itself: a method not a symbol, a reader not a procedure, a host not a string, settings make-handshake-settings did not make, and a field read as neither a string nor #f, X-Forwarded-Proto among them |
| H-FRESH | each answer's fields are bytevectors of its own, and its subprotocol a string of its own: writing over one answer's leaves the next answer's as they were |
| P-KEEP | settings keep copies of what they were made with: the handler's lists and strings, changed afterwards, change nothing |
| D-SERVER | every answer of (websocket handshake) is one the server writes: a 101's fields pass its switch-fault against the request's, and a refusal's its response-fault |

| # | mutation | red |
|---|----------|-----|
| B-0 | the library as written | none: the library unmutated, 26 and 5 passes |
| A-1 | a method that is not a symbol is not refused | P-API |
| A-2 | a reader that is not a procedure is not refused | P-API |
| A-3 | a host that is not a string is not refused | P-API |
| A-4 | subprotocols that are not a list reach for-all | P-SETTINGS |
| A-5 | subprotocols are not checked as tokens | P-TOKEN, P-SETTINGS |
| A-6 | token? takes a symbol to string-length | P-SETTINGS |
| A-7 | an empty subprotocol is a token | P-SETTINGS |
| A-8 | a token's characters are not checked | P-TOKEN, P-SETTINGS |
| A-9 | tchar's lower letters start at b | H-RFC, R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, P-TOKEN, H-FRESH, P-KEEP, D-SERVER |
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
| A-22 | tchar takes a comma | P-TOKEN, P-SETTINGS |
| A-23 | origins any is refused | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, S-PICK, S-NONE, S-LIST, S-EXACT, O-ABSENT, O-ANY, O-SCHEME, P-TOKEN, P-API, H-FRESH, P-KEEP, D-SERVER |
| A-24 | origins that are not a list reach for-all | P-SETTINGS |
| A-25 | origins' elements are not checked | P-SETTINGS |
| A-26 | same-host is not an origin | O-DEFAULT, O-ABSENT, O-SAME, O-SCHEME, O-HOST |
| A-27 | a listed origin string is refused | R-ORDER, O-ABSENT, O-LIST, O-SCHEME, O-HOST, P-KEEP |
| A-28 | a field's value is not checked | P-API |
| A-29 | settings that are not a settings record are not refused | P-API |
| C-1 | the method is not checked | R-METHOD, R-ORDER |
| C-2 | the method must be get, in lower case | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-SCHEME, O-HOST, P-TOKEN, P-API, H-FRESH, P-KEEP |
| C-3 | Upgrade is not checked | R-UPGRADE, R-ORDER, P-API, D-SERVER |
| C-4 | Upgrade's websocket is compared with case | H-LISTS |
| C-5 | Upgrade is compared whole, not as a list | H-LISTS |
| C-6 | Connection is not checked | R-CONNECTION, R-ORDER |
| C-7 | Connection's upgrade is compared with case | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-SCHEME, O-HOST, P-TOKEN, P-API, H-FRESH, P-KEEP |
| C-8 | Connection is compared whole, not as a list | H-LISTS |
| C-9 | the version is not checked | R-VERSION, R-ORDER, H-FRESH |
| C-10 | the version may be a list holding 13 | R-VERSION |
| C-11 | the version is read as a number | R-VERSION |
| C-12 | a wrong version is refused 426, the design's first answer | R-VERSION, R-ORDER, H-FRESH |
| C-13 | a wrong version is refused with no field | R-VERSION, H-FRESH |
| C-14 | the key is not checked | R-KEY, R-ORDER |
| C-15 | a key is any 24 characters | R-KEY |
| C-16 | a key is the base64 of sixteen bytes or more | R-KEY |
| C-17 | a missing key reaches the decoder | R-KEY |
| C-18 | a key that is not base64 reaches bytevector-length | R-KEY, R-ORDER, D-SERVER |
| C-19 | the Origin is not checked | R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-SCHEME, O-HOST, P-API |
| C-20 | an Origin refused is answered 400 | R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-SCHEME, O-HOST |
| O-1 | a request with no Origin is refused | O-DEFAULT, O-ABSENT |
| O-2 | any is judged as a list | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, O-SCHEME, P-TOKEN, H-FRESH, P-KEEP, D-SERVER |
| O-15 | any accepts only the request's own host | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, O-SCHEME, P-TOKEN, H-FRESH, P-KEEP |
| O-3 | a listed origin is compared with case | O-LIST |
| O-4 | an Origin is accepted when a listed origin begins it | O-LIST |
| O-5 | same-host accepts nothing | O-DEFAULT, O-SAME, O-SCHEME, O-HOST |
| O-6 | same-host accepts everything | O-DEFAULT, O-SAME, O-SCHEME, O-HOST |
| O-7 | same-host is read as a listed origin | O-DEFAULT, O-SAME, O-SCHEME, O-HOST |
| O-8 | an Origin with no scheme is compared whole with the host | O-SAME |
| O-9 | the host is compared with case | O-HOST |
| O-10 | an Origin is accepted when the host begins what follows its scheme | O-SAME |
| O-11 | past-scheme misses a :// that ends the origin | O-HOST |
| O-12 | past-scheme finds the last :// | O-SAME |
| O-13 | past-scheme ends at :/ | O-DEFAULT, O-SAME, O-SCHEME, O-HOST |
| O-14 | past-scheme ends at //, the colon unasked | O-SAME, O-HOST |
| L-1 | an absent field reaches has-element? | R-UPGRADE, R-CONNECTION |
| L-2 | the empty last element is passed over (equivalent: no token is empty) | none (equivalent) |
| L-3 | after a comma, the next character is skipped | H-LISTS, S-LIST |
| L-4 | OWS before an element is kept | H-LISTS, S-PICK, S-LIST |
| L-5 | OWS after an element is kept | H-LISTS, S-LIST |
| L-6 | elements are separated by semicolons | H-RFC, H-LISTS, S-PICK, S-LIST, H-FRESH, P-KEEP |
| L-7 | find-comma runs past the end | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-SCHEME, O-HOST, P-TOKEN, P-API, H-FRESH, P-KEEP, D-SERVER |
| L-8 | skip-ows runs past the end | R-UPGRADE, R-CONNECTION, S-NONE |
| L-9 | back-ows runs past the start | H-LISTS, R-UPGRADE, R-CONNECTION, S-NONE, S-LIST |
| L-10 | HTAB is not OWS | H-LISTS, S-LIST |
| L-11 | SP is not OWS | H-LISTS, S-PICK |
| L-12 | range=? does not compare lengths | R-UPGRADE, R-CONNECTION, S-NONE, S-EXACT, O-LIST, O-SAME, O-SCHEME, O-HOST |
| L-13 | range=? does not compare characters | R-UPGRADE, R-CONNECTION, S-EXACT, O-DEFAULT, O-LIST, O-SAME, O-SCHEME, O-HOST |
| L-14 | range=? leaves the last character unread | R-UPGRADE, O-LIST, O-SAME, O-HOST |
| L-15 | A is not folded | H-LISTS, O-LIST, O-HOST |
| L-16 | Z is not folded | O-LIST |
| L-17 | capitals fold one short | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, R-VERSION, R-KEY, R-ORDER, S-PICK, S-NONE, S-LIST, S-EXACT, O-DEFAULT, O-ABSENT, O-ANY, O-LIST, O-SAME, O-SCHEME, O-HOST, P-TOKEN, P-API, H-FRESH, P-KEEP |
| S-1 | an absent offer reaches has-element? | S-NONE |
| S-2 | subprotocols are compared without regard to case | S-EXACT |
| S-3 | the handler's last preference wins | S-PICK |
| S-4 | when the offer names none of them, the handler's first is chosen | S-NONE, S-EXACT |
| F-1 | the 101 never names the subprotocol | H-RFC, S-PICK, S-LIST, P-TOKEN, H-FRESH |
| F-2 | the 101's Upgrade is WebSocket | H-RFC, H-CHROME, H-FRESH |
| F-3 | the accept field is named Sec-Websocket-Accept | H-RFC, H-CHROME, H-KEYBITS, H-FRESH |
| F-4 | the accept value is of the key re-encoded | H-KEYBITS |
| F-5 | the GUID ends in 2 | H-RFC, H-CHROME, H-KEYBITS, H-FRESH |
| F-6 | the version's refusal names 8, 13 | R-VERSION, H-FRESH |
| F-7 | a refusal carries Content-Length: 0 | R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, H-FRESH, D-SERVER |
| F-8 | a refusal names no check | R-METHOD, R-UPGRADE, R-CONNECTION, R-VERSION, R-KEY, R-ORDER, O-DEFAULT, O-LIST, O-SAME, O-SCHEME, O-HOST, H-FRESH |
| R-1 | the method is checked after Upgrade | R-ORDER |
| R-2 | Connection is checked before Upgrade | R-ORDER, P-API |
| R-3 | the version is checked before Connection | R-ORDER |
| R-4 | the key is checked after the Origin | R-ORDER |
| R-5 | the version is checked after the key | R-ORDER |
| D-1 | a handler that names no origins gets any | O-DEFAULT |
| D-2 | a handler that names no origins gets none | O-DEFAULT |
| D-3 | origins given are dropped for the default | H-RFC, H-CHROME, H-KEYBITS, H-LISTS, S-PICK, S-NONE, S-LIST, S-EXACT, O-ANY, O-LIST, O-SCHEME, O-HOST, P-TOKEN, H-FRESH, P-KEEP |
| X-1 | same-host ignores the scheme, as before the review | O-SCHEME |
| X-2 | the Origin's scheme is held to X-Forwarded-Proto with case | O-SCHEME |
| X-3 | only a lower-case X-Forwarded-Proto names a scheme | O-SCHEME |
| X-4 | any X-Forwarded-Proto names a scheme | O-SCHEME |
| X-5 | only https names a scheme | O-SCHEME |
| X-6 | only http names a scheme | O-SCHEME |
| X-7 | a listed origin is held to X-Forwarded-Proto too | O-SCHEME |
| X-8 | any is held to X-Forwarded-Proto too | O-SCHEME |
| X-9 | an empty Origin is taken as none | O-LIST, O-SAME |
| X-10 | the settings keep the handler's list of subprotocols | P-KEEP |
| X-11 | the settings keep the handler's subprotocol strings | P-KEEP |
| X-12 | the settings keep the handler's list of origins | P-KEEP |
| X-13 | the settings keep the handler's origin strings | P-KEEP |
| X-14 | the answer's subprotocol is the settings' own string | H-FRESH |
| X-15 | every 101 shares one Upgrade field | H-FRESH |
| X-16 | every version refusal shares one field list | H-FRESH |
| X-17 | X-Forwarded-Proto is not read | O-SCHEME, P-API |
| X-18 | the scheme compared runs on into its :// | O-SCHEME |
| AUD-1 | (websocket handshake) imports (chezscheme) | the import audit's check of its library, alone |

**The run**, each red set named before the run and hashed (`6684df1`): 121 rows, 120
mutants and the baseline, 0 mismatches, on the first run.
- **Re-cut to the review's library:**
  - the settings' guards and their indentation (A-4 to A-8, A-22 to A-27);
  - the version's clause, now on two lines (C-9 to C-13, R-3, R-5);
  - the Origin's clause, which reads `X-Forwarded-Proto` (C-19, C-20, R-4);
  - the 101's fields, made by `header` (F-1 to F-3, F-6);
  - `same-host?` (O-8 to O-10), and the default (D-1 to D-3).
- **Red sets that changed with the review's suite:**
  - **P-SETTINGS** takes from P-API the refusals of subprotocols and origins (A-4 to
    A-8, A-22, A-24, A-25).
  - **D-SERVER** is H-SERVER, moved.
  - **H-FRESH and P-KEEP** go red with every mutant that refuses or reshapes a 101 of
    the RFC's request.
  - **O-SCHEME** goes red with every mutant of `same-host` or of the Origin's refusal.
  - **P-API's `X-Forwarded-Proto` row** goes red with every mutant that refuses the
    RFC's request before its Origin is judged: C-2, C-7, L-7, L-17, C-19 and X-17.
- **New:**
  - A-29, a settings record unchecked;
  - X-1 to X-8, X-17 and X-18, the scheme;
  - X-9, the empty Origin;
  - X-10 to X-13, the copies;
  - X-14 to X-16, the answers' own values.

L-2 is still equivalent. In 24 rows a check went red through a raise:
- A-9 to A-14, A-20, A-21, A-23, A-26, A-27;
- C-14, C-17, C-18;
- F-3;
- L-1, L-7, L-8, L-9, L-12, L-14;
- O-2, O-7;
- S-1.

Every such check has a killer by value too. Every check of the handshake's suite, and
D-SERVER, has killers by value. The door's other four checks never touch this library;
their killers are M0's (`m0-mutations.md`).

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
| O-LIST | C-2, C-7, C-19, C-20, D-3, F-8, L-13, L-14, L-15, L-16, L-17, O-3, O-4, X-9 |
| O-SAME | C-2, C-7, C-19, C-20, F-8, L-13, L-14, L-17, O-5, O-6, O-8, O-10, O-12, O-13, O-14, X-9 |
| O-SCHEME | C-2, C-7, C-19, C-20, D-3, F-8, L-13, L-17, O-5, O-6, O-13, O-15, X-1, X-2, X-3, X-4, X-5, X-6, X-7, X-8, X-17, X-18 |
| O-HOST | C-2, C-7, C-19, C-20, D-3, F-8, L-12, L-13, L-15, L-17, O-5, O-6, O-9, O-11, O-13, O-14 |
| P-TOKEN | A-5, A-8, A-15, A-16, A-17, A-18, A-19, A-22, C-2, C-7, D-3, F-1, L-17, O-15 |
| P-SETTINGS | A-4, A-5, A-6, A-7, A-8, A-22, A-24, A-25 |
| P-API | A-1, A-2, A-3, A-28, A-29, C-2, C-3, C-7, C-19, L-7, L-17, R-2, X-17 |
| H-FRESH | C-2, C-7, C-9, C-12, C-13, D-3, F-1, F-2, F-3, F-5, F-6, F-7, F-8, L-6, L-17, O-15, X-14, X-15, X-16 |
| P-KEEP | C-2, C-7, D-3, L-6, L-17, O-15, X-10, X-11, X-12, X-13 |
| D-SERVER | C-3, F-7 |

## M4.2 — the binding's test driver

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09.
- **The suites:** `tests/test-driver.sps`, 12 checks (blob a43ec74), and the door suite,
  `tests/test-door.sps`, now 6 (blob bfda47d).
- **The code they hold** is the pinned server's, at v0.4.0 (388ec43):
  - its fake shell, `tests/fake-shell.sls` (blob c355517);
  - `src/http-server/transport.sls` (f9d77d2);
  - `src/http-server/view.sls` (aa98353).

**The runner** is the server's for its decision 0024, pointed at this tree, with this
project's library path. It applies each mutant alone, to a copy of one of the pinned
server's libraries put first on the library path, so neither the pin nor the tree is
edited. It runs both suites and compares the checks that went red with the set named
before the run. Before the run, a pre-flight checks that every cut matches its text once
and keeps its paren balance.

### The oracles

- **RFC 6455's examples:** §1.2's opening handshake, and §5.7's masked "Hello" from a
  client, 11 bytes.
- **The server's documented door**, at v0.4.0:
  - its decisions 0016 (the hand-off, the bytes handed over, the server's 101), 0023 (a
    take-over's `awaiting`, its waits told when the stream closes) and 0024 (the abort,
    and every line of a field);
  - its fake shell's header: a write is the client's on its turn, a close waits for the
    writes before it, the deadline is armed at the clock's now plus its time, the drain
    call runs once, a raise in a taker's call is its failure and aborts the stream.
- **RFC 9110 §5.3:** a field's lines in order.

### The test-first runs

Each red set was named and hashed before its run.
- **Stage 0, the new checks on the v0.3.0 pin** (`550cfc1`; an earlier hash, `7411470`,
  said "seven" over a list of eight suites and was replaced before the run):
  - both new suites stopped at load, exit 255: `attempt to reference unbound identifier
    transport-abort!`;
  - the other eight suites green, 246 passes.
- **Stage 1, on the v0.4.0 pin** (`560f2b6`): every suite green.
  - The prediction said 11 checks in the driver suite, as stage 0's did. There are 12, a
    miscount of my own: ten suites, 264 passes.
- **The gap run** (`1c8b920`): the driver suite on the v0.4.0 pin, with v0.3.0's fake
  shell (blob cd30588) first on the library path. Exactly the four predicted went red,
  each for its reason; the other 8 passed, exit 1.
  - D-ARMED: `#f`, nothing armed once the close was asked for.
  - D-ABORT: no deadline, so no abort; the client read the write, told `#f`.
  - D-RAISE-DL: the raise escaped `fake-shell-fire!`, nothing recorded, the stream left
    open.
  - D-RAISE-THUNK: the close waited behind the write, and the client read it.

### The mutants

| key | check |
|---|---|
| DR-ABORT | door: an abort is handed to the transport's eighth procedure |
| D-RETAINED | a frame sent with the handshake is handed to the take-over, and the client reads its echo after the 101 |
| D-WAKE | a read's bytes resume the thunk parked on `await`, and the client reads its echo |
| D-STOP | a stopped read takes no delivery, and a read started again takes the next |
| D-CLOCK | the taker's deadline is armed at the fake clock's now plus its time, and passes then and not a millisecond before |
| D-DRAIN | the server's drain runs the taker's drain call, once |
| D-BEHIND | a close asked for behind a write the client has not read waits: the client reads the write, then the stream closes |
| D-ARMED | a deadline asked for while that close waits is armed |
| D-ABORT | an abort at that deadline ends the stream: the write is told `ECANCELED`, the client reads none of it, and the close call comes |
| D-OUTSIDE | the stream closed while the thunk waits: its wait raises `&client-closed`, which is no taker failure |
| D-RAISE-DL | a raise in the deadline's call is the taker's failure: recorded, and the stream closed, with nothing escaping to the test |
| D-RAISE-THUNK | a waiting thunk's raise is the taker's failure, and ends the stream at once: its write told `ECANCELED`, and never read |
| D-VALUES | `request-header-values` reads every line of a field, in order, through the server's parse, and `request-header` the first |

Specs hashed before the run (`7b25053`, names `2f36490`). The run: 28 rows, 27 mutants and
the baseline, 0 mismatches. M-2 was drafted and withdrawn before the run, on a premise
not checked: that a copy of the bytes handed over, one byte short, would raise when nothing
was handed over. The core hands over #f then (0006 item 3's contract, in its
`connection.sls`), and the fake copies nothing. M4.2's review ran it: D-RETAINED alone, as
predicted (below).

| # | mutation | red, as predicted |
|---|----------|-----|
| B-0 | none | none: 18 passes |
| M-1 | the bytes read past the request are not handed over | D-RETAINED |
| M-3 | a delivery to a taker leaves the scheduler undrained | D-WAKE, D-STOP, D-BEHIND, D-ARMED, D-ABORT |
| M-4 | read-stop stops nothing | D-STOP |
| M-5 | read-start starts nothing | D-STOP |
| M-6 | the deadline armed a millisecond late | D-CLOCK, D-ARMED, D-ABORT, D-RAISE-DL |
| M-7 | the deadline armed a millisecond early | D-CLOCK, D-ARMED |
| M-8 | the timer fires a millisecond behind the clock | D-CLOCK, D-ABORT, D-RAISE-DL |
| M-9 | the drain does not call the taker | D-DRAIN |
| M-10 | the drain's two guards both gone (the shell's draining flag and the taker's) | D-DRAIN |
| M-10a | the shell's guard gone, the taker's left | none: the call still once |
| M-10b | the taker's guard gone, the shell's left | none: the call still once |
| M-11 | the last write's turn never begins a close asked for | D-BEHIND |
| M-12 | the close begins at once, whatever is outstanding | D-ARMED, D-ABORT |
| M-13 | no deadline armed once the taker's close is asked for (v0.3.0's gate) | D-ARMED, D-ABORT |
| M-14 | the abort only asks for the close | D-ABORT, D-RAISE-THUNK |
| M-15 | the abort marks nothing aborted | D-ABORT, D-RAISE-THUNK |
| M-16 | an aborted write's bytes are the client's | D-ABORT, D-RAISE-THUNK |
| M-17 | `transport-abort!` calls the transport's close | DR-ABORT, D-ABORT |
| M-18 | the close tells no wait | D-OUTSIDE, D-RAISE-DL |
| M-19 | the close's `&client-closed` counted a failure | D-OUTSIDE, D-RAISE-DL |
| M-20 | the taker's close call is not made | D-BEHIND, D-ABORT, D-OUTSIDE, D-RAISE-DL, D-RAISE-THUNK |
| M-21 | the deadline's call unguarded | D-RAISE-DL |
| M-22 | a waiting thunk's raise only asks for the close | D-RAISE-THUNK |
| M-23 | a waiting thunk's raise not recorded | D-RAISE-THUNK |
| M-24 | `request-header-values` reads the first line only | D-VALUES |
| M-25 | `request-header-values` reads the lines last first | D-VALUES |
| M-26 | `request-header` reads the last line | D-VALUES |

M-12 leaves D-BEHIND green. A close begun at once queues its turn behind the write's, and
the fake tells a write that was not aborted `#f` on its turn, so the client still reads
it and the order is the same. D-ARMED sees M-12: nothing is armed once the close has
begun.

**The drain's "once" is held twice**: by the shell's draining flag, and by the taker's
drained flag. M-10a and M-10b, each taking one away, pass, as predicted. M-10, taking
both, reddens D-DRAIN.

| check | killers by value |
|---|---|
| DR-ABORT | M-17 |
| D-RETAINED | M-1 |
| D-WAKE | M-3 |
| D-STOP | M-3, M-4, M-5 |
| D-CLOCK | M-6, M-7, M-8 |
| D-DRAIN | M-9, M-10 |
| D-BEHIND | M-3, M-11, M-20 |
| D-ARMED | M-3, M-6, M-7, M-12, M-13 |
| D-ABORT | M-3, M-6, M-8, M-12, M-13, M-14, M-15, M-16, M-17, M-20 |
| D-OUTSIDE | M-18, M-19, M-20 |
| D-RAISE-DL | M-6, M-8, M-18, M-19, M-20, M-21 |
| D-RAISE-THUNK | M-14, M-15, M-16, M-20, M-22, M-23 |
| D-VALUES | M-24, M-25, M-26 |

The door suite's other five checks did not change; their mutants are M0's (M0-7 to
M0-11) and M4.1's review's (D-SERVER).

## M4.2's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09.
- **The suites:** `tests/test-driver.sps`, now 14 checks (blob bf02dff), and the door
  suite, 6 (unchanged).
- **The Makefile** (blob 0ecfc71): the suites' path, `TEST_LIBDIRS`.
- **The pinned server**, as M4.2's section has it, and its serializer,
  `src/http-server/serializer.sls`.

`/code-review` at extra-high effort over #32 to #34 reported nine findings. The owner said
"fix all".

### The findings and their fixes

1. **Squashing #33 would merge the pin and the driver** on main, where a pin moves alone
   (global-constraints). The pin commit, a2c6904, is now a PR of its own, #35, and #33 is
   based on it. Nothing was rewritten.
2. **`fake-shell-deliver!` hands a taker its events whatever the read state**; only
   `fake-shell-feed-input!` honours read-stop, as libuv does.
   - The driver suite's header and the design's §8 now say how a test plays the client.
   - D-INSIDE holds a read stopped from inside the taker's own read, as the binding stops
     at a full queue.
3. **D-BEHIND could not see the wait** (M-12 left it green). It now arms a deadline before
   the close, as the binding's ping is. A close that has begun disarms it, so the check
   reads it while the close waits and again after.
4. **The design's §6 mapped `close-stream` to `transport-close!` alone.** Its row now
   names `transport-abort!` where the client is not reading what is unsent (0004). M4.3
   names those places.
5. **M-2's withdrawal rested on a wrong premise.** The sentence above is corrected, and
   M-2 and M-2b ran.
6. **The server's `tests/` was on the one path**, the one `make run` and `make dev` use.
   - It is now on `TEST_LIBDIRS` alone, with chez-httparse's test harness (finding 9
     needs it).
   - `make test` refuses to run if either is on `LIBDIRS`.
7. **That no borrowed library has one of our names was a comment.** D-NAMES checks it,
   reading every library under the borrowed directories and ours with Chez's reader.
8. **The design's §9 compared against the server's v0.1.0 numbers** without saying so.
   They are now attributed, and M4.3 measures the server's own again at the pin.
9. **`client-reads` read the status at bytes 9 to 12.** It now reads the head as a client
   would, by the server's `(response-reader)`, on chez-httparse's strict response parser.

### The test-first runs

Each red set was named and hashed before its run.
- **R0, the review's suites on the unmutated pin** (`bdefeaf`): every suite green. Ten
  suites, 266 passes; the driver suite 14.
- **G-1, the gap run** (in `b303e45`): the driver suite as it was before the review
  (0f9d1dd), under M-29, the status line ending in a bare LF. All 12 pass. The review's
  suite reddens seven under it (below).

### The mutants

| key | check |
|---|---|
| D-INSIDE | a read stopped from inside the taker's read takes no later delivery: of three frames sent one a read, two are taken and echoed |
| D-BEHIND | a close asked for behind a write the client has not read waits: the deadline armed before it stays armed, and once the client reads the write the stream closes, the deadline disarmed |
| D-NAMES | no library of the test code borrowed onto the suites' path has the name of one of this project's, the fake shell and the response reader among them |

**The runner's rows.** M4.2's 27 mutants were re-predicted for the review's suite, and
the review's five added, with the baseline.
- Specs hashed before the run: `27d205e`, names `c2e4bc3`.
- **33 rows, 32 mutants and the baseline: 1 mismatch**, M-5.
- **M-5, read-start starts nothing**, reddened D-STOP alone. I predicted D-INSIDE too,
  from a premise not checked: that the core stops reading when it calls the handler. It
  does so on one path (its `connection.sls`, line 2011), but not for this request, a GET
  with no body.
  - A probe found the connection reading at the take-over and after it, with no
    read-stop among the core's actions.
  - The libuv shell's hand-off leaves reading as it was, and the taker's read-start
    replaces what its reads are handed to (`shell.sls`, `taker-read-start!`). The two
    shells agree.
  - So D-INSIDE's read-start found reading on, and its check held under M-5. A
    prediction error; M-4, M-28 and M-29 redden D-INSIDE by value.

| # | mutation | red |
|---|----------|-----|
| B-0 | none | none: 20 passes |
| M-1 | the bytes read past the request are not handed over | D-RETAINED |
| M-2 | the bytes handed over copied one short at the end | D-RETAINED |
| M-2b | the bytes handed over copied from one byte late | D-RETAINED |
| M-3 | a delivery to a taker leaves the scheduler undrained | D-WAKE, D-STOP, D-INSIDE, D-BEHIND, D-ARMED, D-ABORT |
| M-4 | read-stop stops nothing | D-STOP, D-INSIDE |
| M-5 | read-start starts nothing | D-STOP (predicted D-INSIDE too: above) |
| M-6 | the deadline armed a millisecond late | D-CLOCK, D-BEHIND, D-ARMED, D-ABORT, D-RAISE-DL |
| M-7 | the deadline armed a millisecond early | D-CLOCK, D-BEHIND, D-ARMED |
| M-8 | the timer fires a millisecond behind the clock | D-CLOCK, D-ABORT, D-RAISE-DL |
| M-9 | the drain does not call the taker | D-DRAIN |
| M-10 | the drain's two guards both gone | D-DRAIN |
| M-10a, M-10b | one of the drain's guards gone | none: the call still once |
| M-11 | the last write's turn never begins a close asked for | D-BEHIND |
| M-12 | the close begins at once, whatever is outstanding | D-BEHIND, D-ARMED, D-ABORT |
| M-13 | no deadline armed once the taker's close is asked for | D-ARMED, D-ABORT |
| M-14, M-15, M-16 | the abort only asks for the close; marks nothing aborted; an aborted write's bytes the client's | D-ABORT, D-RAISE-THUNK |
| M-17 | `transport-abort!` calls the transport's close | DR-ABORT, D-ABORT |
| M-18, M-19 | the close tells no wait; its `&client-closed` counted a failure | D-OUTSIDE, D-RAISE-DL |
| M-20 | the taker's close call is not made | D-BEHIND, D-ABORT, D-OUTSIDE, D-RAISE-DL, D-RAISE-THUNK |
| M-21 | the deadline's call unguarded | D-RAISE-DL |
| M-22, M-23 | a waiting thunk's raise only asks for the close; not recorded | D-RAISE-THUNK |
| M-24, M-25, M-26 | `request-header-values` the first line only; last first; `request-header` the last | D-VALUES |
| M-27 | a close begun leaves the deadline armed | D-BEHIND |
| M-28 | the client's bytes fed whatever the read state | D-STOP, D-INSIDE |
| M-29 | the status line ends in a bare LF (the serializer) | D-RETAINED, D-WAKE, D-STOP, D-INSIDE, D-BEHIND, D-ABORT, D-RAISE-THUNK |

**The rows outside the runner** (predicted in `b303e45`), each as predicted:
- **N-1, a borrowed library named as one of ours.** A scratch tree's copy of the
  server's `tests/` holds a library named `(ws-testing)`. D-NAMES alone goes red, its
  overlap `((ws-testing))`.
- **N-2, the borrowed directories read empty.** D-NAMES alone goes red: no fake shell,
  no response reader.
- **MK-1, the server's `tests/` back on `LIBDIR_LIST`.** `make test` exits 2, naming it
  test code on `LIBDIRS`, before any suite runs.
- **MK-2, `TEST_ONLY_DIRS` without the server's `tests/`.** The driver suite stops at
  load (`(fake-shell)` not found, exit 255), and the other nine pass.

| check | killers by value |
|---|---|
| D-BEHIND | M-3, M-6, M-7, M-11, M-12, M-20, M-27, M-29 |
| D-INSIDE | M-3, M-4, M-28, M-29 |
| D-NAMES | N-1, N-2 |

## M4.3, step 1 — the binding and the facade

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09.
- **The code:** `src/websocket/private/binding.sls` (blob 6d10ab9) and the facade,
  `src/websocket.sls` (3fac36f).
- **The suites:** `tests/test-binding.sps`, 35 checks (e9bbc4c), with the child program
  it runs, `tests/start-with-environment.sps` (b3729af); and the import audit,
  `tests/test-imports.sps`, now 10 (9a7964e).

**The runner** is M4.1's, pointed at the binding. It applies each mutant alone, to a
copy of the binding put first on the suites' path, and runs the binding suite, whose
child program inherits that path. An audit row mutates a scratch copy of `src/` and
`tests/`, or moves a file there, and runs the import audit in it. The repository is
never edited. Before the run, a pre-flight checks that every cut matches its text once
and keeps its paren balance.

### The oracles

- **RFC 6455, from its raw text:**
  - §1.3's handshake and its accept value;
  - §4.2.1's checks, and §4.4's `Sec-WebSocket-Version: 13`;
  - §5.1, an unmasked frame failed with 1002;
  - §5.5.1, a close echoing the code it received;
  - §5.5.2, a ping of no payload;
  - §5.7's frames, the suite's own checked against them before any check (a
    provenance failure otherwise);
  - §7.1.4 to §7.1.6, clean only once a close has gone each way, and 1006 with an
    empty reason when none came;
  - §7.4.1's 1001 and 1011.
- **RFC 9110 §5.3** with decision 0004: a field's lines are one list. A split
  `Connection` is taken; two keys are refused 400, as websockets, coder and ws refuse
  them.
- **Decision 0001:** the queue's cap, and 20 s and 20 s for the ping clock.
- **Decision 0003:** `same-host` when a handler names no origins.
- **The design's §6 and §7:**
  - each action performed;
  - the water marks, compared as the server compares its own (its
    `configuration.org`: past the high water a stream waits until no more than the
    low water is unsent);
  - U+FEFF kept;
  - the drain's 1001 "going away";
  - the procedure's end;
  - the environment read as the program starts.
- **websockets 17.2's `send_context`:** a send while closing waits for the close, then
  raises.
- **Chez:** a library's body runs before the program's (measured: a library's display
  printed before the program's first line). An uncaught raise exits 255, which `system`
  answers (measured).

### The test-first runs

Each red set was named and hashed before its run.
- **Stage 0** (`edd34c9`): the new suite stopped at load, `library (websocket) not
  found`, exit 255. The other ten suites were green: 266 passes.
- **Stage 1** (`f6dd4d9`): the binding, the facade and the audit's two exceptions.
  - The prediction's text corrects itself mid-line, "ten suites... eleven suites", as
    it was typed. Its count, 296, is the run's.
  - The first run stopped the binding suite after 21 passes, exit 2: `incorrect number
    of arguments 1 to #<procedure current-output-port>`. The suite was at fault, not
    the binding. In Chez, `(rnrs)`'s `current-output-port` is not the parameter, so
    `parameterize` refused it.
  - With the suite importing Chez's parameter under a name of its own, eleven suites
    were green: 296.
- **Stage 1c** (`bc6429b`), 299 passes, as predicted:
  - the binding's close call (`transport-on-close!`) taken out, since both shells tell
    the wait first and a close call's wake would be a late resume;
  - three checks added: the close timeout, the stream closed under the binding, and a
    handler's own ping times;
  - two widened: the queue's clock, and the procedure's own wait seeing the stream's
    close.
- **Stage 1d** (`cfb520c`): five checks added from the mutant draft, which found them
  missing, and five checks changed. 304 passes, as predicted.
  - The five added: a send woken by the end, a default Origin refused, accept's
    refusals, each verb's refusals, and how a raise is logged.
  - The five changed: C-SERVER and C-SENDCLOSING read the end before the client
    reads; C-TIMEOUT and C-SENDCLOSING close with a code of their own; V-ENV's child
    goes through both accept forms.

### The mutants

| key | check |
|---|---|
| H-ACCEPT | RFC 6455's example handshake is answered 101, `Upgrade: websocket`, with its accept value |
| H-VERSION | a version other than 13 is refused 400 with `Sec-WebSocket-Version: 13`, and the procedure never runs |
| H-CONN2 | `Connection` over two lines, keep-alive then Upgrade, is read whole: 101 |
| H-PROTO2 | a subprotocol offered on the second of two lines is read, answered, and named by `websocket-subprotocol` |
| H-KEY2 | two `Sec-WebSocket-Key` lines are refused 400 |
| H-ORIGIN | a handler that names no origins refuses a browser's Origin of another host, 403 |
| H-ARGS | `websocket-accept` refuses a procedure that is not one, and limits that are not limits, naming itself |
| C-ARGS | receive, send and close refuse what is not a WebSocket, each naming itself |
| M-RETAINED | a masked Hello sent with the handshake is received as "Hello", and its echo is §5.7's unmasked frame |
| M-WAKE | a message that comes while receive waits wakes it, and the client reads its echo |
| M-BINARY | a binary message is received as its bytevector, and echoed as §5.7's 256-byte frame |
| M-BOM | U+FEFF kept at a text's start, and alone; an empty text; U+EEFF, U+FEBF and U+FEFE as themselves; each echoed as its bytes |
| M-REFUSE | a send of neither a string nor a bytevector is refused, naming `websocket-send!` |
| W-HIGH | a send that leaves the high water unsent goes on, one past it waits, and reading down to the low water lets it go on |
| W-LOW | a send waiting with more than the low water unsent still waits, and goes on once the client has read down to it |
| W-END | a send waiting when the connection ends is woken at once, before the client reads, and raises `&websocket-closed` |
| R-QUEUE | a queue of one stops reading and the clock until it is received; then reading, the clock afresh, and the next |
| C-SERVER | `websocket-close!` writes 1000; the client's close ends it cleanly, told at once, before the stream has closed |
| C-CLIENT | a client's close is answered with its code echoed, and receive raises its code and reason, cleanly |
| C-EOF | the stream's end with no close: 1006, an empty reason, not clean, nothing written |
| C-TIMEOUT | a close of the handler's code and reason, not answered within 10 s, ends the connection anyway, 1006, not a millisecond before |
| C-OUTSIDE | the stream closed under the binding while receive waits: the wait's `&client-closed` ends the connection, 1006 |
| C-QUEUED | messages queued before the end are received first, then `&websocket-closed` |
| C-AGAIN | after the end, every receive and every send raises `&websocket-closed` again |
| C-SENDCLOSING | a send while the server's close (a code alone) is under way waits, writes nothing, and raises at once at the end |
| D-DRAIN | the server's drain sends a close of 1001, "going away" |
| E-RETURN | a procedure that returns closes with 1000 |
| E-CLOSED | a procedure that lets `&websocket-closed` out: nothing more written or logged, no taker failure |
| E-RAISE | a procedure that raises anything else closes with 1011, logged, no taker failure |
| E-DETAILS | a raise's detail logged as the server logs one: a string, a record, a list, a two-line condition |
| E-CLIENTCLOSED | the stream's end closes the stream, so a procedure's own wait raises `&client-closed`; let out, nothing more |
| P-SILENT | a client silent after the 101 is pinged at 20 s and failed with 1011 20 s later, neither a millisecond early, logged |
| P-OWN | a handler's own ping interval and timeout, 30 s and 5 s, are the times armed |
| L-1002 | an unmasked frame fails the connection with 1002, logged with its code |
| V-ENV | the limits read from the environment as the program starts, and taken by both accept forms; a malformed one stops it |
| I-AMONG | the audit: the binding and the facade are among the sources |
| I-binding, I-facade | the audit: each imports only the pure, and the one more its exception names |

Specs hashed before each run, the names (`750524d`) and the runner (`e2a3035`) with them:
- **Run 1** (`5052e3c`): 83 rows, 1 mismatch. K-16 also reddened C-TIMEOUT.
  - My premise was wrong. `fake-shell-fire!` runs the deadline's call but does not
    drain the scheduler, so the receive the close timeout woke ran only at the next
    later turn. The stream's close made that turn, and K-16 takes the close away.
  - The libuv shell drains its scheduler after every turn, so C-TIMEOUT now drains it
    after each fire (`fake-shell-schedule!`). It is renamed to what it holds: "ends
    the connection anyway".
- **Run 2** (`5052e3c` again; only the suite changed): 83 rows, 1 mismatch. K-48 also
  reddened C-TIMEOUT.
  - That is the change's point: the check now reads the end's own wake. But I did not
    predict again the rows the changed check reads.
- **Run 3** (`aa0e798`, K-48's set widened): 83 rows, 0 mismatches.
- **Run 4** (`e4be871`): 86 rows, 85 mutants and the baseline, 0 mismatches.
  - M-BOM gained the three texts one byte off U+FEFF, U+EEFF, U+FEBF and U+FEFE.
  - Their mutants, K-34c to K-34e, each take one of the byte-order mark's three byte
    tests away.
- **Run 5** (`e4be871` again), after CI's first run: 86 rows, 0 mismatches, on the suite
  whose child runs on the suites' own Chez (blob e9bbc4c).
  - CI's run 37921568542 failed V-ENV, (127 127) for (8 255). The child was run as
    `chez`, and CI names Chez `scheme`, in `CHEZ`.
  - The child now runs `"${CHEZ:-chez}"`. make hands its recipes a `CHEZ` set in the
    environment or on its command line (measured with GNU Make 3.81). The Makefile's
    own default is `chez`.
  - Test first, on a PATH holding Chez only as `scheme`, with `CHEZ=scheme`: V-ENV red,
    (127 127), the other 34 green; after the fix, 35 there, and 304 under `make test`.

| # | mutation | red, as predicted |
|---|----------|-----|
| BASE | none | none: the binding suite 35, the audit 10 |
| K-1 | a field's first line alone, not every line joined | H-CONN2, H-PROTO2, H-KEY2 |
| K-3 | a refusal's fields dropped | H-VERSION |
| K-4 | the 101's fields: `Upgrade` alone | H-ACCEPT, H-PROTO2 |
| K-5 | the subprotocol chosen not handed to the WebSocket | H-PROTO2 |
| K-58 | a handler that names no origins gets `any` | H-ORIGIN |
| K-59a, K-59b | accept takes any procedure; any limits | H-ARGS |
| K-60a, K-60b, K-60c | receive, send, close do not check their WebSocket | C-ARGS |
| K-6 | the bytes read past the request not fed to the core | M-RETAINED, M-BINARY, M-BOM, C-CLIENT, E-CLOSED, L-1002 |
| K-7 | the deadline `ws-deadline` names not armed as the take-over starts | P-SILENT, P-OWN, V-ENV |
| K-12 | the take-over starts no reading | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE, C-SERVER, C-EOF, C-QUEUED, C-AGAIN, C-SENDCLOSING, E-CLIENTCLOSED |
| K-35 | the drain closes with 1000 and no reason | D-DRAIN |
| K-36 | no drain call registered | D-DRAIN |
| K-71 | a read's end not stepped | W-END, C-EOF, C-QUEUED, C-AGAIN, E-CLIENTCLOSED |
| K-72 | every read stepped as no bytes | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE, C-SERVER, C-QUEUED, C-SENDCLOSING |
| K-73 | a deadline's passing not stepped | C-TIMEOUT, P-SILENT, P-OWN |
| K-37 | a procedure's return closes nothing | E-RETURN |
| K-38 | a procedure's raise not logged | E-RAISE, E-DETAILS |
| K-39 | a procedure's raise closes with 1000 | E-RAISE |
| K-40 | a `&websocket-closed` let out taken as a failure | E-CLOSED |
| K-41 | a `&client-closed` let out taken as a failure | E-CLIENTCLOSED |
| K-42 | either raised on to the server | E-CLOSED |
| K-13 | `read-stop` not performed | R-QUEUE |
| K-14 | `read-start` not performed | R-QUEUE |
| K-15 | `disarm-deadline` not performed | R-QUEUE |
| K-16 | `close-stream` not performed | E-CLIENTCLOSED |
| K-17 | `closed` not performed | W-END, C-SERVER, C-CLIENT, C-EOF, C-TIMEOUT, C-OUTSIDE, C-QUEUED, C-AGAIN, C-SENDCLOSING |
| K-47 | a delivery wakes no receive | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE |
| K-20 | a log line without its `websocket-` prefix | P-SILENT, L-1002 |
| K-21 | a log line without its details | P-SILENT, L-1002 |
| K-8 | ping armed for the ping timeout | P-OWN, V-ENV |
| K-9 | pong armed for the ping interval | P-OWN |
| K-10 | close armed for the ping interval | C-TIMEOUT |
| K-18 | every end clean | W-END, C-EOF, C-TIMEOUT, C-OUTSIDE, C-QUEUED, C-AGAIN |
| K-19 | an end's reason left empty | C-CLIENT |
| K-48 | the end wakes no receive | C-SERVER, C-TIMEOUT |
| K-49 | the end wakes no send | W-END, C-SENDCLOSING |
| K-50, K-50b, K-45 | a woken receive's, a woken send's, or a raised wait's resume kept | none: survivors, as predicted |
| K-43 | a wait's `&client-closed` not stepped as the stream's end | C-OUTSIDE |
| K-44 | a wait's `&client-closed` let out | C-OUTSIDE |
| K-30 | receive raises the end before the queued messages | C-QUEUED |
| K-31 | a take not stepped | R-QUEUE |
| K-32 | a text received as its bytes | M-RETAINED, M-WAKE, M-BOM, R-QUEUE, C-QUEUED |
| K-66 | the queue's tail kept once it empties | R-QUEUE |
| K-66b | each message enqueued in place of those before | M-BOM, C-QUEUED |
| K-33 | a leading U+FEFF not put back | M-BOM |
| K-34 | a text of U+FEFF alone not put back | M-BOM |
| K-34c, K-34d, K-34e | one of the byte-order mark's three bytes not checked | M-BOM |
| K-34b | no length guard before the byte-order mark's bytes | M-BOM, W-END, C-SERVER, C-EOF, C-TIMEOUT, C-OUTSIDE, C-QUEUED, C-AGAIN, C-SENDCLOSING, E-CLOSED, E-CLIENTCLOSED, P-SILENT, P-OWN, L-1002 |
| K-55 | a send of anything else sent as binary | M-REFUSE |
| K-22 | a write not counted unsent | W-HIGH, W-LOW, W-END |
| K-23 | a write's done not counted | W-HIGH, W-LOW |
| K-24 | a send goes on only below the low water | W-HIGH |
| K-25 | a send goes on at any write's done | W-LOW |
| K-26 | a send waits at the high water | W-HIGH, W-END |
| K-27 | a send never waits | W-HIGH, W-LOW, W-END |
| K-28 | a send woken by the end returns | W-END |
| K-29 | a send while closing sent | C-SENDCLOSING |
| K-53 | a close stepped is not remembered | C-SENDCLOSING |
| K-62 | close's default code 1001 | C-SERVER |
| K-63 | close of a code alone gives a reason | C-SENDCLOSING |
| K-63b | close of a code and reason drops the reason | C-TIMEOUT |
| K-69 | a log line without its newline | E-RAISE, E-DETAILS, P-SILENT |
| K-70a to K-70e | a condition logged as a record; its line breaks kept; a record written; a string written; anything else displayed | E-DETAILS |
| K-56 | the environment not read | V-ENV |
| K-57, K-61 | the two- or three-argument accept takes the defaults | V-ENV |
| A-1, A-2 | the facade imports `(http-server)`; `(chezscheme)` | I-facade |
| A-3, A-4 | the binding imports `(rnrs eval)`; the facade | I-binding |
| A-5, A-6 | a pure library imports `(chezscheme)`; `(http-server)` | I-limits; I-protocol |
| A-7, A-8 | the facade moved; the binding moved | I-AMONG, and the moved file's check |

**K-34b's wide set** is the fake's taker-call: a raise in a taker's call is recorded and
aborts the stream. An empty reason, at every end but C-CLIENT's, raises there, and the
writes before it are dropped.

**Survivors, as predicted: K-45, K-50 and K-50b.** Each leaves a resume the binding has
called, or one whose wait raised, to be called again: a late resume. The server logs it
(`late-resume await`) and wakes nothing. The fake logs it nowhere. The real-socket
suite, step 3, reads the server's log and holds them.

**Not run, as equivalent:**
- the bytes read past the request fed when there are none (`fx>=?`): an empty read
  steps nothing;
- the lines joined with "," for ", ": the handshake passes over the space;
- the state not stored back: the core returns the state it was given;
- `close-from!`'s two guards: the core answers a second close, or one after the end,
  with nothing;
- the log's flush: the suite's port is a string port.

Every new or changed check has a killer by value; none is red only through a raise.

| check | killers by value |
|---|---|
| H-ACCEPT | K-4 |
| H-VERSION | K-3 |
| H-CONN2, H-KEY2 | K-1 |
| H-PROTO2 | K-1, K-4, K-5 |
| H-ORIGIN | K-58 |
| H-ARGS | K-59a, K-59b |
| C-ARGS | K-60a, K-60b, K-60c |
| M-RETAINED | K-6, K-32 |
| M-WAKE | K-12, K-32, K-47, K-72 |
| M-BINARY | K-6 |
| M-BOM | K-6, K-32, K-33, K-34, K-34b to K-34e, K-66b |
| M-REFUSE | K-55 |
| W-HIGH | K-12, K-22 to K-24, K-26, K-27, K-47, K-72 |
| W-LOW | K-12, K-22, K-23, K-25, K-27, K-47, K-72 |
| W-END | K-12, K-17, K-18, K-22, K-26 to K-28, K-34b, K-47, K-49, K-71, K-72 |
| R-QUEUE | K-12 to K-15, K-31, K-32, K-47, K-66, K-72 |
| C-SERVER | K-12, K-17, K-34b, K-48, K-62, K-72 |
| C-CLIENT | K-6, K-17, K-19 |
| C-EOF | K-12, K-17, K-18, K-34b, K-71 |
| C-TIMEOUT | K-10, K-17, K-18, K-34b, K-48, K-63b, K-73 |
| C-OUTSIDE | K-17, K-18, K-34b, K-43, K-44 |
| C-QUEUED | K-12, K-17, K-18, K-30, K-32, K-34b, K-66b, K-71, K-72 |
| C-AGAIN | K-12, K-17, K-18, K-34b, K-71 |
| C-SENDCLOSING | K-12, K-17, K-29, K-34b, K-49, K-53, K-63, K-72 |
| D-DRAIN | K-35, K-36 |
| E-RETURN | K-37 |
| E-CLOSED | K-6, K-34b, K-40, K-42 |
| E-RAISE | K-38, K-39, K-69 |
| E-DETAILS | K-38, K-69, K-70a to K-70e |
| E-CLIENTCLOSED | K-12, K-16, K-34b, K-41, K-71 |
| P-SILENT | K-7, K-20, K-21, K-34b, K-69, K-73 |
| P-OWN | K-7 to K-9, K-34b, K-73 |
| L-1002 | K-6, K-20, K-21, K-34b |
| V-ENV | K-7, K-8, K-56, K-57, K-61 |
| I-AMONG | A-7, A-8 |
| I-binding | A-3, A-4 |
| I-facade | A-1, A-2 |
| I-limits, I-protocol | A-5; A-6 |

## M4.3 step 1's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09.
- **The code:**
  - `src/websocket/private/binding.sls` (blob 7013300);
  - `src/websocket/protocol.sls` (1ff1fbf): `ws-open?` and `ws-sendable-close?`;
  - `src/websocket/handshake.sls` (eea44d4): X-Forwarded-Proto's leftmost element;
  - the Makefile (27081c1): the suites run with no `CHEZ_WS_` variable set.
- **The suites:** `tests/test-binding.sps`, 45 checks (50aeeb4);
  `tests/test-protocol.sps`, 87 (ef62721); `tests/test-handshake.sps`, 26 (5f675ce).

**The runner** is step 1's, extended:
- a copy of the core or the handshake goes first on the path too, and runs with its
  own suite and the binding's;
- the baseline runs the binding, audit, protocol and handshake suites.

### The oracles

Step 1's, and:
- **Decision 0005**, by form, "Many senders, one receive":
  - websockets 17.2 refuses a second receive (`asyncio/connection.py:302-306`) and wakes
    every drained sender together (`:1054-1060`);
  - coder documents one reader (`read.go:29`);
  - gorilla documents one reader and one writer (`doc.go:122-134`).
- **Decision 0003's amendment of 2026-10-09**, by form, "Leftmost element": RFC 7239 §4
  puts the client-facing hop first.
- **The server's own `log-line`** (`(http-server private serve)`) writes the binding's
  expected log lines, so the two formats are tied.
- **The server's waits** (its `waits.sls` header): a resume called after its wait has
  ended is logged `late-resume` and wakes nothing.

### The test-first runs

Each red set was named and hashed before its run, but two, said below.
- **R0** (`ddcf0aa`), as predicted:
  - the protocol suite stopped at load, `ws-open?` unbound, exit 255;
  - the binding suite red in exactly its five new checks, each by value (35 passing);
  - the other nine suites, 184;
  - with `CHEZ_WS_PING_INTERVAL=30` set, the binding suite refused to run, exit 2.
- **R0'** (`d95cab7`), the forms' checks, as predicted:
  - the binding suite red in eight, each by value;
  - the handshake suite red in its scheme check;
  - 305 passes in all.
- **R1** (`251cfcd`): the fixes, 314. **The first run of this tree was not hashed**: I
  ran `make test` straight after the edit. The prediction was then written, naming that
  run, and the second run matched it.
  - R1b, with the variable set: exit 2.
  - R1c, the Makefile unsetting the seven variables: 314.
- **Three checks widened after R1c ran green unhashed at 315**:
  - R-QUEUE-BYTES added;
  - C-QUEUED fed a frame a read;
  - E-DETAILS raising `#f`.

  R1d (`414d51c`), with R-DEADLINE added and the parked waiter no longer cleared: 316,
  as predicted.

### The mutants

New keys, beside step 1's:

| key | check |
|---|---|
| H-FWD2 | X-Forwarded-Proto over two lines is read by its leftmost element: an http Origin for the request's host refused 403 |
| C-ARGS2 | `websocket-close!` refuses a code no endpoint may send, a reason past 123 bytes, a non-code, naming itself; `websocket-accept` refuses settings, naming itself |
| R-QUEUE-BYTES | a queue of a cap's worth of bytes stops reading until it is received |
| X-FOREIGN | a procedure waiting to send to another's WebSocket, whose client leaves, is told `&client-closed`; the other goes on |
| CC-SENDERS | two procedures waiting to send to one WebSocket both go on at the low water |
| CC-RECEIVE | a receive while another waits is refused, naming `websocket-receive`; the waiting one gets the message |
| X-FOREIGN-CLOSED | another WebSocket's `&websocket-closed` let out closes with 1011, logged |
| X-SPENT | the stream closed while the procedure waits on its own: a receive and a send after it raise, 1006 |
| R-DEADLINE | a receive a handler's deadline ends lets go: a later receive waits and gets the next message |
| R-ALLOC | a read the core answers with only its clock allocates nothing in the binding |
| PR-OPEN, PR-SENDABLE | the protocol suite: `ws-open?`, `ws-sendable-close?` |
| HS-SCHEME | the handshake suite: the Origin's scheme held to X-Forwarded-Proto's leftmost element |

Changed: C-OUTSIDE closes with the abort, as the server's own close is at once;
C-QUEUED feeds a frame a read; E-DETAILS and P-SILENT read their lines from the server's
`log-line`, and E-DETAILS raises `#f` too.

Specs hashed before each run, with the names (`e9954ed`) and the runner (`056ee3a`):
- **`987cfe3`**: stopped at the pre-flight, before any row ran. K-37's cut no longer
  matched the rewritten `run`.
- **Run 1** (`c559bef`, K-37's cut fixed): 106 rows, 1 mismatch.
  - K-34b left X-FOREIGN-CLOSED green, against my prediction. Under it, B's take-over
    raised, so B's procedure never ran and the test's `b-ws` stayed `#f`. A's receive
    then raised an assertion with the same text as the one the test had made: the
    check passed on what it did not mean to show.
  - The check now also holds that what B raised is a `&websocket-closed`.
- **Run 2** (`c559bef` again; only the suite changed): 106 rows, 105 mutants and the
  baseline, 0 mismatches.
- **Run 3** (`392775c`): the two mutants that undo the allocation fix, R-25 and R-26,
  and the baseline: 0 mismatches. R-ALLOC's killers had not included them.

Every earlier mutant was re-cut against the rewritten binding and predicted again over
the 45 checks.

| # | mutation | red, as predicted |
|---|----------|-----|
| BASE | none | none: 168 passes over the four suites |
| K-1, K-3, K-4, K-5 | step 1's | as step 1's |
| K-58 | no origins named gets `any` | H-ORIGIN, H-FWD2 |
| R-17 | accept takes any settings | C-ARGS2 |
| R-16 | close takes any code and reason | C-ARGS2 |
| K-6 | the bytes read past the request not fed | M-RETAINED, M-BINARY, M-BOM, C-CLIENT, E-CLOSED, L-1002, X-FOREIGN-CLOSED |
| K-12 | the take-over starts no reading | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE, R-QUEUE-BYTES, C-SERVER, C-EOF, C-QUEUED, C-AGAIN, C-SENDCLOSING, X-FOREIGN, CC-RECEIVE, R-DEADLINE, R-ALLOC, E-CLIENTCLOSED |
| K-71 | a read's end not stepped | W-END, C-EOF, C-QUEUED, C-AGAIN, E-CLIENTCLOSED, X-FOREIGN |
| K-72 | every read stepped as no bytes | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE, R-QUEUE-BYTES, C-SERVER, C-QUEUED, C-SENDCLOSING, X-FOREIGN, CC-RECEIVE, R-DEADLINE |
| R-22 | a read's start not filled in | C-QUEUED |
| R-24 | a read's bytevector not filled in | K-72's, and R-ALLOC |
| R-25 | a read steps a fresh event | R-ALLOC |
| R-26 | a step's actions performed by `for-each` over a closure | R-ALLOC |
| R-4, R-5 | no close call; the close call steps no end | C-OUTSIDE, X-SPENT |
| R-3 | the procedure run with no current WebSocket | C-OUTSIDE |
| R-2 | no waiter's owner | C-OUTSIDE |
| K-44 | the own wait's `&client-closed` let out | C-OUTSIDE |
| R-1 | another's wait's `&client-closed` taken as the own | X-FOREIGN |
| K-38 | a raise not logged | E-RAISE, E-DETAILS, X-FOREIGN-CLOSED |
| K-39 | a raise closes 1000 | E-RAISE, X-FOREIGN-CLOSED |
| K-40, K-42 | the own end let out taken as a failure; raised on | E-CLOSED |
| K-41 | a `&client-closed` let out taken as a failure | E-CLIENTCLOSED |
| R-14 | any `&websocket-closed` let out taken as the own end | X-FOREIGN-CLOSED |
| R-15 | the own end matched while none has come | E-DETAILS |
| K-16 | `close-stream` not performed | E-CLIENTCLOSED, X-FOREIGN |
| K-17 | `closed` not performed | W-END, C-SERVER, C-CLIENT, C-EOF, C-TIMEOUT, C-OUTSIDE, C-QUEUED, C-AGAIN, C-SENDCLOSING, X-FOREIGN-CLOSED, X-SPENT |
| K-47 | a delivery wakes no receive | M-WAKE, W-HIGH, W-LOW, W-END, R-QUEUE, R-QUEUE-BYTES, X-FOREIGN, CC-RECEIVE, R-DEADLINE |
| K-13, K-14 | read-stop, read-start not performed | R-QUEUE, R-QUEUE-BYTES |
| K-15 | disarm not performed | R-QUEUE |
| K-18 | every end clean | W-END, C-EOF, C-TIMEOUT, C-OUTSIDE, C-QUEUED, C-AGAIN, X-SPENT |
| K-48 | the end wakes no receive | C-SERVER, C-TIMEOUT |
| K-49 | the end wakes no send | W-END, C-SENDCLOSING |
| K-50 | a woken receive's waiter kept | M-WAKE, X-FOREIGN, CC-RECEIVE |
| R-8, R-9 | only the newest sender woken; one sender kept | CC-SENDERS |
| R-10 | a second receive not refused | CC-RECEIVE |
| K-45 | a wait that raises keeps its waiter | R-DEADLINE |
| K-31 | a take not stepped | R-QUEUE, R-QUEUE-BYTES |
| R-21 | a take's length not filled in | R-QUEUE-BYTES |
| K-32 | a text received as its bytes | M-RETAINED, M-WAKE, M-BOM, R-QUEUE, R-QUEUE-BYTES, C-QUEUED, X-FOREIGN, CC-RECEIVE, R-DEADLINE |
| K-66 | the queue's tail kept once empty | R-QUEUE, R-QUEUE-BYTES |
| K-34b | no length guard before the mark | step 1's set, and X-SPENT, X-FOREIGN-CLOSED |
| K-22 | a write not counted | W-HIGH, W-LOW, W-END, CC-SENDERS, X-FOREIGN |
| K-23 | a done not counted | W-HIGH, W-LOW, CC-SENDERS |
| K-26 | wait at the high water | W-HIGH, W-END, X-FOREIGN, CC-SENDERS |
| K-27 | a send never waits | W-HIGH, W-LOW, W-END, CC-SENDERS, X-FOREIGN |
| K-29 | a send while the core is not open sent | C-SENDCLOSING |
| K-69 | no newline | E-RAISE, E-DETAILS, P-SILENT, X-FOREIGN-CLOSED |
| K-70a, K-70b | a condition logged as a record; its line breaks kept | E-DETAILS, X-FOREIGN-CLOSED |
| P-1 | `ws-open?` counts a closing connection open | PR-OPEN, C-SENDCLOSING |
| P-2 | `ws-open?` checks no connection | PR-OPEN |
| P-3 | `ws-sendable-close?` does not measure the reason | PR-SENDABLE, PR-CLOSE-REFUSED, PR-REASON-UTF8, C-ARGS2 |
| HS-1, HS-4 | X-Forwarded-Proto read whole; its leftmost element runs to the end | HS-SCHEME, H-FWD2 |
| HS-2, HS-3 | the leftmost element's leading, or trailing, OWS kept | HS-SCHEME |
| the rest of step 1's | re-cut where the rewrite moved their text | as step 1's |
| A-1, A-3, A-5, A-7 | the audit, a spot check | as step 1's |

**Survivors, as predicted:**
- **Late resumes, which the fake logs nowhere:**
  - R-6: the close call marks no wait ended;
  - R-7: a dead waiter woken;
  - R-6b: a procedure's wait not recorded as parked;
  - K-50b: woken senders kept.
- **R-20**: a read's bytevector kept after its step.
- Each is held on step 3's real socket, or by its footprint.

**Not run, as equivalent:**
- K-53 is gone with the binding's closing flag.
- `close-from!` stepping a close whatever `ws-open?` says: the core answers a close
  once one is sent, or after the end, with nothing.

**Every new or changed check has a killer by value**; none is red only through a raise.

| check | killers by value |
|---|---|
| H-FWD2 | K-58, HS-1, HS-4 |
| C-ARGS2 | R-16, R-17, P-3 |
| R-QUEUE-BYTES | K-12, K-13, K-14, K-31, K-32, K-47, K-66, K-72, R-21, R-24 |
| C-OUTSIDE | K-17, K-18, K-34b, K-44, R-2, R-3, R-4, R-5 |
| C-QUEUED | K-12, K-17, K-18, K-30, K-32, K-34b, K-66b, K-71, K-72, R-22, R-24 |
| X-FOREIGN | K-12, K-16, K-22, K-26, K-27, K-32, K-47, K-50, K-71, K-72, R-1, R-24 |
| CC-SENDERS | K-22, K-23, K-26, K-27, R-8, R-9 |
| CC-RECEIVE | K-12, K-32, K-47, K-50, K-72, R-10, R-24 |
| X-FOREIGN-CLOSED | K-6, K-17, K-34b, K-38, K-39, K-69, K-70a, K-70b, R-14 |
| X-SPENT | K-17, K-18, K-34b, R-4, R-5 |
| R-DEADLINE | K-12, K-32, K-45, K-47, K-72, R-24 |
| R-ALLOC | K-12, R-24, R-25, R-26 |
| E-DETAILS | K-38, K-69, K-70a to K-70e, R-15 |
| P-SILENT | K-7, K-20, K-21, K-34b, K-69, K-73 |
| PR-OPEN | P-1, P-2 |
| PR-SENDABLE | P-3 |
| HS-SCHEME | HS-1 to HS-4 |

## M4.3 step 2 — a client that does not read

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09.
- **The code:**
  - `src/websocket/limits.sls` (blob 959076a): `write-timeout-ms`, `CHEZ_WS_WRITE_TIMEOUT`;
  - `src/websocket.sls` (387ef63): the facade exports its accessor;
  - `src/websocket/protocol.sls` (e49b4a3): the write side and the close timeout's abort;
  - `src/websocket/private/binding.sls` (86a55ce): each done stepped, `abort-stream`,
    `close-stream` with the close timeout armed first, a send waiting on `ws-behind?`;
  - the Makefile (d34dce5): `make test` unsets `CHEZ_WS_WRITE_TIMEOUT` too.
- **The suites:** `tests/test-limits.sps`, 15 checks (829b52f);
  `tests/test-protocol.sps`, 101 (5609494); `tests/test-binding.sps`, 52 (806b565).

**The runner** (`wsmut2.py`, a29c22e) is the review's, extended:
- the limits or the facade can go first on the path too: the limits with the limits,
  protocol and binding suites, the facade with the binding's;
- a suite that stops at load is named `LOAD:<suite>`, a red like any other.

### The oracles

Step 1's and its review's, and:
- **Decision 0006**, by form, "Reading stops past the high water" and "60 s, its own
  variable":
  - the server's own `CHEZ_HTTP_WRITE_TIMEOUT`, 60 s, for a client that stops reading
    (its `docs/configuration.org`, `docs/connections.org`);
  - websockets 17.2's `close_timeout` ends in `transport.abort()`
    (`asyncio/connection.py:910-911`, `:942-957`).
- **RFC 6455 §5.2's frame sizes**: a client's ping of 125 bytes is 131, masked; its pong
  127; Hello's frame 7; a close of 1000, 4; a ping of no payload, 2.
- **What was measured before the form** (0006's Context, on main 1d8ed80 and on three
  prototypes, the scratch `s2/measures.md`): the five closes, the send waiting, the
  pinging client and the 1 MiB of pings, each held for an hour of fake time on main.

### The test-first runs

Each red set was named and hashed before its run.
- **Stage 0** (`62ec54c`), the tests alone, as predicted:
  - the limits suite stopped at load, `websocket-limits-write-timeout-ms` unbound, exit 255;
  - the protocol suite stopped at load, `ws-behind?` unbound, exit 255;
  - the binding suite red in exactly its six new checks, each by value: the close asked
    for with no deadline, `(#t #f #f)`; the close timeout closing, not aborting; the
    send's ping read and `ping` armed at 25,000; all 1,048,524 B of pings read and
    1,016,508 B of pongs held; the slow reader failed at the pong's timeout with 255
    sent; reading never stopped. 45 passing.
- **Stage 1** (`00a89fa`), the limits' field and the facade's export: as predicted, the
  limits suite 15; the rest as stage 0.
- **Stage 2** (`ab03f57`), the core, the binding as on main, as predicted:
  - the protocol suite 100 (W-FAIL came in stage 5);
  - the binding suite red in a different six: X-FOREIGN in, since the old binding never
    steps a done and B stays behind; the ping flood's check out, since the core alone
    stops reading.
- **Stage 3** (`93bdd4e`), the binding: eleven suites, 335, as predicted.
- **Stage 4** (`0efa8fa`), the Makefile, red first:
  - 4a, `CHEZ_WS_WRITE_TIMEOUT=5 make test` before the Makefile unset it: the binding
    suite refused to run, naming the variable, exit 2, as predicted. **My prediction's
    count was wrong**: I wrote 320 for the other ten suites, subtracting wrongly; they
    ran 284, which is 335 less the binding suite's 51, as they ran in stage 3.
  - 4b, the variable in `WS_ENV_VARS`: 335 with it set.
- **Stage 5** (`6403988`): four checks the mutant plan found missing, and `written!`'s
  after-the-end clause taken out as redundant. As predicted, 337:
  - W-TAKE takes with no more than the high water unsent, so the hold's "behind" term
    is what stops it;
  - W-FAIL, a failure whose close passes the high water stops and arms nothing after;
  - `ws-behind?`'s own refusal, in W-REFUSE;
  - R-DONE-ALLOC, a write's done allocates nothing in the binding.

### The mutants

New keys, beside step 1's and its review's:

| key | check |
|---|---|
| A-LINGER | a close the client does not read: asked for with the close timeout armed, aborted once it passes |
| A-TIMEOUT | the server's close unanswered by a client that reads nothing: aborted, not closed, at the close timeout |
| B-STALL | a send past the high water to a client that reads nothing: reading stopped, its ping unread, aborted at 60 s; the facade's 60 s |
| B-FLOOD | 1 MiB of pings, nothing read: reading stops at the pong that passes the high water; 2,065 pongs, 262,255 B held |
| B-SLOW | a client reading one write a second: all 300 messages of 1 KiB sent, nothing aborted |
| B-CATCHUP | a client that reads down to the low water is read again, the ping clock afresh |
| R-DONE-ALLOC | a write's done allocates nothing in the binding |
| W-PAST ... W-LETGO | the protocol suite's write side: past the high water, a done, the queue full, a take, pings, the ping, the write timeout, after the server's close, pinging off, a send while behind, a failure, refusals, allocation, letting go |
| PR-CLOSE-TIMEOUT, PR-QUEUE-CLOSE, PR-END-AFTER, PR-CLOSE-CLOCK | the protocol suite's close-timeout checks, now `(abort-stream)` |
| PR-DEADLINES | the deadline named against the one told, with the write side's sequence |
| L-* | the limits suite's fifteen, keyed by their name's start |

Changed: X-FOREIGN's client reads what was sent before it sends, since B reads nothing
while behind; the four close-timeout checks; PR-DEADLINES; and the limits suite's,
for an eighth field.

Specs hashed before each run, with the names (`7ece50d`) and the runner (`a29c22e`):
- **Run 1** (`a40d914`): 42 rows, 41 mutants and the baseline, 0 mismatches.
- **Run 2** (`0e50362`): step 1's K-16, whose cut the binding's new `close-stream` moved,
  re-cut and predicted over the 52 checks; and the baseline: 0 mismatches.

| # | mutation | red, as predicted |
|---|----------|-----|
| BASE | none | none: 178 passes over the binding, audit, protocol and limits suites |
| LM-1 | the write timeout's default 20 s | L-DEFAULTS, L-EMPTY, L-MOVES, L-EDGE, L-WATER, L-FIXNUM, L-ZEROS, L-WITH, B-STALL, B-CATCHUP |
| LM-2 | its least 0 | L-BELOW, L-MAKE-REFUSE |
| LM-3 | read in ms, not seconds | L-MOVES, L-ALL, L-EDGE, L-FIXNUM |
| LM-4 | its variable named otherwise | L-VARS, L-MOVES, L-ALL, L-EDGE, L-BELOW, L-MALFORMED, L-FIXNUM |
| LM-5 | the facade does not export its accessor | LOAD:test-binding |
| LM-6 | `make-websocket-limits` ignores it | L-MAKE, L-MAKE-REFUSE, L-WITH |
| P-EDGE-HIGH | the high water unsent counts as past it | W-PAST, W-DONE, W-FULL, W-TAKE, W-PONGS, W-TIMEOUT, W-CLOSING, W-PINGOFF, W-ALLOC, PR-DEADLINES, W-HIGH, W-END, B-STALL, X-FOREIGN, CC-SENDERS |
| P-EDGE-LOW | the low water unsent still behind | W-DONE, W-CLOSING, W-HIGH |
| P-NO-STOP | behind, reading goes on | W-PAST, W-DONE, W-PONGS, W-PING, W-TIMEOUT, W-CLOSING, W-PINGOFF, W-SEND-END, B-STALL, B-FLOOD, B-CATCHUP |
| P-NO-ARM | behind, no write deadline | W-PAST, W-DONE, W-FULL, W-TAKE, W-PONGS, W-PING, W-TIMEOUT, W-PINGOFF, W-SEND-END, W-LETGO, PR-DEADLINES, B-STALL, B-SLOW, B-CATCHUP |
| P-NO-REARM | a done while behind re-arms nothing | W-DONE, W-FULL, W-TAKE, W-PONGS, B-SLOW |
| P-NO-DISARM | the end of behind leaves the write deadline | W-DONE, W-FULL, W-TAKE, W-PONGS, W-PINGOFF |
| P-HELD-HIGH | a read does not stop at the frame that passes | W-PONGS, B-FLOOD |
| P-HELD-BEHIND | behind, what waits is read | W-TAKE |
| P-READING-ON | a take while behind starts reading | W-TAKE |
| P-CLOSING-ARM | behind after the server's close, the write deadline armed | W-CLOSING |
| P-TIMEOUT-CLOSE | the write timeout closes, not aborts | W-TIMEOUT, B-STALL |
| P-TIMEOUT-LOG | the write timeout logged as the ping's | W-TIMEOUT, B-STALL |
| P-LETGO | the end keeps what waits | W-LETGO |
| P-CLOSE-ABORT | the close timeout closes, not aborts | PR-CLOSE-TIMEOUT, PR-QUEUE-CLOSE, PR-END-AFTER, PR-CLOSE-CLOCK, W-CLOSING, A-TIMEOUT |
| P-REFUSE | a done of more than is unsent accepted | W-REFUSE |
| P-SEND-TEXT | a text send never puts the client behind | W-PAST, W-DONE, W-FULL, W-TAKE, W-TIMEOUT, W-PINGOFF, W-SEND-END, W-LETGO, PR-DEADLINES, W-HIGH, W-LOW, W-END, B-STALL, B-CATCHUP, X-FOREIGN, CC-SENDERS |
| P-SEND-BINARY | a binary send never does | B-SLOW |
| P-CLOSE-FALLEN | the server's close never does | W-CLOSING |
| P-PING-FALLEN | the ping never does | W-PING |
| P-BYTES-FALLEN | a read never does | W-PONGS, B-FLOOD |
| P-PAST-ENDED | an ended connection falls behind | W-FAIL |
| P-PAST-BEHIND | a client behind falls behind again | W-SEND-END |
| P-REARM-FRESH | a re-arming done allocates its action | W-ALLOC |
| P-BEHIND-CHECK | `ws-behind?` checks no connection | W-REFUSE |
| B-WROTE-NOWAKE | a done wakes no send | W-HIGH, W-LOW, B-SLOW, B-CATCHUP, CC-SENDERS |
| B-WAKE-ALWAYS | every done wakes the sends | W-LOW |
| B-WROTE-NOSTEP | a done not stepped | W-HIGH, W-LOW, B-SLOW, B-CATCHUP, X-FOREIGN, CC-SENDERS |
| B-WROTE-FRESH | a done's event made afresh | R-DONE-ALLOC |
| B-LINGER-NONE | the close asked for with no deadline | A-LINGER |
| B-LINGER-PING | the close's deadline the ping timeout | A-LINGER |
| B-ABORT-NOP | `abort-stream` does nothing | A-TIMEOUT, B-STALL |
| B-ABORT-CLOSE | `abort-stream` closes, lingering | A-TIMEOUT, B-STALL |
| B-ARM-WRITE | the write deadline armed for the close timeout | B-STALL, B-CATCHUP |
| B-SEND-NOWAIT | a send never waits | W-HIGH, W-LOW, W-END, B-STALL, B-SLOW, X-FOREIGN, CC-SENDERS |
| K-16' | `close-stream` not performed (run 2) | E-CLIENTCLOSED, X-FOREIGN, A-LINGER |

Three reds came through a raise, besides their value: W-LETGO under P-NO-ARM and
P-SEND-TEXT, the write deadline passing with none armed; W-CLOSING under
P-CLOSING-ARM.

**Superseded:** step 1's K-22 and K-23 (a write, a done, not counted), K-24 and K-26
(the water marks' edges) and K-27 (a send never waits) cut the binding's own count,
which is gone. P-SEND-TEXT, P-SEND-BINARY, B-WROTE-NOSTEP, P-EDGE-LOW, P-EDGE-HIGH and
B-SEND-NOWAIT take their places.

**A survivor, as predicted:** B-LINGER-AFTER, the close's deadline armed after the close
is asked for. Both shells arm a deadline asked for while a close waits for its writes,
and neither arms one once the close has begun (the fake's `fake-transport`, the libuv
shell's `taker-deadline!`), so the order is not observable.

**Every new or changed check has a killer by value.**

| check | killers by value |
|---|---|
| A-LINGER | B-LINGER-NONE, B-LINGER-PING, K-16' |
| A-TIMEOUT | P-CLOSE-ABORT, B-ABORT-NOP, B-ABORT-CLOSE |
| B-STALL | LM-1, B-ARM-WRITE, P-TIMEOUT-CLOSE, P-TIMEOUT-LOG, B-ABORT-NOP, P-NO-STOP, B-SEND-NOWAIT |
| B-FLOOD | P-HELD-HIGH, P-BYTES-FALLEN, P-NO-STOP |
| B-SLOW | P-NO-REARM, P-SEND-BINARY, B-WROTE-NOWAKE, B-WROTE-NOSTEP |
| B-CATCHUP | LM-1, B-ARM-WRITE, P-NO-STOP, B-WROTE-NOWAKE |
| R-DONE-ALLOC | B-WROTE-FRESH |
| X-FOREIGN | P-EDGE-HIGH, P-SEND-TEXT, B-WROTE-NOSTEP, B-SEND-NOWAIT, K-16' |
| W-PAST, W-DONE | P-EDGE-HIGH, P-NO-STOP, P-NO-ARM; and W-DONE P-EDGE-LOW, P-NO-REARM, P-NO-DISARM |
| W-FULL, W-TAKE | P-NO-REARM, P-NO-DISARM; and W-TAKE P-HELD-BEHIND, P-READING-ON |
| W-PONGS | P-HELD-HIGH, P-BYTES-FALLEN |
| W-PING | P-PING-FALLEN |
| W-TIMEOUT | P-TIMEOUT-CLOSE, P-TIMEOUT-LOG |
| W-CLOSING | P-CLOSE-FALLEN, P-EDGE-LOW, P-CLOSE-ABORT |
| W-PINGOFF | P-NO-DISARM |
| W-SEND-END | P-PAST-BEHIND |
| W-FAIL | P-PAST-ENDED |
| W-REFUSE | P-REFUSE, P-BEHIND-CHECK |
| W-ALLOC | P-REARM-FRESH, P-EDGE-HIGH |
| W-LETGO | P-LETGO |
| PR-CLOSE-TIMEOUT, PR-QUEUE-CLOSE, PR-END-AFTER, PR-CLOSE-CLOCK | P-CLOSE-ABORT |
| PR-DEADLINES | P-EDGE-HIGH, P-NO-ARM, P-SEND-TEXT |
| L-DEFAULTS, L-EMPTY, L-WATER, L-ZEROS | LM-1 |
| L-VARS, L-MALFORMED | LM-4 |
| L-MOVES, L-ALL, L-EDGE, L-FIXNUM | LM-3, LM-4; and all but L-ALL LM-1 |
| L-BELOW | LM-2, LM-4 |
| L-MAKE | LM-6 |
| L-MAKE-REFUSE | LM-2, LM-6 |
| L-WITH | LM-1, LM-6 |
| the Makefile's `WS_ENV_VARS` | stage 4a |

## M4.3 step 2's review

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`),
2026-10-09. `/code-review` at xhigh over #43 to #45, 12 findings; the owner's "fix all".
- **The code:**
  - `src/websocket/limits.sls` (blob 6e3b181): the close timeout at least 1 ms;
  - `src/websocket/protocol.sls` (c34839a): `over-high?`, `behind-tail`, the constant
    `caught-up`, `written!` testing the phase;
  - `src/websocket/private/binding.sls` (eb27e37): `write-piece`, 64 KiB; a failed
    done stepped as the end; a send waiting before it writes.
- **The suites:** `tests/test-limits.sps`, 15 checks (3c53516);
  `tests/test-protocol.sps`, 103 (af23fa8); `tests/test-binding.sps`, 55 (7989bc3).

**The runner** is step 2's (`wsmut2.py`), its specs file named for each run.

### The oracles

Step 2's, and:
- **0006's amendment, by form**: "From queueing, as peers do" (websockets 17.2's
  `close_deadline` as the close is sent, `asyncio/connection.py:910-911`; ws 8.22.0's
  30 s from `close()`, `websocket.js:1323-1327`; coder v1.8.15's 5 s, `close.go:185`);
  "Wait before writing too"; "In 64 KiB writes" (nginx's `send_timeout`, "between two
  successive write operations", its docs).
- **RFC 6455 §5.2's frame sizes**: a 1 KiB binary's frame 1,028 bytes, a 16-bit length;
  one of 300,000 bytes 300,010, a 64-bit length; a pong of no payload 2.
- **What was measured before the forms** (0006's amendment, the scratch
  `rv/measures.md`): the close, the large message and the senders, on the tree and
  four prototypes.

### The test-first runs

Each red set was named and hashed before its run.
- **Stage 0** (`919d4eb`), the tests alone, on b9c9d77's library, as predicted:
  - the limits suite red in L-BELOW and L-MAKE-REFUSE, a close timeout of 0 accepted;
  - the protocol suite red in W-TAIL-ALLOC: 16, 32, 32 and 32 bytes, not 0;
  - the binding suite red in CC-SENDERS (28 bytes held, not 14), B-PIECES (one write of
    300,010, aborted) and B-WRITE-ERROR (nothing closed, nothing told).
- **Stage 1** (`65cb802`), the library: **not as predicted**, 339 and four red, for 341:
  - W-DONE, W-TAKE and W-PONGS expected the catch-up's `(disarm-deadline)`, which the
    first cut dropped, the clock's arm replacing it. Put back, as the constant
    `caught-up`.
  - B-PIECES's 150 s outlasted the clock armed afresh as the client caught up: a ping
    of 2 bytes written at 152 s, a sixth write. My check's design; it now turns
    pinging off.
- **Stage 1b** (`be48013`): eleven suites, 341, as predicted.
- **Stage 2** (`41edd15`): W-CLOSING-REARM, the check run 1 found missing: 342, as
  predicted.

### The mutants

New keys, beside step 2's:

| key | check |
|---|---|
| B-PIECES | a message past 64 KiB written in writes of 64 KiB, so a client reading 2 KiB a second is not cut off |
| B-WRITE-ERROR | a write's done that tells a failure ends the connection: the close asked for, 1006 told |
| R-DONE-ALLOC-BEHIND | a done the core answers by re-arming the write timeout allocates nothing in the binding |
| W-TAIL-ALLOC | falling behind and catching up allocate nothing more |
| W-CLOSING-REARM | behind when the server's close is sent: a done above the low water re-arms nothing, one at it starts reading |

Changed: CC-SENDERS (three procedures; the later two wait before they write, 14 bytes
held); B-SLOW (its 255 derived); C-TIMEOUT, P-SILENT and P-OWN (`tick!`); L-EDGE, L-ALL,
L-BELOW and L-MAKE-REFUSE (a close timeout of 1 s at least).

Specs hashed before each run:
- **Run 1** (specs `0cf1ecc`, names `0df4877`): step 2's 42 rows and run 2's K-16',
  nine re-cut where the review moved their code, all predicted again over the new
  and changed checks; and 15 rows of the review's. **58 rows, 57 mutants and the
  baseline, 2 mismatches, each a prediction error:**
  - **P-EDGE-HIGH**, re-cut onto `over-high?`, now makes the read's hold `>=` too, so
    W-FAIL, whose high water is 0, holds its read before the frame: red, not predicted.
    W-ALLOC stayed green, predicted red from step 2's run: its catch-up no longer
    allocates (finding 11).
  - **P-NO-ARM**: B-SLOW stayed green, predicted red from step 2's run. `written!` now
    re-arms by the phase (finding 10), so the first done replaces the stale ping
    deadline that failed B-SLOW in step 2.
  - **PW-1 reddened W-CLOSING only through a raise**: no check stepped a done above the
    low water after the server's close. Stage 2 added W-CLOSING-REARM.
- **Run 2** (specs `f4037a3`, names `5f312fc`): the core's 31 rows again over
  W-CLOSING-REARM, P-EDGE-HIGH's and P-NO-ARM's predicted as run 1 found them, and PW-2
  and PW-3 splitting PW-1's phase test; and the baseline. **0 mismatches.**

| # | mutation | red, as found |
|---|----------|-----|
| BASE | none | none: 183 passes over the binding, audit, protocol and limits suites |
| LM-1 | the write timeout's default 20 s | step 2's, and B-PIECES |
| P-EDGE-HIGH | the high water unsent counts as past it (re-cut: `over-high?`) | W-HIGH, W-END, B-STALL, X-FOREIGN, CC-SENDERS, PR-DEADLINES, W-PAST, W-DONE, W-FULL, W-TAKE, W-PONGS, W-TIMEOUT, W-CLOSING, W-CLOSING-REARM, W-PINGOFF, W-FAIL |
| P-EDGE-LOW | the low water unsent still behind | W-HIGH, W-DONE, W-CLOSING, W-CLOSING-REARM |
| P-NO-STOP | behind, reading goes on | step 2's, and R-DONE-ALLOC-BEHIND, W-CLOSING-REARM |
| P-NO-ARM | behind, no write deadline | step 2's, less B-SLOW, and W-CLOSING-REARM |
| P-NO-REARM | a done while behind re-arms nothing | step 2's, and B-PIECES |
| P-NO-DISARM | the end of behind leaves the write deadline (re-cut: `written!`'s catch-up) | as step 2's |
| P-HELD-HIGH, P-HELD-BEHIND | re-cut onto `over-high?` | as step 2's |
| P-SEND-TEXT, P-SEND-BINARY | re-cut: a send's tail skipped for its kind | step 2's, P-SEND-TEXT with W-CLOSING-REARM |
| P-CLOSE-FALLEN, P-PING-FALLEN | re-cut: their tails `'()` | as step 2's |
| P-BYTES-FALLEN | a read never puts the client behind | step 2's, and R-DONE-ALLOC-BEHIND |
| P-REARM-FRESH | a re-arming done allocates its action | W-ALLOC, R-DONE-ALLOC-BEHIND |
| B-WROTE-NOWAKE, B-WROTE-NOSTEP, B-ARM-WRITE | as step 2's | step 2's, and B-PIECES |
| B-WROTE-FRESH | a done's event made afresh | R-DONE-ALLOC, R-DONE-ALLOC-BEHIND |
| B-SEND-NOWAIT | a send never waits (re-cut: before and after) | as step 2's |
| K-16' | `close-stream` not performed | E-CLIENTCLOSED, X-FOREIGN, A-LINGER, B-WRITE-ERROR |
| LM-C1 | the close timeout's least 0 | L-BELOW, L-MAKE-REFUSE |
| LM-C2 | its least just past 1 s | L-EDGE, L-ALL, L-MAKE, L-WITH |
| PT-S, PT-C, PT-P | a send, the server's close, a ping, falling behind, copy their actions, as `fallen` did | W-TAIL-ALLOC |
| PT-K | catching up conses its disarm | W-TAIL-ALLOC |
| PW-1 | after the server's close a done re-arms and disarms as while open | W-CLOSING, W-CLOSING-REARM |
| PW-2 | a done while behind re-arms whatever the phase | W-TIMEOUT, W-CLOSING-REARM |
| PW-3 | a done that catches up disarms whatever the phase | W-CLOSING, W-CLOSING-REARM |
| BP-1 | a frame in one write | B-PIECES |
| BP-2 | pieces of 65,535 bytes | B-PIECES |
| BP-3 | each piece's done steps the whole frame's bytes | B-PIECES |
| BS-1 | a send does not wait before it writes | CC-SENDERS |
| BE-1 | a done's failure is not the stream's end | B-WRITE-ERROR |
| BA-1 | arming the write deadline allocates a call | R-DONE-ALLOC-BEHIND |
| BT-1 | the close deadline armed for the ping interval | C-TIMEOUT, A-TIMEOUT |
| BT-2 | the pong deadline a millisecond late | P-SILENT, P-OWN |

The other step 2 rows went red as in step 2.

Reds through a raise, besides their value: W-LETGO under P-NO-ARM and P-SEND-TEXT, as in
step 2; L-MAKE and L-WITH under LM-C2, the constructor refusing outside the check's
guard; W-CLOSING under PW-1 and PW-3, a deadline passing with none armed.

**The survivor, as predicted:** B-LINGER-AFTER, as in step 2.

**Every new or changed check has a killer by value.**

## M4.3 step 3 — the real socket

Platform: Darwin 25.6.0 arm64 (Apple M1), Chez Scheme 10.4.1 (`tarm64osx`), 2026-10-09; and
Linux 6.12.76-linuxkit aarch64 in Docker (Ubuntu 24.04.5, libuv 1.48.0) for the socket suite's
rows.
- **The code:**
  - `src/websocket/private/binding.sls` (blob 5d3f741): `park!`'s way back by `call/cc`;
  - `src/websocket/limits.sls` (6cc0d84): the header's ping-timeout caveat, a comment;
  - `Makefile` (322fc46): chez-libuv's `tests/` among `TEST_ONLY_DIRS`.
- **The suites:**
  - `tests/test-socket.sps`, 6 checks (248d64d);
  - `tests/test-driver.sps`, 14 (459edd6), its names check widened;
  - `tests/test-binding.sps`, 55 (7989bc3), unchanged.

**The runner** is step 2's review's (`wsmut2.py`) as `wsmut3.py`:
- a binding mutant runs the binding suite and the socket suite, on a path with chez-libuv's
  `tests/`;
- a driver-suite target runs a mutated copy of that suite;
- a Makefile target runs `make -f <mutated> test`, a suite that stops at load named
  `LOAD:<suite>`.

On Linux the binding's mutants ran against the socket suite alone, from shadow copies made on
Darwin.

### The oracles

- **The server's waits** (its `waits.sls`, R4): a resume called once its wait has ended is
  logged `late-resume`, naming the verb, and wakes nothing. Its drain logs `draining`, then
  `drain-timeout` and `stopped`.
- **RFC 6455** §5.7's masked "Hello"; §5.5.1, a close echoing its code; §7.4.1's 1001 and
  1011; §7.1.5's 1006.
- **0005's amendment, by form** ("call/cc"), and its bound: a receive's wait within 2 KiB of a
  bare `await`'s.
  - Measured in the suite's setting: 2,778 to 4,277 B more by `call/1cc`, and at most 980 B by
    `call/cc`, on Darwin and Linux.
  - The fake shows only about 170 B by `call/1cc`, and −20 B by `call/cc`.
- **A read's bytevector:** a client's 4,000-byte binary is one frame of 4,008 bytes, read at
  once on loopback. The bound is half of it. Measured unmutated: 8 to 144 B.
- **0001:** a silent client pinged at the interval and failed with 1011 a timeout later.

### The test-first runs

Each red set was named and hashed before its run.
- **Stage 0:** the suite, the path and the driver's widened check, on main's binding. As
  predicted:
  - the socket suite red only in S-PARK, at 4,047 B;
  - the driver suite green;
  - twelve suites, 347 passes and one failure.
- **Stage 1:** `call/cc`.
  - **A void run.** The edit was refused, since the file had not been read in the session, so
    the first run was stage 0's tree, S-PARK red at 4,006 B. It is kept, named void.
  - **Rerun on the fixed tree:** green, 348, as predicted.

### The mutants

Each red set was named and hashed before its run. Run 1 was on blobs whose comments run 3's
changed.

| id | mutant | red, predicted and seen |
|---|---|---|
| BASE | the unmutated tree | none |
| R-6 | the close call marks no wait ended | S-DRAIN |
| R-7 | a dead waiter woken | S-DRAIN |
| R-6b | a procedure's wait not recorded as parked | S-DRAIN |
| K-50b | woken senders kept | S-SENDERS |
| R-20 | a read's bytevector kept after its step | S-LETGO |
| P-1CC | `park!`'s way back by `call/1cc` again | S-PARK |
| K-1 | the take-over arms no first deadline | P-SILENT, P-OWN, V-ENV, S-SILENT |
| K-32 | a text received as its bytes | M-RETAINED, M-WAKE, M-BOM, B-CATCHUP, R-QUEUE, R-QUEUE-BYTES, C-QUEUED, X-FOREIGN, CC-RECEIVE, R-DEADLINE, S-ECHO |
| B-LINGER-AFTER | the close's deadline armed after the close is asked for | none: the survivor, as in step 2 |
| D-1 | the driver suite's borrowed list without chez-libuv's `tests/` | D-NAMES |
| MK-1 | `TEST_ONLY_DIRS` without chez-libuv's `tests/` | LOAD:test-socket |

- **Run 1: 12 rows, 1 mismatch.** K-32 also reddened B-CATCHUP. Its set was step 1's review's,
  and B-CATCHUP, step 2's, receives a text after the catch-up: a prediction error. Its actual
  was `(sent #vu8(72 101 108 108 111))`, by value.
- **Run 2,** K-32's set with B-CATCHUP: **0 mismatches.**
- **Run 3,** on the blobs above: **0 mismatches.**
- **On Linux** each binding mutant reddened the same socket check, by value. P-1CC measured
  2,796 B and R-20 4,112 to 4,136 B.

**Every new or changed check has a killer by value:**
- S-ECHO, K-32 (`(binary 5)` for `(text "Hello")`);
- S-SILENT, K-1 (no frame);
- S-DRAIN, R-6, R-7 and R-6b (`late-resume` logged);
- S-SENDERS, K-50b (three);
- S-LETGO, R-20;
- S-PARK, P-1CC;
- D-NAMES, D-1.

The path's change has MK-1.

**The survivor, as predicted:** B-LINGER-AFTER. The libuv shell arms a taker's deadline while
its close waits for writes, and none once the close has begun (`taker-deadline!`), so the
order is not observable on a real socket either.

**Step 1's review's survivors are all killed now:** R-6, R-7, R-6b and K-50b by the server's
`late-resume`, and R-20 by the heap.
