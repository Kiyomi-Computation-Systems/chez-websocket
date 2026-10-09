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
;;; - Decision 0006 (M4.3 step 2): every close the binding asks for gives the
;;;   client the close timeout to read what was written, then aborts; and by
;;;   form, "Reading stops past the high water" and "60 s, its own
;;;   variable": past the high water, reading stops and the write timeout,
;;;   60 s, runs, re-armed by each done, its passing aborting the stream.
;;;   The frames' sizes are RFC 6455 §5.2's: a client's ping of 125 bytes is
;;;   131, masked, and its pong 127; a 1 KiB binary's frame 1,028 bytes, a
;;;   16-bit length; one of 300,000 bytes 300,010, a 64-bit length.
;;; - Decision 0006's amendments at step 2's review, by form: "Wait before
;;;   writing too", a send waits while the client is behind before it
;;;   writes, so many procedures sending make the server hold no more than
;;;   one does; and "In 64 KiB writes", a frame written in pieces of 64 KiB
;;;   at most, each done re-arming the write timeout, as nginx's
;;;   send_timeout runs between two writes (its docs).  And the design's
;;;   §6: a write's done that tells a failure is the stream's end.
;;;
;;; How a test plays the client is the driver suite's: `fake-shell-feed-input!`
;;; delivers only while the binding reads, `fake-shell-deliver!` hands over
;;; one event whatever the read state, and `fake-shell-deliver-later!` the
;;; next later turn, such as a write the client reads.  feed-input! lets
;;; every later turn happen before each read, a client that reads; `unread!`
;;; plays one that reads nothing, `reading-at!` one that reads at a rate,
;;; and a spy sees what the binding asks of the transport.  What the client reads
;;; is read as a client would, the 101 by the server's (response-reader).
;;; The binding logs to the current output port, which each check that looks
;;; for a line takes for its own.
(import (rnrs) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (chezscheme) parameterize system getenv)
        (rename (only (chezscheme) current-output-port) (current-output-port output-port-parameter))
        (only (http-server limits) default-limits)
        (only (http-server switch) switch? switch-headers switch-take-over)
        (only (http-server private serve) log-line)
        (only (websocket limits) websocket-limits-environment-variables)
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

;; wrapping : (Request -> Answer) (Transport -> Transport) -> (Request -> Answer)
;; The handler, its switch's take-over handed `(wrap t)` in place of the
;; fake's transport t.
(define (wrapping handler wrap)
  (lambda (request)
    (let ((a (handler request)))
      (if (switch? a)
          (switch-protocols (switch-headers a)
                            (lambda (t retained) ((switch-take-over a) (wrap t) retained)))
          a))))

;; holding : (Request -> Answer) (Transport -> Any) -> (Request -> Answer)
;; The handler, its switch's take-over wrapped to hand the transport to
;; `keep` first, so a test can close the stream under the binding, as the
;; server does when its drain times out.
(define (holding handler keep)
  (wrapping handler (lambda (t) (keep t) t)))

;; logged : (-> Any) -> (List Any String)
;; What the thunk answers, and what was written to the current output port
;; while it ran: the binding's log.  The port is Chez's parameter, which
;; (rnrs)'s current-output-port reads but cannot be given to parameterize.
(define (logged thunk)
  (let-values (((port get) (open-string-output-port)))
    (let ((v (parameterize ((output-port-parameter port)) (thunk))))
      (list v (get)))))

;; server-logged : Symbol (Listof Any) -> String
;; The line the server's own log writes for `what` and its details: the
;; binding logs as the server does, and this ties the two.
(define (server-logged what details)
  (cadr (logged (lambda () (log-line what details)))))

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

;; --- a client that reads nothing (0006) --------------------------------------

