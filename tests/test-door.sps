#!r6rs
;;; The door this library builds on, through the pin.
;;;
;;; chez-http-server's facade loads from the one library path, the pins it
;;; carries under it, and the verbs the binding calls behave as the server
;;; documents them ((http-server transport), (http-server private waits)): a
;;; transport made of procedures hands each its verb's arguments in one
;;; shape, the abort to its eighth, and `await` refuses where no coroutine
;;; may park, before it calls `register`.  The binding's driver suite holds
;;; the rest, on the server's fake shell.
;;;
;;; And what websocket-accept answers, (websocket handshake)'s answer made
;;; the server's own, is what the server writes: a 101 its switch-fault
;;; passes against the request's fields, a refusal its response-fault
;;; passes, each answer made on the server's fake shell for a request sent
;;; there.  Those are the rules the server applies to what a handler
;;; answers, in (http-server serializer), a library its facade does not
;;; export, so this suite is where they are named: the handshake's own suite
;;; needs no server.
(import (rnrs) (srfi :64) (ws-testing) (http-server) (fake-shell)
        (only (http-server limits) default-limits)
        (only (http-server serializer) switch-fault response-fault)
        (only (http-server switch) switch-headers)
        (only (http-server response) response-headers)
        (websocket))

;; The example request of RFC 6455 §1.3 and §4.1, its fields in order.
(define rfc-request
  '(("Host" . "server.example.com")
    ("Upgrade" . "websocket")
    ("Connection" . "Upgrade")
    ("Sec-WebSocket-Key" . "dGhlIHNhbXBsZSBub25jZQ==")
    ("Origin" . "http://example.com")
    ("Sec-WebSocket-Protocol" . "chat, superchat")
    ("Sec-WebSocket-Version" . "13")))

;; with : Fields String String -> Fields — `name`'s value replaced.
(define (with fields name value)
  (cons (cons name value) (remp (lambda (f) (string-ci=? (car f) name)) fields)))

