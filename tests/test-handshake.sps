#!r6rs
;;; (websocket handshake) against its oracles (M4.1).
;;;
;;; - RFC 6455's example handshake (§1.3, §4.2.2): its key's accept value,
;;;   s3pPLMBiTxaQ9kYGzzhZRbK+xOo=, and the subprotocol its server chose.
;;; - Chrome 152's handshakes, as a probe on the server measured them: one
;;;   from a page of the same origin, one from a page on another host.
;;; - Accept values of other keys, which three peers computed alike:
;;;   Python's hashlib and base64, Node's crypto, and OpenSSL (the ledger).
;;;   Among them RFC 6455 §4.1's example key as printed, whose last digit
;;;   sets bits past its data (erratum 3150): the accept value is of the key
;;;   as sent.
;;; - The design's §3: its checks, in its order, each refusal's status and
;;;   fields, a wrong version's 400 by decision 0003; the subprotocol chosen;
;;;   Sec-WebSocket-Extensions never answered.
;;; - What a handler accepts of Origin, and what it gets when it names none:
;;;   same-host, by decision 0003, as coder and gorilla do; the Origin's
;;;   scheme, held to X-Forwarded-Proto when that names http or https, by
;;;   0003's amendment (M4.1's review).
;;; - A handler's settings, checked once where they are made, keep copies of
;;;   what they were made with; each answer's bytes and strings are its own.
;;;
;;; That every answer is one the server writes is the door suite's to hold:
;;; this suite needs no server.
;;;
;;; A request's fields are given as the server's request-header reads them:
;;; the value of the first field of a name, without regard to ASCII case,
;;; or #f.
(import (rnrs) (rnrs mutable-pairs) (rnrs mutable-strings) (srfi :64) (ws-testing)
        (websocket handshake))

;; Fields = (Listof (Pair String String))