;; A spy between the fake's transport and the binding: whether the binding
;; has asked for the close, and for the abort; what it has written whose
;; done has not come, in writes and in bytes, and those writes' sizes,
;; oldest first; every write's size, newest first; and the failure its
;; dones tell the binding in place of the fake's, or #f.
(define-record-type spy
  (fields (mutable closed?) (mutable aborted?) (mutable held) (mutable held-bytes)
          (mutable pending) (mutable asked) (mutable fail))
  (protocol (lambda (new) (lambda () (new #f #f 0 0 '() '() #f)))))

;; spying : (Request -> Answer) Spy -> (Request -> Answer)
;; The handler, its switch's take-over given a transport over the fake's
;; that notes in `spy` what the binding asks of it, and passes each call on.
(define (spying handler spy)
  (wrapping
   handler
   (lambda (t)
     (make-transport
      (lambda (bytes start end written)
        (let ((n (- end start)))
          (spy-held-set! spy (+ (spy-held spy) 1))
          (spy-held-bytes-set! spy (+ (spy-held-bytes spy) n))
          (spy-pending-set! spy (append (spy-pending spy) (list n)))
          (spy-asked-set! spy (cons n (spy-asked spy)))
          (transport-write! t bytes start end
                            (lambda (why)
                              (spy-held-set! spy (- (spy-held spy) 1))
                              (spy-held-bytes-set! spy (- (spy-held-bytes spy) n))
                              (spy-pending-set! spy (cdr (spy-pending spy)))
                              (when written (written (or (spy-fail spy) why)))))))
      (lambda (on-bytes on-end) (transport-read-start! t on-bytes on-end))
      (lambda () (transport-read-stop! t))
      (lambda () (spy-closed?-set! spy #t) (transport-close! t))
      (lambda (ms passed) (if ms (transport-deadline! t ms passed) (transport-deadline! t #f)))
      (lambda (thunk) (transport-on-drain! t thunk))
      (lambda (thunk) (transport-on-close! t thunk))
      (lambda () (spy-aborted?-set! spy #t) (transport-abort! t))))))

;; unread! : FakeShell Bytevector -> Nat
;; The client's bytes, 4 KiB a read, delivered only while the binding reads,
;; as libuv delivers them, and no later turn between: a client that reads
;; nothing.  Returns how many bytes were delivered.
(define (unread! sh bytes)
  (let ((len (bytevector-length bytes)))
    (let loop ((from 0))
      (if (and (< from len) (fake-shell-reading? sh))
          (let ((to (min len (+ from 4096))))
            (fake-shell-deliver! sh (list 'bytes-arrived bytes from to))
            (loop to))
          from))))

;; tick! : FakeShell Nat -> Void
;; The fake clock moved on ms, its timer fired, and the scheduler drained,
;; as the libuv shell drains it after every turn.
(define (tick! sh ms)
  (fake-shell-advance! sh ms)
  (fake-shell-fire! sh)
  (fake-shell-schedule! sh))

;; reading-at! : FakeShell Spy Nat Nat -> Void
;; A client that reads `rate` bytes a second, for `secs` seconds: each write
;; the binding asked for is the client's, its later turn delivered, once
;; the client has read its last byte; then the clock moves on a second.
(define (reading-at! sh spy rate secs)
  (let second ((s 0) (budget rate))
    (when (< s secs)
      (let ((pending (spy-pending spy)))
        (if (and (pair? pending) (<= (car pending) budget))
            (begin (fake-shell-deliver-later! sh) (second s (- budget (car pending))))
            (begin (tick! sh 1000) (second (+ s 1) (+ budget rate))))))))

(run-suite "binding"
  (lambda ()
    ;; Its numbers are the defaults': the binding reads CHEZ_WS_ variables as
    ;; the program starts, and make test runs the suites with none set.
    (let ((set (filter getenv websocket-limits-environment-variables)))
      (unless (null? set)
        (assertion-violation 'binding-suite "a CHEZ_WS_ variable is set; make test unsets them" set)))
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

    (let ((sh (connect (accepting (echoing (make-notes)))
                       (request upgrade connection rfc-key version "Origin: http://server.example.com"
                                "X-Forwarded-Proto: https" "X-Forwarded-Proto: http"))))
      (test-equal "X-Forwarded-Proto over two lines is read by its leftmost element, the client-facing hop's: https, so an Origin of http for the request's own host is refused 403"
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

    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (note! n (who-of (lambda () (websocket-close! ws 1005))))
                                     (note! n (who-of (lambda () (websocket-close! ws 1000 (make-string 124 #\a)))))
                                     (note! n (who-of (lambda () (websocket-close! ws 'normal))))
                                     (websocket-receive ws)))
                        handshake)))
      (test-equal "websocket-close! refuses a code an endpoint may not send, a reason past 123 bytes, and a code that is not one, naming itself, and closes nothing; websocket-accept refuses settings that are not settings, naming itself"
        (list '(websocket-close! websocket-close! websocket-close!) (list 101 nothing) 'websocket-accept)
        (list (seen n) (after-101 sh)
              (who-of (lambda () (websocket-accept 'request (lambda (ws) #t) 'settings))))))

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

    ;; --- a client that does not read (0006; M4.3 step 2) ---

    ;; An unmasked frame fails the connection with 1002: its close written,
    ;; the stream's close asked for.  The client reads none of it.
    (let* ((spy (make-spy))
           (n (make-notes))
           (run (logged
                 (lambda ()
                   (let ((sh (connect (spying (accepting (receiving-all n)) spy) handshake)))
                     (unread! sh rfc-hello)
                     (let ((asked (list (spy-closed? spy) (spy-aborted? spy) (fake-shell-armed sh))))
                       (tick! sh 9999)
                       (let ((before (spy-aborted? spy)))
                         (tick! sh 1)
                         (list asked before (spy-aborted? spy) (seen n)))))))))
      (test-equal "a close the client does not read: the binding asks for it with the close timeout armed, 10 s, and aborts the stream once it passes, not a millisecond before; the connection ended at once, 1006"
        (list '(#t #f 15000) #f #t '((closed 1006 "" #f)))
        (car run)))

    (let* ((spy (make-spy))
           (n (make-notes))
           (told (until-told (lambda (ws) (websocket-close! ws 4000 "bye") ((receiving-all n) ws))))
           (sh (connect (spying (accepting (car told)) spy) handshake)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (tick! sh 9999)
      (let ((before (list (spy-aborted? spy) (seen n))))
        (tick! sh 1)
        (let ((at (list (spy-closed? spy) (spy-aborted? spy) (seen n))))
          (fake-shell-settle! sh)
          (test-equal "the server's close not answered by a client that reads nothing: at the close timeout, 10 s, the stream is aborted, not closed, and the close unsent dropped: 1006, not clean"
            (list '(#f ()) '(#f #t ((closed 1006 "" #f))) (list 101 nothing))
            (list before at (after-101 sh))))))

    ;; Hello's frame is 7 bytes: with the high water at 7, a second is past it.
    (let* ((spy (make-spy))
           (n (make-notes))
           (told (until-told (lambda (ws)
                               (guard (e ((websocket-closed? e) (note! n (closed e))))
                                 (websocket-send! ws "Hello") (note! n 1)
                                 (websocket-send! ws "Hello") (note! n 2)))))
           (run (logged
                 (lambda ()
                   (let ((sh (connect (spying (accepting (car told) (make-handshake-settings '())
                                                         (limits '((write-high-water . 7) (write-low-water . 4))))
                                              spy)
                                      handshake)))
                     ((cadr told))
                     (fake-shell-schedule! sh)
                     (let ((armed (fake-shell-armed sh)) (reading (fake-shell-reading? sh)))
                       (tick! sh 30000)
                       (let ((pinged (unread! sh (client-frame #x89 nothing))))
                         (tick! sh 29999)
                         (let ((before (list (seen n) (spy-aborted? spy))))
                           (tick! sh 1)
                           (list armed reading pinged before (seen n) (spy-aborted? spy))))))))))
      (test-equal "a send past the high water to a client that reads nothing waits; reading stops, so the client's ping is not read, and the write timeout, 60 s, the facade's environment's, aborts the stream, not a millisecond before: the send raises &websocket-closed, 1006, logged write-timeout"
        (list 60000
              (list (list 65000 #f 0 '((1) #f) '(1 (closed 1006 "" #f)) #t)
                    (server-logged 'websocket-failed '(#f write-timeout))))
        (list (websocket-limits-write-timeout-ms environment-websocket-limits) run)))

    ;; A client's ping of 125 bytes is 131 bytes, masked, and its pong 127:
    ;; the pong that takes what is unsent past the high water, 256 KiB, is
    ;; the (div 262144 127) + 1st, and the read it came in is the last.
    (let* ((spy (make-spy))
           (sh (connect (spying (accepting (receiving-all (make-notes))) spy) handshake))
           (one (client-frame #x89 (make-bytevector 125 7)))
           (delivered (unread! sh (concat (vector->list (make-vector (div 1048576 (bytevector-length one)) one))))))
      (test-equal "a client that sends pings and reads nothing: reading stops at the pong that takes what is unsent past the high water, so the server holds the high water and that one pong"
        (let ((pongs (+ 1 (div 262144 127))))
          (list (* 4096 (+ 1 (div (* pongs 131) 4096))) pongs (* pongs 127) #f))
        (list delivered (spy-held spy) (spy-held-bytes spy) (fake-shell-reading? sh))))

    ;; A 1 KiB binary's frame is 1,028 bytes: (div 262144 1028) of them fit
    ;; at or under the high water, and the next passes it, is written, and
    ;; waits.
    (let* ((sent 0)
           (spy (make-spy))
           (told (until-told (lambda (ws)
                               (do ((i 0 (+ i 1))) ((= i 300))
                                 (websocket-send! ws (make-bytevector 1024 7))
                                 (set! sent (+ sent 1)))
                               (websocket-receive ws))))
           (sh (connect (spying (accepting (car told)) spy) handshake)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (let ((behind sent))
        (let loop ((s 0))
          (when (and (< sent 300) (< s 300))
            (fake-shell-deliver-later! sh)
            (tick! sh 1000)
            (loop (+ s 1))))
        (test-equal "a client that reads one write a second is not cut off: past the high water the send waits, each done re-arms the write timeout, and all 300 messages of 1 KiB are sent"
          (list (div 262144 1028) 300 #f) (list behind sent (spy-aborted? spy)))))

    (let* ((n (make-notes))
           (told (until-told (lambda (ws)
                               (websocket-send! ws "Hello") (websocket-send! ws "Hello") (note! n 'sent)
                               ((receiving-all n) ws))))
           (sh (connect (accepting (car told) (make-handshake-settings '())
                                   (limits '((write-high-water . 7) (write-low-water . 4))))
                        handshake)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (let ((behind (list (fake-shell-reading? sh) (fake-shell-armed sh))))
        (fake-shell-settle! sh)
        (let ((caught-up (list (fake-shell-reading? sh) (fake-shell-armed sh))))
          (fake-shell-feed-input! sh rfc-masked-hello 4096)
          (fake-shell-settle! sh)
          (test-equal "a client that reads down to the low water is read again: reading stops while it is behind, the write timeout armed; once it has read, reading starts, the ping clock armed afresh, and its next message is received"
            (list '(#f 65000) '(#t 25000) '(sent "Hello")) (list behind caught-up (seen n))))))

    ;; A binary of 300,000 bytes: its frame, 300,010 bytes, past the high
    ;; water, goes in four writes of 65,536 and one of the 37,866 left.  A
    ;; client reading 2 KiB a second reads a piece in 32 s, within the write
    ;; timeout, though the whole frame takes 147 s.  Pinging is off, so the
    ;; clock, armed afresh as the client catches up, writes nothing.
    (let* ((n (make-notes))
           (spy (make-spy))
           (payload (make-bytevector 300000 7))
           (told (until-told (lambda (ws) (websocket-send! ws payload) (note! n 'sent) (websocket-receive ws))))
           (sh (connect (spying (accepting (car told) (make-handshake-settings '()) (limits '((ping-interval-ms . 0)))) spy)
                        handshake)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (reading-at! sh spy 2048 150)
      (test-equal "a message past 64 KiB is written in writes of 64 KiB, the last the rest, so a client that reads each within the write timeout is not cut off, however long the whole message takes: 300,000 bytes read at 2 KiB a second"
        (list '(65536 65536 65536 65536 37866) #f '(sent)
              (list 101 (concat (list (bv (cons #x82 (length-bytes 300000 0))) payload))))
        (list (reverse (spy-asked spy)) (spy-aborted? spy) (seen n) (after-101 sh))))

    ;; A write's done that tells a failure: the client has gone.  No read
    ;; need tell the binding: the done does.
    (let* ((n (make-notes))
           (spy (make-spy))
           (told (until-told (lambda (ws) (websocket-send! ws "Hello") ((receiving-all n) ws))))
           (sh (connect (spying (accepting (car told)) spy) handshake)))
      (spy-fail-set! spy 'ECONNRESET)
      ((cadr told))
      (fake-shell-schedule! sh)
      (fake-shell-deliver-later! sh)
      (test-equal "a write's done that tells a failure ends the connection at once: the stream's close asked for, and the receive that waits raises &websocket-closed, 1006, not clean"
        (list #t '((closed 1006 "" #f))) (list (spy-closed? spy) (seen n))))

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

    ;; A cap of 5 bytes: Hello's 5 fill the queue by bytes, its one message
    ;; short of its count.
    (let* ((n (make-notes))
           (told (until-told (lambda (ws) (note! n (websocket-receive ws)) (note! n (websocket-receive ws)))))
           (sh (connect (accepting (car told) (make-handshake-settings '()) (limits '((max-message-bytes . 5))))
                        handshake))
           (first (fake-shell-feed-input! sh rfc-masked-hello 4096))
           (stopped (fake-shell-feed-input! sh rfc-masked-hello 4096)))
      ((cadr told))
      (fake-shell-schedule! sh)
      (let ((again (fake-shell-feed-input! sh rfc-masked-hello 4096)))
        (fake-shell-settle! sh)
        (test-equal "a queue of a cap's worth of bytes stops reading until it is received, and then reads the next"
          '(11 0 11 ("Hello" "Hello")) (list first stopped again (seen n)))))

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
      (tick! sh 9999)
      (let ((before (seen n)))
        (tick! sh 1)
        (test-equal "a close of a code and reason the handler gives, not answered within the close timeout, 10 s, ends the connection anyway: 1006, not clean, and not a millisecond before"
          (list 15000 '() '((closed 1006 "" #f)) (list 101 (server-close 4000 "bye")))
          (list armed before (seen n) (after-101 sh)))))

    ;; The server closes a stream at once when its drain times out: as an
    ;; abort does.
    (let* ((n (make-notes))
           (t #f)
           (sh (connect (holding (accepting (echoing n)) (lambda (x) (set! t x))) handshake)))
      (transport-abort! t)
      (fake-shell-settle! sh)
      (test-equal "the stream closed under the binding while receive waits: the wait's &client-closed ends the connection, 1006, not clean"
        (list '((closed 1006 "" #f)) (list 101 nothing))
        (list (seen n) (after-101 sh))))

    (let* ((n (make-notes))
           (told (until-told (receiving-all n)))
           (sh (connect (accepting (car told)) handshake)))
      ;; A frame a read: the second read begins 11 bytes into what was fed.
      (fake-shell-feed-input! sh (concat (list rfc-masked-hello (client-frame #x81 (b "again"))))
                              (bytevector-length rfc-masked-hello))
      (fake-shell-deliver! sh '(eof))
      ((cadr told))
      (fake-shell-schedule! sh)
      (fake-shell-settle! sh)
      (test-equal "messages queued before the end, read a frame a read, are received first, then &websocket-closed"
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

    ;; --- one WebSocket reached from another's procedure (M4.3's review) ---

    ;; A's procedure sends to B's WebSocket until it waits there, B's client
    ;; reading nothing yet; then A's client leaves.  The &client-closed is
    ;; A's stream's, so it is A's procedure's, and B goes on.
    (let* ((na (make-notes))
           (nb (make-notes))
           (b-ws #f)
           (shb (connect (accepting (lambda (ws) (set! b-ws ws) ((echoing nb) ws))
                                    (make-handshake-settings '())
                                    (limits '((write-high-water . 7) (write-low-water . 4))))
                         handshake))
           (sha (connect (accepting (lambda (ws)
                                      (guard (e ((client-closed? e) (note! na 'client-closed) (raise e)))
                                        (websocket-send! b-ws "Hello")
                                        (websocket-send! b-ws "Hello")
                                        (note! na 'sent))))
                         handshake)))
      (fake-shell-deliver! sha '(eof))
      (fake-shell-settle! sha)
      ;; B's client reads what A sent, so B reads again (0006), then sends.
      (fake-shell-feed-input! shb rfc-masked-hello 4096)
      (fake-shell-settle! shb)
      (test-equal "a procedure waiting to send to another connection's WebSocket, whose own client leaves, is told &client-closed, and the other connection goes on: it receives, and its client reads what was sent and the echo"
        (list '(client-closed) '("Hello") (list 101 (concat (list rfc-hello rfc-hello rfc-hello))))
        (list (seen na) (seen nb) (after-101 shb))))

    ;; Three procedures, A's, C's and D's, send to B's WebSocket, B's client
    ;; reading nothing yet: A's second Hello takes what is unsent past the
    ;; high water, and C and D, coming while B's client is behind, wait
    ;; before they write, so B holds A's two Hellos alone.  Once B's client
    ;; reads, all go on (decision 0005: many senders), each in turn while
    ;; the client is not behind, and it reads every Hello.
    (let* ((na (make-notes))
           (nc (make-notes))
           (nd (make-notes))
           (spy (make-spy))
           (b-ws #f)
           (shb (connect (spying (accepting (lambda (ws) (set! b-ws ws) ((echoing (make-notes)) ws))
                                            (make-handshake-settings '())
                                            (limits '((write-high-water . 7) (write-low-water . 4))))
                                 spy)
                         handshake))
           (sending (lambda (n first)
                      (lambda (ws)
                        (when first (websocket-send! b-ws "Hello"))
                        (websocket-send! b-ws "Hello")
                        (note! n 'sent)
                        (websocket-receive ws))))
           (sha (connect (accepting (sending na #t)) handshake))
           (shc (connect (accepting (sending nc #f)) handshake))
           (shd (connect (accepting (sending nd #f)) handshake))
           (waiting (list (seen na) (seen nc) (seen nd) (spy-held-bytes spy))))
      (let turns ((k 0))
        (when (< k 3)
          (fake-shell-settle! shb)
          (for-each fake-shell-schedule! (list sha shc shd))
          (turns (+ k 1))))
      (test-equal "procedures sending to one WebSocket whose client is behind wait before they write, so it holds what one would; once its client has read down to the low water, all go on"
        (list '(() () () 14) '(sent) '(sent) '(sent)
              (list 101 (concat (list rfc-hello rfc-hello rfc-hello rfc-hello))))
        (list waiting (seen na) (seen nc) (seen nd) (after-101 shb))))

    ;; B's procedure waits to receive; A's procedure asks to receive from B's
    ;; WebSocket too (decision 0005: one receive).
    (let* ((na (make-notes))
           (nb (make-notes))
           (b-ws #f)
           (shb (connect (accepting (lambda (ws) (set! b-ws ws) ((echoing nb) ws))) handshake))
           (sha (connect (accepting (lambda (ws)
                                      (note! na (who-of (lambda () (websocket-receive b-ws))))
                                      (websocket-receive ws)))
                         handshake)))
      (fake-shell-deliver! shb (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (fake-shell-settle! shb)
      (test-equal "a receive while another waits on the same WebSocket is refused, naming websocket-receive, and the waiting one still gets the message"
        (list '(websocket-receive) '("Hello") (list 101 rfc-hello))
        (list (seen na) (seen nb) (after-101 shb))))

    ;; B's client has closed; A's procedure receives from B's WebSocket, and
    ;; lets B's &websocket-closed out.  That is not A's end: any other raise.
    (let* ((b-ws #f)
           (shb (connect (accepting (lambda (ws) (set! b-ws ws))) (concat (list handshake (client-close 1000 "")))))
           (b-closed (guard (e (#t e)) (websocket-receive b-ws)))
           (run (logged (lambda ()
                          (after-101 (connect (accepting (lambda (ws) (websocket-receive b-ws))) handshake))))))
      (test-equal "a procedure that lets another WebSocket's &websocket-closed out has not ended its own: it closes with 1011, logged as any other raise"
        (list #t (list 101 (server-close 1011 "")) (server-logged 'websocket-handler-failed (list b-closed)))
        (cons (websocket-closed? b-closed) run)))

    ;; The stream closed under the binding while the procedure waits on a wait
    ;; of its own: the &client-closed is spent there, and the WebSocket has
    ;; still ended.
    (let* ((n (make-notes))
           (t #f)
           (sh (connect (holding (accepting (lambda (ws)
                                              (guard (e ((client-closed? e) (note! n 'client-closed)))
                                                (await (lambda (resume) #f)))
                                              (guard (e ((websocket-closed? e) (note! n (closed e))))
                                                (websocket-receive ws))
                                              (guard (e ((websocket-closed? e) (note! n (closed e))))
                                                (websocket-send! ws "late"))))
                                 (lambda (x) (set! t x)))
                        handshake)))
      (transport-abort! t)
      (fake-shell-settle! sh)
      (test-equal "a stream closed under the binding while the procedure waits on a wait of its own: the &client-closed is spent there, and a receive and a send after it raise &websocket-closed, 1006, not wait"
        '(client-closed (closed 1006 "" #f) (closed 1006 "" #f)) (seen n)))

    ;; A handler's own deadline ends its receive: the wait lets go, so a
    ;; later receive waits as before (decision 0005: one receive at a time).
    (let* ((n (make-notes))
           (sh (connect (accepting (lambda (ws)
                                     (guard (e ((deadline-passed? e) (note! n 'timed-out)))
                                       (with-deadline 1000 (lambda () (websocket-receive ws))))
                                     (note! n (websocket-receive ws))))
                        handshake)))
      (fake-shell-advance! sh 1000)
      (fake-shell-fire-waits! sh)
      (fake-shell-deliver! sh (list 'bytes-arrived rfc-masked-hello 0 (bytevector-length rfc-masked-hello)))
      (fake-shell-settle! sh)
      (test-equal "a receive a handler's own deadline ends lets go of its wait: a later receive waits as before and gets the next message"
        '(timed-out "Hello") (seen n)))

    ;; --- what a read costs the binding (M4.3's review) ---

    ;; A read the core answers with nothing but its clock: one byte of a
    ;; header whose 64-bit length is still to come.  Through the binding, and
    ;; through a taker that only re-arms its deadline at a read, as the core's
    ;; clock has the binding do; the fake's own work is the same for both.
    (let* ((rearming (lambda (r)
                       (switch-protocols (list (cons (b "Upgrade") (b "websocket")))
                         (lambda (t retained)
                           (let ((passed (lambda () #f)))
                             (transport-read-start! t (lambda (bv start end) (transport-deadline! t 20000 passed))
                                                    (lambda (why) #f)))
                           (awaiting (lambda () (await (lambda (resume) #f))))))))
           (base (connect rearming handshake))
           (ws-sh (connect (accepting (receiving-all (make-notes))) handshake))
           (one (list 'bytes-arrived (make-bytevector 1 0) 0 1)))
      (fake-shell-deliver! ws-sh (list 'bytes-arrived (bv '(#x82 #xFF)) 0 2))
      (test-equal "a read the core answers with only its clock allocates nothing in the binding: no more than a taker that only re-arms its deadline"
        0 (- (allocated (lambda () (fake-shell-deliver! ws-sh one)))
             (allocated (lambda () (fake-shell-deliver! base one))))))

    ;; A write's done the core answers with nothing: through the binding,
    ;; and through a taker whose done does nothing; the fake's own work is
    ;; the same for both.  Each has three writes the client has not read.
    (let* ((go-base #f)
           (writing (lambda (r)
                      (switch-protocols (list (cons (b "Upgrade") (b "websocket")))
                        (lambda (t retained)
                          (awaiting (lambda ()
                                      (await (lambda (resume) (set! go-base resume)))
                                      (do ((i 0 (+ i 1))) ((= i 3)) (transport-write! t rfc-hello 0 7 (lambda (why) #f)))
                                      (await (lambda (resume) #f))))))))
           (told (until-told (lambda (ws)
                               (do ((i 0 (+ i 1))) ((= i 3)) (websocket-send! ws "Hello"))
                               (websocket-receive ws))))
           (base (connect writing handshake))
           (ws-sh (connect (accepting (car told)) handshake)))
      (go-base #t)
      (fake-shell-schedule! base)
      ((cadr told))
      (fake-shell-schedule! ws-sh)
      (test-equal "a write's done the core answers with nothing allocates nothing in the binding: no more than a taker whose done does nothing"
        0 (- (allocated (lambda () (fake-shell-deliver-later! ws-sh)))
             (allocated (lambda () (fake-shell-deliver-later! base))))))

    ;; A write's done while the client is behind, which the core answers by
    ;; re-arming the write timeout: through the binding, and through a taker
    ;; whose done re-arms its deadline.  The client pings four times and
    ;; reads nothing: four pongs of 2 bytes, 8 past the high water of 7, so
    ;; each of the first three dones leaves more than the low water, 0.
    (let* ((go-base #f)
           (rearming (lambda (r)
                       (switch-protocols (list (cons (b "Upgrade") (b "websocket")))
                         (lambda (t retained)
                           (let ((passed (lambda () #f)) (pong (bv '(#x8A #x00))))
                             (awaiting (lambda ()
                                         (await (lambda (resume) (set! go-base resume)))
                                         (do ((i 0 (+ i 1))) ((= i 4))
                                           (transport-write! t pong 0 2 (lambda (why) (transport-deadline! t 60000 passed))))
                                         (await (lambda (resume) #f)))))))))
           (base (connect rearming handshake))
           (ws-sh (connect (accepting (receiving-all (make-notes)) (make-handshake-settings '())
                                      (limits '((write-high-water . 7) (write-low-water . 0))))
                           handshake))
           (pinged (unread! ws-sh (concat (vector->list (make-vector 4 (client-frame #x89 nothing)))))))
      (go-base #t)
      (fake-shell-schedule! base)
      (test-equal "a write's done the core answers by re-arming the write timeout allocates nothing in the binding: no more than a taker whose done re-arms its deadline"
        (list 24 #f 0)
        (list pinged (fake-shell-reading? ws-sh)
              (- (allocated (lambda () (fake-shell-deliver-later! ws-sh)))
                 (allocated (lambda () (fake-shell-deliver-later! base)))))))

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

    (let* ((raised (list "hi there" #f (make-oops) '("a b")
                         (condition (make-error) (make-message-condition "line one\nline two"))))
           (run (logged (lambda ()
                          (for-each (lambda (x) (connect (accepting (lambda (ws) (raise x))) handshake))
                                    raised)))))
      (test-equal "a procedure's raise is logged as the server's own log-line writes the detail: a string, #f, a record, a list, and a condition over two lines"
        (apply string-append (map (lambda (x) (server-logged 'websocket-handler-failed (list x))) raised))
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
                     (tick! sh 19999)
                     (fake-shell-settle! sh)
                     (let ((quiet (after-101 sh)))
                       (tick! sh 1)
                       (fake-shell-settle! sh)
                       (let ((pinged (after-101 sh)))
                         (tick! sh 19999)
                         (fake-shell-settle! sh)
                         (let ((waiting (after-101 sh)))
                           (tick! sh 1)
                           (fake-shell-settle! sh)
                           (list armed quiet pinged waiting (after-101 sh))))))))))
      (test-equal "a client silent after the 101 is pinged at 20 s, not before, and failed with 1011 20 s later, not before, logged"
        (list (list 25000 (list 101 nothing) (list 101 ping) (list 101 ping)
                    (list 101 (concat (list ping (server-close 1011 "")))))
              (server-logged 'websocket-failed '(1011 ping-timeout)))
        run))

    (let* ((run (logged
                 (lambda ()
                   (let* ((sh (connect (accepting (receiving-all (make-notes)) (make-handshake-settings '())
                                                  (limits '((ping-interval-ms . 30000) (ping-timeout-ms . 5000))))
                                       handshake))
                          (armed (fake-shell-armed sh)))
                     (tick! sh 30000)
                     (let ((pong (fake-shell-armed sh)))
                       (tick! sh 5000)
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

    ;; The child runs on the Chez that runs the suites: CHEZ names it, as the
    ;; Makefile's CHEZ does, and make hands its recipes a CHEZ set in the
    ;; environment or on its command line (CI's is `scheme`); unset, it is
    ;; `chez`, the Makefile's default.
    (test-equal "the limits are read from the environment as a program that imports the facade starts, and websocket-accept takes them in both its forms: a ping interval of 4 s armed twice, and a malformed one stopping the program before its first line"
      '(8 255)
      (map (lambda (value)
             (system (string-append "CHEZ_WS_PING_INTERVAL=" value
                                    " \"${CHEZ:-chez}\" --program tests/start-with-environment.sps >/dev/null 2>&1")))
           '("4" "x")))))
