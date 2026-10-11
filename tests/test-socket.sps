#!r6rs
;;; The binding on a real socket (M4.3, step 3): the server's libuv shell
;;; listening on 127.0.0.1:0, its clients on the same loop, so one turn moves
;;; both ends, and every wait capped by an iteration count, as the server's
;;; own socket lane runs (its tests/shell-testing.sls).  Each check has a
;;; server of its own, closed with its clients and its loop drained before
;;; the next.  A wait that reaches the cap ends its check's waiting: the
;;; check's later waits are not waited for, so a check that cannot finish
;;; costs one cap, and is red by its value.
;;;
;;; What the fake shell cannot show is held here (the design's §8): the
;;; server logs a resume called once its wait has ended, `late-resume`, where
;;; the fake logs nothing.
;;;
;;; The checks:
;;;   - the handshake answered 101, a masked text echoed, and the client's
;;;     close answered, then the stream's end, with nothing logged;
;;;   - a client silent after the 101 pinged once the ping interval has
;;;     passed and before it passes twice over, and failed with 1011 within
;;;     the ping timeout's own window, both timed by the loop's clock from
;;;     the take-over to what the server writes;
;;;   - the server's drain closing the stream under a receive that is seen to
;;;     wait, its client answering nothing: the receive raises 1006, not
;;;     clean, and no late resume is logged, since the close call marks the
;;;     procedure's wait ended;
;;;   - a send seen to wait on a client reading nothing, then going on once it
;;;     reads, and the client's close after: no late resume, since the woken
;;;     senders are let go;
;;;   - a read's bytevector let go after its step, held by the heap.
;;;
;;; Not checked here: what a procedure waiting in a receive holds over one at
;;; a bare `await`.  The suite held it until the server's v0.4.1, whose full
;;; park leaves no change to the binding's wait that reddens it: its way back
;;; by call/1cc adds about 150 B, and a guard about 486 B (measured at v0.4.0).
;;; A message kept is S-LETGO's to catch, and the server's own suite holds
;;; what its park keeps (decision 0005's amendment of 2026-10-09).
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
;;;   `drain-timeout` and `stopped` once its time is up.  Its deadlines are met
;;;   at the first time its timer fires at or after them, never before, by the
;;;   loop's clock, `uv_now`, brought up to date as one is armed (its
;;;   shell.sls).  So timed by that clock from the take-over, read and not
;;;   brought up to date, the ping comes at the interval or later, and the
;;;   close at the timeout or later after the ping, to the millisecond.  The
;;;   suite's own clock would not do: on Linux the loop's is
;;;   CLOCK_MONOTONIC_COARSE wherever that ticks every millisecond, and its
;;;   lag behind Chez's, CLOCK_MONOTONIC, varies, so a ping on time measured
;;;   98 ms on CI (the research record of 2026-10-10).
;;; - Decision 0001: a client quiet for the ping interval is pinged, and
;;;   failed with 1011 when no pong comes within the ping timeout.  Here the
;;;   interval is 100 ms and the timeout 300 ms, so either taken for the other
;;;   falls outside its window.
;;; - A read's bytevector: a client's 16,000-byte binary is one frame of
;;;   16,008 bytes, which one read of the server's 16,384-byte buffer takes
;;;   whole; kept, it held 16,088 to 18,968 B.  Should a frame come in pieces,
;;;   a kept read would hold only the last, the oracle has gone, and the suite
;;;   says so (status 3), as it did at 40,000 bytes.  Let go, the heap after
;;;   it and after a 1-byte message measured 88 to 112 B apart on the server's
;;;   v0.4.0, and 2,872 to 2,952 B on its v0.4.1, about as after a 4,000-,
;;;   40,000- or 400,000-byte message (decision 0007).  Two 1-byte messages
;;;   measure as far apart, 2,888 to 2,944 B on its v0.5.0, whose drain is
;;;   v0.4.1's: the heap falls between the readings, as the full drain uses
;;;   up the thread's stack, and nothing is kept (0007's amendment of
;;;   2026-10-11).  The bound is half the frame.
;;; - The cap, 4,000 turns: over ten times the most a wait here took, 366
;;;   turns on Darwin and 205 on Linux.  A turn with nothing to do takes about
;;;   1.2 ms on Darwin, so a check that cannot finish costs about 5 s.
(import (rnrs) (srfi :64) (ws-testing) (ws-play)
        (only (chezscheme) collect collect-maximum-generation bytes-allocated)
        (libuv) (uv-testing) (shell-testing) (response-reader)
        (http-server)
        (only (http-server limits) default-limits limits-with)
        (only (http-server private shell) make-shell shell-listen! shell-shutdown! wall-clock)
        (websocket))

