#!r6rs
;;; The examples: each program in examples/, read as `make run` reads it, its
;;; handler played on the server's fake shell as a client plays it.
;;;
;;; The oracles:
;;; - RFC 6455: §1.3's handshake and its Sec-WebSocket-Accept; §5.7's frames,
;;;   a masked Hello and its unmasked form; §5.5.1, a close answered with a
;;;   close that echoes its code; §7.1.5, a connection that ends with no close
;;;   is closed.
;;; - What each example is for:
;;;   echo.sps answers / with a page whose script opens a WebSocket to /echo
;;;   on the page's own host, which /echo lets in, and sends each message back;
;;;   chat.sps tells a newcomer how many are in the room, itself counted, and
;;;   sends each message to everyone else in it;
;;;   clock.sps sends "tick 1", "tick 2", ... a second apart, a client's
;;;   messages between ticks moving none, and closes with 1000 "stopped" when
;;;   the client says "stop".
;;;
;;; A program is read with Chez's reader: its import form made an environment,
;;; its other forms run there with `serve` bound to a procedure that keeps the
;;; handler it is handed.  Each connection is a fake of its own, its clock at
;;; 5,000 ms, and a program's connections share its one handler, as the
;;; server's do.
(import (rnrs) (rnrs eval) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (http-server limits) default-limits)
        (websocket) (ws-play))

;; --- a program, its handler kept ----------------------------------------------

