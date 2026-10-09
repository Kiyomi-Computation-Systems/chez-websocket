#!r6rs
;;; (websocket limits): the defaults, and their reading from an environment's
;;; strings (M3.1).
;;;
;;; The oracles are the design's §7 table (each variable, its default and its
;;; unit), decision 0001 (the 1 MiB cap, and the ping clock's 20 s and 20 s),
;;; and its amendment of 2026-10-05, decided by form: reading also stops at 16
;;; queued messages, which CHEZ_WS_MAX_QUEUE overrides.  The conventions are
;;; the server's (its (http-server limits)): durations are given in whole
;;; seconds and kept in milliseconds; sizes and counts are given and kept in
;;; their own unit; a variable absent or empty is its default; and a write low
;;; water above the high water is refused, whichever was set.  The bounds
;;; are each field's least sensible value: a cap or a queue of at least one,
;;; since reading stops once the queue holds a cap's worth, so a cap of 0
;;; would stop it for good; a pong timeout of at least a second, since one of
;;; 0 would pass as its ping went; a write timeout of at least a second,
;;; since one of 0 would pass as reading stopped; a close timeout of at
;;; least a second, since every close the binding asks for is aborted once
;;; it passes, so one of 0 would abort a close before the client could read
;;; it (decision 0006, and its amendment at step 2's review, by form: "From
;;; queueing, as peers do"); and 0 for the rest, an interval of 0 turning
;;; pinging off (0001).  Decision 0006, by form ("60 s, its own variable"):
;;; CHEZ_WS_WRITE_TIMEOUT, 60 s, the server's own CHEZ_HTTP_WRITE_TIMEOUT.  A
;;; value is a whole number, written in ASCII digits alone.
;;;
;;; - The defaults, field by field, and the variables, in field order.
;;; - Each variable moves its own field alone; absent or empty is the default.
;;; - Each bound, accepted at its edge and refused below it; the water marks.
;;; - Malformed values refused, naming their variable: a sign, a radix
;;;   prefix, an exponent, a fraction, a space, a word, a digit outside ASCII.
;;; - Each value a fixnum at most: the server's transport arms a deadline
;;;   only for a fixnum of ms, and the step counts in fixnums.
;;; - make-websocket-limits and websocket-limits-with check what they make,
;;;   naming the field.
(import (rnrs) (srfi :64) (ws-testing) (websocket limits))

;; env : (Pair String String) ... -> (String -> (U String #f))
;; An environment holding just these variables.
(define (env . pairs)
  (lambda (name) (let ((p (assoc name pairs))) (and p (cdr p)))))

;; Each field: its name, its accessor, its variable, and its default, from the
;; design's §7 table, 0001's amendment and 0006, in make-websocket-limits'
;; order.
(define named-fields
  (list (list 'max-message-bytes websocket-limits-max-message-bytes "CHEZ_WS_MAX_MESSAGE_BYTES" 1048576)
        (list 'max-queue websocket-limits-max-queue "CHEZ_WS_MAX_QUEUE" 16)
        (list 'ping-interval-ms websocket-limits-ping-interval-ms "CHEZ_WS_PING_INTERVAL" 20000)
        (list 'ping-timeout-ms websocket-limits-ping-timeout-ms "CHEZ_WS_PING_TIMEOUT" 20000)
        (list 'close-timeout-ms websocket-limits-close-timeout-ms "CHEZ_WS_CLOSE_TIMEOUT" 10000)
        (list 'write-high-water websocket-limits-write-high-water "CHEZ_WS_WRITE_HIGH_WATER" 262144)
        (list 'write-low-water websocket-limits-write-low-water "CHEZ_WS_WRITE_LOW_WATER" 65536)
        (list 'write-timeout-ms websocket-limits-write-timeout-ms "CHEZ_WS_WRITE_TIMEOUT" 60000)))

(define field-name car)
(define (field-accessor f) (cadr f))
(define (field-variable f) (caddr f))
(define (field-default f) (cadddr f))

(define defaults (map field-default named-fields))

;; values-of : Limits -> (Listof Nat)
;; Every field of the limits, in order.
(define (values-of L)
  (map (lambda (f) ((field-accessor f) L)) named-fields))

;; read-env : (String -> (U String #f)) -> (U (Listof Nat) (List 'refused Symbol Any))
;; The fields read from the environment, or what its refusal named: the
;; procedure, and the first irritant.
(define (read-env lookup)
  (refusal (lambda () (values-of (websocket-limits-from-environment lookup)))))

;; refusal : (-> Any) -> Any
;; The thunk's answer, or, if it raised an assertion violation,
;; (refused who first-irritant).
(define (refusal thunk)
  (guard (e ((assertion-violation? e)
             (list 'refused
                   (and (who-condition? e) (condition-who e))
                   (and (irritants-condition? e)
                        (pair? (condition-irritants e))
                        (car (condition-irritants e))))))
    (thunk)))

;; with-field : Nat Any -> (Listof Any)
;; The defaults with field i's replaced by v.
(define (with-field i v)
  (let loop ((k 0) (ds defaults))
    (if (null? ds) '() (cons (if (= k i) v (car ds)) (loop (+ k 1) (cdr ds))))))

;; index-of : String -> Nat
;; The index of the field a variable sets.
(define (index-of variable)
  (let loop ((k 0) (fs named-fields))
    (if (string=? (field-variable (car fs)) variable) k (loop (+ k 1) (cdr fs)))))

;; set-one : String String -> (U (Listof Nat) (List 'refused Symbol Any))
;; The fields read from an environment holding one variable.
(define (set-one variable value)
  (read-env (env (cons variable value))))

;; Malformed values: a sign, a radix prefix, an exponent, a fraction, a
;; decimal point, a space before and after, a word, an exactness prefix, and
;; ARABIC-INDIC DIGIT THREE (U+0663), which char-numeric? takes for a digit.
(define malformed
  (list "-1" "+5" "#x10" "1e3" "10/2" "1.5" " 5" "5 " "five" "#e5"
        (string (integer->char #x0663))))

(run-suite "limits"
  (lambda ()
    ;; --- the defaults (design §7, 0001 and its amendment) ---
    (test-equal "the defaults: a 1 MiB cap, 16 messages queued, a ping after 20 s and its pong within 20 s, 10 s for a close, the water marks at 256 KiB and 64 KiB, and 60 s for a write"
                defaults (values-of default-websocket-limits))
    (test-equal "the variables, in the fields' order"
                (map field-variable named-fields) websocket-limits-environment-variables)

    ;; --- each variable alone (design §7) ---
    (test-equal "an empty environment, and every variable empty, give the defaults"
                (list defaults defaults)
                (list (read-env (env))
                      (read-env (apply env (map (lambda (f) (cons (field-variable f) "")) named-fields)))))
    (test-equal "each variable moves its own field alone: sizes and counts in their unit, durations in whole seconds kept in ms"
                (list (with-field 0 65536) (with-field 1 4) (with-field 2 30000) (with-field 3 5000)
                      (with-field 4 3000) (with-field 5 131072) (with-field 6 4096) (with-field 7 7000))
                (list (set-one "CHEZ_WS_MAX_MESSAGE_BYTES" "65536") (set-one "CHEZ_WS_MAX_QUEUE" "4")
                      (set-one "CHEZ_WS_PING_INTERVAL" "30") (set-one "CHEZ_WS_PING_TIMEOUT" "5")
                      (set-one "CHEZ_WS_CLOSE_TIMEOUT" "3") (set-one "CHEZ_WS_WRITE_HIGH_WATER" "131072")
                      (set-one "CHEZ_WS_WRITE_LOW_WATER" "4096") (set-one "CHEZ_WS_WRITE_TIMEOUT" "7")))
    (test-equal "every variable at once"
                '(1000 2 0 1000 1000 200 100 1000)
                (read-env (env '("CHEZ_WS_MAX_MESSAGE_BYTES" . "1000") '("CHEZ_WS_MAX_QUEUE" . "2")
                               '("CHEZ_WS_PING_INTERVAL" . "0") '("CHEZ_WS_PING_TIMEOUT" . "1")
                               '("CHEZ_WS_CLOSE_TIMEOUT" . "1") '("CHEZ_WS_WRITE_HIGH_WATER" . "200")
                               '("CHEZ_WS_WRITE_LOW_WATER" . "100") '("CHEZ_WS_WRITE_TIMEOUT" . "1"))))

    ;; --- the bounds ---
    (test-equal "each bound at its edge is accepted: a cap and a queue of 1, pinging off, a pong timeout of 1 s, a close timeout of 1 s, both water marks at 0, and a write timeout of 1 s"
                (list (with-field 0 1) (with-field 1 1) (with-field 2 0) (with-field 3 1000)
                      (with-field 4 1000) '(1048576 16 20000 20000 10000 0 0 60000) (with-field 7 1000))
                (list (set-one "CHEZ_WS_MAX_MESSAGE_BYTES" "1") (set-one "CHEZ_WS_MAX_QUEUE" "1")
                      (set-one "CHEZ_WS_PING_INTERVAL" "0") (set-one "CHEZ_WS_PING_TIMEOUT" "1")
                      (set-one "CHEZ_WS_CLOSE_TIMEOUT" "1")
                      (read-env (env '("CHEZ_WS_WRITE_HIGH_WATER" . "0") '("CHEZ_WS_WRITE_LOW_WATER" . "0")))
                      (set-one "CHEZ_WS_WRITE_TIMEOUT" "1")))
    (test-equal "below its bound, each is refused, naming its variable: a cap of 0, a queue of 0, a pong timeout of 0, a close timeout of 0, a write timeout of 0"
                '((refused websocket-limits-from-environment "CHEZ_WS_MAX_MESSAGE_BYTES")
                  (refused websocket-limits-from-environment "CHEZ_WS_MAX_QUEUE")
                  (refused websocket-limits-from-environment "CHEZ_WS_PING_TIMEOUT")
                  (refused websocket-limits-from-environment "CHEZ_WS_CLOSE_TIMEOUT")
                  (refused websocket-limits-from-environment "CHEZ_WS_WRITE_TIMEOUT"))
                (list (set-one "CHEZ_WS_MAX_MESSAGE_BYTES" "0") (set-one "CHEZ_WS_MAX_QUEUE" "0")
                      (set-one "CHEZ_WS_PING_TIMEOUT" "0") (set-one "CHEZ_WS_CLOSE_TIMEOUT" "0")
                      (set-one "CHEZ_WS_WRITE_TIMEOUT" "0")))
    (test-equal "a low water above the high water is refused, whichever was set, naming the low water's variable; equal marks are accepted"
                '((refused websocket-limits-from-environment "CHEZ_WS_WRITE_LOW_WATER")
                  (refused websocket-limits-from-environment "CHEZ_WS_WRITE_LOW_WATER")
                  (refused websocket-limits-from-environment "CHEZ_WS_WRITE_LOW_WATER")
                  (1048576 16 20000 20000 10000 11 11 60000))
                (list (set-one "CHEZ_WS_WRITE_HIGH_WATER" "65535")
                      (set-one "CHEZ_WS_WRITE_LOW_WATER" "262145")
                      (read-env (env '("CHEZ_WS_WRITE_HIGH_WATER" . "10") '("CHEZ_WS_WRITE_LOW_WATER" . "11")))
                      (read-env (env '("CHEZ_WS_WRITE_HIGH_WATER" . "11") '("CHEZ_WS_WRITE_LOW_WATER" . "11")))))

    ;; --- malformed values ---
    (test-equal "a value not in ASCII digits alone is refused, naming its variable, for every variable"
                (map (lambda (f)
                       (map (lambda (s) (list 'refused 'websocket-limits-from-environment (field-variable f)))
                            malformed))
                     named-fields)
                (map (lambda (f)
                       (map (lambda (s) (set-one (field-variable f) s)) malformed))
                     named-fields))
    ;; The server's transport arms a deadline only for a fixnum of ms
    ;; (transport-deadline!), and the step counts in fixnums, so a value is
    ;; a fixnum, Chez's own (greatest-fixnum) at most.
    (let* ((gf (greatest-fixnum))
           (s (lambda (n) (number->string n)))
           (secs (div gf 1000)))
      (test-equal "a value is a fixnum at most: each at the edge is accepted, and one past it refused, naming its variable"
                  (list (with-field 0 gf) (with-field 1 gf) (with-field 2 (* 1000 secs)) (with-field 3 (* 1000 secs))
                        (with-field 4 (* 1000 secs)) (with-field 5 gf)
                        (list 1048576 16 20000 20000 10000 gf gf 60000) (with-field 7 (* 1000 secs))
                        '(refused websocket-limits-from-environment "CHEZ_WS_MAX_MESSAGE_BYTES")
                        '(refused websocket-limits-from-environment "CHEZ_WS_MAX_QUEUE")
                        '(refused websocket-limits-from-environment "CHEZ_WS_PING_INTERVAL")
                        '(refused websocket-limits-from-environment "CHEZ_WS_PING_TIMEOUT")
                        '(refused websocket-limits-from-environment "CHEZ_WS_CLOSE_TIMEOUT")
                        '(refused websocket-limits-from-environment "CHEZ_WS_WRITE_HIGH_WATER")
                        '(refused websocket-limits-from-environment "CHEZ_WS_WRITE_LOW_WATER")
                        '(refused websocket-limits-from-environment "CHEZ_WS_WRITE_TIMEOUT")
                        '(refused make-websocket-limits max-message-bytes))
                  (list (set-one "CHEZ_WS_MAX_MESSAGE_BYTES" (s gf)) (set-one "CHEZ_WS_MAX_QUEUE" (s gf))
                        (set-one "CHEZ_WS_PING_INTERVAL" (s secs)) (set-one "CHEZ_WS_PING_TIMEOUT" (s secs))
                        (set-one "CHEZ_WS_CLOSE_TIMEOUT" (s secs)) (set-one "CHEZ_WS_WRITE_HIGH_WATER" (s gf))
                        (read-env (env (cons "CHEZ_WS_WRITE_HIGH_WATER" (s gf)) (cons "CHEZ_WS_WRITE_LOW_WATER" (s gf))))
                        (set-one "CHEZ_WS_WRITE_TIMEOUT" (s secs))
                        (set-one "CHEZ_WS_MAX_MESSAGE_BYTES" (s (+ gf 1))) (set-one "CHEZ_WS_MAX_QUEUE" (s (+ gf 1)))
                        (set-one "CHEZ_WS_PING_INTERVAL" (s (+ secs 1))) (set-one "CHEZ_WS_PING_TIMEOUT" (s (+ secs 1)))
                        (set-one "CHEZ_WS_CLOSE_TIMEOUT" (s (+ secs 1)))
                        (read-env (env (cons "CHEZ_WS_WRITE_HIGH_WATER" (s (+ gf 1)))))
                        (read-env (env (cons "CHEZ_WS_WRITE_HIGH_WATER" (s gf)) (cons "CHEZ_WS_WRITE_LOW_WATER" (s (+ gf 1)))))
                        (set-one "CHEZ_WS_WRITE_TIMEOUT" (s (+ secs 1)))
                        (refusal (lambda () (make-websocket-limits (+ gf 1) 16 20000 20000 10000 262144 65536 60000))))))
    (test-equal "leading zeros are digits too: 007 seconds is 7000 ms"
                (with-field 2 7000) (set-one "CHEZ_WS_PING_INTERVAL" "007"))

    ;; --- what makes limits checks them ---
    (test-equal "make-websocket-limits makes what its arguments say"
                '(5 6 7 8 9 11 10 12)
                (values-of (make-websocket-limits 5 6 7 8 9 11 10 12)))
    (test-equal "make-websocket-limits refuses a field below its bound, or not an exact whole number, 16.0 among them, naming the field"
                '((refused make-websocket-limits max-message-bytes)
                  (refused make-websocket-limits max-queue)
                  (refused make-websocket-limits ping-interval-ms)
                  (refused make-websocket-limits ping-timeout-ms)
                  (refused make-websocket-limits close-timeout-ms)
                  (refused make-websocket-limits write-high-water)
                  (refused make-websocket-limits write-low-water)
                  (refused make-websocket-limits write-timeout-ms)
                  (refused make-websocket-limits max-message-bytes)
                  (refused make-websocket-limits max-queue)
                  (refused make-websocket-limits max-queue)
                  (refused make-websocket-limits write-low-water))
                (map (lambda (args) (refusal (lambda () (apply make-websocket-limits args))))
                     '((0 16 20000 20000 10000 262144 65536 60000)
                       (1048576 0 20000 20000 10000 262144 65536 60000)
                       (1048576 16 -1 20000 10000 262144 65536 60000)
                       (1048576 16 20000 0 10000 262144 65536 60000)
                       (1048576 16 20000 20000 0 262144 65536 60000)
                       (1048576 16 20000 20000 10000 -1 0 60000)
                       (1048576 16 20000 20000 10000 262144 -1 60000)
                       (1048576 16 20000 20000 10000 262144 65536 0)
                       (1.5 16 20000 20000 10000 262144 65536 60000)
                       (1048576 "16" 20000 20000 10000 262144 65536 60000)
                       (1048576 16.0 20000 20000 10000 262144 65536 60000)
                       (1048576 16 20000 20000 10000 10 11 60000))))
    (test-equal "websocket-limits-with replaces each field alone, by name, and keeps the rest of its base, defaults or not"
                (append (map (lambda (i) (with-field i (if (= i 6) 1 (+ 1 (list-ref defaults i))))) '(0 1 2 3 4 5 6 7))
                        (list '(5 2 7 8 9 11 10 12)))
                (append (map (lambda (f i)
                               (values-of (websocket-limits-with default-websocket-limits
                                            (list (cons (field-name f)
                                                        (if (= i 6) 1 (+ 1 (list-ref defaults i))))))))
                             named-fields '(0 1 2 3 4 5 6 7))
                        (list (values-of (websocket-limits-with (make-websocket-limits 5 6 7 8 9 11 10 12)
                                                                '((max-queue . 2)))))))
    (test-equal "websocket-limits-with refuses a name that is not a field, an override that is not a pair, and a value make-websocket-limits refuses"
                '((refused websocket-limits-with (cap . 5))
                  (refused websocket-limits-with max-queue)
                  (refused make-websocket-limits max-queue))
                (list (refusal (lambda () (websocket-limits-with default-websocket-limits '((cap . 5)))))
                      (refusal (lambda () (websocket-limits-with default-websocket-limits '(max-queue))))
                      (refusal (lambda () (websocket-limits-with default-websocket-limits '((max-queue . 0)))))))))
