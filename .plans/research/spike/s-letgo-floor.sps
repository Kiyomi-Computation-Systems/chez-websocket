#!r6rs
;;; S-LETGO's measure, and its floor: the heap after a big message less the
;;; heap after a 1-byte one, as the socket suite reads it, beside the heap
;;; after a 1-byte message less the heap after another.  Equal, the
;;; difference is the heap falling between the readings, not a message kept
;;; (decision 0007's amendment of 2026-10-11; the research record's section
;;; "S-LETGO's 2.9 KB, measured again").  A reading near -55 KB is a step
;;; where Chez gave the thread a fresh stack segment.
;;;
;;; Run from the repository's root, after `make build`, on the suites' path
;;; (`make -n test` prints it as CHEZSCHEMELIBDIRS), with none of the
;;; CHEZ_WS_ variables set:
;;;
;;;   CHEZSCHEMELIBDIRS=... BIG=4000 CONNS=1 chez --program .plans/research/spike/s-letgo-floor.sps
;;;
;;; BIG is the big message's size, CONNS how many connections send each one.
;;; It prints three of each difference, after two rounds' warm-up.
(import (rnrs) (ws-play)
        (only (chezscheme) collect collect-maximum-generation bytes-allocated getenv)
        (libuv) (uv-testing) (shell-testing)
        (http-server)
        (only (http-server limits) default-limits limits-with)
        (only (http-server private shell) make-shell shell-listen! wall-clock)
        (websocket))

(define (env-num name default)
  (let ((v (getenv name))) (if (and v (> (string-length v) 0)) (string->number v) default)))
(define size (env-num "BIG" 4000))
(define conns (env-num "CONNS" 1))
(define cap 4000)
(define (handshake path)
  (string->utf8 (string-append "GET " path " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                               "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")))

;; footprint : -> Nat — the heap after two full collections, as the socket
;; suite reads it.
(define (footprint)
  (collect (collect-maximum-generation))
  (collect (collect-maximum-generation))
  (bytes-allocated))

;; The socket suite's server: its drain 200 ms, its tick 10 ms, each
;; procedure receiving and dropping what it receives, counting.
(define loop (make-uv-loop))
(define taken 0)
(define sh (make-shell loop
                       (accepting (lambda (ws) (let take () (websocket-receive ws) (set! taken (+ taken 1)) (take)))
                                  (make-handshake-settings '()) default-websocket-limits)
                       (limits-with default-limits '((drain-timeout-ms . 200) (tick-ms . 10)))
                       wall-clock
                       (lambda (what details) #f)))
(define port (shell-listen! sh "127.0.0.1" 0))

;; run! : (-> Boolean) -> Void — turns until `pred` holds; stops at the cap.
(define (run! pred)
  (unless (eq? 'satisfied (run-shell-until loop sh pred cap))
    (display "stalled\n")
    (exit 3)))
(define (settle! n) (run-shell-until loop sh (lambda () #f) n))

(define big (client-frame #x82 (make-bytevector size 9)))
(define small (client-frame #x82 (make-bytevector 1 9)))
(define clients
  (let make ((i 0) (acc '()))
    (if (= i conns) acc (make (+ i 1) (cons (open-client loop port (handshake "/") #t) acc)))))
(run! (lambda () (for-all (lambda (cl) (> (bytevector-length (client-bytes cl)) 100)) clients)))

;; sent! : Bytevector -> Void — each client sends the frame; every one is
;; received, then five turns more, as S-LETGO's are.
(define (sent! frame)
  (let ((want (+ taken conns)))
    (for-each (lambda (cl) (client-send! cl frame)) clients)
    (run! (lambda () (= taken want)))
    (settle! 5)))

;; apart : Bytevector -> Integer — the heap after `first`, less the heap
;; after a 1-byte message sent next.
(define (apart first)
  (sent! first)
  (let ((after-first (footprint)))
    (sent! small)
    (- after-first (footprint))))

(apart big)
(apart big)
(display (list 'size size 'conns conns
               'big-then-small (list (apart big) (apart big) (apart big))
               'small-then-small (list (apart small) (apart small) (apart small))))
(newline)
(exit 0)
