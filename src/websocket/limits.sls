#!r6rs
;;; (websocket limits) — a connection's limits, and their reading from an
;;; environment's strings (design §7).
;;;
;;; Pure: reading the process's environment is I/O, so this library is given
;;; a lookup, String -> (U String #f), as the server's (http-server limits)
;;; is.  The binding hands it the real environment once, as the program
;;; starts, so a malformed value stops the program there; a test hands it a
;;; table.
;;;
;;; The defaults, each with its source:
;;;   max-message-bytes  1 MiB: the largest message; past it, 1009 (0001)
;;;   max-queue          16 messages (0001's amendment of 2026-10-05): reading
;;;                      stops once the queue holds a cap's worth of bytes or
;;;                      this many messages, websockets' max_queue
;;;   ping-interval-ms   20 s of quiet before a ping; 0 turns pinging off (0001)
;;;   ping-timeout-ms    20 s for its pong; past it, 1011 (0001)
;;;   close-timeout-ms   10 s for the client's close, after the server's
;;;                      (websockets' close_timeout), and for a client to read
;;;                      what was unsent when a close was asked for; past it,
;;;                      the stream aborted (decision 0006): at a close, a
;;;                      client reads the high water within it, 25.6 KiB/s
;;;                      by default
;;;   write-high-water   256 KiB unsent before a send waits, and reading
;;;                      stops, and
;;;   write-low-water    64 KiB unsent when both go on: the server's own
;;;   write-timeout-ms   60 s for a write's done while past the high water;
;;;                      past it, the stream aborted: the server's own
;;;                      CHEZ_HTTP_WRITE_TIMEOUT (decision 0006)
;;; Durations are given in whole seconds and kept in milliseconds, the unit
;;; the server's transport arms a deadline in; sizes and counts are given and
;;; kept in their own unit.  A variable absent or empty is its default.  A
;;; value is a whole number in ASCII digits, nothing else: no sign, no radix
;;; or exactness prefix, no exponent, no space.
;;;
;;; Each field has a least value, and anything below it is refused, by the
;;; constructor and by the reading, which names the variable.  A cap and a
;;; queue are at least 1: reading stops once the queue holds a cap's worth,
;;; so a cap of 0 would stop it for good.  A pong's timeout is at least
;;; 1 ms, since one of 0 would pass as its ping went; read in whole seconds,
;;; that is at least 1 s.  So is a write's timeout, since one of 0 would
;;; pass as reading stopped, and a close's, since one of 0 would abort a
;;; close before the client could read it (0006's amendment, by form).  The
;;; rest are at least 0.  Each is a fixnum at
;;; most: the server's transport arms a deadline only for a fixnum of ms
;;; (transport-deadline!), and the step counts in fixnums, so a value past
;;; one is refused here, as the program starts, not where it is used.  A low
;;; water above the high water is refused too: a send would go on before it
;;; had waited.
(library (websocket limits)
  (export make-websocket-limits websocket-limits? default-websocket-limits
          websocket-limits-with websocket-limits-from-environment
          websocket-limits-environment-variables
          websocket-limits-max-message-bytes websocket-limits-max-queue
          websocket-limits-ping-interval-ms websocket-limits-ping-timeout-ms
          websocket-limits-close-timeout-ms websocket-limits-write-high-water
          websocket-limits-write-low-water websocket-limits-write-timeout-ms)
  (import (rnrs))

  ;; The record, as made: new-limits checks nothing.  The record type
  ;; defines its predicate and the eight accessors:
  ;;   websocket-limits? : Any -> Boolean
  ;;   websocket-limits-max-message-bytes : WebsocketLimits -> Nat
  ;;   websocket-limits-max-queue : WebsocketLimits -> Nat
  ;;   websocket-limits-ping-interval-ms : WebsocketLimits -> Nat
  ;;   websocket-limits-ping-timeout-ms : WebsocketLimits -> Nat
  ;;   websocket-limits-close-timeout-ms : WebsocketLimits -> Nat
  ;;   websocket-limits-write-high-water : WebsocketLimits -> Nat
  ;;   websocket-limits-write-low-water : WebsocketLimits -> Nat
  ;;   websocket-limits-write-timeout-ms : WebsocketLimits -> Nat
  (define-record-type (websocket-limits new-limits websocket-limits?)
    (fields (immutable max-message-bytes) (immutable max-queue)
            (immutable ping-interval-ms) (immutable ping-timeout-ms)
            (immutable close-timeout-ms) (immutable write-high-water)
            (immutable write-low-water) (immutable write-timeout-ms)))

  ;; The fields, in order: each one's name, its variable, its least value,
  ;; how many of its kept unit one of its variable's makes, and its accessor.
  (define specs
    (list (list 'max-message-bytes "CHEZ_WS_MAX_MESSAGE_BYTES" 1 1    websocket-limits-max-message-bytes)
          (list 'max-queue         "CHEZ_WS_MAX_QUEUE"         1 1    websocket-limits-max-queue)
          (list 'ping-interval-ms  "CHEZ_WS_PING_INTERVAL"     0 1000 websocket-limits-ping-interval-ms)
          (list 'ping-timeout-ms   "CHEZ_WS_PING_TIMEOUT"      1 1000 websocket-limits-ping-timeout-ms)
          (list 'close-timeout-ms  "CHEZ_WS_CLOSE_TIMEOUT"     1 1000 websocket-limits-close-timeout-ms)
          (list 'write-high-water  "CHEZ_WS_WRITE_HIGH_WATER"  0 1    websocket-limits-write-high-water)
          (list 'write-low-water   "CHEZ_WS_WRITE_LOW_WATER"   0 1    websocket-limits-write-low-water)
          (list 'write-timeout-ms  "CHEZ_WS_WRITE_TIMEOUT"     1 1000 websocket-limits-write-timeout-ms)))

  (define spec-name car)
  (define (spec-variable spec) (cadr spec))
  (define (spec-least spec) (caddr spec))
  (define (spec-unit spec) (cadddr spec))
  (define (spec-accessor spec) (car (cddddr spec)))

  ;; named : Symbol (Listof Any) -> Any
  ;; Of a list in the fields' order, the element that is the named field's.
  (define (named name xs)
    (let loop ((ss specs) (xs xs))
      (if (eq? (spec-name (car ss)) name)
          (car xs)
          (loop (cdr ss) (cdr xs)))))

  ;; checked : Symbol (Listof Any) (Listof Any) -> (Listof Nat)
  ;; The values, each a fixnum at or above its field's least, and the low
  ;; water at or below the high water; else an assertion violation naming
  ;; `who` and, first, the label of the value it refuses.
  (define (checked who labels vs)
    (for-each (lambda (spec label v)
                (unless (and (fixnum? v) (fx>=? v (spec-least spec)))
                  (assertion-violation who "not a fixnum at or above its least"
                                       label v (spec-least spec))))
              specs labels vs)
    (let ((high (named 'write-high-water vs)) (low (named 'write-low-water vs)))
      (unless (fx<=? low high)
        (assertion-violation who "the write low water is above the high water"
                             (named 'write-low-water labels) low
                             (named 'write-high-water labels) high)))
    vs)

  ;; make-websocket-limits : Nat Nat Nat Nat Nat Nat Nat Nat -> WebsocketLimits
  ;; Limits of these values, in the fields' order: max-message-bytes
  ;; max-queue ping-interval-ms ping-timeout-ms close-timeout-ms
  ;; write-high-water write-low-water write-timeout-ms.  A value below its
  ;; field's least, or not a fixnum, or a low water above the high water, is
  ;; an assertion violation naming the field.
  (define (make-websocket-limits max-message-bytes max-queue ping-interval-ms
                                 ping-timeout-ms close-timeout-ms
                                 write-high-water write-low-water write-timeout-ms)
    (apply new-limits
           (checked 'make-websocket-limits (map spec-name specs)
                    (list max-message-bytes max-queue ping-interval-ms ping-timeout-ms
                          close-timeout-ms write-high-water write-low-water write-timeout-ms))))

  ;; default-websocket-limits : WebsocketLimits
  (define default-websocket-limits
    (make-websocket-limits 1048576 16 20000 20000 10000 262144 65536 60000))

  ;; websocket-limits-environment-variables : (Listof String)
  ;; The variables websocket-limits-from-environment reads, in the fields'
  ;; order.
  (define websocket-limits-environment-variables
    (map spec-variable specs))

  ;; field-values : WebsocketLimits -> (Listof Nat)
  ;; The fields' values, in their order.
  (define (field-values L)
    (map (lambda (spec) ((spec-accessor spec) L)) specs))

  ;; websocket-limits-with : WebsocketLimits (Listof (Pair Symbol Any)) -> WebsocketLimits
  ;; `base` with the fields named in `overrides` replaced, each as (name .
  ;; value), the name being make-websocket-limits' for the field.  A name
  ;; that is not a field is an assertion violation, and the values are
  ;; checked as make-websocket-limits checks them.
  (define (websocket-limits-with base overrides)
    (for-each (lambda (o)
                (unless (and (pair? o) (assq (car o) specs))
                  (assertion-violation 'websocket-limits-with "not a field of the limits" o)))
              overrides)
    (apply make-websocket-limits
           (map (lambda (spec v)
                  (let ((o (assq (spec-name spec) overrides)))
                    (if o (cdr o) v)))
                specs (field-values base))))

  ;; digits? : String -> Boolean
  ;; Whether every character of the string is an ASCII digit.  The reading
  ;; takes an empty value for the default before it asks.
  (define (digits? s)
    (for-all (lambda (c) (and (char<=? #\0 c) (char<=? c #\9)))
             (string->list s)))

  ;; read-value : (String -> (U String #f)) Spec Nat -> Nat
  ;; The field's value as its variable gives it, in the field's unit, or
  ;; `default` when the variable is absent or empty.  Anything but digits is
  ;; an assertion violation naming the variable.
  (define (read-value lookup spec default)
    (let ((s (lookup (spec-variable spec))))
      (cond ((or (not s) (string=? s "")) default)
            ((digits? s) (* (spec-unit spec) (string->number s 10)))
            (else (assertion-violation 'websocket-limits-from-environment
                                       "not a whole number in ASCII digits"
                                       (spec-variable spec) s)))))

  ;; websocket-limits-from-environment : (String -> (U String #f)) -> WebsocketLimits
  ;; default-websocket-limits with each variable `lookup` gives applied over
  ;; it.  A malformed value, one below its field's least, or a low water
  ;; above the high water, whichever was set, is an assertion violation
  ;; naming the variable.
  (define (websocket-limits-from-environment lookup)
    (apply new-limits
           (checked 'websocket-limits-from-environment
                    websocket-limits-environment-variables
                    (map (lambda (spec default) (read-value lookup spec default))
                         specs (field-values default-websocket-limits))))))
