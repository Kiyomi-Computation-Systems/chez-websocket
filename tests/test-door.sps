#!r6rs
;;; The door this library builds on, through the pin (M0's smoke).
;;;
;;; chez-http-server's facade loads from the one library path, the pins it
;;; carries under it, and the verbs the binding will call behave as its
;;; v0.4.0 documents them ((http-server transport), (http-server private
;;; waits)): a transport made of procedures hands each its verb's arguments
;;; in one shape, the abort to its eighth (decision 0024), and `await`
;;; refuses where no coroutine may park, before it calls `register`.  The
;;; binding's driver suite holds the rest, on the server's fake shell.
;;;
;;; And what (websocket handshake) answers is what the server writes: a 101
;;; its switch-fault passes against the request's fields, a refusal its
;;; response-fault passes.  Those are the rules the server applies to what a
;;; handler answers, in (http-server serializer), a library its facade does
;;; not export, so this suite is where they are named (M4.1's review: the
;;; handshake's own suite needs no server).
(import (rnrs) (srfi :64) (ws-testing) (http-server)
        (only (http-server serializer) switch-fault response-fault)
        (websocket handshake))

;; The example request of RFC 6455 §1.3 and §4.1, as request-header reads a
;; request's fields: the value of the first of a name, without regard to case.
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

;; reader : Fields -> (String -> (U String #f))
(define (reader fields)
  (lambda (name)
    (let ((f (find (lambda (f) (string-ci=? (car f) name)) fields)))
      (and f (cdr f)))))

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
    (test-equal "every answer of (websocket handshake) is one the server writes: a 101's fields pass its switch-fault against the request's, and a refusal's its response-fault"
      (map (lambda (x) 'ok) '(1 2 3 4 5 6 7 8 9 10))
      (map (lambda (method fields subprotocols origins)
             (let ((a (handshake-answer method (reader fields) "server.example.com"
                                        (make-handshake-settings subprotocols origins)))
                   (offered (map (lambda (f) (cons (string->utf8 (car f)) (string->utf8 (cdr f)))) fields)))
               (or (case (car a)
                     ((accept) (switch-fault (switch-protocols (cadr a) (lambda (t r) t)) offered))
                     ((refuse) (response-fault (make-response (cadr a) #f (caddr a) #f)))
                     (else (car a)))
                   'ok)))
           '(GET GET GET POST GET GET GET GET GET GET)
           (list rfc-request rfc-request (with rfc-request "Upgrade" "WebSocket")
                 rfc-request (with rfc-request "Upgrade" "h2c") (with rfc-request "Connection" "close")
                 (with rfc-request "Sec-WebSocket-Version" "8") (with rfc-request "Sec-WebSocket-Key" "x")
                 rfc-request (with rfc-request "Sec-WebSocket-Protocol" "superchat"))
           '(("chat") () () () () () () () () ("superchat"))
           '(any any any any any any any any () any)))))
