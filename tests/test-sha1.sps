#!r6rs
;;; (websocket sha1) against its oracles (M1.1).
;;;
;;; - RFC 3174 §7.3's four test cases, each pattern repeated as its driver
;;;   repeats it.
;;; - RFC 6455 §4.2.2's digest of its example key and the GUID: the one
;;;   input this library is for.
;;; - Six inputs at the padding's edges (RFC 3174 §4): 55 bytes are the most
;;;   one block holds with its padding, 56 the fewest that need two, and 63,
;;;   64 and 65 sit at a block's end.  Byte i of each is i x 37 mod 256, so
;;;   low and high bytes both appear.  Their digests are two peers', Perl's
;;;   Digest::SHA and OpenSSL, which agreed (m1-mutations.md).
;;; - What it allocates: nothing for each block, so ten blocks more cost
;;;   only their longer padded copy.  A hash allocates its padded copy, its
;;;   schedule and its digest; only the copy grows with the input, and a
;;;   bytevector is its bytes and a header rounded up alike for both sizes.
(import (chezscheme) (srfi :64) (ws-testing) (websocket sha1))

;; hex : Bytevector -> String
;; Lowercase hex, two digits a byte, as the peers print a digest.
(define (hex bv)
  (let ((digits "0123456789abcdef"))
    (list->string
      (apply append
        (map (lambda (b) (list (string-ref digits (div b 16)) (string-ref digits (mod b 16))))
             (bytevector->u8-list bv))))))

;; repeated : String Nat -> Bytevector
;; The string's ASCII bytes, n times over.
(define (repeated s n)
  (let* ((one (string->utf8 s))
         (k (bytevector-length one))
         (out (make-bytevector (* k n))))
    (do ((i 0 (+ i 1))) ((= i n) out)
      (bytevector-copy! one 0 out (* i k) k))))

;; pattern : Nat -> Bytevector
;; n bytes, byte i being i x 37 mod 256.
(define (pattern n)
  (let ((out (make-bytevector n)))
    (do ((i 0 (+ i 1))) ((= i n) out)
      (bytevector-u8-set! out i (mod (* i 37) 256)))))

(run-suite "sha1"
  (lambda ()
    (test-equal "RFC 3174 TEST1: abc"
      "a9993e364706816aba3e25717850c26c9cd0d89d"
      (hex (sha1 (repeated "abc" 1))))
    (test-equal "RFC 3174 TEST2: 56 bytes"
      "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
      (hex (sha1 (repeated "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" 1))))
    (test-equal "RFC 3174 TEST3: a, a million times"
      "34aa973cd4c4daa4f61eeb2bdbad27316534016f"
      (hex (sha1 (repeated "a" 1000000))))
    (test-equal "RFC 3174 TEST4: 64 bytes ten times, a whole number of blocks"
      "dea356a2cddd90c7a7ecedc5ebb563934f460452"
      (hex (sha1 (repeated "0123456701234567012345670123456701234567012345670123456701234567" 10))))

    (test-equal "RFC 6455's example key and the GUID"
      "b37a4f2cc0624f1690f64606cf385945b2bec4ea"
      (hex (sha1 (string->utf8 (string-append "dGhlIHNhbXBsZSBub25jZQ=="
                                              "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))))

    (test-equal "0 bytes: the padding alone"
      "da39a3ee5e6b4b0d3255bfef95601890afd80709"
      (hex (sha1 (pattern 0))))
    (test-equal "55 bytes: the most one block holds"
      "c5c6c6489395b389610c07e696a74908840d5be1"
      (hex (sha1 (pattern 55))))
    (test-equal "56 bytes: the fewest that need two blocks"
      "9f28a611cdc197211cc44d24deac7fc4e8c52d46"
      (hex (sha1 (pattern 56))))
    (test-equal "63 bytes: the padding's first byte ends the block"
      "1aad096920c502124f20d608cbd152a49cc94a03"
      (hex (sha1 (pattern 63))))
    (test-equal "64 bytes: a whole block, its padding a block of its own"
      "8c378cc64f4bcf0b8279f405ccbf0a0a571e97f2"
      (hex (sha1 (pattern 64))))
    (test-equal "65 bytes: one byte into the second block"
      "da051c9640eac8ca7925201d97f9a91d2abf6de0"
      (hex (sha1 (pattern 65))))

    ;; 0 bytes pad to 64, one block; 640 pad to 704, eleven (RFC 3174 §4).
    (let ((one-block (pattern 0))
          (eleven-blocks (pattern 640)))
      (sha1 one-block)
      (sha1 eleven-blocks)
      (test-equal "ten blocks more allocate only their padded copy's 640 bytes more"
        (- 704 64)
        (- (allocated (lambda () (sha1 eleven-blocks)))
           (allocated (lambda () (sha1 one-block))))))))
