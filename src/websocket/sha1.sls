#!r6rs
;;; (websocket sha1) — SHA-1 (RFC 3174) of a bytevector.
;;;
;;; For the opening handshake's accept value alone (RFC 6455 §4.2.2), where
;;; it is a checksum rather than a defence: SHA-1 no longer resists
;;; collisions, and nothing here relies on it.
;;;
;;; A word is an exact integer below 2^32.  Each sum is masked back to 32
;;; bits.  A rotation masks the bits it keeps before it shifts them, so
;;; nothing passes 2^35, which keeps every value a fixnum on a 64-bit Chez.
;;; No arithmetic or bitwise call takes more than three arguments: Chez
;;; 10.4.1 allocates for each call with four or more (measured in M1.1).
(library (websocket sha1)
  (export sha1)
  (import (rnrs))

  (define mask32 #xFFFFFFFF)

  ;; rotl : Word Nat -> Word
  ;; x rotated left by n bits, 0 < n < 32: RFC 3174 §3's S^n.
  (define (rotl x n)
    (bitwise-ior
      (bitwise-arithmetic-shift-left
        (bitwise-and x (- (bitwise-arithmetic-shift-left 1 (- 32 n)) 1))
        n)
      (bitwise-arithmetic-shift-right x (- 32 n))))

  ;; f : Nat Word Word Word -> Word
  ;; Step t's function of B, C and D (§5).
  (define (f t b c d)
    (cond ((< t 20) (bitwise-ior (bitwise-and b c) (bitwise-and (bitwise-not b) d)))
          ((< t 40) (bitwise-xor b c d))
          ((< t 60) (bitwise-ior (bitwise-and b c) (bitwise-and b d) (bitwise-and c d)))
          (else (bitwise-xor b c d))))

  ;; k : Nat -> Word
  ;; Step t's constant (§5).
  (define (k t)
    (cond ((< t 20) #x5A827999)
          ((< t 40) #x6ED9EBA1)
          ((< t 60) #x8F1BBCDC)
          (else #xCA62C1D6)))

  ;; pad : Bytevector -> Bytevector
  ;; The message, a 1 bit, 0 bits, and the message's length in bits as 64
  ;; bits big-endian, to a whole number of 64-byte blocks (§4).
  (define (pad message)
    (let* ((len (bytevector-length message))
           (size (* 64 (+ 1 (div (+ len 8) 64))))
           (padded (make-bytevector size 0)))
      (bytevector-copy! message 0 padded 0 len)
      (bytevector-u8-set! padded len #x80)
      (bytevector-u64-set! padded (- size 8) (* 8 len) (endianness big))
      padded))

  ;; schedule! : (Vectorof Word) Bytevector Nat -> Unspecified
  ;; W(0) to W(79) of the block at byte `at` (§6.1 a and b).
  (define (schedule! w padded at)
    (do ((t 0 (+ t 1))) ((= t 16))
      (vector-set! w t (bytevector-u32-ref padded (+ at (* 4 t)) (endianness big))))
    (do ((t 16 (+ t 1))) ((= t 80))
      (vector-set! w t (rotl (bitwise-xor (bitwise-xor (vector-ref w (- t 3)) (vector-ref w (- t 8))
                                                       (vector-ref w (- t 14)))
                                          (vector-ref w (- t 16)))
                             1))))

  ;; sha1 : Bytevector -> Bytevector
  ;; The 20-byte SHA-1 digest of all of the message's bytes (§6.1).
  (define (sha1 message)
    (let* ((padded (pad message))
           (size (bytevector-length padded))
           (w (make-vector 80 0)))
      (let next-block ((at 0)
                       (h0 #x67452301) (h1 #xEFCDAB89) (h2 #x98BADCFE)
                       (h3 #x10325476) (h4 #xC3D2E1F0))
        (if (= at size)
            (let ((digest (make-bytevector 20)))
              (bytevector-u32-set! digest 0 h0 (endianness big))
              (bytevector-u32-set! digest 4 h1 (endianness big))
              (bytevector-u32-set! digest 8 h2 (endianness big))
              (bytevector-u32-set! digest 12 h3 (endianness big))
              (bytevector-u32-set! digest 16 h4 (endianness big))
              digest)
            (begin
              (schedule! w padded at)
              (let step ((t 0) (a h0) (b h1) (c h2) (d h3) (e h4))
                (if (= t 80)
                    (next-block (+ at 64)
                                (bitwise-and (+ h0 a) mask32)
                                (bitwise-and (+ h1 b) mask32)
                                (bitwise-and (+ h2 c) mask32)
                                (bitwise-and (+ h3 d) mask32)
                                (bitwise-and (+ h4 e) mask32))
                    (step (+ t 1)
                          (bitwise-and (+ (+ (rotl a 5) (f t b c d) e) (vector-ref w t) (k t))
                                       mask32)
                          a
                          (rotl b 30)
                          c
                          d)))))))))
