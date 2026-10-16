#!r6rs
;;; (websocket utf8) — an incremental UTF-8 checker (RFC 3629 §4).
;;;
;;; A text message arrives in pieces, a character may straddle two, and a
;;; bad byte fails the connection at once (RFC 6455 §8.1).  So the checker
;;; takes bytes as they come and carries what a character still needs from
;;; piece to piece in a state.  It refuses a byte as soon as no valid UTF-8
;;; can go on with it, which is §4's grammar read a byte at a time: an
;;; overlong form, a surrogate (U+D800 to U+DFFF) or a code point past
;;; U+10FFFF is refused at the first byte that shows it.  A refusal is #f,
;;; and final: fed on, it stays #f, and it is never whole.
;;;
;;; A state is a fixnum.  It is 0 between characters.  Otherwise it holds
;;; how many bytes the character still needs, and the range its next byte
;;; must fall in.  It is unpacked with fixnum shifts, and a later byte's
;;; next state is one of two constants: Chez 10.4.1 calls the generic
;;; bitwise-arithmetic-shift procedures out of line, which more than doubled
;;; the cost of each byte past a character's first.  A feed allocates
;;; nothing.
(library (websocket utf8)
  (export utf8-start utf8-feed utf8-whole?)
  (import (rnrs))

  ;; utf8-start : Utf8State
  ;; The state before any byte: between characters.
  (define utf8-start 0)

  ;; need : Nat Byte Byte -> Utf8State
  ;; A character that needs `count` more bytes, the next one in lo..hi.
  (define (need count lo hi)
    (bitwise-ior (bitwise-arithmetic-shift-left count 16)
                 (bitwise-arithmetic-shift-left lo 8)
                 hi))

  ;; lead : Byte -> (U Utf8State #f)
  ;; The state after a character's first byte, by §4's rows, or #f when no
  ;; character starts with it.
  (define (lead b)
    (cond ((<= b #x7F) 0)
          ((<= #xC2 b #xDF) (need 1 #x80 #xBF))
          ((= b #xE0) (need 2 #xA0 #xBF))
          ((<= #xE1 b #xEC) (need 2 #x80 #xBF))
          ((= b #xED) (need 2 #x80 #x9F))
          ((<= #xEE b #xEF) (need 2 #x80 #xBF))
          ((= b #xF0) (need 3 #x90 #xBF))
          ((<= #xF1 b #xF3) (need 3 #x80 #xBF))
          ((= b #xF4) (need 3 #x80 #x8F))
          (else #f)))

  ;; step : Utf8State Byte -> (U Utf8State #f)
  ;; The state after one more byte, or #f when it cannot go on.
  (define (step s b)
    (if (= s 0)
        (lead b)
        (let ((count (fxarithmetic-shift-right s 16))
              (lo (fxand (fxarithmetic-shift-right s 8) #xFF))
              (hi (fxand s #xFF)))
          (and (<= lo b hi)
               (case count
                 ((1) 0)
                 ((2) (need 1 #x80 #xBF))
                 (else (need 2 #x80 #xBF)))))))

  ;; utf8-feed : (U Utf8State #f) Bytevector Nat Nat -> (U Utf8State #f)
  ;; The state after the bytes from start to end, or #f at the first of them
  ;; that cannot go on, or when given #f.  A range outside the bytevector is
  ;; an assertion violation.
  (define (utf8-feed state bv start end)
    (unless (and (<= 0 start end) (<= end (bytevector-length bv)))
      (assertion-violation 'utf8-feed "not a range of the bytevector" start end))
    (and state
         (let loop ((i start) (s state))
           (if (= i end)
               s
               (let ((next (step s (bytevector-u8-ref bv i))))
                 (and next (loop (+ i 1) next)))))))

  ;; utf8-whole? : (U Utf8State #f) -> Boolean
  ;; Whether the bytes so far end on a whole character; never after a
  ;; refusal.
  (define (utf8-whole? state)
    (eqv? state 0)))
