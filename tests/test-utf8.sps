#!r6rs
;;; (websocket utf8) against its oracles (M1.3).
;;;
;;; - Every row of RFC 3629 §4's grammar, at its edges: each row's first and
;;;   last code point, whole.
;;; - The refusals, each at the first byte that shows it, fed a byte at a
;;;   time and as one piece: a byte that starts no character, a tail outside
;;;   80..BF, overlong forms, surrogates (U+D800 to U+DFFF), and code points
;;;   past U+10FFFF.  The indexes are the grammar's.  Node's fatal
;;;   TextDecoder agrees with every one, and Python's incremental decoder
;;;   with all but the surrogates, which it refuses a byte later
;;;   (m1-mutations.md).
;;; - RFC 3629 §7's four examples.
;;; - Pieces: a character split at every byte, and §7's examples as one text
;;;   split in two at every byte, and fed a byte at a time.  A state is whole
;;;   exactly where a character ends; the boundaries are Python's.
;;; - The range a feed reads, the state before any byte, and an empty piece.
;;; - What a feed allocates: nothing for each byte.
(import (chezscheme) (srfi :64) (ws-testing) (websocket utf8))

;; outcome : (U Utf8State #f) -> (U 'whole 'unfinished 'refused)
;; A feed's answer as a value a check can compare.  It is never #f, so a
;; feed that raised cannot pass for one that refused.
(define (outcome s)
  (cond ((not s) 'refused)
        ((utf8-whole? s) 'whole)
        (else 'unfinished)))

;; refused-at : (Listof Byte) -> (U Nat 'whole 'unfinished)
;; The bytes fed one piece a byte: the index of the first refused, or how
;; the last piece left the state.
(define (refused-at bytes)
  (let loop ((s utf8-start) (i 0) (rest bytes))
    (if (null? rest)
        (outcome s)
        (let ((next (utf8-feed s (u8-list->bytevector (list (car rest))) 0 1)))
          (if next (loop next (+ i 1) (cdr rest)) i)))))

;; both : (Listof Byte) -> (List (U Nat Symbol) Symbol)
;; The bytes fed a byte at a time, and as one piece.
(define (both bytes)
  (let ((bv (u8-list->bytevector bytes)))
    (list (refused-at bytes)
          (outcome (utf8-feed utf8-start bv 0 (bytevector-length bv))))))

;; split : (Listof Byte) Nat -> (List Symbol Symbol)
;; How the bytes before k leave the state, and how the rest then do.
(define (split bytes k)
  (let* ((bv (u8-list->bytevector bytes))
         (first (utf8-feed utf8-start bv 0 k)))
    (list (outcome first)
          (outcome (and first (utf8-feed first bv k (bytevector-length bv)))))))

;; range : Nat Nat -> (Listof Nat)
;; The naturals from `from` up to, but not including, `to`.
(define (range from to)
  (if (>= from to) '() (cons from (range (+ from 1) to))))

;; allocated : (-> Any) -> Nat
;; The bytes allocated while the thunk runs.  It collects first, so no
;; collection falls inside the thunk.
(define (allocated thunk)
  (collect)
  (let ((before (sstats-bytes (statistics))))
    (thunk)
    (- (sstats-bytes (statistics)) before)))

;; RFC 3629 §7's examples, as one text, and where its characters end.
(define rfc3629-text
  '(#x41 #xE2 #x89 #xA2 #xCE #x91 #x2E
    #xED #x95 #x9C #xEA #xB5 #xAD #xEC #x96 #xB4
    #xE6 #x97 #xA5 #xE6 #x9C #xAC #xE8 #xAA #x9E
    #xEF #xBB #xBF #xF0 #xA3 #x8E #xB4))
(define rfc3629-boundaries '(0 1 4 6 7 10 13 16 19 22 25 28 32))

;; Each row's first and last code point.
(define row-edges
  '((#x00) (#x7F)
    (#xC2 #x80) (#xDF #xBF)
    (#xE0 #xA0 #x80) (#xE0 #xBF #xBF)
    (#xE1 #x80 #x80) (#xEC #xBF #xBF)
    (#xED #x80 #x80) (#xED #x9F #xBF)
    (#xEE #x80 #x80) (#xEF #xBF #xBF)
    (#xF0 #x90 #x80 #x80) (#xF0 #xBF #xBF #xBF)
    (#xF1 #x80 #x80 #x80) (#xF3 #xBF #xBF #xBF)
    (#xF4 #x80 #x80 #x80) (#xF4 #x8F #xBF #xBF)))

(run-suite "utf8"
  (lambda ()
    (test-equal "UTF8-1: U+0000 and U+007F"
      '((whole whole) (whole whole))
      (map both '((#x00) (#x7F))))
    (test-equal "UTF8-2: U+0080 and U+07FF"
      '((whole whole) (whole whole))
      (map both '((#xC2 #x80) (#xDF #xBF))))
    (test-equal "UTF8-3 from E0: U+0800 and U+0FFF"
      '((whole whole) (whole whole))
      (map both '((#xE0 #xA0 #x80) (#xE0 #xBF #xBF))))
    (test-equal "UTF8-3 from E1 to EC: U+1000 and U+CFFF"
      '((whole whole) (whole whole))
      (map both '((#xE1 #x80 #x80) (#xEC #xBF #xBF))))
    (test-equal "UTF8-3 from ED: U+D000 and U+D7FF"
      '((whole whole) (whole whole))
      (map both '((#xED #x80 #x80) (#xED #x9F #xBF))))
    (test-equal "UTF8-3 from EE and EF: U+E000 and U+FFFF"
      '((whole whole) (whole whole))
      (map both '((#xEE #x80 #x80) (#xEF #xBF #xBF))))
    (test-equal "UTF8-4 from F0: U+10000 and U+3FFFF"
      '((whole whole) (whole whole))
      (map both '((#xF0 #x90 #x80 #x80) (#xF0 #xBF #xBF #xBF))))
    (test-equal "UTF8-4 from F1 to F3: U+40000 and U+FFFFF"
      '((whole whole) (whole whole))
      (map both '((#xF1 #x80 #x80 #x80) (#xF3 #xBF #xBF #xBF))))
    (test-equal "UTF8-4 from F4: U+100000 and U+10FFFF"
      '((whole whole) (whole whole))
      (map both '((#xF4 #x80 #x80 #x80) (#xF4 #x8F #xBF #xBF))))

    (test-equal "a byte that starts no character is refused at once"
      '((0 refused) (0 refused) (0 refused) (0 refused) (0 refused) (0 refused)
        (0 refused) (0 refused) (0 refused) (0 refused) (0 refused) (0 refused))
      (map both '((#x80) (#xBF) (#xC0) (#xC1) (#xF5) (#xF7) (#xF8) (#xFB) (#xFC) (#xFD) (#xFE) (#xFF))))
    (test-equal "a tail outside its range is refused at that tail"
      '((1 refused) (1 refused) (1 refused) (1 refused) (1 refused) (2 refused) (2 refused)
        (1 refused) (2 refused) (3 refused) (3 refused)
        (1 refused) (1 refused) (1 refused) (1 refused))
      (map both '((#xC2 #x7F) (#xC2 #xC0) (#xDF #x41) (#xE1 #x7F) (#xE1 #xC0)
                  (#xE1 #x80 #x7F) (#xE1 #x80 #xC0)
                  (#xF1 #x7F) (#xF1 #x80 #xC0) (#xF1 #x80 #x80 #x7F) (#xF1 #x80 #x80 #xC0)
                  (#xED #x7F) (#xE0 #xC0) (#xF0 #xC0) (#xF4 #x7F))))
    (test-equal "an overlong form is refused at the first byte that shows it"
      '((0 refused) (0 refused) (1 refused) (1 refused) (1 refused) (1 refused))
      (map both '((#xC0 #x80) (#xC1 #xBF) (#xE0 #x80 #x80) (#xE0 #x9F #xBF)
                  (#xF0 #x80 #x80 #x80) (#xF0 #x8F #xBF #xBF))))
    (test-equal "a surrogate is refused at its second byte"
      '((1 refused) (1 refused) (1 refused) (1 refused))
      (map both '((#xED #xA0 #x80) (#xED #xBF #xBF) (#xED #xA0 #x80 #xED #xB0 #x80)
                  (#xED #xA1 #x8C #xED #xBE #xB4))))
    (test-equal "a code point past U+10FFFF is refused at the first byte that shows it"
      '((1 refused) (1 refused) (0 refused) (0 refused) (0 refused) (0 refused))
      (map both '((#xF4 #x90 #x80 #x80) (#xF4 #xBF #xBF #xBF) (#xF5 #x80 #x80 #x80)
                  (#xF7 #xBF #xBF #xBF) (#xF8 #x88 #x80 #x80 #x80) (#xFC #x84 #x80 #x80 #x80 #x80))))

    (test-equal "RFC 3629's four examples are whole"
      '((whole whole) (whole whole) (whole whole) (whole whole))
      (map both '((#x41 #xE2 #x89 #xA2 #xCE #x91 #x2E)
                  (#xED #x95 #x9C #xEA #xB5 #xAD #xEC #x96 #xB4)
                  (#xE6 #x97 #xA5 #xE6 #x9C #xAC #xE8 #xAA #x9E)
                  (#xEF #xBB #xBF #xF0 #xA3 #x8E #xB4))))
    (test-equal "a character's first bytes alone are unfinished, not refused"
      '((unfinished unfinished) (unfinished unfinished) (unfinished unfinished)
        (unfinished unfinished) (unfinished unfinished))
      (map both '((#xC2) (#xE0 #xA0) (#xE1) (#xF0 #x90 #x80) (#xF4 #x8F #xBF))))

    (test-equal "a character split at every byte is unfinished, then whole"
      '()
      (filter (lambda (r) (not (equal? r '(unfinished whole))))
              (apply append
                (map (lambda (bytes) (map (lambda (k) (split bytes k)) (range 1 (length bytes))))
                     row-edges))))
    (test-equal "RFC 3629's text split in two at every byte: whole where a character ends, then whole"
      (map (lambda (k) (list k (if (memv k rfc3629-boundaries) 'whole 'unfinished) 'whole))
           (range 0 33))
      (map (lambda (k) (cons k (split rfc3629-text k))) (range 0 33)))
    (test-equal "RFC 3629's text fed a byte at a time is whole exactly where a character ends"
      (map (lambda (k) (if (memv k rfc3629-boundaries) 'whole 'unfinished)) (range 1 33))
      (let ((bv (u8-list->bytevector rfc3629-text)))
        (let loop ((s utf8-start) (k 0) (out '()))
          (if (= k 32)
              (reverse out)
              (let ((next (utf8-feed s bv k (+ k 1))))
                (loop next (+ k 1) (cons (outcome next) out)))))))

    (let ((bv (u8-list->bytevector '(#xFF #xC3 #xA9 #xFF))))
      (test-equal "a feed reads only the bytes from start to end"
        '(whole unfinished refused refused)
        (list (outcome (utf8-feed utf8-start bv 1 3))
              (outcome (utf8-feed utf8-start bv 1 2))
              (outcome (utf8-feed utf8-start bv 0 3))
              (outcome (utf8-feed utf8-start bv 1 4))))
      (test-equal "the state before any byte is whole, and an empty piece changes nothing"
        '(whole whole unfinished)
        (list (outcome utf8-start)
              (outcome (utf8-feed utf8-start bv 2 2))
              (outcome (utf8-feed (utf8-feed utf8-start bv 1 2) bv 2 2)))))

    ;; §7's text 32,768 times: a mebibyte of every length of character.
    (let* ((n (* 32 32768))
           (big (make-bytevector n)))
      (do ((i 0 (+ i 32))) ((= i n))
        (bytevector-copy! (u8-list->bytevector rfc3629-text) 0 big i 32))
      (utf8-feed utf8-start big 0 n)
      (test-equal "a feed allocates nothing for each byte"
        0
        (- (allocated (lambda () (utf8-feed utf8-start big 0 n)))
           (allocated (lambda () (utf8-feed utf8-start big 0 0))))))))
