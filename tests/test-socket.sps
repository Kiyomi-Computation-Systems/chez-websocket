#!r6rs
;;; The binding on a real socket (M4.3, step 3): the server's libuv shell
;;; listening on 127.0.0.1:0, its clients on the same loop, so one turn moves
;;; both ends, and every wait capped by an iteration count, as the server's
;;; own socket lane runs (its tests/shell-testing.sls).  Each check has a
;;; server of its own, closed with its clients and its loop drained before
;;; the next.
;;;
;;; What the fake shell cannot show is held here (the design's §8): the
;;; server logs a resume called once its wait has ended, `late-resume`, where
;;; the fake logs nothing; and a procedure that waits holds its coroutine's
;;; stack on the heap, which the fake's coroutines do not show.
;;;
;;; The checks:
;;;   - the handshake answered 101, a masked text echoed, and the client's
;;;     close answered, then the stream's end, with nothing logged;
;;;   - a client silent after the 101 pinged at the ping interval, then
;;;     failed with 1011 a ping timeout later, on the shell's own timer;
;;;   - the server's drain closing the stream under a receive whose client
;;;     answers nothing: the receive raises 1006, not clean, and no late
;;;     resume is logged, since the close call marks the procedure's wait
;;;     ended;
;;;   - a send that waits on a client reading nothing, then goes on once it
;;;     reads, and the client's close after: no late resume, since the woken
;;;     senders are let go;
;;;   - a read's bytevector let go after its step, held by the heap;
;;;   - a procedure waiting in a receive holding about what one waiting at a
;;;     bare `await` holds (decision 0005's amendment).
;;;
;;; The oracles:
;;; - RFC 6455, read from its raw text: §5.7's masked "Hello"; §5.5.1, a
;;;   close answered with a close echoing its code; §7.4.1's 1001, going
;;;   away, and 1011, an unexpected condition; §7.1.5, 1006 for a connection
;;;   closed with no close received; §7.1.4, clean once a close went each
;;;   way.
;;; - The server's waits (its waits.sls, R4): a resume called after its wait
;;;   has ended is logged `late-resume`, naming the verb, and wakes nothing.
;;;   Its drain (its M8.1): told to finish, it logs `draining`, then
;;;   `drain-timeout` and `stopped` once its time is up.
;;; - Decision 0001: a client quiet for the ping interval is pinged, and
;;;   failed with 1011 when no pong comes within the ping timeout.
;;; - Decision 0005's amendment, by form ("call/cc (Recommended)"): measured
;;;   with these clients, 100 connections of each, a receive's wait held
;;;   2,778 to 3,485 B (Darwin) and 4,237 to 4,277 B (Linux) a connection
;;;   more than a bare await's while it escaped by call/1cc, and 78 to 294 B
;;;   and 879 to 980 B by call/cc.  The bound, 2 KiB, lies between.
;;; - A read's bytevector: a client's 4,000-byte binary is one frame of
;;;   4,008 bytes, read at once on loopback; kept, it would hold at least
;;;   that.  Let go, the heap after it and after a 1-byte message measured 8
;;;   to 144 B apart.  The bound is half the frame.
(import (rnrs) (srfi :64) (ws-testing)
        (only (chezscheme) parameterize collect collect-maximum-generation bytes-allocated
              current-time time-second time-nanosecond)
        (rename (only (chezscheme) current-output-port) (current-output-port output-port-parameter))
        (libuv) (uv-testing) (shell-testing) (response-reader)
        (http-server)
        (only (http-server limits) default-limits limits-with)
        (only (http-server private shell) make-shell shell-listen! shell-shutdown! wall-clock)
        (websocket))

(define (b s) (string->utf8 s))

;; How many turns of the loop any one wait may take.
(define cap 200000)

;; --- frames ------------------------------------------------------------------

;; client-frame : Nat Bytevector -> Bytevector
;; A final frame of the opcode and payload, masked with RFC 6455 §5.7's key.
(define mask '#vu8(#x37 #xFA #x21 #x3D))
(define (client-frame op payload)
  (let* ((n (bytevector-length payload))
         (head (cond ((< n 126) (list (+ #x80 op) (+ #x80 n)))
                     ((< n 65536) (list (+ #x80 op) (+ #x80 126) (div n 256) (mod n 256)))
                     (else (assertion-violation 'client-frame "longer than the suite sends" n))))
         (h (length head))
         (out (make-bytevector (+ h 4 n))))
    (let put ((i 0) (l head))
      (unless (null? l) (bytevector-u8-set! out i (car l)) (put (+ i 1) (cdr l))))
    (bytevector-copy! mask 0 out h 4)
    (do ((i 0 (+ i 1))) ((= i n) out)
      (bytevector-u8-set! out (+ h 4 i)
                          (bitwise-xor (bytevector-u8-ref payload i) (bytevector-u8-ref mask (mod i 4)))))))

(define (close-payload code)
  (let ((bv (make-bytevector 2))) (bytevector-u16-set! bv 0 code (endianness big)) bv))

;; head-end : Bytevector -> (U Nat #f) — the index just past the first CRLFCRLF.
(define (head-end bv)
  (let ((n (bytevector-length bv)))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) #f)
            ((and (= (bytevector-u8-ref bv i) 13) (= (bytevector-u8-ref bv (+ i 1)) 10)
                  (= (bytevector-u8-ref bv (+ i 2)) 13) (= (bytevector-u8-ref bv (+ i 3)) 10))
             (+ i 4))
            (else (scan (+ i 1)))))))

;; status : Bytevector -> (U Nat Symbol)
;; The status of the head the client read first, as the server's
;; (response-reader) reads that head alone, or 'no-head.
(define (status bv)
  (let ((e (head-end bv)))
    (if e
        (let ((r (read-response (bytes-between bv 0 e) #f #f)))
          (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4))))
        'no-head)))

;; frames : Bytevector -> (Listof Datum)
;; The whole unmasked frames after the head, each as (text String), (binary
;; length), (ping String), (pong String) or (close code reason).
(define (frames bv)
  (let ((n (bytevector-length bv)) (e (head-end bv)))
    (let next ((i (or e n)) (acc '()))
      (if (> (+ i 2) n)
          (reverse acc)
          (let* ((op (bitwise-and (bytevector-u8-ref bv i) 15))
                 (l7 (bitwise-and (bytevector-u8-ref bv (+ i 1)) 127))
                 (hl (cond ((< l7 126) 2) ((= l7 126) 4) (else 10))))
            (if (> (+ i hl) n)
                (reverse acc)
                (let ((len (cond ((< l7 126) l7)
                                 ((= l7 126) (bytevector-u16-ref bv (+ i 2) (endianness big)))
                                 (else (bytevector-u64-ref bv (+ i 2) (endianness big))))))
                  (if (> (+ i hl len) n)
                      (reverse acc)
                      (let ((p (bytes-between bv (+ i hl) (+ i hl len))))
                        (next (+ i hl len)
                              (cons (case op
                                      ((1) (list 'text (utf8->string p)))
                                      ((2) (list 'binary len))
                                      ((9) (list 'ping (utf8->string p)))
                                      ((10) (list 'pong (utf8->string p)))
                                      ((8) (if (>= len 2)
                                               (list 'close (bytevector-u16-ref p 0 (endianness big))
                                                     (utf8->string (bytes-between p 2 len)))
                                               (list 'close)))
                                      (else (list 'opcode op)))
                                    acc)))))))))))

(define (handshake path)
  (b (string-append "GET " path " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")))

;; --- a server of the check's own ---------------------------------------------

;; A server: its loop, the libuv shell, the port it listens on, and what it
;; logged, newest first.
(define-record-type ws-server (fields loop (mutable shell) (mutable port) (mutable log)))

;; serving : (Request -> Answer) -> WsServer
;; A shell on a loop of its own, its drain 200 ms and its timer's tick 10
;; ms, listening on 127.0.0.1:0, its log kept.
(define (serving handler)
  (let* ((loop (make-uv-loop))
         (s (make-ws-server loop #f #f '())))
    (ws-server-shell-set! s (make-shell loop handler
                                        (limits-with default-limits '((drain-timeout-ms . 200) (tick-ms . 10)))
                                        wall-clock
                                        (lambda (what details) (ws-server-log-set! s (cons what (ws-server-log s))))))
    (ws-server-port-set! s (shell-listen! (ws-server-shell s) "127.0.0.1" 0))
    s))

;; logged-kinds : WsServer -> (Listof Symbol) — what it logged, in order.
(define (logged-kinds s) (reverse (ws-server-log s)))

;; run! : WsServer (-> Boolean) -> Symbol — turns until `pred` holds, at most cap.
(define (run! s pred) (run-shell-until (ws-server-loop s) (ws-server-shell s) pred cap))

;; settle! : WsServer Nat -> Void — n turns, whatever happens.
(define (settle! s n) (run-shell-until (ws-server-loop s) (ws-server-shell s) (lambda () #f) n))

;; connect! : WsServer String Boolean -> Client
(define (connect! s path read?) (open-client (ws-server-loop s) (ws-server-port s) (handshake path) read?))

;; finish! : WsServer (Listof Client) -> Void
;; The clients closed, the server shut down unless its drain has begun, and
;; its loop run until nothing but a timer is live on it.
(define (finish! s clients)
  (for-each client-close! clients)
  (unless (memq 'draining (logged-kinds s)) (shell-shutdown! (ws-server-shell s)))
  (run! s (lambda () (memq 'stopped (logged-kinds s))))
  (run-until-drained (ws-server-loop s) cap))

;; accepting : (WebSocket -> Any) WebsocketLimits -> (Request -> Answer)
;; A handler answering websocket-accept's switch, no subprotocols, these limits.
(define (accepting proc lim)
  (lambda (request) (websocket-accept request proc (make-handshake-settings '()) lim)))

;; limits : (Listof (Pair Symbol Nat)) -> WebsocketLimits — the defaults, these replaced.
(define (limits overrides) (websocket-limits-with default-websocket-limits overrides))

;; closed : Condition -> (List 'closed Nat String Boolean)
(define (closed e)
  (list 'closed (websocket-closed-code e) (websocket-closed-reason e) (websocket-closed-clean? e)))

;; captured : (-> Any) -> (List Any String)
;; What the thunk answers, and what the binding logged on the current output
;; port while it ran.
(define (captured thunk)
  (let-values (((port get) (open-string-output-port)))
    (let ((v (parameterize ((output-port-parameter port)) (thunk))))
      (list v (get)))))

;; footprint : -> Nat — the heap after two full collections.
(define (footprint)
  (collect (collect-maximum-generation))
  (collect (collect-maximum-generation))
  (bytes-allocated))

(define (now-ms)
  (let ((t (current-time 'time-monotonic)))
    (+ (* 1000 (time-second t)) (div (time-nanosecond t) 1000000))))

(run-suite "socket"
  (lambda ()
    ;; The suite's masked frame is §5.7's.
    (unless (equal? (client-frame 1 (b "Hello"))
                    '#vu8(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
      (provenance-failure "the suite's masked frame is not RFC 6455 §5.7's"))

    ;; --- a connection, end to end ---

    (let* ((s (serving (accepting (lambda (ws) (let echo () (websocket-send! ws (websocket-receive ws)) (echo)))
                                  default-websocket-limits)))
           (cl (connect! s "/" #t)))
      (run! s (lambda () (head-end (client-bytes cl))))
      (client-send! cl (client-frame 1 (b "Hello")))
      (run! s (lambda () (pair? (frames (client-bytes cl)))))
      (client-send! cl (client-frame 8 (close-payload 1000)))
      (run! s (lambda () (not (eq? (client-end cl) 'open))))
      (let ((seen (list (status (client-bytes cl)) (frames (client-bytes cl)) (client-end cl) (logged-kinds s))))
        (finish! s (list cl))
        (test-equal "on a real socket, the handshake is answered 101, a masked text echoed, and the client's close answered with a close echoing 1000, then the stream's end, with nothing logged"
          '(101 ((text "Hello") (close 1000 "")) eof ())
          seen)))

    (let* ((s (serving (accepting (lambda (ws) (websocket-receive ws))
                                  (limits '((ping-interval-ms . 200) (ping-timeout-ms . 200))))))
           (cl (connect! s "/" #t))
           (at-101 #f) (at-ping #f) (at-close #f)
           (run (captured
                 (lambda ()
                   (run! s (lambda ()
                             (let ((now (now-ms)) (fs (frames (client-bytes cl))))
                               (unless (or at-101 (not (head-end (client-bytes cl)))) (set! at-101 now))
                               (unless (or at-ping (null? fs)) (set! at-ping now))
                               (unless (or at-close (< (length fs) 2)) (set! at-close now))
                               (not (eq? (client-end cl) 'open)))))
                   (frames (client-bytes cl))))))
      (finish! s (list cl))
      (test-equal "a client silent after the 101 is pinged at the ping interval, 200 ms, and failed with 1011 a ping timeout later, 200 ms, on the shell's own timer, its failure logged"
        '(((ping "") (close 1011 "")) at-or-after-the-interval at-or-after-the-timeout "websocket-failed 1011 ping-timeout\n")
        (list (car run)
              (if (and at-101 at-ping (>= (- at-ping at-101) 190)) 'at-or-after-the-interval (list at-101 at-ping))
              (if (and at-ping at-close (>= (- at-close at-ping) 190)) 'at-or-after-the-timeout (list at-ping at-close))
              (cadr run))))

    ;; --- late resumes, which the fake logs nowhere ---

    (let* ((saw #f)
           (s (serving (accepting (lambda (ws)
                                    (guard (e ((websocket-closed? e) (set! saw (closed e)) (raise e)))
                                      (websocket-receive ws)))
                                  default-websocket-limits)))
           (cl (connect! s "/" #t)))
      (run! s (lambda () (head-end (client-bytes cl))))
      (settle! s 20)
      (shell-shutdown! (ws-server-shell s))
      (run! s (lambda () (and saw (memq 'stopped (logged-kinds s)))))
      (settle! s 20)
      (let ((seen (list saw (frames (client-bytes cl)) (logged-kinds s))))
        (finish! s (list cl))
        (test-equal "the server's drain closes the stream under a receive whose client answers nothing: the receive raises &websocket-closed 1006, not clean, the client has read the close 1001, going away, and the server logs its drain and no late resume"
          '((closed 1006 "" #f) ((close 1001 "going away")) (draining drain-timeout stopped))
          seen)))

    (let* ((sent #f) (saw #f)
           (s (serving (accepting (lambda (ws)
                                    (websocket-send! ws (make-bytevector (* 8 1024 1024) 7))
                                    (set! sent #t)
                                    (guard (e ((websocket-closed? e) (set! saw (closed e)) (raise e)))
                                      (websocket-receive ws)))
                                  default-websocket-limits)))
           (cl (connect! s "/" #f)))
      (settle! s 300)
      (let ((waited (if sent 'sent-at-once 'waited)))
        (client-read! cl)
        (run! s (lambda () (and sent (= 1 (length (frames (client-bytes cl)))))))
        (client-send! cl (client-frame 8 (close-payload 1000)))
        (run! s (lambda () (and saw (not (eq? (client-end cl) 'open)))))
        (settle! s 20)
        (let ((seen (list waited (frames (client-bytes cl)) saw (logged-kinds s))))
          (finish! s (list cl))
          (test-equal "a send of 8 MiB to a client that reads nothing waits, and goes on once the client reads; the client's close then ends the connection cleanly, and the server logs no late resume"
            '(waited ((binary 8388608) (close 1000 "")) (closed 1000 "" #t) ())
            seen))))

    ;; --- what a connection holds ---

    (let* ((taken 0)
           (s (serving (accepting (lambda (ws) (let take () (websocket-receive ws) (set! taken (+ taken 1)) (take)))
                                  default-websocket-limits)))
           (cl (connect! s "/" #t))
           (big (client-frame 2 (make-bytevector 4000 9)))
           (small (client-frame 2 (make-bytevector 1 9))))
      (define (sent! frame)
        (let ((want (+ taken 1)))
          (client-send! cl frame)
          (run! s (lambda () (= taken want)))
          (settle! s 5)))
      (define (apart)
        (sent! big)
        (let ((after-big (footprint)))
          (sent! small)
          (- after-big (footprint))))
      (run! s (lambda () (head-end (client-bytes cl))))
      (apart)
      (apart)
      (let ((measured (list (apart) (apart) (apart))))
        (finish! s (list cl))
        (test-equal "a read's bytevector is let go after its step: the heap after a 4,000-byte message, then after a 1-byte one, three times, differs by less than half its 4,008-byte frame"
          'let-go
          (if (for-all (lambda (d) (< d 2004)) measured) 'let-go measured))))

    (let* ((waiting 0) (n 100)
           (s (serving (lambda (request)
                         (websocket-accept request
                                           (if (string=? (request-path request) "/await")
                                               (lambda (ws) (set! waiting (+ waiting 1)) (await (lambda (resume) #f)))
                                               (lambda (ws) (set! waiting (+ waiting 1)) (websocket-receive ws)))
                                           (make-handshake-settings '())
                                           default-websocket-limits))))
           (clients '()))
      (define (opened! path)
        (let ((want (+ waiting n)))
          (do ((i 0 (+ i 1))) ((= i n)) (set! clients (cons (connect! s path #t) clients)))
          (run! s (lambda () (= waiting want)))
          (settle! s 20)))
      (opened! "/await")
      (let* ((none (footprint))
             (awaiting (begin (opened! "/await") (footprint)))
             (receiving (begin (opened! "/receive") (footprint)))
             (more (div (- (- receiving awaiting) (- awaiting none)) n)))
        (finish! s clients)
        (test-equal "a procedure waiting in websocket-receive holds less than 2 KiB a connection more than one waiting at a bare await: 100 of each, footprints back to back"
          'within
          (if (< more 2048) 'within more))))))
