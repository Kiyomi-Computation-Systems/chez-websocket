#!r6rs
;;; The binding's test driver: the server's fake shell.
;;;
;;; The binding's waits need a coroutine, which only the server's shells
;;; run.  The server keeps a fake shell in its tests/, which is on this
;;; project's library path: the server's own core, parser and 101, the
;;; hand-off, coroutines, and a clock the test moves.  This suite holds,
;;; through the pin, that the fake drives a taker shaped as the binding is,
;;; as the binding needs and as the server documents its libuv shell doing:
;;;   - the bytes handed over with the take-over, its reads, read-stop and
;;;     read-start, its deadline on the fake clock, and the drain;
;;;   - a client that reads nothing: a close waits behind the write it has
;;;     not read, a deadline asked for meanwhile is armed, and an abort ends
;;;     the stream, the write dropped;
;;;   - the stream's close while the thunk waits, and a taker's raise;
;;;   - every line of a field;
;;;   - that the test code borrowed onto the suites' path shares no
;;;     library name with this project's;
;;;   - and the server's libuv shell as the socket suite drives it: through
;;;     its private (http-server private shell) and the server's
;;;     (shell-testing), a shell listening on 127.0.0.1:0, a client on its
;;;     loop, the shutdown that stops it, and the loop drained.
;;;
;;; How a test plays the client.  `fake-shell-feed-input!` delivers the
;;; client's bytes only while the taker reads, as libuv does, so a test of
;;; read-stop feeds its bytes that way.  `fake-shell-deliver!` hands the taker
;;; one event, a read already under way, at once while it reads; while it has
;;; stopped, the fake keeps the event until it reads again, as the server
;;; does.  A test uses it to place a read, or the client's end, between two
;;; turns.  What
;;; the client reads is read back as a client would, by the server's
;;; (response-reader), on chez-httparse's strict response parser.
(import (rnrs) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (chezscheme) directory-list file-directory? library-extensions)
        (only (http-server limits) default-limits limits-with)
        (only (http-server private shell) make-shell shell-listen! shell-shutdown! wall-clock)
        (only (libuv) make-uv-loop)
        (only (shell-testing) open-client client-bytes client-close! run-shell-until run-until-drained responses)
        (websocket handshake))

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