;; How many turns of the loop any one wait may take.
(define cap 4000)

;; --- what the client reads -----------------------------------------------------

;; head-end : Bytevector -> (U Nat #f) — the index just past the first CRLFCRLF.
(define (head-end bv)
  (let ((n (bytevector-length bv)))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) #f)
            ((and (= (bytevector-u8-ref bv i) 13) (= (bytevector-u8-ref bv (+ i 1)) 10)
                  (= (bytevector-u8-ref bv (+ i 2)) 13) (= (bytevector-u8-ref bv (+ i 3)) 10))
             (+ i 4))
            (else (scan (+ i 1)))))))

;; status : Bytevector -> (U Nat Datum)
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
;; length), (ping String), (pong String) or (close code reason).  A binary's
;; payload is not copied.
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
                      (next (+ i hl len)
                            (cons (if (= op 2)
                                      (list 'binary len)
                                      (let ((p (bytes-between bv (+ i hl) (+ i hl len))))
                                        (case op
                                          ((1) (list 'text (utf8->string p)))
                                          ((9) (list 'ping (utf8->string p)))
                                          ((10) (list 'pong (utf8->string p)))
                                          ((8) (if (>= len 2)
                                                   (list 'close (bytevector-u16-ref p 0 (endianness big))
                                                         (utf8->string (bytes-between p 2 len)))
                                                   (list 'close)))
                                          (else (list 'opcode op)))))
                                  acc))))))))))

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

;; Whether a wait of the check under way has reached the cap.
(define stalled #f)

;; run! : WsServer (-> Boolean) -> Symbol
;; Turns until `pred` holds, at most cap: 'satisfied or
;; 'iterations-exhausted; or 'skipped, with no turn, once a wait of the
;; check has reached the cap.
(define (run! s pred)
  (if stalled
      'skipped
      (let ((outcome (run-shell-until (ws-server-loop s) (ws-server-shell s) pred cap)))
        (when (eq? outcome 'iterations-exhausted) (set! stalled #t))
        outcome)))

;; settle! : WsServer Nat -> Void — n turns, whatever happens.
(define (settle! s n) (run-shell-until (ws-server-loop s) (ws-server-shell s) (lambda () #f) n))

;; connect! : WsServer String Boolean -> Client
(define (connect! s path read?) (open-client (ws-server-loop s) (ws-server-port s) (handshake path) read?))

;; finish! : WsServer (Listof Client) -> Void
;; The clients closed, the server shut down unless its drain has begun, and,
;; unless a wait has reached the cap, its loop run until nothing but a timer
;; is live on it; then the next check waits afresh.
(define (finish! s clients)
  (for-each client-close! clients)
  (unless (memq 'draining (logged-kinds s)) (shell-shutdown! (ws-server-shell s)))
  (run! s (lambda () (memq 'stopped (logged-kinds s))))
  (unless stalled (run-until-drained (ws-server-loop s) cap))
  (set! stalled #f))

;; No subprotocols, and the request's own host as the one origin.
(define no-subprotocols (make-handshake-settings '()))

;; timing : Transport (Byte -> Any) -> Transport
;; A transport over t that tells `note` each write's first byte as the
;; write is asked for, and passes every call on.
(define (timing t note)
  (make-transport
   (lambda (bytes start end written)
     (note (bytevector-u8-ref bytes start))
     (transport-write! t bytes start end written))
   (lambda (on-bytes on-end) (transport-read-start! t on-bytes on-end))
   (lambda () (transport-read-stop! t))
   (lambda () (transport-close! t))
   (lambda (ms passed) (if ms (transport-deadline! t ms passed) (transport-deadline! t #f)))
   (lambda (thunk) (transport-on-drain! t thunk))
   (lambda (thunk) (transport-on-close! t thunk))
   (lambda () (transport-abort! t))))

;; reading : Transport (Nat -> Any) -> Transport
;; A transport over t that tells `note` each read's length as it arrives,
;; and passes every call on.
(define (reading t note)
  (make-transport
   (lambda (bytes start end written) (transport-write! t bytes start end written))
   (lambda (on-bytes on-end)
     (transport-read-start! t (lambda (bv start end) (note (- end start)) (on-bytes bv start end)) on-end))
   (lambda () (transport-read-stop! t))
   (lambda () (transport-close! t))
   (lambda (ms passed) (if ms (transport-deadline! t ms passed) (transport-deadline! t #f)))
   (lambda (thunk) (transport-on-drain! t thunk))
   (lambda (thunk) (transport-on-close! t thunk))
   (lambda () (transport-abort! t))))

;; footprint : -> Nat — the heap after two full collections.
(define (footprint)
  (collect (collect-maximum-generation))
  (collect (collect-maximum-generation))
  (bytes-allocated))

(run-suite "socket"
  (lambda ()
    ;; The suite's masked frame is §5.7's.
    (unless (equal? (client-frame #x81 (b "Hello")) rfc-masked-hello)
      (provenance-failure "the suite's masked frame is not RFC 6455 §5.7's"))

    ;; --- a connection, end to end ---

    (let* ((s (serving (accepting (lambda (ws) (let echo () (websocket-send! ws (websocket-receive ws)) (echo)))
                                  no-subprotocols default-websocket-limits)))
           (cl (connect! s "/" #t)))
      (run! s (lambda () (head-end (client-bytes cl))))
      (client-send! cl (client-frame #x81 (b "Hello")))
      (run! s (lambda () (pair? (frames (client-bytes cl)))))
      (client-send! cl (client-frame #x88 (close-body 1000 "")))
      (run! s (lambda () (not (eq? (client-end cl) 'open))))
      (let ((seen (list (status (client-bytes cl)) (frames (client-bytes cl)) (client-end cl) (logged-kinds s))))
        (finish! s (list cl))
        (test-equal "on a real socket, the handshake is answered 101, a masked text echoed, and the client's close answered with a close echoing 1000, then the stream's end, with nothing logged"
          '(101 ((text "Hello") (close 1000 "")) eof ())
          seen)))

    ;; --- the clock, on the shell's own timer ---

    ;; Each time is the loop's, as the server last brought it up to date.
    (letrec* ((taken-over #f) (writes '())
              (now (lambda () (uv-now (ws-server-loop s))))
              (s (serving (wrapping (accepting (lambda (ws) (websocket-receive ws))
                                               no-subprotocols
                                               (limits '((ping-interval-ms . 100) (ping-timeout-ms . 300))))
                                    (lambda (t)
                                      (set! taken-over (now))
                                      (timing t (lambda (first) (set! writes (cons (cons first (now)) writes))))))))
              (cl (connect! s "/" #t))
              (run (logged (lambda ()
                             (run! s (lambda () (not (eq? (client-end cl) 'open))))
                             (frames (client-bytes cl)))))
              (written (lambda (first)
                         (let ((w (assv first writes))) (and w taken-over (- (cdr w) taken-over))))))
      (finish! s (list cl))
      (test-equal "a client silent after the 101 is pinged once the ping interval, 100 ms, has passed and before 250 ms, and failed with 1011 from 300 ms, its timeout, to 450 ms after the ping, each timed by the loop's clock from the take-over to what the server writes, its failure logged"
        '(((ping "") (close 1011 "")) within-the-interval within-the-timeout "websocket-failed 1011 ping-timeout\n")
        (let ((ping (written #x89)) (close (written #x88)))
          (list (car run)
                (if (and ping (<= 100 ping) (< ping 250)) 'within-the-interval ping)
                (if (and ping close (<= 300 (- close ping)) (< (- close ping) 450))
                    'within-the-timeout
                    (list ping close))
                (cadr run)))))

    ;; --- late resumes, which the fake logs nowhere ---

    (let* ((receiving #f) (saw #f)
           (s (serving (accepting (lambda (ws)
                                    (set! receiving #t)
                                    (guard (e ((websocket-closed? e) (set! saw (closed e)) (raise e)))
                                      (websocket-receive ws)))
                                  no-subprotocols default-websocket-limits)))
           (cl (connect! s "/" #t)))
      (run! s (lambda () receiving))
      (let ((waiting (if (and receiving (not saw) (null? (frames (client-bytes cl)))) 'waiting 'not-waiting)))
        (shell-shutdown! (ws-server-shell s))
        (run! s (lambda () (and saw (memq 'stopped (logged-kinds s)))))
        (settle! s 20)
        (let ((seen (list waiting saw (frames (client-bytes cl)) (logged-kinds s))))
          (finish! s (list cl))
          (test-equal "the server's drain closes the stream under a receive seen to wait, whose client answers nothing: the receive raises &websocket-closed 1006, not clean, the client has read the close 1001, going away, and the server logs its drain and no late resume"
            '(waiting (closed 1006 "" #f) ((close 1001 "going away")) (draining drain-timeout stopped))
            seen))))

    (let* ((sending #f) (sent #f) (saw #f) (size (* 8 1024 1024))
           (s (serving (accepting (lambda (ws)
                                    (set! sending #t)
                                    (websocket-send! ws (make-bytevector size 7))
                                    (set! sent #t)
                                    (guard (e ((websocket-closed? e) (set! saw (closed e)) (raise e)))
                                      (websocket-receive ws)))
                                  no-subprotocols default-websocket-limits)))
           (cl (connect! s "/" #f)))
      ;; Once the procedure has begun its send, the drain it ran in ends with
      ;; the send returned, or parked.
      (run! s (lambda () sending))
      (let ((waited (cond ((not sending) 'not-run) (sent 'sent-at-once) (else 'waited))))
        (client-read! cl)
        (run! s (lambda () (and sent
                                (>= (collector-count (client-collector cl)) size)
                                (= 1 (length (frames (client-bytes cl)))))))
        (client-send! cl (client-frame #x88 (close-body 1000 "")))
        (run! s (lambda () (and saw (not (eq? (client-end cl) 'open)))))
        (settle! s 20)
        (let ((seen (list waited (frames (client-bytes cl)) saw (logged-kinds s))))
          (finish! s (list cl))
          (test-equal "a send of 8 MiB to a client that reads nothing waits, and goes on once the client reads; the client's close then ends the connection cleanly, and the server logs no late resume"
            '(waited ((binary 8388608) (close 1000 "")) (closed 1000 "" #t) ())
            seen))))

    ;; --- what a connection holds ---

    (let* ((taken 0) (whole 0)
           (big (client-frame #x82 (make-bytevector 16000 9)))
           (small (client-frame #x82 (make-bytevector 1 9)))
           (s (serving (wrapping (accepting (lambda (ws) (let take () (websocket-receive ws) (set! taken (+ taken 1)) (take)))
                                            no-subprotocols default-websocket-limits)
                                 (lambda (t)
                                   (reading t (lambda (n) (when (>= n (bytevector-length big)) (set! whole (+ whole 1)))))))))
           (cl (connect! s "/" #t)))
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
      (let* ((measured (list (apart) (apart) (apart))) (all-taken taken))
        (finish! s (list cl))
        (unless (= whole 5)
          (provenance-failure
           (string-append "a 16,008-byte frame came in pieces: " (number->string whole) " of 5 read whole")))
        (test-equal "a read's bytevector is let go after its step: the heap after a 16,000-byte message, then after a 1-byte one, three times, differs by less than half its 16,008-byte frame, each message received"
          '(let-go 10)
          (list (if (for-all (lambda (d) (< d 8004)) measured) 'let-go measured) all-taken))))))

