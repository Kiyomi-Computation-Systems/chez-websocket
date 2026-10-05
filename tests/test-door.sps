#!r6rs
;;; The door this library builds on, through the pin (M0's smoke).
;;;
;;; chez-http-server's facade loads from the one library path, the pins it
;;; carries under it, and the verbs the binding will call behave as its
;;; v0.3.0 documents them ((http-server transport), (http-server private
;;; waits)): a transport made of procedures hands each its verb's arguments
;;; in one shape, and `await` refuses where no coroutine may park, before it
;;; calls `register`.  The binding's own tests will hold the rest.
(import (rnrs) (srfi :64) (ws-testing) (http-server))

;; noting-transport : (Any -> Any) -> Transport
;; A transport whose procedures hand `note` what they were called with.
;; Its read-start delivers two bytes and then the end at once.
(define (noting-transport note)
  (make-transport
    (lambda (bv start end written) (note (list 'write (bytevector-length bv) start end written)))
    (lambda (on-bytes on-end) (on-bytes (u8-list->bytevector '(9 8)) 0 2) (on-end 'eof))
    (lambda () (note '(read-stop)))
    (lambda () (note '(close)))
    (lambda (ms on-passed) (note (list 'deadline ms on-passed)))
    (lambda (thunk) (note (list 'on-drain)))
    (lambda (thunk) (note (list 'on-close)))))

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
        '(await not-called) (list who registered)))))
