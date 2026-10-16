#!r6rs
;;; (websocket sha1) against its oracles.
;;;
;;; - RFC 3174 §7.3's four test cases, each pattern repeated as its driver
;;;   repeats it.
;;; - RFC 6455 §4.2.2's digest of its example key and the GUID: the one
;;;   input this library is for.
;;; - Six inputs at the padding's edges (RFC 3174 §4): 55 bytes are the most
;;;   one block holds with its padding, 56 the fewest that need two, and 63,
;;;   64 and 65 sit at a block's end.  Byte i of each is i x 37 mod 256, so
;;;   low and high bytes both appear.  Their digests are two peers', Perl's
;;;   Digest::SHA and OpenSSL, which agreed.
;;; - 4 MiB less a byte, whose length in bits sets every bit of the length
;;;   field from 3 to 24; the other inputs set only some.  Its digest is three
;;;   peers', which agreed.
;;; - A hash is pure: two digests held at once are each their own, a hash
;;;   leaves its message as it was, and a hash run inside another, from a
;;;   timer interrupt, disturbs neither.
;;; - What it allocates: what RFC 3174 says a hash holds, the message padded
;;;   to whole blocks (§4), the schedule of 80 words (§6.1) and the 20-byte
;;;   digest, and nothing else, from 0 bytes to 2,000 blocks.  The test
;;;   allocates those three objects itself, so Chez's own sizes are the
;;;   oracle.  2,000 blocks reach past where a block loop that kept a frame
;;;   for each block would outgrow the stack's first segment.
(import (rnrs) (only (chezscheme) set-timer timer-interrupt-handler) (srfi :64) (ws-testing) (websocket sha1))

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

(define abc "abc")
(define test2 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
(define test4 "0123456701234567012345670123456701234567012345670123456701234567")
(define abc-digest "a9993e364706816aba3e25717850c26c9cd0d89d")
(define test2-digest "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
(define test4-digest "dea356a2cddd90c7a7ecedc5ebb563934f460452")

;; with-a-hash-inside : Bytevector Bytevector -> (List String Boolean String)
;; Hashes outer, and inner from a timer interrupt partway through it.
;; Answers outer's digest, whether the interrupt came before outer's hash
;; returned, and inner's digest; (no-interrupt) when none came.
(define (with-a-hash-inside outer inner)
  (let ((running #f) (inside '(no-interrupt)) (handler (timer-interrupt-handler)))
    (dynamic-wind
      (lambda ()
        (timer-interrupt-handler (lambda () (set! inside (list running (hex (sha1 inner))))))
        (set! running #t)
        (set-timer 500))
      (lambda ()
        (let ((digest (sha1 outer)))
          (set! running #f)
          (cons (hex digest) inside)))
      (lambda ()
        (set-timer 0)
        (timer-interrupt-handler handler)))))

;; rfc3174-objects : Nat -> Unspecified
;; Allocates and keeps what RFC 3174 says a hash of n bytes holds: the
;; message padded with a 1 bit, 0 bits and a 64-bit length to whole 64-byte
;; blocks (§4), the schedule of 80 words (§6.1), and the 160-bit digest.
(define (rfc3174-objects n)
  (keep! (make-bytevector (* 64 (div (+ n 9 63) 64)) 0))
  (keep! (make-vector 80 0))
  (keep! (make-bytevector 20)))

(run-suite "sha1"
  (lambda ()
    (test-equal "RFC 3174 TEST1: abc"
      abc-digest
      (hex (sha1 (repeated abc 1))))
    (test-equal "RFC 3174 TEST2: 56 bytes"
      test2-digest
      (hex (sha1 (repeated test2 1))))
    (test-equal "RFC 3174 TEST3: a, a million times"
      "34aa973cd4c4daa4f61eeb2bdbad27316534016f"
      (hex (sha1 (repeated "a" 1000000))))
    (test-equal "RFC 3174 TEST4: 64 bytes ten times, a whole number of blocks"
      test4-digest
      (hex (sha1 (repeated test4 10))))

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

    (test-equal "4 MiB less a byte: a length in bits with every bit from 3 to 24 set"
      "4cb28b705337e4487cc93d13c3e69882120b0750"
      (hex (sha1 (make-bytevector (- (expt 2 22) 1) (char->integer #\a)))))

    (test-equal "two digests held at once are each their own"
      (list abc-digest test2-digest)
      (let* ((first (sha1 (repeated abc 1)))
             (second (sha1 (repeated test2 1))))
        (list (hex first) (hex second))))
    (test-equal "a hash leaves its message as it was"
      (bytevector->u8-list (pattern 65))
      (let ((message (pattern 65)))
        (sha1 message)
        (bytevector->u8-list message)))
    (test-equal "a hash run inside another, from a timer interrupt, disturbs neither"
      (list test4-digest #t abc-digest)
      (with-a-hash-inside (repeated test4 10) (repeated abc 1)))

    ;; 0, 55, 56, 64 and 640 bytes pad to 1, 1, 2, 2 and 11 blocks, and
    ;; 128,000 bytes to 2,001 (RFC 3174 §4).
    (let ((lengths '(0 55 56 64 640 128000)))
      (test-equal "a hash allocates its padded message, its schedule and its digest, and nothing else"
        (map (lambda (n) (allocated (lambda () (rfc3174-objects n)))) lengths)
        (map (lambda (n)
               (let ((message (pattern n)))
                 (allocated (lambda () (keep! (sha1 message))))))
             lengths)))))