;; RFC 6455 §1.2's opening handshake, and §5.7's masked "Hello" from a client.
(define handshake
  (b (string-append "GET /chat HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\n"
                    "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                    "Sec-WebSocket-Version: 13\r\n\r\n")))
(define hello (u8-list->bytevector '(#x81 #x85 #x37 #xfa #x21 #x3d #x7f #x9f #x4d #x51 #x58)))
(define nothing (make-bytevector 0))

;; arrived : Bytevector -> Event — a read of all of bv, as the shell delivers it.
(define (arrived bv) (list 'bytes-arrived bv 0 (bytevector-length bv)))

;; client-reads : FakeShell -> (List (U Nat Datum) Bytevector)
;; What the client has read: the status of the head it read first, as the
;; server's (response-reader) reads that head alone, and every byte after
;; it.  A head the reader does not finish exactly at its end is answered
;; `(unread status)`, with the reader's last status.
(define (client-reads sh)
  (let* ((all (concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head all))
            ((equal? (copy all i (+ i 4)) blank)
             (let ((r (read-response (copy all 0 (+ i 4)) #f #f)))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (copy all (+ i 4) n))))
            (else (scan (+ i 1)))))))

;; library-names : String -> (Listof Datum)
;; The name each library under `dir` gives, at any depth, read with Chez's
;; own reader: a file whose name ends in an extension Chez looks for a
;; library under, and whose first datum is a library form.
(define (library-names dir)
  (apply append
    (map (lambda (name)
           (let ((path (string-append dir "/" name)))
             (cond ((char=? (string-ref name 0) #\.) '())
                   ((file-directory? path) (library-names path))
                   ((exists (lambda (x)
                              (let ((n (string-length name)) (k (string-length x)))
                                (and (> n k) (string=? (substring name (- n k) n) x))))
                            (map car (library-extensions)))
                    (let ((form (call-with-input-file path read)))
                      (if (and (pair? form) (eq? (car form) 'library) (pair? (cdr form)))
                          (list (cadr form))
                          '())))
                   (else '()))))
         (directory-list dir))))

;; The test code the suites borrow, last on their path (the Makefile's
;; TEST_ONLY_DIRS), and this project's own libraries.
(define borrowed
  '("vendor/chez-http-server/tests" "vendor/chez-http-server/vendor/chez-httparse/test/support/harness"
    "vendor/chez-http-server/vendor/chez-libuv/tests"))
(define ours '("src" "tests"))

;; A taker shaped as the binding is.  Its take-over keeps the bytes handed
;; over, registers its drain and close calls, reads into a queue, and
;; answers (awaiting thunk); the thunk takes the queue's pieces, parking on
;; `await` when it is empty.  `log` is what the taker saw, in order.
(define-record-type taker
  (fields (mutable pieces) (mutable resume) (mutable ended) (mutable log) (mutable transport))
  (protocol (lambda (new) (lambda () (new '() #f #f '() #f)))))

(define (note! t x) (taker-log-set! t (cons x (taker-log t))))
(define (log-of t) (reverse (taker-log t)))
(define (wake! t) (let ((r (taker-resume t))) (when r (taker-resume-set! t #f) (r #t))))

;; on-bytes, on-end : Taker -> the procedures its reads are handed to.
(define (on-bytes t)
  (lambda (bv from to)
    (taker-pieces-set! t (append (taker-pieces t) (list (copy bv from to))))
    (wake! t)))
(define (on-end t)
  (lambda (why) (taker-ended-set! t why) (wake! t)))

;; next-piece : Taker -> (U Bytevector Symbol) — a piece, or the end; parks.
(define (next-piece t)
  (cond ((pair? (taker-pieces t))
         (let ((p (car (taker-pieces t)))) (taker-pieces-set! t (cdr (taker-pieces t))) p))
        ((taker-ended t) => (lambda (why) why))
        (else (await (lambda (resume) (taker-resume-set! t resume))) (next-piece t))))

;; echo-closing : Taker (Transport -> Any) -> (-> Any)
;; A thunk that echoes each piece, its write's callback noted, and at the
;; client's end notes it and calls `at-end`; its wait's &client-closed is
;; noted on its way out.
(define (echo-closing t at-end)
  (lambda ()
    (guard (e ((client-closed? e) (note! t 'client-closed) (raise e)))
      (let loop ()
        (let ((p (next-piece t)))
          (cond ((bytevector? p)
                 (transport-write! (taker-transport t) p 0 (bytevector-length p)
                                   (lambda (why) (note! t (list 'wrote why))))
                 (loop))
                (else (note! t (list 'end p))
                      (at-end (taker-transport t)))))))))

;; echo : Taker -> (-> Any) — at the end, the stream's close.
(define (echo t) (echo-closing t transport-close!))

;; bounded : Taker -> (-> Any)
;; At the end, the stream's close, and then the close timeout's bound: a
;; deadline of 10,000 ms that aborts, as the binding closes a client that
;; does not read.
(define (bounded t)
  (echo-closing t (lambda (tr)
                    (transport-close! tr)
                    (transport-deadline! tr 10000 (lambda () (note! t 'passed) (transport-abort! tr))))))

;; write-then-raise : Taker -> (-> Any) — writes "Hello", then raises.
(define (write-then-raise t)
  (lambda ()
    (transport-write! (taker-transport t) hello 0 (bytevector-length hello)
                      (lambda (why) (note! t (list 'wrote why))))
    (raise 'failed)))

(define (none transport) #f)

;; handler : Taker (Transport -> Any) (Taker -> (-> Any)) -> (Request -> Answer)
;; (websocket handshake)'s answer from the request.  Accepted, the
;; take-over as above, `extra` run with the transport before it answers.
(define (handler t extra thunk-of)
  (lambda (request)
    (let ((a (handshake-answer (request-method request)
                               (lambda (name) (request-header request name))
                               (request-host request)
                               (make-handshake-settings '() 'any))))
      (if (eq? (car a) 'accept)
          (switch-protocols
           (cadr a)
           (lambda (transport retained)
             (taker-transport-set! t transport)
             (when (> (bytevector-length retained) 0) (taker-pieces-set! t (list retained)))
             (transport-on-drain! transport (lambda () (note! t 'drain)))
             (transport-on-close! transport (lambda () (note! t 'closed)))
             (transport-read-start! transport (on-bytes t) (on-end t))
             (extra transport)
             (awaiting (thunk-of t))))
          (make-response (cadr a) #f (caddr a) #f)))))

;; connect : Taker (Transport -> Any) (Taker -> (-> Any)) Bytevector -> FakeShell
;; A fake connection, its clock at 5,000 ms, read `input` and settled: every
;; write the client is to read so far read.
(define (connect t extra thunk-of input)
  (let ((sh (make-fake-connection default-limits (handler t extra thunk-of) #f 5000)))
    (fake-shell-feed-input! sh input 4096)
    (fake-shell-settle! sh)
    sh))

(run-suite "driver"
  (lambda ()
    (let* ((t (make-taker))
           (sh (connect t none echo (concat (list handshake hello)))))
      (test-equal "a frame sent with the handshake is handed to the take-over, and the client reads its echo after the 101"
        (list 101 hello) (client-reads sh)))

    (let* ((t (make-taker))
           (sh (connect t none echo handshake))
           (parked (if (taker-resume t) 'parked 'not-parked)))
      (fake-shell-deliver! sh (arrived hello))
      (fake-shell-settle! sh)
      (let ((read (client-reads sh)))
        (test-equal "a read's bytes resume the thunk parked on await, and the client reads its echo"
          (list 'parked 101 hello) (cons parked read))))

    (let* ((t (make-taker))
           (sh (connect t none echo handshake)))
      (transport-read-stop! (taker-transport t))
      (let ((stopped (fake-shell-feed-input! sh hello 4096)))
        (transport-read-start! (taker-transport t) (on-bytes t) (on-end t))
        (let ((started (fake-shell-feed-input! sh hello 4096)))
          (fake-shell-settle! sh)
          (let ((read (client-reads sh)))
            (test-equal "a stopped read takes no delivery, and a read started again takes the next"
              (list 0 (bytevector-length hello) 101 hello) (cons* stopped started read))))))

    ;; The binding stops reading from inside its read, once its queue is
    ;; full: three frames sent one a read, and the taker stops after the
    ;; second.
    (let* ((t (make-taker))
           (sh (connect t none echo handshake))
           (reads 0))
      (transport-read-start! (taker-transport t)
        (lambda (bv from to)
          (set! reads (+ reads 1))
          ((on-bytes t) bv from to)
          (when (= reads 2) (transport-read-stop! (taker-transport t))))
        (on-end t))
      (let ((delivered (fake-shell-feed-input! sh (concat (list hello hello hello)) (bytevector-length hello))))
        (fake-shell-settle! sh)
        (let ((read (client-reads sh)))
          (test-equal "a read stopped from inside the taker's read takes no later delivery: of three frames sent one a read, two are taken and echoed"
            (list (* 2 (bytevector-length hello)) 101 (concat (list hello hello)))
            (cons delivered read)))))

    (let* ((t (make-taker))
           (sh (connect t (lambda (tr) (transport-deadline! tr 20000 (lambda () (note! t 'passed))))
                        echo handshake))
           (armed (fake-shell-armed sh)))
      (fake-shell-advance! sh 19999)
      (fake-shell-fire! sh)
      (let ((before (log-of t)))
        (fake-shell-advance! sh 1)
        (fake-shell-fire! sh)
        (let ((after (log-of t)))
          (test-equal "the taker's deadline is armed at the fake clock's now plus its time, and passes then and not a millisecond before"
            '(25000 () (passed)) (list armed before after)))))

    (let* ((t (make-taker))
           (sh (connect t none echo handshake)))
      (fake-shell-drain! sh)
      (fake-shell-drain! sh)
      (test-equal "the server's drain runs the taker's drain call, once"
        '(drain) (log-of t)))

    ;; A client that sends "Hello" and ends, and reads nothing until the
    ;; test delivers the later turns: the echo is outstanding when the
    ;; thunk asks for the close.  A deadline armed before the close, as the
    ;; binding's ping is, shows whether the close has begun: a close begun
    ;; disarms it, as the libuv shell's does.
    (let* ((t (make-taker))
           (sh (connect t (lambda (tr) (transport-deadline! tr 60000 (lambda () (note! t 'passed))))
                        echo handshake)))
      (fake-shell-deliver! sh (arrived hello))
      (fake-shell-deliver! sh '(eof))
      (let ((before (list (log-of t) (fake-shell-armed sh))))
        (fake-shell-settle! sh)
        (let* ((after (list (log-of t) (fake-shell-armed sh)))
               (read (client-reads sh)))
          (test-equal "a close asked for behind a write the client has not read waits: the deadline armed before it stays armed, and once the client reads the write the stream closes, the deadline disarmed"
            (list (list '((end eof)) 65000) (list '((end eof) (wrote #f) closed) #f) (list 101 hello))
            (list before after read)))))

    (let* ((t (make-taker))
           (sh (connect t none bounded handshake)))
      (fake-shell-deliver! sh (arrived hello))
      (fake-shell-deliver! sh '(eof))
      (let ((armed (fake-shell-armed sh)))
        (test-equal "a deadline asked for while that close waits is armed"
          15000 armed)
        (fake-shell-advance! sh 10000)
        (fake-shell-fire! sh)
        (fake-shell-settle! sh)
        (let* ((log (log-of t))
               (read (client-reads sh)))
          (test-equal "an abort at that deadline ends the stream: the write is told ECANCELED, the client reads none of it, and the close call comes"
            (list '((end eof) passed (wrote ECANCELED) closed) (list 101 nothing))
            (list log read)))))

    (let* ((t (make-taker))
           (sh (connect t none echo handshake)))
      (transport-close! (taker-transport t))
      (fake-shell-deliver! sh '(eof))
      (fake-shell-settle! sh)
      (let* ((log (log-of t))
             (failures (fake-shell-taker-failures sh)))
        (test-equal "the stream closed while the thunk waits, the client then ending: its wait raises &client-closed, which is no taker failure"
          '((closed client-closed) ()) (list log failures))))

    (let* ((t (make-taker))
           (sh (connect t (lambda (tr) (transport-deadline! tr 100 (lambda () (raise 'bound))))
                        echo handshake)))
      (fake-shell-advance! sh 100)
      (let ((escaped (guard (e (#t (list 'escaped e))) (fake-shell-fire! sh) 'kept)))
        (fake-shell-settle! sh)
        (let* ((failures (fake-shell-taker-failures sh))
               (log (log-of t)))
          (test-equal "a raise in the deadline's call is the taker's failure: recorded, and the stream closed, with nothing escaping to the test"
            '(kept (bound) (closed client-closed)) (list escaped failures log)))))

    (let* ((t (make-taker))
           (sh (connect t none write-then-raise handshake)))
      (let* ((failures (fake-shell-taker-failures sh))
             (log (log-of t))
             (read (client-reads sh)))
        (test-equal "a waiting thunk's raise is the taker's failure, and ends the stream at once: its write told ECANCELED, and never read"
          (list '(failed) '((wrote ECANCELED) closed) (list 101 nothing))
          (list failures log read))))

    ;; A field over two lines (RFC 9110 §5.3): the server's parse keeps each.
    (let* ((seen 'not-called)
           (sh (make-fake-connection default-limits
                 (lambda (r)
                   (set! seen (list (request-header-values r "connection")
                                    (request-header r "Connection")
                                    (request-header-values r "Sec-WebSocket-Protocol")
                                    (request-header-values r "Origin")))
                   (make-response 400 #f '() #f)))))
      (fake-shell-feed-input! sh
        (b (string-append "GET /chat HTTP/1.1\r\nHost: server.example.com\r\n"
                          "Connection: keep-alive\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
                          "Sec-WebSocket-Protocol: chat\r\nSec-WebSocket-Protocol: superchat\r\n\r\n"))
        4096)
      (fake-shell-settle! sh)
      (test-equal "request-header-values reads every line of a field, in order, through the server's parse, and request-header the first"
        '(("keep-alive" "Upgrade") "keep-alive" ("chat" "superchat") ()) seen))

    ;; Chez takes a library from the first directory on the path that holds
    ;; its name, so a borrowed library named as one of ours would be ours to
    ;; whatever imports it.
    (let* ((theirs (apply append (map library-names borrowed)))
           (mine (apply append (map library-names ours))))
      (test-equal "no library of the test code borrowed onto the suites' path has the name of one of this project's, the fake shell, the response reader, the shell's clients and chez-libuv's test loop among them"
        '(ours fake-shell response-reader shell-testing uv-testing ())
        (list (if (member '(websocket handshake) mine) 'ours 'none-of-ours)
              (if (member '(fake-shell) theirs) 'fake-shell 'no-fake-shell)
              (if (member '(response-reader) theirs) 'response-reader 'no-response-reader)
              (if (member '(shell-testing) theirs) 'shell-testing 'no-shell-testing)
              (if (member '(uv-testing) theirs) 'uv-testing 'no-uv-testing)
              (filter (lambda (name) (member name mine)) theirs))))

    ;; The socket suite drives the server's libuv shell as the server's own
    ;; socket lane does: what it needs of the server's code, held through
    ;; the pin, as the fake's is above.
    (let* ((loop (make-uv-loop))
           (logged '())
           (sh (make-shell loop (lambda (request) (make-response 200 #f '() (b "ok")))
                           (limits-with default-limits '((drain-timeout-ms . 200) (tick-ms . 10)))
                           wall-clock
                           (lambda (what details) (set! logged (cons what logged)))))
           (port (shell-listen! sh "127.0.0.1" 0))
           (cl (open-client loop port (b "GET / HTTP/1.1\r\nHost: x\r\n\r\n") #t))
           (answered (run-shell-until loop sh (lambda () (pair? (responses (client-bytes cl)))) 4000))
           (status (let ((r (responses (client-bytes cl)))) (if (pair? r) (car (car r)) 'none))))
      (client-close! cl)
      (shell-shutdown! sh)
      (let* ((stopped (run-shell-until loop sh (lambda () (memq 'stopped logged)) 4000))
             (drained (run-until-drained loop 4000)))
        (test-equal "the server's libuv shell, as the socket suite drives it: listening on 127.0.0.1:0, a client on its loop answered 200, the shutdown that stops it, and its loop drained, each wait within its turns"
          '(#t satisfied 200 satisfied satisfied)
          (list (and (fixnum? port) (> port 0)) answered status stopped drained))))))
