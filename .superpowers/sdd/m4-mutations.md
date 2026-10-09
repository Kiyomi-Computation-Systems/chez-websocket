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
