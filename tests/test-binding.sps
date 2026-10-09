#!r6rs
;;; The binding and the facade (M4.3, step 1) on the server's fake shell
;;; (decision 0004): a handler answers what `websocket-accept` returns, and
;;; its procedure reads, sends and closes as a client plays the other side.
;;;
;;; The oracles:
;;; - RFC 6455, read from its raw text: §1.3's example handshake and its
;;;   Sec-WebSocket-Accept; §4.2.1's checks, a version other than 13 answered
;;;   with Sec-WebSocket-Version: 13 (§4.4); §5.1, a client's frame masked,
;;;   else failed with 1002; §5.5.1, a close answered with a close, which
;;;   echoes the code it received; §5.5.2, a ping may carry no payload;
;;;   §5.7's frames; §7.1.5 and §7.1.6, a connection that closed with no close
;;;   received told 1006 and an empty reason; §7.1.4, clean once a close has
;;;   gone each way; §7.4.1's codes, 1001 for going away, 1011 for a
;;;   condition the server did not expect.
;;; - RFC 9110 §5.3: a field's lines are one list, joined with commas, and
;;;   decision 0004: the facade reads every line (request-header-values), so
;;;   a split Connection is taken, and two keys or two versions refused 400,
;;;   as websockets, coder and ws refuse them.
;;; - Decision 0001: a queue of max-queue messages stops reading; the ping
;;;   clock, 20 s quiet then a ping, 20 s for its pong, then 1011.
;;; - The design's §6: each action performed; a send that waits while more
;;;   than the high water is unsent, until no more than the low water is, as
;;;   the server's own streams wait (its configuration.org); a message
;;;   delivered whole, a text's string keeping a leading U+FEFF; the drain's
;;;   1001 "going away"; the procedure's end: its return closes with 1000, a
;;;   &websocket-closed it lets out does nothing more, any other raise closes
;;;   with 1011 and is logged.  Its §7: the limits read from the environment
;;;   once, as the program starts, a malformed value stopping it there.
;;; - websockets 17.2 (asyncio/connection.py, send_context): a send while the
;;;   closing handshake is under way waits for the connection to close, then
;;;   raises ConnectionClosed.
;;;
;;; How a test plays the client is the driver suite's: `fake-shell-feed-input!`
;;; delivers only while the binding reads, `fake-shell-deliver!` hands over
;;; one event whatever the read state, and `fake-shell-deliver-later!` the
;;; next later turn, such as a write the client reads.  What the client reads
;;; is read as a client would, the 101 by the server's (response-reader).
;;; The binding logs to the current output port, which each check that looks
;;; for a line takes for its own.
(import (rnrs) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (chezscheme) parameterize system display-condition)
        (rename (only (chezscheme) current-output-port) (current-output-port output-port-parameter))
        (only (http-server limits) default-limits)
        (only (http-server switch) switch? switch-headers switch-take-over)
        (websocket))

(define (b s) (string->utf8 s))

;; copy : Bytevector Nat Nat -> Bytevector — bv[from, to), copied.
(define (copy bv from to)
  (let ((o (make-bytevector (- to from)))) (bytevector-copy! bv from o 0 (- to from)) o))

;; concat : (Listof Bytevector) -> Bytevector
(define (concat bvs)
  (let ((out (make-bytevector (fold-left (lambda (n bv) (+ n (bytevector-length bv))) 0 bvs))))
    (fold-left (lambda (at bv) (bytevector-copy! bv 0 out at (bytevector-length bv)) (+ at (bytevector-length bv)))
               0 bvs)
    out))

(define bv u8-list->bytevector)

;; --- the frames, by RFC 6455 §5.2 and §5.3 ----------------------------------

