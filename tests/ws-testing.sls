#!r6rs
;;; (ws-testing) — the chez-websocket test-harness bridge.
;;;
;;; Suites are SRFI-64 (global-constraints), but SRFI-64 sets no process
;;; status.  `run-suite` runs a suite's assertions and then exits with the
;;; project's status vocabulary:
;;;
;;;   0  every assertion passed and at least one ran
;;;   1  one or more assertions failed (or unexpectedly passed)
;;;   2  a harness / registration error: the body escaped with an exception,
;;;      or the selection was empty (no assertion ran)
;;;   3  a provenance failure, raised by `provenance-failure`
;;;
;;; "Empty selection is failure at every layer" (global-constraints): a suite
;;; that registers no assertion exits 2, never 0.
;;;
;;; The SRFI-64 footgun — an exception inside a test expression is silently
;;; turned into #f — is defended by discipline, not code: assertions compare
;;; against a value only success can produce, never #f or bare truthiness
;;; (global-constraints).  So that a red can be read from the log, a failed
;;; assertion's line is followed by what it expected and what it got, and a
;;; harness error names what was raised.
;;;
;;; `allocated` measures what a thunk allocates, for suites that hold a
;;; library to an allocation, and `keep!` keeps what a measured thunk
;;; allocates from being optimized away.
;;;
;;; It began as chez-http-server's (testing), named apart so the server's own
;;; test libraries can share the library path with it.
(library (ws-testing)
  (export run-suite provenance-failure provenance-error? allocated keep!)
  (import (rnrs) (srfi :64) (only (chezscheme) collect statistics sstats-bytes))

  ;; provenance-error : a raised marker mapping a suite to status 3.
  (define-record-type provenance-error
    (fields (immutable message provenance-error-message)))

  ;; provenance-failure : String -> [raises]
  (define (provenance-failure message)
    (raise (make-provenance-error message)))

  ;; keep! : Any -> Unspecified
  ;; Holds the value where no compiler can prove it unused, so an allocation
  ;; a measured thunk is meant to make is not optimized away.
  (define kept (make-vector 1 #f))
  (define (keep! x) (vector-set! kept 0 x))

  ;; counted : (-> Any) -> Nat
  ;; The bytes Chez counts across one call of the thunk, from a collection.
  ;; Reading the counter allocates a record, and this includes it.
  (define (counted thunk)
    (collect)
    (let ((before (sstats-bytes (statistics))))
      (thunk)
      (- (sstats-bytes (statistics)) before)))

  ;; deeper : Nat (-> Any) -> Any
  ;; The thunk's answer, from a call made n frames deeper than this one.
  (define (deeper n thunk)
    (if (= n 0)
        (thunk)
        (let ((answer (deeper (- n 1) thunk)))
          (keep! answer)
          answer)))

  ;; least-counted : (-> Any) -> Nat
  ;; The least of three calls' counts, each called from its own depth of the
  ;; stack, 100 frames apart.  A call whose stack reaches past the end of the
  ;; Scheme stack's segment also pays for a new segment, about 64 KiB, and
  ;; does at every call from that depth; calls 100 frames apart cannot all be
  ;; that near an end, unless the thunk's own stack runs deep, as it does
  ;; when it should be counted.
  (define (least-counted thunk)
    (min (deeper 0 (lambda () (counted thunk)))
         (deeper 100 (lambda () (counted thunk)))
         (deeper 200 (lambda () (counted thunk)))))

  ;; Whether the counter has been checked, which the first measurement does.
  (define counter-checked? #f)

  ;; allocated : (-> Any) -> Nat
  ;; The bytes one call of the thunk allocates: the least of three calls'
  ;; counts, less what an empty thunk's count is.  A collection inside the
  ;; thunk counts too, so the answer is exact for a thunk that allocates well
  ;; under (collect-trip-bytes).  The first call checks the counter, and
  ;; raises unless a bytevector 1,024 bytes longer counts 1,024 bytes more
  ;; (both lengths are multiples of 16, so their headers and rounding are
  ;; alike): a counter that read nothing would pass "allocates nothing".
  (define (allocated thunk)
    (unless counter-checked?
      (unless (= 1024 (- (least-counted (lambda () (keep! (make-bytevector 2048))))
                         (least-counted (lambda () (keep! (make-bytevector 1024))))))
        (assertion-violation 'allocated "the counter does not count a 1,024-byte bytevector"))
      (set! counter-checked? #t))
    (- (least-counted thunk) (least-counted (lambda () #f))))

  ;; suite-status : test-runner -> (U 0 1 2)
  ;; 1 if any assertion failed or unexpectedly passed; 2 if none ran; else 0.
  (define (suite-status runner)
    (let ((failed (+ (test-runner-fail-count runner)
                     (test-runner-xpass-count runner)))
          (ran (+ (test-runner-pass-count runner)
                  (test-runner-fail-count runner)
                  (test-runner-xpass-count runner)
                  (test-runner-xfail-count runner))))
      (cond ((> failed 0) 1)
            ((= ran 0) 2)
            (else 0))))

  ;; note : String -> unspecified — one diagnostic line to stderr.
  (define (note line)
    (let ((p (current-error-port)))
      (put-string p line) (put-char p #\newline) (flush-output-port p)))

  ;; written : Any -> String
  ;; A value as `put-datum` writes it.
  (define (written v)
    (call-with-string-output-port (lambda (p) (put-datum p v))))

  ;; raised : Any -> String
  ;; What was raised, as far as (rnrs) can tell: a condition's who, message
  ;; and irritants, or the object itself.
  (define (raised e)
    (written (if (condition? e)
                 (append (if (who-condition? e) (list (condition-who e)) '())
                         (if (message-condition? e) (list (condition-message e)) '())
                         (if (irritants-condition? e) (condition-irritants e) '()))
                 e)))

  ;; show-values! : test-runner -> unspecified
  ;; Has the runner follow each failed assertion's line with what it
  ;; expected, when it has an expected value, and what it got: #f where its
  ;; expression raised.
  (define (show-values! runner)
    (let ((simple (test-runner-on-test-end runner))
          (none (list 'none)))
      (test-runner-on-test-end! runner
        (lambda (r)
          (simple r)
          (when (eq? (test-result-kind r) 'fail)
            (let ((p (current-output-port))
                  (expected (test-result-ref r 'expected-value none)))
              (unless (eq? expected none)
                (put-string p (string-append "  expected: " (written expected) "\n")))
              (put-string p (string-append "  actual:   " (written (test-result-ref r 'actual-value)) "\n"))))))))

  ;; run-suite : String (-> Any) -> [does not return; exits with the status]
  (define (run-suite name body)
    (let ((runner (test-runner-simple)))
      (show-values! runner)
      (test-runner-current runner)
      (test-begin name)
      (let ((status
             (guard (e ((provenance-error? e)
                        (note (string-append "PROVENANCE-ERROR " name ": "
                                             (provenance-error-message e)))
                        3)
                       (#t
                        (note (string-append "HARNESS-ERROR " name
                                             ": the suite body raised before finishing: "
                                             (raised e)))
                        2))
               (body)
               (suite-status runner))))
        (test-end name)
        (exit status)))))