;; read-forms : String -> (Listof Datum) — the file's forms, as Chez reads them.
(define (read-forms path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
    (lambda (port)
      (let loop ((out '()))
        (let ((d (get-datum port)))
          (if (eof-object? d) (reverse out) (loop (cons d out))))))))

;; definition? : Datum -> Boolean
(define (definition? form)
  (and (pair? form) (memq (car form) '(define define-record-type define-syntax)) #t))

;; body : (Listof Datum) -> (Listof Datum)
;; A top-level program's body, definitions and expressions in any order
;; (R6RS §8.1), as a lambda's: each expression a definition of its own, run
;; in its place.
(define (body forms)
  (let loop ((fs forms) (i 0) (out '()))
    (cond ((null? fs) (reverse (cons #f out)))
          ((definition? (car fs)) (loop (cdr fs) i (cons (car fs) out)))
          (else (loop (cdr fs) (+ i 1)
                      (cons `(define ,(string->symbol (string-append "%form-" (number->string i)))
                               (begin ,(car fs) #f))
                            out))))))

;; program-handler : String -> (Request -> Answer)
;; The handler the program at `path` hands `serve`, from a run of its own.  A
;; program that does not run, or hands `serve` no procedure, gives a handler
;; that raises, so the server answers its every request 500.
(define (program-handler path)
  (guard (e (#t (lambda (request) (raise e))))
    (let ((forms (read-forms path))
          (kept #f))
      ((eval `(lambda (serve) ,@(body (cdr forms))) (apply environment (cdar forms)))
       (lambda (handler . _) (set! kept handler)))
      (if (procedure? kept) kept (lambda (request) (raise (list 'no-handler path)))))))

;; --- a client ------------------------------------------------------------------

;; RFC 6455 §1.3's opening handshake, to the path given, with any more fields
;; given, each a line.
(define (handshake path . fields)
  (b (apply string-append
            "GET " path " HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            (append (map (lambda (f) (string-append f "\r\n")) fields) '("\r\n")))))

;; get : String -> Bytevector — a plain GET of the path.
(define (get path) (b (string-append "GET " path " HTTP/1.1\r\nHost: server.example.com\r\n\r\n")))

(define rfc-accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

;; said : String -> Bytevector — the client's text frame, masked.
(define (said s) (client-frame #x81 (b s)))
;; text : String -> Bytevector — the server's text frame.
(define (text s) (server-frame #x81 (b s)))
(define client-close (client-frame #x88 (close-body 1000 "")))
;; server-close : Nat String -> Bytevector — the server's close frame.
(define (server-close code reason) (server-frame #x88 (close-body code reason)))

;; connect : (Request -> Answer) Bytevector -> FakeShell
;; A fake connection, its clock at 5,000 ms, read `input` and settled.
(define (connect handler input)
  (let ((sh (make-fake-connection default-limits handler #f 5000)))
    (fake-shell-feed-input! sh input 4096)
    (fake-shell-settle! sh)
    sh))

;; send! : FakeShell Bytevector -> Void — the client's bytes, read and settled.
(define (send! sh bytes)
  (fake-shell-feed-input! sh bytes 4096)
  (fake-shell-settle! sh))

;; wait! : FakeShell Nat -> Void
;; The clock moved on ms, the waits then due fired, and the connection settled.
(define (wait! sh ms)
  (fake-shell-advance! sh ms)
  (fake-shell-fire-waits! sh)
  (fake-shell-settle! sh))

;; --- what the client read ------------------------------------------------------

;; read-head : FakeShell -> (List (U Nat Datum) (Listof (Pair String String)) Bytevector)
;; The head's status, as the server's (response-reader) reads that head
;; alone, its fields, and every byte after it.
(define (read-head sh)
  (let* ((all (bv-concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head '() all))
            ((equal? (bv-slice all i (+ i 4)) blank)
             (let ((r (read-response (bv-slice all 0 (+ i 4)) #f #f)))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (list-ref r 2)
                     (bv-slice all (+ i 4) n))))
            (else (scan (+ i 1)))))))

;; field : (Listof (Pair String String)) String -> (U String #f)
(define (field fields name)
  (let ((f (find (lambda (f) (string-ci=? (car f) name)) fields)))
    (and f (cdr f))))

;; status : FakeShell -> Nat — the status of the answer, read whole.
(define (status sh) (car (read-response (bv-concat (fake-shell-writes sh)) #f #f)))

;; after-head : FakeShell -> (List (U Nat Datum) Bytevector)
;; The status, and what the client read after the head.
(define (after-head sh) (let ((h (read-head sh))) (list (car h) (caddr h))))

;; contains? : String String -> Boolean — whether `part` is a substring of `s`.
(define (contains? s part)
  (let ((n (string-length s)) (k (string-length part)))
    (let scan ((i 0))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring s i (+ i k)) part) #t)
            (else (scan (+ i 1)))))))

(run-suite "examples"
  (lambda ()
    ;; --- echo.sps ---

    (let ((echo (program-handler "examples/echo.sps")))
      (test-equal "echo.sps answers / 200 with an HTML page whose script opens a WebSocket to /echo on the page's own host"
        '(200 complete "text/html; charset=utf-8" #t #t)
        (let* ((r (read-response (bv-concat (fake-shell-writes (connect echo (get "/")))) #f #f))
               (page (list-ref r 3)))
          (list (car r) (list-ref r 4) (field (list-ref r 2) "Content-Type")
                (contains? page "location.host") (contains? page "/echo"))))

      (test-equal "echo.sps takes RFC 6455's handshake to /echo with §1.3's accept, sends a masked Hello back as §5.7's frame, and answers the client's close 1000 with 1000"
        (list 101 rfc-accept (bv-concat (list rfc-hello (server-close 1000 ""))))
        (let ((sh (connect echo (bv-concat (list (handshake "/echo") rfc-masked-hello)))))
          (send! sh client-close)
          (let ((h (read-head sh))) (list (car h) (field (cadr h) "Sec-WebSocket-Accept") (caddr h)))))

      (test-equal "echo.sps lets /echo take a browser's page from its own host, and refuses one from another site 403"
        '(101 403)
        (list (status (connect echo (handshake "/echo" "Origin: http://server.example.com")))
              (status (connect echo (handshake "/echo" "Origin: https://elsewhere.example")))))

      (test-equal "echo.sps answers any other path 404"
        404 (status (connect echo (get "/other")))))

    ;; --- chat.sps ---

    ;; Alice, Bob and Carol join, in turn, and Alice says Hello.
    (let* ((chat (program-handler "examples/chat.sps"))
           (alice (connect chat (handshake "/chat")))
           (bob (connect chat (handshake "/chat")))
           (carol (connect chat (handshake "/chat"))))
      (send! alice rfc-masked-hello)
      (for-each fake-shell-settle! (list bob carol))
      (test-equal "chat.sps tells each newcomer how many are in the room, itself counted, and sends a message to everyone else in it, not back to its sender"
        (list (list 101 (text "here: 1"))
              (list 101 (bv-concat (list (text "here: 2") rfc-hello)))
              (list 101 (bv-concat (list (text "here: 3") rfc-hello))))
        (map after-head (list alice bob carol))))

    ;; Alice and Bob join, Bob leaves, then Dan joins and Alice says Hello.
    (let* ((chat (program-handler "examples/chat.sps"))
           (alice (connect chat (handshake "/chat")))
           (bob (connect chat (handshake "/chat"))))
      (send! bob client-close)
      (let ((dan (connect chat (handshake "/chat"))))
        (send! alice rfc-masked-hello)
        (fake-shell-settle! dan)
        (test-equal "chat.sps takes a client that leaves out of the room: the next newcomer counts two, and only it hears the next message"
          (list (list 101 (text "here: 1"))
                (list 101 (bv-concat (list (text "here: 2") (server-close 1000 ""))))
                (list 101 (bv-concat (list (text "here: 2") rfc-hello))))
          (map after-head (list alice bob dan)))))

    ;; Carol, Bob and Alice join, in turn.  Bob's client goes, its WebSocket
    ;; closed while Bob's procedure has yet to run to leave the room (its
    ;; scheduler held), and Alice says Hello then: her send to Bob raises
    ;; Bob's &websocket-closed.
    (let* ((chat (program-handler "examples/chat.sps"))
           (carol (connect chat (handshake "/chat")))
           (bob (connect chat (handshake "/chat")))
           (alice (connect chat (handshake "/chat"))))
      (fake-shell-hold! bob #t)
      (fake-shell-deliver! bob '(eof))
      (send! alice rfc-masked-hello)
      (fake-shell-settle! carol)
      (test-equal "chat.sps sends past a client whose WebSocket has closed before it left the room: the sender goes on, and the rest of the room hears it"
        (list (list 101 (text "here: 3"))
              (list 101 (bv-concat (list (text "here: 1") rfc-hello))))
        (map after-head (list alice carol))))

    ;; --- clock.sps ---

    ;; A client connects to /clock and listens, a second and a half.
    (let* ((clock (program-handler "examples/clock.sps"))
           (sh (connect clock (handshake "/clock"))))
      (wait! sh 999)
      (let ((before (after-head sh)))
        (wait! sh 1)
        (let ((first (after-head sh)))
          (wait! sh 1000)
          (test-equal "clock.sps sends nothing for a second, then tick 1, then tick 2 a second after it"
            (list (list 101 (bv '())) (list 101 (text "tick 1")) (list 101 (bv-concat (list (text "tick 1") (text "tick 2")))))
            (list before first (after-head sh))))))

    ;; Half a second in, the client says hi; half a second later, tick 1.
    (let* ((clock (program-handler "examples/clock.sps"))
           (sh (connect clock (handshake "/clock"))))
      (wait! sh 500)
      (send! sh (said "hi"))
      (wait! sh 500)
      (test-equal "clock.sps keeps its second while the client talks: a message half a second in moves tick 1 none"
        (list 101 (text "tick 1")) (after-head sh)))

    ;; After tick 1 the client says stop, then waits two seconds more.
    (let* ((clock (program-handler "examples/clock.sps"))
           (sh (connect clock (handshake "/clock"))))
      (wait! sh 1000)
      (send! sh (said "stop"))
      (wait! sh 2000)
      (test-equal "clock.sps closes with 1000 \"stopped\" when the client says stop, and ticks no more"
        (list 101 (bv-concat (list (text "tick 1") (server-close 1000 "stopped"))))
        (after-head sh)))))
