#!r6rs
;;; (websocket utf8) against its oracles.
;;;
;;; The oracles are RFC 3629: §4's grammar, row by row, and §7's examples.  A
;;; refusal's index is the first byte at which no row can go on.  Two
;;; incremental decoders were fed every case below, a byte at a time and in
;;; its pieces.  Node's fatal TextDecoder agreed with every index.  Python's
;;; agreed with all but the surrogates', which it refuses a byte later, and
;;; gave the boundaries of §7's text.
;;;
;;; - Every row at its edges, and every refusal at its index, fed a byte at a
;;;   time and as one piece, and again after an "A" in the same piece.
;;; - Pieces: each refusal split after its first byte; each character split
;;;   at every byte and at every pair of bytes; an empty piece inside a
;;;   character or a refusal; §7's text split in two at every byte, and fed a
;;;   byte at a time.
;;; - The API: the range a feed reads, a range outside its bytevector, the
;;;   start state, and a refusal, which is final and never whole.
;;; - What a feed allocates: nothing, per call or per byte.
(import (rnrs) (srfi :64) (ws-testing) (websocket utf8))

;; outcome : (U Utf8State #f) -> (U 'whole 'unfinished 'refused)
;; A state as a value a check can compare.  It is never #f, so a feed that
;; raised cannot pass for one that refused.
(define (outcome s)
  (cond ((not s) 'refused)
        ((utf8-whole? s) 'whole)
        (else 'unfinished)))

;; range : Nat Nat -> (Listof Nat)
;; The naturals from `from` up to, but not including, `to`.
(define (range from to)
  (if (>= from to) '() (cons from (range (+ from 1) to))))

;; in-pieces : (Listof Byte) (Listof Nat) -> (Listof Symbol)
;; The bytes fed as pieces of one bytevector, cut at each point (ascending;
;; a point given twice makes an empty piece): how each piece leaves the
;; state, each fed the state the last one left.  A refusal ends the feeding,
;; as it ends a connection: the pieces after it are refused, unfed.
(define (in-pieces bytes cuts)
  (let ((bv (u8-list->bytevector bytes)))
    (let loop ((s utf8-start) (from 0) (ends (append cuts (list (bytevector-length bv)))) (out '()))
      (cond ((null? ends) (reverse out))
            ((not s) (loop s (car ends) (cdr ends) (cons 'refused out)))
            (else
             (let ((next (utf8-feed s bv from (car ends))))
               (loop next (car ends) (cdr ends) (cons (outcome next) out))))))))

;; bytewise : (Listof Byte) -> (Listof Symbol)
;; The bytes fed one piece a byte: how each byte leaves the state.
(define (bytewise bytes)
  (in-pieces bytes (range 1 (length bytes))))

;; refused-at : (Listof Byte) -> (U Nat Symbol)
;; Fed a byte at a time: the index of the first byte refused, or how the
;; last byte left the state.
(define (refused-at bytes)
  (let loop ((outcomes (bytewise bytes)) (i 0))
    (cond ((eq? (car outcomes) 'refused) i)
          ((null? (cdr outcomes)) (car outcomes))
          (else (loop (cdr outcomes) (+ i 1))))))

;; both : (Listof Byte) -> (List (U Nat Symbol) Symbol)
;; The bytes fed a byte at a time, and as one piece.
(define (both bytes)
  (list (refused-at bytes) (car (in-pieces bytes '()))))

;; §4's rows: each row's first and last code point.
(define rows
  '(("UTF8-1: U+0000 and U+007F" (#x00) (#x7F))
    ("UTF8-2: U+0080 and U+07FF" (#xC2 #x80) (#xDF #xBF))
    ("UTF8-3 from E0: U+0800 and U+0FFF" (#xE0 #xA0 #x80) (#xE0 #xBF #xBF))
    ("UTF8-3 from E1 to EC: U+1000 and U+CFFF" (#xE1 #x80 #x80) (#xEC #xBF #xBF))
    ("UTF8-3 from ED: U+D000 and U+D7FF" (#xED #x80 #x80) (#xED #x9F #xBF))
    ("UTF8-3 from EE and EF: U+E000 and U+FFFF" (#xEE #x80 #x80) (#xEF #xBF #xBF))
    ("UTF8-4 from F0: U+10000 and U+3FFFF" (#xF0 #x90 #x80 #x80) (#xF0 #xBF #xBF #xBF))
    ("UTF8-4 from F1 to F3: U+40000 and U+FFFFF" (#xF1 #x80 #x80 #x80) (#xF3 #xBF #xBF #xBF))
    ("UTF8-4 from F4: U+100000 and U+10FFFF" (#xF4 #x80 #x80 #x80) (#xF4 #x8F #xBF #xBF))))
(define characters (apply append (map cdr rows)))

;; The refusals by kind: each case is the index of the byte refused, then
;; the bytes.  The tails cover each row's first tail at both edges.
(define refusals
  '(("a byte that starts no character is refused at once"
     (0 #x80) (0 #xBF) (0 #xC0) (0 #xC1) (0 #xF5) (0 #xF7)
     (0 #xF8) (0 #xFB) (0 #xFC) (0 #xFD) (0 #xFE) (0 #xFF))
    ("a tail outside its range is refused at that tail"
     (1 #xC2 #x7F) (1 #xC2 #xC0) (1 #xDF #x41)
     (1 #xE0 #x9F) (1 #xE0 #xC0)
     (1 #xE1 #x7F) (1 #xE1 #xC0) (2 #xE1 #x80 #x7F) (2 #xE1 #x80 #xC0)
     (1 #xED #x7F) (1 #xED #xA0)
     (1 #xEE #x7F) (1 #xEF #xC0)
     (1 #xF0 #x8F) (1 #xF0 #xC0)
     (1 #xF1 #x7F) (1 #xF3 #xC0) (2 #xF1 #x80 #xC0)
     (3 #xF1 #x80 #x80 #x7F) (3 #xF1 #x80 #x80 #xC0)
     (1 #xF4 #x7F) (1 #xF4 #x90))
    ("an overlong form is refused at the first byte that shows it"
     (0 #xC0 #x80) (0 #xC1 #xBF) (1 #xE0 #x80 #x80) (1 #xE0 #x9F #xBF)
     (1 #xF0 #x80 #x80 #x80) (1 #xF0 #x8F #xBF #xBF))
    ("a surrogate is refused at its second byte"
     (1 #xED #xA0 #x80) (1 #xED #xBF #xBF)
     (1 #xED #xA0 #x80 #xED #xB0 #x80) (1 #xED #xA1 #x8C #xED #xBE #xB4))
    ("a code point past U+10FFFF is refused at the first byte that shows it"
     (1 #xF4 #x90 #x80 #x80) (1 #xF4 #xBF #xBF #xBF) (0 #xF5 #x80 #x80 #x80)
     (0 #xF7 #xBF #xBF #xBF) (0 #xF8 #x88 #x80 #x80 #x80) (0 #xFC #x84 #x80 #x80 #x80 #x80))))
(define refusal-cases (apply append (map cdr refusals)))
(define refused-later (filter (lambda (c) (> (car c) 0)) refusal-cases))

;; RFC 3629 §7's examples, as one text, and where its characters end
;; (Python's character lengths).
(define rfc3629-examples
  '((#x41 #xE2 #x89 #xA2 #xCE #x91 #x2E)
    (#xED #x95 #x9C #xEA #xB5 #xAD #xEC #x96 #xB4)
    (#xE6 #x97 #xA5 #xE6 #x9C #xAC #xE8 #xAA #x9E)
    (#xEF #xBB #xBF #xF0 #xA3 #x8E #xB4)))
(define rfc3629-text (apply append rfc3629-examples))
(define rfc3629-boundaries '(0 1 4 6 7 10 13 16 19 22 25 28 32))

(run-suite "utf8"
  (lambda ()
    (for-each
      (lambda (row)
        (test-equal (car row)
          '((whole whole) (whole whole))
          (map both (cdr row))))
      rows)
    (for-each
      (lambda (kind)
        (test-equal (car kind)
          (map (lambda (c) (list (car c) 'refused)) (cdr kind))
          (map (lambda (c) (both (cdr c))) (cdr kind))))
      refusals)
    (test-equal "RFC 3629's four examples are whole"
      '((whole whole) (whole whole) (whole whole) (whole whole))
      (map both rfc3629-examples))
    (test-equal "a character's first bytes alone are unfinished, not refused"
      '((unfinished unfinished) (unfinished unfinished) (unfinished unfinished)
        (unfinished unfinished) (unfinished unfinished))
      (map both '((#xC2) (#xE0 #xA0) (#xE1) (#xF0 #x90 #x80) (#xF4 #x8F #xBF))))
    (test-equal "after an A in the same piece, every character is whole and every refusal one byte later"
      (append (map (lambda (bytes) '(whole whole)) characters)
              (map (lambda (c) (list (+ 1 (car c)) 'refused)) refusal-cases))
      (append (map (lambda (bytes) (both (cons #x41 bytes))) characters)
              (map (lambda (c) (both (cons #x41 (cdr c)))) refusal-cases)))

    (test-equal "a refusal split after its first byte is refused in its second piece"
      (map (lambda (c) '(unfinished refused)) refused-later)
      (map (lambda (c) (in-pieces (cdr c) '(1))) refused-later))
    (let ((cuts (apply append
                  (map (lambda (bytes) (map (lambda (k) (list bytes k)) (range 1 (length bytes))))
                       characters))))
      (test-equal "a character split at every byte is unfinished, then whole"
        (map (lambda (c) '(unfinished whole)) cuts)
        (map (lambda (c) (in-pieces (car c) (cdr c))) cuts)))
    (let ((cuts (apply append
                  (map (lambda (bytes)
                         (apply append
                           (map (lambda (k1)
                                  (map (lambda (k2) (list bytes k1 k2)) (range (+ k1 1) (length bytes))))
                                (range 1 (length bytes)))))
                       characters))))
      (test-equal "a character split at every pair of bytes is unfinished, unfinished, then whole"
        (map (lambda (c) '(unfinished unfinished whole)) cuts)
        (map (lambda (c) (in-pieces (car c) (cdr c))) cuts)))
    (let ((cuts (apply append
                  (map (lambda (bytes) (map (lambda (k) (list bytes k k)) (range 1 (length bytes))))
                       characters))))
      (test-equal "an empty piece inside a character or a refusal changes nothing"
        (append (map (lambda (c) '(unfinished unfinished whole)) cuts)
                (map (lambda (c) '(unfinished unfinished refused)) refused-later))
        (append (map (lambda (c) (in-pieces (car c) (cdr c))) cuts)
                (map (lambda (c) (in-pieces (cdr c) '(1 1))) refused-later))))

    (let ((n (length rfc3629-text)))
      (test-equal "RFC 3629's text split in two at every byte: whole where a character ends, then whole"
        (map (lambda (k) (list k (if (memv k rfc3629-boundaries) 'whole 'unfinished) 'whole))
             (range 0 (+ n 1)))
        (map (lambda (k) (cons k (in-pieces rfc3629-text (list k)))) (range 0 (+ n 1))))
      (test-equal "RFC 3629's text fed a byte at a time is whole exactly where a character ends"
        (map (lambda (k) (if (memv k rfc3629-boundaries) 'whole 'unfinished)) (range 1 (+ n 1)))
        (bytewise rfc3629-text)))

    (let ((bv (u8-list->bytevector '(#xFF #xC3 #xA9 #xFF))))
      (test-equal "a feed reads only the bytes from start to end"
        '(whole unfinished refused refused)
        (list (outcome (utf8-feed utf8-start bv 1 3))
              (outcome (utf8-feed utf8-start bv 1 2))
              (outcome (utf8-feed utf8-start bv 0 3))
              (outcome (utf8-feed utf8-start bv 1 4))))
      (test-equal "a range outside its bytevector is an assertion naming utf8-feed"
        '(utf8-feed utf8-feed utf8-feed utf8-feed)
        (map (lambda (r)
               (guard (e ((assertion-violation? e) (and (who-condition? e) (condition-who e))))
                 (utf8-feed utf8-start bv (car r) (cadr r))
                 'accepted))
             '((1 0) (3 2) (0 5) (-1 2))))
      (test-equal "the state before any byte is whole, and so is an empty piece of it"
        '(whole whole)
        (list (outcome utf8-start)
              (outcome (utf8-feed utf8-start bv 2 2)))))

    (let ((text? (lambda (bytes)
                   (let ((bv (u8-list->bytevector bytes)))
                     (if (utf8-whole? (utf8-feed utf8-start bv 0 (bytevector-length bv)))
                         'text
                         'not-text)))))
      (test-equal "a refusal is final and never whole, so one call checks a whole text"
        '(refused not-whole (text not-text not-text))
        (list (outcome (utf8-feed #f (u8-list->bytevector '(#x41)) 0 1))
              (if (utf8-whole? #f) 'whole 'not-whole)
              (map text? '((#x68 #xC3 #xA9) (#x68 #xED #xA0 #x80) (#x68 #xC3))))))

    ;; §7's text 32,768 times: a mebibyte of every length of character, fed
    ;; as one piece and a byte a piece.
    (let* ((unit (u8-list->bytevector rfc3629-text))
           (size (bytevector-length unit))
           (n (* size 32768))
           (big (make-bytevector n)))
      (do ((i 0 (+ i size))) ((= i n))
        (bytevector-copy! unit 0 big i size))
      (let ((whole-feed (lambda () (utf8-feed utf8-start big 0 n)))
            (bytewise-feed (lambda ()
                             (let loop ((s utf8-start) (i 0))
                               (if (= i n) s (loop (utf8-feed s big i (+ i 1)) (+ i 1)))))))
        (test-equal "a feed allocates nothing, per call or per byte"
          '(whole whole 0 0)
          (list (outcome (whole-feed))
                (outcome (bytewise-feed))
                (allocated whole-feed)
                (allocated bytewise-feed)))))))
