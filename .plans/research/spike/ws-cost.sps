#!r6rs
;;; What an idle connection costs the server: the server's own method (its
;;; .plans/research/spike/m7-exit-budget.sps).  A python child,
;;; ws-hold.py beside this file, holds the connections; the heap is read
;;; after two full collections once every connection is held and every
;;; procedure waits in websocket-receive; a connection's cost is (heap with
;;; 500 - heap with 100) / 400.  Kinds: a WebSocket idle after the 101; one
;;; idle after 10 echoes; and, for scale, the server's own connection idle
;;; after a GET.  Measured for v0.1.0 (M6; the research record's section
;;; "For v0.1.0, on the server's v0.5.0").
;;;
;;; Run from the repository's root, after `make build`, on the suites' path
;;; (`make -n test` prints it as CHEZSCHEMELIBDIRS), with none of the
;;; CHEZ_WS_ variables set, python3 on PATH, and room for 1,000 sockets:
;;;
;;;   ulimit -n 4096
;;;   CHEZSCHEMELIBDIRS=... chez --program .plans/research/spike/ws-cost.sps \
;;;     .plans/research/spike/ws-hold.py 5
;;;
;;; The last argument is how many holds of each kind.  A hold that did not
;;; end cleanly prints a line beginning "!".
(import (rnrs)
        (only (chezscheme) printf collect collect-maximum-generation bytes-allocated scheme-version)
        (libuv) (uv-testing) (shell-testing)
        (http-server) (websocket)
        (only (http-server private shell) shell-connections)
        (only (http-server private serve) start-server))

(define hold (cadr (command-line)))
(define rounds (string->number (caddr (command-line))))
(define cap 1000000)

(define (heap)
  (collect (collect-maximum-generation))
  (collect (collect-maximum-generation))
  (bytes-allocated))

;; How many procedures wait in websocket-receive.
(define waiting 0)

(define (echo ws)
  (guard (e ((websocket-closed? e) #t))
    (let loop ()
      (set! waiting (+ waiting 1))
      (let ((m (websocket-receive ws)))
        (set! waiting (- waiting 1))
        (websocket-send! ws m)
        (loop)))))

(define (handler request)
  (if (string=? (request-path request) "/ws")
      (websocket-accept request echo)
      (make-response 200 #f '() (string->utf8 "ok"))))

(define loop (make-uv-loop))
(define logged '())
(define sh (start-server loop handler
                         (lambda (name) (and (string=? name "CHEZ_HTTP_PORT") "0"))
                         (lambda (what details) (set! logged (cons (cons what details) logged)))))
(define port (caddr (assq 'listening logged)))

;; held : String Nat Nat -> Nat — the heap while the child holds n of `mode`.
(define (held mode n r)
  (set! waiting 0)
  (let* ((in (make-uv-pipe loop)) (out (make-uv-pipe loop)) (said (make-byte-collector)) (exit #f)
         (child (uv-spawn! loop "python3"
                           (list "python3" hold mode (number->string port) (number->string n) (number->string r))
                           (list (cons 'stdio (list (list 'pipe in 'to-child) (list 'pipe out 'from-child)
                                                    '(inherit-fd . 2))))
                           (lambda (status signal) (set! exit (list status signal))))))
    (uv-read-start! out (lambda (bv start end) (collect-span! said bv start end)) (lambda () #f) (lambda (e) #f))
    (let ((ready (run-shell-until loop sh
                                  (lambda ()
                                    (and (equal? (collector-bytes said) (string->utf8 "ready\n"))
                                         (= (length (shell-connections sh)) n)
                                         (or (string=? mode "http") (= waiting n))))
                                  cap)))
      (let ((h (heap)))
        (uv-close! in)
        (let ((gone (run-shell-until loop sh (lambda () (and exit (null? (shell-connections sh)))) cap)))
          (uv-close! child)
          (uv-close! out)
          (run-until-drained loop 1000)
          (unless (and (eq? ready 'satisfied) (eq? gone 'satisfied) (equal? exit '(0 #f)))
            (printf "  ! ~a ~a: ready ~a, gone ~a, exit ~a\n" mode n ready gone exit))
          h)))))

(printf "~a, libuv ~a\n" (scheme-version) (uv-version))
(for-each
 (lambda (kind)
   (let ((mode (car kind)) (r (cadr kind)) (name (caddr kind)))
     (do ((i 0 (+ i 1))) ((= i rounds))
       (let* ((a100 (held mode 100 r)) (a500 (held mode 500 r)))
         (printf "~a, hold ~a: ~a B\n" name (+ i 1) (inexact (/ (- a500 a100) 400)))))))
 '(("ws" 0 "a WebSocket in websocket-receive, after the 101")
   ("ws" 10 "the same, after 10 echoes")
   ("http" 0 "the server's own connection, idle after a GET")))