;; reader : Fields -> (String -> (U String #f))
;; The fields, read as request-header reads a request's.
(define (reader fields)
  (lambda (name)
    (let ((f (find (lambda (f) (string-ci=? (car f) name)) fields)))
      (and f (cdr f)))))

;; with : Fields String (U String #f) -> Fields
;; The fields with `name`'s value replaced, or taken out when #f.
(define (with fields name value)
  (let ((rest (remp (lambda (f) (string-ci=? (car f) name)) fields)))
    (if value (cons (cons name value) rest) rest)))

;; strings : (Listof (Pair Bytevector Bytevector)) -> Fields
(define (strings headers)
  (map (lambda (h) (cons (utf8->string (car h)) (utf8->string (cdr h)))) headers))

;; readable : Answer -> (U (List 'accept Fields (U String #f))
;;                         (List 'refuse Nat Fields Symbol))
;; An answer, its fields as strings, to compare.
(define (readable a)
  (case (car a)
    ((accept) (list 'accept (strings (cadr a)) (caddr a)))
    ((refuse) (list 'refuse (cadr a) (strings (caddr a)) (cadddr a)))
    (else (list 'not-an-answer a))))

;; answer : Symbol Fields String (Listof String) Origins -> readable's
(define (answer method fields host subprotocols origins)
  (readable (handshake-answer method (reader fields) host
                              (make-handshake-settings subprotocols origins))))

;; The example of RFC 6455 §1.3 and §4.1: its server spoke chat.
(define rfc-request
  '(("Host" . "server.example.com")
    ("Upgrade" . "websocket")
    ("Connection" . "Upgrade")
    ("Sec-WebSocket-Key" . "dGhlIHNhbXBsZSBub25jZQ==")
    ("Origin" . "http://example.com")
    ("Sec-WebSocket-Protocol" . "chat, superchat")
    ("Sec-WebSocket-Version" . "13")))
(define rfc-host "server.example.com")

;; Chrome 152's, from a page of the server's own origin, and from a page on
;; localhost, the same server's port: what the server's accessors read.
(define chrome-host "127.0.0.1:18741")
(define chrome-request
  '(("Host" . "127.0.0.1:18741")
    ("Origin" . "http://127.0.0.1:18741")
    ("Upgrade" . "websocket")
    ("Connection" . "Upgrade")
    ("Sec-WebSocket-Version" . "13")
    ("Sec-WebSocket-Key" . "paXiuy6y3wvbRlTyo8QTdQ==")
    ("Sec-WebSocket-Protocol" . "chat, superchat")
    ("Sec-WebSocket-Extensions" . "permessage-deflate; client_max_window_bits")))
(define chrome-other-request
  (with (with chrome-request "Origin" "http://localhost:18741")
        "Sec-WebSocket-Key" "DKc5BAi1AbRhaFkzw73YJg=="))

;; accepted : String -> Fields — the 101's fields with no subprotocol.
(define (accepted accept-value)
  (list (cons "Upgrade" "websocket") (cons "Sec-WebSocket-Accept" accept-value)))

;; accept-value-of : String -> (U String readable's)
;; The accept value the 101 to the RFC's request with this key carries, or
;; the answer if it is not a 101.
(define (accept-value-of key)
  (let ((a (answer 'GET (with rfc-request "Sec-WebSocket-Key" key) rfc-host '() 'any)))
    (if (eq? (car a) 'accept) (cdr (assoc "Sec-WebSocket-Accept" (cadr a))) a)))

;; answers-with : String (Listof (U String #f)) -> (Listof readable's)
;; The answers to the RFC's request with `name` set to each value in turn.
(define (answers-with name values)
  (map (lambda (v) (answer 'GET (with rfc-request name v) rfc-host '("chat") 'any)) values))

;; chosen : String (Listof String) -> (List (U String #f) Fields)
;; The subprotocol chosen for the RFC's request offering `offer` (#f: none),
;; and the 101's fields past Upgrade and Sec-WebSocket-Accept.
(define (chosen offer subprotocols)
  (let ((a (answer 'GET (with rfc-request "Sec-WebSocket-Protocol" offer) rfc-host subprotocols 'any)))
    (if (eq? (car a) 'accept) (list (caddr a) (cddr (cadr a))) a)))

;; origin-answer : (U String #f) String Origins -> (U 'accept (List Nat Symbol) readable's)
(define (origin-answer origin host origins)
  (let ((a (answer 'GET (with (with chrome-request "Origin" origin) "Host" host) host '() origins)))
    (case (car a)
      ((accept) 'accept)
      ((refuse) (list (cadr a) (cadddr a)))
      (else a))))

;; scheme-answer : String (U String #f) Origins -> (U 'accept (List Nat Symbol) readable's)
;; The answer to Chrome's request from `origin`, to the host app.example.com,
;; with X-Forwarded-Proto `proto`, or none when #f.
(define (scheme-answer origin proto origins)
  (let ((a (answer 'GET (with (with (with chrome-request "Origin" origin) "Host" "app.example.com")
                              "X-Forwarded-Proto" proto)
                   "app.example.com" '() origins)))
    (case (car a)
      ((accept) 'accept)
      ((refuse) (list (cadr a) (cadddr a)))
      (else a))))

;; who-refused : (-> Any) -> (U Symbol 'no-assertion)
;; The who of the assertion violation the thunk raises.
(define (who-refused thunk)
  (guard (c ((assertion-violation? c) (if (who-condition? c) (condition-who c) 'no-who)))
    (thunk)
    'no-assertion))

(run-suite "handshake"
  (lambda ()
    (test-equal "RFC 6455's example handshake, the handler speaking chat: a 101 with Upgrade: websocket, the example's accept value and chat, and nothing more"
      (list 'accept
            (list (cons "Upgrade" "websocket")
                  (cons "Sec-WebSocket-Accept" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
                  (cons "Sec-WebSocket-Protocol" "chat"))
            "chat")
      (answer 'GET rfc-request rfc-host '("chat") 'any))

    (test-equal "Chrome 152's handshakes, as measured: accepted with the accept values three peers computed, and no answer to its permessage-deflate offer"
      (list (list 'accept (accepted "5U4UI4Mo7N9BGeXhuHaBN1/uENs=") #f)
            (list 'accept (accepted "w5g+AqJ3sLE19bigfXXLuee7fyI=") #f))
      (list (answer 'GET chrome-request chrome-host '() 'any)
            (answer 'GET chrome-other-request chrome-host '() 'any)))

    (test-equal "a key whose last digit sets bits past its data, as RFC 6455 §4.1 prints its example, is accepted, and the accept value is of the key as sent"
      '("OfS0wDaT5NoxF2gqm7Zj2YtetzM=" "C/0nmHhBztSRGR1CwL6Tf4ZjwpY=")
      (map accept-value-of '("AQIDBAUGBwgJCgsMDQ4PEC==" "AQIDBAUGBwgJCgsMDQ4PEA==")))

    (test-equal "Upgrade and Connection are lists, read without regard to case: Upgrade: WebSocket, Connection: keep-alive, Upgrade, and OWS and empty elements around them"
      '(accept accept accept accept accept accept accept accept accept
        accept accept accept accept accept accept accept accept accept)
      (append
       (map (lambda (v) (car (answer 'GET (with rfc-request "Upgrade" v) rfc-host '() 'any)))
            '("WebSocket" "WEBSOCKET" "h2c, websocket" "websocket, h2c" "h2c,websocket"
              "h2c ,\twebsocket" ",websocket" "websocket, ," "websocket\t, h2c"))
       (map (lambda (v) (car (answer 'GET (with rfc-request "Connection" v) rfc-host '() 'any)))
            '("upgrade" "UPGRADE" "keep-alive, Upgrade" "Upgrade, keep-alive" "keep-alive,upgrade"
              "close ,\tUpgrade" ",Upgrade" "Upgrade," "Upgrade , close"))))

    (test-equal "a method other than GET is refused 400, for its method"
      '((refuse 400 () method) (refuse 400 () method) (refuse 400 () method) (refuse 400 () method)
        (refuse 400 () method) (refuse 400 () method) (refuse 400 () method))
      (map (lambda (m) (answer m rfc-request rfc-host '("chat") 'any))
           '(POST HEAD PUT DELETE OPTIONS PATCH CONNECT)))

    ;; The last value is not trimmed, as the server's reader trims a value:
    ;; elements of OWS alone, at either end, are read as none.
    (test-equal "an Upgrade missing, empty, or not listing websocket is refused 400, for its upgrade"
      (map (lambda (v) '(refuse 400 () upgrade)) '(1 2 3 4 5 6 7 8 9 10 11 12))
      (answers-with "Upgrade"
        '(#f "" "h2c" "websocket2" "websockets" "xwebsocket" "web socket" "websocket/13"
          "\"websocket\"" "websock" "websocked" " \t,h2c, \t")))

    (test-equal "a Connection missing, empty, or not listing upgrade is refused 400, for its connection"
      (map (lambda (v) '(refuse 400 () connection)) '(1 2 3 4 5 6 7 8 9))
      (answers-with "Connection"
        '(#f "" "keep-alive" "upgrades" "Upgrade2" "up grade" "close" "\"Upgrade\"" "degrade")))

    (test-equal "a Sec-WebSocket-Version missing, or not 13, is refused 400 with Sec-WebSocket-Version: 13, for its version (0003)"
      (map (lambda (v) '(refuse 400 (("Sec-WebSocket-Version" . "13")) version))
           '(1 2 3 4 5 6 7 8 9 10 11))
      (answers-with "Sec-WebSocket-Version"
        '(#f "" "8" "12" "14" "013" "13.0" "13, 8" "+13" "1 3" "130")))

    (test-equal "a Sec-WebSocket-Key missing, not base64, or the base64 of other than sixteen bytes is refused 400, for its key"
      (map (lambda (v) '(refuse 400 () key)) '(1 2 3 4 5 6 7 8 9 10 11))
      (answers-with "Sec-WebSocket-Key"
        '(#f "" "AQIDBAUGBwgJCgsMDQ4P" "AQIDBAUGBwgJCgsMDQ4PEBE=" "dGhlIHNhbXBsZSBub25jZQ"
          "dGhlIHNhbXBsZSBub25jZQ=" "dGhlIHNhbXBsZSBub25jZQ===" "dGhlIHNhbXBsZSBub25jZQ-="
          "dGhlIHNhbXBsZSBu b25jZQ==" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "dGhlIHNhbXBsZSBub25j=Q==")))

    ;; Each request breaks one check and every check after it, so only the
    ;; order the checks are made in tells what it is refused for.
    (test-equal "the checks are made in the design's order, the first that fails answering: method, Upgrade, Connection, Sec-WebSocket-Version, Sec-WebSocket-Key, Origin"
      '((400 method) (400 upgrade) (400 connection) (400 version) (400 key) (403 origin))
      (let* ((origin (with rfc-request "Origin" "http://elsewhere.example"))
             (key (with origin "Sec-WebSocket-Key" "not a key"))
             (version (with key "Sec-WebSocket-Version" "8"))
             (connection (with version "Connection" "keep-alive"))
             (upgrade (with connection "Upgrade" "h2c")))
        (map (lambda (method fields)
               (let ((a (answer method fields rfc-host '("chat") '("http://example.com"))))
                 (if (eq? (car a) 'refuse) (list (cadr a) (cadddr a)) a)))
             '(POST GET GET GET GET GET)
             (list upgrade upgrade connection version key origin))))

    (test-equal "the handler's first subprotocol the client offered is chosen, in the handler's order, not the client's, and the 101 names it"
      '(("superchat" (("Sec-WebSocket-Protocol" . "superchat")))
        ("chat" (("Sec-WebSocket-Protocol" . "chat")))
        ("chat" (("Sec-WebSocket-Protocol" . "chat"))))
      (list (chosen "chat, superchat" '("superchat" "chat"))
            (chosen "superchat, chat" '("chat" "superchat"))
            (chosen "chat, superchat" '("v2" "chat"))))

    (test-equal "when none matches, the client offers none, or the handler speaks none, none is chosen, the 101 names none, and the handshake succeeds"
      '((#f ()) (#f ()) (#f ()) (#f ()))
      (list (chosen "chat, superchat" '("v2"))
            (chosen #f '("chat"))
            (chosen "chat, superchat" '())
            (chosen "" '("chat"))))

    (test-equal "the client's offer is a list: OWS around elements, and empty elements, are passed over"
      '(("chat" (("Sec-WebSocket-Protocol" . "chat")))
        ("chat" (("Sec-WebSocket-Protocol" . "chat")))
        ("chat" (("Sec-WebSocket-Protocol" . "chat")))
        ("chat" (("Sec-WebSocket-Protocol" . "chat"))))
      (list (chosen "v1 ,\tchat" '("chat"))
            (chosen ",,chat,," '("chat"))
            (chosen "superchat,chat" '("chat"))
            (chosen "chat\t,v1" '("chat"))))

    (test-equal "a subprotocol is offered only as a whole element, case and all: Chat, chatty, xchat, cha and \"chat\" are not chat"
      '(#f ())
      (chosen "Chat, chatty, xchat, cha, \"chat\", ch at" '("chat")))

    (test-equal "a handler that names no origins gets same-host (0003): Chrome's page of the same origin is accepted, its page on localhost refused 403, and a request with no Origin accepted"
      '(accept (403 origin) accept)
      (map (lambda (fields)
             (let ((a (readable (handshake-answer 'GET (reader fields) chrome-host
                                                  (make-handshake-settings '())))))
               (case (car a) ((accept) 'accept) ((refuse) (list (cadr a) (cadddr a))) (else a))))
           (list chrome-request chrome-other-request (with chrome-request "Origin" #f))))

    (test-equal "a request with no Origin, which is not a browser's, is accepted whatever the handler lists"
      '(accept accept accept accept)
      (map (lambda (origins) (origin-answer #f chrome-host origins))
           (list 'any '() '(same-host) '("http://example.com"))))

    (test-equal "any accepts every Origin: another host's, null, and an empty one"
      '(accept accept accept accept)
      (map (lambda (origin) (origin-answer origin chrome-host 'any))
           '("http://localhost:18741" "null" "https://elsewhere.example" "")))

    (test-equal "a listed origin is accepted without regard to ASCII case; one not listed, or a part or extension of one, is refused 403, for its origin"
      '(accept accept accept accept (403 origin) (403 origin) (403 origin) (403 origin) (403 origin)
        (403 origin))
      (map (lambda (origin)
             (origin-answer origin chrome-host '("http://localhost:18741" "null" "https://zoo.example")))
           '("http://localhost:18741" "HTTP://LOCALHOST:18741" "null" "HTTPS://ZOO.EXAMPLE"
             "http://localhost:18742" "http://localhost" "http://localhost:187410"
             "https://localhost:18741" "http://localhost:18741/" "")))

    ;; An empty Origin is no origin (RFC 6454 §7.1): it names no host.
    (test-equal "same-host accepts an Origin whose host and port are the request's, without regard to case, of either scheme when no proxy names one, as Chrome's page of the same origin; another host, another port, a path, null, no scheme, or an empty Origin is refused 403"
      '(accept accept accept (403 origin) (403 origin) (403 origin) (403 origin) (403 origin)
        (403 origin) (403 origin) (403 origin) (403 origin) (403 origin))
      (map (lambda (origin) (origin-answer origin chrome-host '(same-host)))
           '("http://127.0.0.1:18741" "https://127.0.0.1:18741" "HTTP://127.0.0.1:18741"
             "http://localhost:18741" "http://127.0.0.1:18742" "http://127.0.0.1"
             "http://127.0.0.1:18741/" "null" "127.0.0.1:18741" "http//127.0.0.1:18741"
             "http://127.0.0.1:187411" "http://elsewhere.example/http://127.0.0.1:18741" "")))

    ;; Caddy writes the scheme its client used in X-Forwarded-Proto, replacing
    ;; any a client sent, and a browser cannot set it on a handshake.  A list
    ;; is read by its leftmost element, the client-facing hop's, by RFC 7239
    ;; §4's order (0003's amendment of 2026-10-09, by form).
    (test-equal "same-host holds the Origin's scheme to X-Forwarded-Proto's leftmost element when that names http or https, without regard to case; any other value, or none, is not compared; a listed origin and any are not held to it (0003's amendments)"
      '(accept (403 origin) (403 origin) accept (403 origin) accept accept accept (403 origin) accept accept
        accept accept (403 origin) accept accept)
      (list (scheme-answer "https://app.example.com" "https" '(same-host))
            (scheme-answer "http://app.example.com" "https" '(same-host))
            (scheme-answer "https://app.example.com" "http" '(same-host))
            (scheme-answer "http://app.example.com" "http" '(same-host))
            (scheme-answer "http://app.example.com" "HTTPS" '(same-host))
            (scheme-answer "HTTPS://app.example.com" "https" '(same-host))
            (scheme-answer "http://app.example.com" #f '(same-host))
            (scheme-answer "https://app.example.com" #f '(same-host))
            (scheme-answer "http://app.example.com" "https, http" '(same-host))
            (scheme-answer "http://app.example.com" "" '(same-host))
            (scheme-answer "http://app.example.com" "https" '("http://app.example.com"))
            (scheme-answer "http://app.example.com" "https" 'any)
            (scheme-answer "http://app.example.com" "http, https" '(same-host))
            (scheme-answer "http://app.example.com" " https ,http" '(same-host))
            (scheme-answer "http://app.example.com" ", https" '(same-host))
            (scheme-answer "https://app.example.com" "https,http" '(same-host))))

    (test-equal "same-host compares the host the request names, letters without regard to case, an empty one too, as coder and gorilla do, and refuses RFC 6455's own example, whose Origin names another host; a list may hold same-host beside origins"
      '(accept accept accept (403 origin) (403 origin) accept accept (403 origin))
      (list (origin-answer "https://app.example.com" "app.example.com" '(same-host))
            (origin-answer "https://App.Example.COM" "app.example.COM" '(same-host))
            (origin-answer "http://" "" '(same-host))
            (origin-answer "https://app.example.com" "app.example.com:443" '(same-host))
            (origin-answer "http://example.com" rfc-host '(same-host))
            (origin-answer "http://127.0.0.1:18741" chrome-host '("http://localhost:5173" same-host))
            (origin-answer "http://localhost:5173" chrome-host '("http://localhost:5173" same-host))
            (origin-answer "http://localhost:18741" chrome-host '("http://localhost:5173" same-host))))

    ;; RFC 9110 §5.6.2: tchar is ALPHA, DIGIT, and !#$%&'*+-.^_`|~.
    (test-equal "a subprotocol the handler speaks is a token: one holding every kind of tchar, and each range's ends, is chosen; one with a character beside a range, a separator, DEL or a character past ASCII is refused, naming make-handshake-settings"
      (cons '("azAZ09!#$%&'*+-.^_`|~" (("Sec-WebSocket-Protocol" . "azAZ09!#$%&'*+-.^_`|~")))
            (map (lambda (x) 'make-handshake-settings) '(1 2 3 4 5 6 7 8 9 10 11 12 13 14)))
      (cons (chosen "azAZ09!#$%&'*+-.^_`|~" '("azAZ09!#$%&'*+-.^_`|~"))
            (map (lambda (c)
                   (who-refused
                    (lambda () (make-handshake-settings (list (string #\a c #\b)) 'any))))
                 (list #\/ #\: #\@ #\[ #\{ #\( #\, #\; #\= #\" #\\ #\space
                       (integer->char #x7F) (integer->char #xE9)))))

    (test-equal "make-handshake-settings refuses settings outside its contract, naming itself: subprotocols not a list of tokens, and origins neither any nor a list of origins and same-host"
      (map (lambda (x) 'make-handshake-settings) '(1 2 3 4 5 6 7 8 9 10 11 12 13))
      (map who-refused
           (list (lambda () (make-handshake-settings "chat" 'any))
                 (lambda () (make-handshake-settings '(chat) 'any))
                 (lambda () (make-handshake-settings '("") 'any))
                 (lambda () (make-handshake-settings '("chat v2") 'any))
                 (lambda () (make-handshake-settings '("chat,v2") 'any))
                 (lambda () (make-handshake-settings (list (string #\c (integer->char #xE9))) 'any))
                 (lambda () (make-handshake-settings '("chat" . "v2") 'any))
                 (lambda () (make-handshake-settings '(chat)))
                 (lambda () (make-handshake-settings '() 'all))
                 (lambda () (make-handshake-settings '() "http://example.com"))
                 (lambda () (make-handshake-settings '() '(1)))
                 (lambda () (make-handshake-settings '() '(any)))
                 (lambda () (make-handshake-settings '() '("http://example.com" . same-host))))))

    (test-equal "handshake-answer refuses arguments outside its contract, naming itself: a method not a symbol, a reader not a procedure, a host not a string, settings make-handshake-settings did not make, and a field read as neither a string nor #f, X-Forwarded-Proto among them"
      (map (lambda (x) 'handshake-answer) '(1 2 3 4 5 6))
      (let ((settings (make-handshake-settings '() 'any)))
        (map who-refused
             (list (lambda () (handshake-answer "GET" (reader rfc-request) rfc-host settings))
                   (lambda () (handshake-answer 'GET rfc-request rfc-host settings))
                   (lambda () (handshake-answer 'GET (reader rfc-request) 'host settings))
                   (lambda () (handshake-answer 'GET (reader rfc-request) rfc-host '(() any)))
                   (lambda () (handshake-answer 'GET (lambda (name) (if (string-ci=? name "Upgrade") 'websocket "13"))
                                                rfc-host settings))
                   (lambda () (handshake-answer 'GET (lambda (name)
                                                       (if (string-ci=? name "X-Forwarded-Proto")
                                                           'https
                                                           ((reader rfc-request) name)))
                                                rfc-host settings))))))

    ;; Each answer is spoiled whole before the next is made.
    (test-equal "each answer's fields are bytevectors of its own, and its subprotocol a string of its own: writing over one answer's leaves the next answer's as they were"
      (list (list 'accept
                  (list (cons "Upgrade" "websocket")
                        (cons "Sec-WebSocket-Accept" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
                        (cons "Sec-WebSocket-Protocol" "chat"))
                  "chat")
            '(refuse 400 (("Sec-WebSocket-Version" . "13")) version))
      (let ((settings (make-handshake-settings '("chat") 'any))
            (version (with rfc-request "Sec-WebSocket-Version" "8")))
        (define (spoil! a)
          (for-each (lambda (h) (bytevector-fill! (car h) 0) (bytevector-fill! (cdr h) 0))
                    (if (eq? (car a) 'accept) (cadr a) (caddr a)))
          (when (and (eq? (car a) 'accept) (caddr a)) (string-fill! (caddr a) #\x)))
        (spoil! (handshake-answer 'GET (reader rfc-request) rfc-host settings))
        (spoil! (handshake-answer 'GET (reader version) rfc-host settings))
        (list (readable (handshake-answer 'GET (reader rfc-request) rfc-host settings))
              (readable (handshake-answer 'GET (reader version) rfc-host settings)))))

    ;; The handler's list and strings are changed after the settings are made.
    (test-equal "settings keep copies of what they were made with: the handler's lists and strings, changed afterwards, change nothing"
      '("chat" accept)
      (let* ((names (list (string-copy "chat")))
             (origin (string-copy "http://example.com"))
             (origins (list origin))
             (by-names (make-handshake-settings names 'any))
             (by-origins (make-handshake-settings '() origins)))
        (string-fill! (car names) #\x)
        (set-car! names "superchat")
        (string-fill! origin #\x)
        (set-car! origins "http://example.org")
        (list (caddr (handshake-answer 'GET (reader rfc-request) rfc-host by-names))
              (car (handshake-answer 'GET (reader rfc-request) rfc-host by-origins)))))))