;; accepted-with : Symbol Fields (Listof String) Origins (Answer -> Any) -> Any
;; What `then` makes of what websocket-accept answers a request of the
;; method and fields, to /chat, a field a line, sent on the server's fake
;; shell, with the settings of the subprotocols and origins; then runs inside
;; the handler.  not-answered when the handler never ran.
(define (accepted-with method fields subprotocols origins then)
  (let* ((found 'not-answered)
         (settings (make-handshake-settings subprotocols origins))
         (sh (make-fake-connection default-limits
               (lambda (request)
                 (let ((a (websocket-accept request (lambda (ws) #t) settings)))
                   (set! found (then a))
                   a))
               #f 0)))
    (fake-shell-feed-input! sh
      (string->utf8 (apply string-append (symbol->string method) " /chat HTTP/1.1\r\n"
                           (append (map (lambda (f) (string-append (car f) ": " (cdr f) "\r\n")) fields)
                                   '("\r\n"))))
      4096)
    (fake-shell-settle! sh)
    found))

;; fault-of : Symbol Fields (Listof String) Origins -> (U #f Symbol)
;; What the server's checks find in what websocket-accept answers, as
;; accepted-with sends the request: a response's response-fault, or else a
;; switch's switch-fault against the request's fields; #f when they find
;; nothing, and not-answered when the handler never ran.
(define (fault-of method fields subprotocols origins)
  (let ((offered (map (lambda (f) (cons (string->utf8 (car f)) (string->utf8 (cdr f)))) fields)))
    (accepted-with method fields subprotocols origins
      (lambda (a) (if (response? a) (response-fault a) (switch-fault a offered))))))

;; fields-of : Answer -> (Listof (Pair Bytevector Bytevector))
;; A 101's or a refusal's fields, as the server holds them.
(define (fields-of a)
  (if (response? a) (response-headers a) (switch-headers a)))

;; noting-transport : (Any -> Any) -> Transport
;; A transport whose eight procedures hand `note` what they were called
;; with.  Its read-start delivers two bytes and then the end at once.
(define (noting-transport note)
  (make-transport
    (lambda (bv start end written) (note (list 'write (bytevector-length bv) start end written)))
    (lambda (on-bytes on-end) (on-bytes (u8-list->bytevector '(9 8)) 0 2) (on-end 'eof))
    (lambda () (note '(read-stop)))
    (lambda () (note '(close)))
    (lambda (ms on-passed) (note (list 'deadline ms on-passed)))
    (lambda (thunk) (note (list 'on-drain)))
    (lambda (thunk) (note (list 'on-close)))
    (lambda () (note '(abort)))))

(run-suite "door"
  (lambda ()
    (let* ((seen '())
           (t (noting-transport (lambda (x) (set! seen (cons x seen))))))

      (transport-write! t (u8-list->bytevector '(1 2 3)))
      (test-equal "a write of a bytevector alone is all of it, with no procedure to tell"
        '(write 3 0 3 #f) (car seen))

      (transport-deadline! t #f)
      (test-equal "a deadline disarmed is handed #f twice"
        '(deadline #f #f) (car seen))

      (transport-abort! t)
      (test-equal "an abort is handed to the transport's eighth procedure"
        '(abort) (car seen))

      (let ((read '()))
        (transport-read-start! t
          (lambda (bv start end) (set! read (cons (list 'bytes (bytevector->u8-list bv) start end) read)))
          (lambda (why) (set! read (cons (list 'end why) read))))
        (test-equal "a read's bytes and then its end reach the taker's procedures"
          '((bytes (9 8) 0 2) (end eof)) (reverse read))))

    (let* ((registered 'not-called)
           (who (guard (e ((who-condition? e) (condition-who e)))
                  (await (lambda (resume) (set! registered 'called)))
                  'waited)))
      (test-equal "await on no coroutine is refused, naming await, before register runs"
        '(await not-called) (list who registered)))

    ;; A 101, then each refusal's kind: method, upgrade, connection, version,
    ;; key and origin; then a 101 naming a subprotocol.
    (test-equal "every answer websocket-accept makes of (websocket handshake)'s is one the server writes: a 101's fields pass its switch-fault against the request's, and a refusal's its response-fault"
      (map (lambda (x) 'ok) '(1 2 3 4 5 6 7 8 9 10))
      (map (lambda (method fields subprotocols origins)
             (or (fault-of method fields subprotocols origins) 'ok))
           '(GET GET GET POST GET GET GET GET GET GET)
           (list rfc-request rfc-request (with rfc-request "Upgrade" "WebSocket")
                 rfc-request (with rfc-request "Upgrade" "h2c") (with rfc-request "Connection" "close")
                 (with rfc-request "Sec-WebSocket-Version" "8") (with rfc-request "Sec-WebSocket-Key" "x")
                 rfc-request (with rfc-request "Sec-WebSocket-Protocol" "superchat"))
           '(("chat") () () () () () () () () ("superchat"))
           '(any any any any any any any any () any)))

    ;; Each answer's bytes are written over whole before the next is made.
    (test-equal "each answer websocket-accept makes has field bytes of its own: writing over one 101's and one refusal's leaves the next answer's as they were"
      '((("Upgrade" . "websocket") ("Sec-WebSocket-Accept" . "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
         ("Sec-WebSocket-Protocol" . "chat"))
        (("Sec-WebSocket-Version" . "13")))
      (let ((spoil! (lambda (a)
                      (for-each (lambda (f) (bytevector-fill! (car f) 0) (bytevector-fill! (cdr f) 0))
                                (fields-of a))))
            (strings (lambda (a)
                       (map (lambda (f) (cons (utf8->string (car f)) (utf8->string (cdr f)))) (fields-of a))))
            (version (with rfc-request "Sec-WebSocket-Version" "8")))
        (accepted-with 'GET rfc-request '("chat") 'any spoil!)
        (accepted-with 'GET version '() 'any spoil!)
        (list (accepted-with 'GET rfc-request '("chat") 'any strings)
              (accepted-with 'GET version '() 'any strings))))))