;; §5.7's masking key.
(define key '(#x37 #xFA #x21 #x3D))

;; big-endian : Nat Nat -> (Listof Byte) — n as k bytes, most significant first.
(define (big-endian n k)
  (let loop ((n n) (k k) (out '()))
    (if (= k 0) out (loop (div n 256) (- k 1) (cons (mod n 256) out)))))

;; length-bytes : Nat Byte -> (Listof Byte)
;; The second byte, the mask bit's value given, then the extended length,
;; in the shortest form.
(define (length-bytes n mask)
  (cond ((< n 126) (list (+ mask n)))
        ((< n 65536) (cons (+ mask 126) (big-endian n 2)))
        (else (cons (+ mask 127) (big-endian n 8)))))

;; client-frame : Byte Bytevector -> Bytevector
;; A client's frame: its first byte, the length masked, the key, the payload
;; masked, byte i with the key's byte i mod 4.
(define (client-frame first payload)
  (let ((p (bytevector->u8-list payload)))
    (bv (append (list first) (length-bytes (length p) 128) key
                (let loop ((p p) (i 0) (out '()))
                  (if (null? p)
                      (reverse out)
                      (loop (cdr p) (+ i 1)
                            (cons (bitwise-xor (car p) (list-ref key (mod i 4))) out))))))))

;; server-frame : Byte Bytevector -> Bytevector
;; The server's frame: its first byte, the length unmasked, the payload.
(define (server-frame first payload)
  (bv (append (list first) (length-bytes (bytevector-length payload) 0) (bytevector->u8-list payload))))

;; close-body : Nat String -> Bytevector — a close's code, then its reason.
(define (close-body code reason)
  (bv (append (big-endian code 2) (bytevector->u8-list (b reason)))))

;; RFC 6455 §5.7's examples, as its text prints them.
(define rfc-masked-hello (bv '(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58)))
(define rfc-hello (bv '(#x81 #x05 #x48 #x65 #x6C #x6C #x6F)))

(define nothing (make-bytevector 0))
(define ping (bv '(#x89 #x00)))
(define (server-close code reason) (server-frame #x88 (close-body code reason)))
(define (client-close code reason) (client-frame #x88 (close-body code reason)))

;; pattern : Nat -> Bytevector — n bytes, byte i being i x 37 mod 256.
(define (pattern n)
  (let ((out (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) out) (bytevector-u8-set! out i (mod (* i 37) 256)))))

;; --- the client --------------------------------------------------------------

;; RFC 6455 §1.3's opening handshake, with the fields given in place of its
;; own, each a line.
(define (request . fields)
  (b (apply string-append "GET /chat HTTP/1.1\r\nHost: server.example.com\r\n"
            (append (map (lambda (f) (string-append f "\r\n")) fields) '("\r\n")))))
(define upgrade "Upgrade: websocket")
(define connection "Connection: Upgrade")
(define rfc-key "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==")
(define version "Sec-WebSocket-Version: 13")
(define handshake (request upgrade connection rfc-key version))

;; answer : FakeShell -> (List (U Nat Datum) (Listof (Pair String String)) Bytevector)
;; What the client has read: the head it read first, as the server's
;; (response-reader) reads that head alone, its status and its fields; then
;; every byte after it.  A head the reader does not finish exactly at its end
;; is answered `(unread status)`, with the reader's last status.
(define (answer sh)
  (let* ((all (concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head '() all))
            ((equal? (copy all i (+ i 4)) blank)
             (let ((r (read-response (copy all 0 (+ i 4)) #f #f)))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (list-ref r 2)
                     (copy all (+ i 4) n))))
            (else (scan (+ i 1)))))))

;; after-101 : FakeShell -> (List (U Nat Datum) Bytevector) — the status, and
;; what the client read after the head.
(define (after-101 sh)
  (let ((a (answer sh))) (list (car a) (caddr a))))

;; field : (Listof (Pair String String)) String -> (U String #f)
(define (field fields name)
  (let ((f (find (lambda (f) (string-ci=? (car f) name)) fields)))
    (and f (cdr f))))

;; --- the server ---------------------------------------------------------------

;; accepting : (WebSocket -> Any) . Any -> (Request -> Answer)
;; A handler answering what websocket-accept answers, with any settings and
;; limits given.
(define (accepting proc . options)
  (lambda (request) (apply websocket-accept request proc options)))

;; connect : (Request -> Answer) Bytevector -> FakeShell
;; A fake connection, its clock at 5,000 ms, read `input` and settled.
(define (connect handler input)
  (let ((sh (make-fake-connection default-limits handler #f 5000)))
    (fake-shell-feed-input! sh input 4096)
    (fake-shell-settle! sh)
    sh))

;; holding : (Request -> Answer) (Transport -> Any) -> (Request -> Answer)
;; The handler, its switch's take-over wrapped to hand the transport to
;; `keep` first, so a test can close the stream under the binding, as the
;; server does when its drain times out.
(define (holding handler keep)
  (lambda (request)
    (let ((a (handler request)))
      (if (switch? a)
          (switch-protocols (switch-headers a)
                            (lambda (t retained) (keep t) ((switch-take-over a) t retained)))
          a))))

;; logged : (-> Any) -> (List Any String)
;; What the thunk answers, and what was written to the current output port
;; while it ran: the binding's log.  The port is Chez's parameter, which
;; (rnrs)'s current-output-port reads but cannot be given to parameterize.
(define (logged thunk)
  (let-values (((port get) (open-string-output-port)))
    (let ((v (parameterize ((output-port-parameter port)) (thunk))))
      (list v (get)))))

;; limits : (Listof (Pair Symbol Nat)) -> WebsocketLimits — the defaults, these replaced.
(define (limits overrides) (websocket-limits-with default-websocket-limits overrides))

;; closed : Condition -> (List 'closed Nat String Boolean)
(define (closed e)
  (list 'closed (websocket-closed-code e) (websocket-closed-reason e) (websocket-closed-clean? e)))

;; who-of : (-> Any) -> (U Symbol 'no-raise)
;; The who of the assertion violation the thunk raises.
(define (who-of thunk)
  (guard (e ((assertion-violation? e) (condition-who e))) (thunk) 'no-raise))

;; A record type of the suite's own, for a procedure to raise.
(define-record-type oops)

;; A notebook: what a procedure saw, in order.
(define-record-type notes (fields (mutable seen)) (protocol (lambda (new) (lambda () (new '())))))
(define (note! n x) (notes-seen-set! n (cons x (notes-seen n))))
(define (seen n) (reverse (notes-seen n)))

;; echoing : Notes -> (WebSocket -> Any)
;; Echoes each message, noting it, until the connection closes, noting how.
(define (echoing n)
  (lambda (ws)
    (guard (e ((websocket-closed? e) (note! n (closed e))))
      (let loop ()
        (let ((m (websocket-receive ws)))
          (note! n m)
          (websocket-send! ws m)
          (loop))))))

;; until-told : (WebSocket -> Any) -> (List (WebSocket -> Any) (-> Any))
;; A procedure that waits, receiving nothing, until the test tells it to go
;; on, then runs `then`; and the test's go, after which the test drains the
;; scheduler.  Its wait is its own, so a stream closed while it waits
;; raises &client-closed there: a test tells it to go on before the close's
;; later turn.
(define (until-told then)
  (let ((go #f))
    (list (lambda (ws) (await (lambda (resume) (set! go resume))) (then ws))
          (lambda () (go #t)))))

;; receiving-all : Notes -> (WebSocket -> Any)
;; Receives and notes each message until the connection closes, noting how.
(define (receiving-all n)
  (lambda (ws)
    (guard (e ((websocket-closed? e) (note! n (closed e))))
      (let loop () (note! n (websocket-receive ws)) (loop)))))

(run-suite "binding"
  (lambda ()
    ;; The suite's own frames are §5.7's.
    (unless (and (equal? (client-frame #x81 (b "Hello")) rfc-masked-hello)
                 (equal? (server-frame #x81 (b "Hello")) rfc-hello))
      (provenance-failure "the suite's frames are not RFC 6455 §5.7's"))

    ;; --- the handshake, through the facade ---

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) handshake))
           (a (answer sh)))
      (test-equal "RFC 6455's example handshake is answered 101, Upgrade: websocket, with its Sec-WebSocket-Accept"
        '(101 "websocket" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
        (list (car a) (field (cadr a) "Upgrade") (field (cadr a) "Sec-WebSocket-Accept"))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) (request upgrade connection rfc-key "Sec-WebSocket-Version: 8")))
           (a (answer sh)))
      (test-equal "a version other than 13 is refused 400 with Sec-WebSocket-Version: 13, and the procedure never runs"
        '(400 "13" ())
        (list (car a) (field (cadr a) "Sec-WebSocket-Version") (seen n))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n))
                        (request upgrade "Connection: keep-alive" connection rfc-key version))))
      (test-equal "Connection over two lines, keep-alive then Upgrade, is read whole and the request taken: 101"
        101 (car (answer sh))))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws) (note! n (websocket-subprotocol ws)) ((echoing n) ws))
                                   (make-handshake-settings '("superchat" "chat")))
                        (request upgrade connection rfc-key version
                                 "Sec-WebSocket-Protocol: chat" "Sec-WebSocket-Protocol: superchat")))
           (a (answer sh)))
      (test-equal "a subprotocol offered on the second of two lines is read: the handler's first choice is answered, and websocket-subprotocol names it"
        '(101 "superchat" ("superchat"))
        (list (car a) (field (cadr a) "Sec-WebSocket-Protocol") (seen n))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n))
                        (request upgrade connection rfc-key "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" version))))
      (test-equal "two Sec-WebSocket-Key lines are refused 400"
        400 (car (answer sh))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n))
                        (request upgrade connection rfc-key version "Origin: http://evil.example"))))
      (test-equal "a handler that names no origins refuses a browser's Origin of another host, 403"
        403 (car (answer sh))))

    (test-equal "websocket-accept refuses a procedure that is not one, and limits that are not limits, naming itself, before it reads the request"
      '(websocket-accept websocket-accept)
      (list (who-of (lambda () (websocket-accept 'request 42)))
            (who-of (lambda () (websocket-accept 'request (lambda (ws) #t) (make-handshake-settings '()) 'limits)))))

    (test-equal "receive, send and close refuse what is not a WebSocket, each naming itself"
      '(websocket-receive websocket-send! websocket-close!)
      (list (who-of (lambda () (websocket-receive 'ws)))
            (who-of (lambda () (websocket-send! 'ws "a")))
            (who-of (lambda () (websocket-close! 'ws)))))

    ;; --- messages ---

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) (concat (list handshake rfc-masked-hello)))))
      (test-equal "a masked Hello sent with the handshake is received as the string Hello, and its echo is §5.7's unmasked frame"
        (list '("Hello") (list 101 rfc-hello))
        (list (seen n) (after-101 sh))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) handshake))
           (before (seen n)))
      (fake-shell-deliver! sh (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (fake-shell-settle! sh)
      (test-equal "a message that comes while receive waits wakes it, and the client reads its echo"
        (list '() '("Hello") (list 101 rfc-hello))
        (list before (seen n) (after-101 sh))))

    (let* ((n (make-notes))
           (data (pattern 256))
           (sh (connect (accepting (echoing n)) (concat (list handshake (client-frame #x82 data))))))
      (test-equal "a binary message is received as its bytevector, and echoed as §5.7's 256-byte binary frame"
        (list (list data) (list 101 (concat (list (bv '(#x82 #x7E #x01 #x00)) data))))
        (list (seen n) (after-101 sh))))

    (let* ((n (make-notes))
           (bom-a (bv '(#xEF #xBB #xBF #x41)))
           (bom (bv '(#xEF #xBB #xBF)))
           ;; U+EEFF, U+FEBF and U+FEFE: each one byte off U+FEFF's three.
           (near (list (bv '(#xEE #xBB #xBF)) (bv '(#xEF #xBA #xBF)) (bv '(#xEF #xBB #xBE))))
           (texts (append (list bom-a bom nothing) near))
           (sh (connect (accepting (echoing n))
                        (concat (cons handshake (map (lambda (x) (client-frame #x81 x)) texts))))))
      (test-equal "a text beginning with U+FEFF is received with it, one of U+FEFF alone, an empty text as the empty string, and texts of U+EEFF, U+FEBF and U+FEFE, one byte off U+FEFF, as themselves; each echoed as its own bytes"
        (list '((#xFEFF #x41) (#xFEFF) () (#xEEFF) (#xFEBF) (#xFEFE))
              (list 101 (concat (map (lambda (x) (server-frame #x81 x)) texts))))
        (list (map (lambda (s) (if (string? s) (map char->integer (string->list s)) s)) (seen n))
              (after-101 sh))))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (guard (e ((assertion-violation? e) (note! n (condition-who e))))
                                       (websocket-send! ws 42))))
                        handshake)))
      (test-equal "a send of neither a string nor a bytevector is refused, naming websocket-send!"
        '(websocket-send!) (seen n)))

    ;; --- the write bound: the server's own water marks (design §6) ---

    ;; Hello's frame is 7 bytes, "ab"'s 4: with the high water at 7 and the
    ;; low at 4, a send waits once more than 7 are unsent, until 4 or fewer are.
    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (websocket-receive ws)
                                     (websocket-send! ws "Hello") (note! n 1)
                                     (websocket-send! ws "ab") (note! n 2)
                                     (websocket-receive ws))
                                   (make-handshake-settings '())
                                   (limits '((write-high-water . 7) (write-low-water . 4))))
                        handshake)))
      (fake-shell-deliver! sh (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (let ((before (seen n)))
        (fake-shell-deliver-later! sh)
        (test-equal "a send that leaves the high water unsent goes on, one past it waits, and the client's reading it down to the low water lets it go on"
          '((1) (1 2)) (list before (seen n)))))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (websocket-receive ws)
                                     (websocket-send! ws "Hello") (note! n 1)
                                     (websocket-send! ws "Hello") (note! n 2)
                                     (websocket-receive ws))
                                   (make-handshake-settings '())
                                   (limits '((write-high-water . 7) (write-low-water . 4))))
                        handshake)))
      (fake-shell-deliver! sh (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (fake-shell-deliver-later! sh)
      (let ((one (seen n)))
        (fake-shell-deliver-later! sh)
        (test-equal "a send waiting with more than the low water unsent still waits, and goes on once the client has read down to it"
          '((1) (1 2)) (list one (seen n)))))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (guard (e ((websocket-closed? e) (note! n (closed e))))
                                       (websocket-receive ws)
                                       (websocket-send! ws "Hello") (note! n 1)
                                       (websocket-send! ws "Hello") (note! n 2)))
                                   (make-handshake-settings '())
                                   (limits '((write-high-water . 7) (write-low-water . 4))))
                        handshake)))
      (fake-shell-deliver! sh (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (fake-shell-deliver! sh '(eof))
      (test-equal "a send waiting when the connection ends is woken at once, before the client reads, and raises &websocket-closed"
        '(1 (closed 1006 "" #f)) (seen n)))

    ;; --- reading on (0001) ---

    (let* ((n (make-notes))
           (told (until-told (lambda (ws) (note! n (websocket-receive ws)) (note! n (websocket-receive ws)))))
           (sh (connect (accepting (car told) (make-handshake-settings '()) (limits '((max-queue . 1))))
                        handshake))
           (first (fake-shell-feed-input! sh rfc-masked-hello 4096))
           (stopped (fake-shell-feed-input! sh rfc-masked-hello 4096))
           (unarmed (fake-shell-armed sh)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (let* ((rearmed (fake-shell-armed sh))
             (again (fake-shell-feed-input! sh rfc-masked-hello 4096)))
        (fake-shell-settle! sh)
        (test-equal "a queue of one message stops reading, and the ping clock, until it is received; then reading starts again, the clock afresh, and the next is read"
          '(11 0 #f 25000 11 ("Hello" "Hello")) (list first stopped unarmed rearmed again (seen n)))))

    ;; --- closing ---

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (websocket-close! ws)
                                     (guard (e ((websocket-closed? e) (note! n (closed e))))
                                       (websocket-receive ws))))
                        handshake))
           (sent (after-101 sh)))
      (let ((c (client-close 1000 "")))
        (fake-shell-deliver! sh (list 'bytes-arrived c 0 (bytevector-length c))))
      (test-equal "websocket-close! writes a close of 1000, and the client's close ends the connection cleanly: receive raises &websocket-closed, 1000, at once, before the stream has closed"
        (list (list 101 (server-close 1000 "")) '((closed 1000 "" #t)))
        (list sent (seen n))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) (concat (list handshake (client-close 1001 "bye"))))))
      (test-equal "a client's close is answered with a close echoing its code, and receive raises &websocket-closed with its code and reason, cleanly"
        (list (list 101 (server-close 1001 "")) '((closed 1001 "bye" #t)))
        (list (after-101 sh) (seen n))))

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) handshake)))
      (fake-shell-deliver! sh '(eof))
      (fake-shell-settle! sh)
      (test-equal "the stream's end with no close: receive raises &websocket-closed, 1006, an empty reason, not clean, and nothing is written"
        (list (list 101 nothing) '((closed 1006 "" #f)))
        (list (after-101 sh) (seen n))))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (websocket-close! ws 4000 "bye")
                                     (guard (e ((websocket-closed? e) (note! n (closed e))))
                                       (websocket-receive ws))))
                        handshake))
           (armed (fake-shell-armed sh)))
      ;; The fake's timer runs the deadline's call alone; the libuv shell
      ;; drains its scheduler after every turn, so the check drains it too.
      (fake-shell-advance! sh 9999)
      (fake-shell-fire! sh)
      (fake-shell-schedule! sh)
      (let ((before (seen n)))
        (fake-shell-advance! sh 1)
        (fake-shell-fire! sh)
        (fake-shell-schedule! sh)
        (test-equal "a close of a code and reason the handler gives, not answered within the close timeout, 10 s, ends the connection anyway: 1006, not clean, and not a millisecond before"
          (list 15000 '() '((closed 1006 "" #f)) (list 101 (server-close 4000 "bye")))
          (list armed before (seen n) (after-101 sh)))))

    (let* ((n (make-notes))
           (t #f)
           (sh (connect (holding (accepting (echoing n)) (lambda (x) (set! t x))) handshake)))
      (transport-close! t)
      (fake-shell-settle! sh)
      (test-equal "the stream closed under the binding while receive waits: the wait's &client-closed ends the connection, 1006, not clean"
        (list '((closed 1006 "" #f)) (list 101 nothing))
        (list (seen n) (after-101 sh))))

    (let* ((n (make-notes))
           (told (until-told (receiving-all n)))
           (sh (connect (accepting (car told)) handshake)))
      (fake-shell-feed-input! sh (concat (list rfc-masked-hello (client-frame #x81 (b "again")))) 4096)
      (fake-shell-deliver! sh '(eof))
      ((cadr told))
      (fake-shell-schedule! sh)
      (fake-shell-settle! sh)
      (test-equal "messages queued before the end are received first, then &websocket-closed"
        '("Hello" "again" (closed 1006 "" #f)) (seen n)))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (define (once thunk)
                                       (guard (e ((websocket-closed? e) (note! n (closed e)))) (thunk)))
                                     (once (lambda () (websocket-receive ws)))
                                     (once (lambda () (websocket-receive ws)))
                                     (once (lambda () (websocket-send! ws "late")))))
                        handshake)))
      (fake-shell-deliver! sh '(eof))
      (fake-shell-settle! sh)
      (test-equal "after the end, every receive and every send raises &websocket-closed again"
        '((closed 1006 "" #f) (closed 1006 "" #f) (closed 1006 "" #f)) (seen n)))

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (websocket-close! ws 4000)
                                     (guard (e ((websocket-closed? e) (note! n (closed e))))
                                       (websocket-send! ws "late"))))
                        handshake))
           (before (seen n)))
      (let ((c (client-close 1000 "")))
        (fake-shell-deliver! sh (list 'bytes-arrived c 0 (bytevector-length c))))
      (let ((told (seen n)))
        (fake-shell-settle! sh)
        (test-equal "a send while the server's close, of a code alone, is under way waits for the connection to close, writes nothing, and raises &websocket-closed at once, before the stream has closed"
          (list '() '((closed 1000 "" #t)) (list 101 (server-close 4000 "")))
          (list before told (after-101 sh)))))

    ;; --- the server's drain ---

    (let* ((n (make-notes))
           (sh (connect (accepting (echoing n)) handshake)))
      (fake-shell-drain! sh)
      (fake-shell-settle! sh)
      (test-equal "the server's drain sends a close of 1001, going away"
        (list 101 (server-close 1001 "going away")) (after-101 sh)))

    ;; --- the procedure's end ---

    (let ((sh (connect (accepting (lambda (ws) 'done)) handshake)))
      (test-equal "a procedure that returns closes with 1000"
        (list 101 (server-close 1000 "")) (after-101 sh)))

    (let* ((run (logged (lambda ()
                          (let ((sh (connect (accepting (lambda (ws) (websocket-receive ws)))
                                             (concat (list handshake (client-close 1000 ""))))))
                            (list (after-101 sh) (fake-shell-taker-failures sh)))))))
      (test-equal "a procedure that lets &websocket-closed out has nothing more done: no close but the answer, nothing logged, no taker failure"
        (list (list (list 101 (server-close 1000 "")) '()) "")
        run))

    (let* ((run (logged (lambda ()
                          (let ((sh (connect (accepting (lambda (ws) (raise 'oops))) handshake)))
                            (list (after-101 sh) (fake-shell-taker-failures sh)))))))
      (test-equal "a procedure that raises anything else closes with 1011, and is logged, with no taker failure"
        (list (list (list 101 (server-close 1011 "")) '()) "websocket-handler-failed oops\n")
        run))

    (let* ((two-lines (condition (make-error) (make-message-condition "line one\nline two")))
           (run (logged (lambda ()
                          (for-each (lambda (x) (connect (accepting (lambda (ws) (raise x))) handshake))
                                    (list "hi there" (make-oops) '("a b") two-lines)))))
           (shown (let-values (((port get) (open-string-output-port)))
                    (display-condition two-lines port)
                    (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list (get)))))))
      (test-equal "a procedure's raise is logged as the server logs a detail: a string displayed, a record by its type's name, a list written, a condition as display-condition shows it, on one line"
        (string-append "websocket-handler-failed hi there\n"
                       "websocket-handler-failed #<oops>\n"
                       "websocket-handler-failed (\"a b\")\n"
                       "websocket-handler-failed " shown "\n")
        (cadr run)))

    (let* ((n (make-notes))
           (run (logged (lambda ()
                          (let ((sh (connect (accepting (lambda (ws)
                                                          (guard (e ((client-closed? e) (note! n 'client-closed) (raise e)))
                                                            (await (lambda (resume) #f)))))
                                             handshake)))
                            (fake-shell-deliver! sh '(eof))
                            (fake-shell-settle! sh)
                            (list (after-101 sh) (fake-shell-taker-failures sh)))))))
      (test-equal "the stream's end closes the stream, so a procedure's own wait raises &client-closed; let out, it has nothing more done: nothing written, nothing logged, no taker failure"
        (list '(client-closed) (list (list 101 nothing) '()) "")
        (cons (seen n) run)))

    ;; --- the ping clock (0001), armed by the binding as it starts ---

    (let* ((run (logged
                 (lambda ()
                   (let* ((sh (connect (accepting (receiving-all (make-notes))) handshake))
                          (armed (fake-shell-armed sh)))
                     (fake-shell-advance! sh 19999)
                     (fake-shell-fire! sh)
                     (fake-shell-settle! sh)
                     (let ((quiet (after-101 sh)))
                       (fake-shell-advance! sh 1)
                       (fake-shell-fire! sh)
                       (fake-shell-settle! sh)
                       (let ((pinged (after-101 sh)))
                         (fake-shell-advance! sh 19999)
                         (fake-shell-fire! sh)
                         (fake-shell-settle! sh)
                         (let ((waiting (after-101 sh)))
                           (fake-shell-advance! sh 1)
                           (fake-shell-fire! sh)
                           (fake-shell-settle! sh)
                           (list armed quiet pinged waiting (after-101 sh))))))))))
      (test-equal "a client silent after the 101 is pinged at 20 s, not before, and failed with 1011 20 s later, not before, logged"
        (list (list 25000 (list 101 nothing) (list 101 ping) (list 101 ping)
                    (list 101 (concat (list ping (server-close 1011 "")))))
              "websocket-failed 1011 ping-timeout\n")
        run))

    (let* ((run (logged
                 (lambda ()
                   (let* ((sh (connect (accepting (receiving-all (make-notes)) (make-handshake-settings '())
                                                  (limits '((ping-interval-ms . 30000) (ping-timeout-ms . 5000))))
                                       handshake))
                          (armed (fake-shell-armed sh)))
                     (fake-shell-advance! sh 30000)
                     (fake-shell-fire! sh)
                     (let ((pong (fake-shell-armed sh)))
                       (fake-shell-advance! sh 5000)
                       (fake-shell-fire! sh)
                       (fake-shell-settle! sh)
                       (list armed pong (after-101 sh))))))))
      (test-equal "a handler's own ping interval and timeout, 30 s and 5 s, are the times armed: pinged at 30 s, failed 5 s later"
        (list 35000 40000 (list 101 (concat (list ping (server-close 1011 "")))))
        (car run)))

    ;; --- a failure, logged ---

    (let* ((run (logged (lambda ()
                          (after-101 (connect (accepting (receiving-all (make-notes)))
                                              (concat (list handshake rfc-hello))))))))
      (test-equal "an unmasked frame fails the connection with 1002, logged with its code"
        (list (list 101 (server-close 1002 "")) "websocket-failed 1002 ")
        (list (car run) (let ((log (cadr run))) (if (>= (string-length log) 22) (substring log 0 22) log)))))

    ;; --- the environment, read once, as the program starts (design §7) ---

    (test-equal "the limits are read from the environment as a program that imports the facade starts, and websocket-accept takes them in both its forms: a ping interval of 4 s armed twice, and a malformed one stopping the program before its first line"
      '(8 255)
      (map (lambda (value)
             (system (string-append "CHEZ_WS_PING_INTERVAL=" value
                                    " chez --program tests/start-with-environment.sps >/dev/null 2>&1")))
           '("4" "x")))))
