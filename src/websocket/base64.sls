#!r6rs
;;; (websocket base64) — base64 (RFC 4648 §4): an encode, and a decode strict
;;; enough to check a key.
;;;
;;; For the opening handshake (RFC 6455 §4.2): the accept value is the base64
;;; of a digest, and a key must be the base64 of sixteen bytes.  A decode
;;; refuses a length that is not a multiple of four, a character outside the
;;; alphabet, and padding anywhere but the last one or two places.  It does
;;; not check the bits a last digit carries past the data: RFC 4648 §3.5 lets
;;; a decoder accept them, RFC 6455 §4.1's own example key sets them, and
;;; four of five peers accept such a key.
;;;
;;; Three bytes make a group of 24 bits, a fixnum on any Chez, worked with
;;; R6RS's fixnum operations, which Chez 10.4.1 compiles inline where the
;;; generic shifts are calls.  Its `fxarithmetic-shift-left` is a call too,
;;; so a group is put together with `fx*` by powers of two (measured in
;;; M1.2's review).
(library (websocket base64)
  (export base64-encode base64-decode)
  (import (rnrs) (rnrs mutable-strings))

  (define digits "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  ;; digit-values : (Vectorof (U Nat #f))
  ;; §4's Table 1 read the other way: each ASCII character's value, or #f for
  ;; one that is not a digit.
  (define digit-values
    (let ((table (make-vector 128 #f)))
      (do ((v 0 (+ v 1))) ((= v 64) table)
        (vector-set! table (char->integer (string-ref digits v)) v))))

  ;; digit-value : Char -> (U Nat #f)
  ;; A character's value in §4's Table 1, or #f when it is not one of its 64.
  (define (digit-value c)
    (let ((n (char->integer c)))
      (and (< n 128) (vector-ref digit-values n))))

  ;; base64-encode : Bytevector -> String
  ;; The bytes' base64, padded with "=" to a multiple of four characters (§4).
  (define (base64-encode bv)
    (let* ((n (bytevector-length bv))
           (left (mod n 3))
           (whole (- n left))
           (out (make-string (* 4 (div (+ n 2) 3)) #\=)))
      (define (byte i) (bytevector-u8-ref bv i))
      ;; put! : Nat Fixnum Nat -> Unspecified
      ;; Writes at o the digit of the group's six bits from bit `shift` up.
      (define (put! o group shift)
        (string-set! out o (string-ref digits (fxand (fxarithmetic-shift-right group shift) 63))))
      (let loop ((i 0) (o 0))
        (if (< i whole)
            (let ((group (fxior (fx* (byte i) 65536) (fx* (byte (+ i 1)) 256) (byte (+ i 2)))))
              (put! o group 18)
              (put! (+ o 1) group 12)
              (put! (+ o 2) group 6)
              (put! (+ o 3) group 0)
              (loop (+ i 3) (+ o 4)))
            ;; One or two bytes left make two or three digits, and "=" the rest.
            (unless (= left 0)
              (let ((group (fxior (fx* (byte i) 65536)
                                  (if (= left 2) (fx* (byte (+ i 1)) 256) 0))))
                (put! o group 18)
                (put! (+ o 1) group 12)
                (when (= left 2) (put! (+ o 2) group 6))))))
      out))

  ;; padding : String -> Nat
  ;; How many of the last two characters are "=", counted from the end.
  (define (padding s)
    (let ((len (string-length s)))
      (cond ((and (>= len 2) (char=? (string-ref s (- len 1)) #\=) (char=? (string-ref s (- len 2)) #\=)) 2)
            ((and (>= len 1) (char=? (string-ref s (- len 1)) #\=)) 1)
            (else 0))))

  ;; base64-decode : String -> (U Bytevector #f)
  ;; The bytes a padded base64 string encodes (§4), or #f when it is not one:
  ;; its length is not a multiple of four, a character before its padding is
  ;; outside the alphabet, or "=" is anywhere but its last one or two places.
  (define (base64-decode s)
    (let* ((len (string-length s))
           (pad (padding s))
           (data (- len pad)))
      (and (= (mod len 4) 0)
           (let all-digits? ((i 0))
             (or (= i data)
                 (and (digit-value (string-ref s i)) (all-digits? (+ i 1)))))
           (let ((out (make-bytevector (- (* 3 (div len 4)) pad)))
                 (whole (if (= pad 0) len (- len 4))))   ; the characters of unpadded groups
             ;; value : Nat -> Nat
             ;; The value of the digit at i, which the check above found one.
             (define (value i) (digit-value (string-ref s i)))
             (let loop ((i 0) (o 0))
               (if (< i whole)
                   (let ((group (fxior (fx* (value i) 262144) (fx* (value (+ i 1)) 4096)
                                       (fx* (value (+ i 2)) 64) (value (+ i 3)))))
                     (bytevector-u8-set! out o (fxarithmetic-shift-right group 16))
                     (bytevector-u8-set! out (+ o 1) (fxand (fxarithmetic-shift-right group 8) 255))
                     (bytevector-u8-set! out (+ o 2) (fxand group 255))
                     (loop (+ i 4) (+ o 3)))
                   ;; A padded last group: two digits make one byte, three two.
                   (unless (= pad 0)
                     (let ((group (fxior (fx* (value i) 262144) (fx* (value (+ i 1)) 4096)
                                         (if (= pad 1) (fx* (value (+ i 2)) 64) 0))))
                       (bytevector-u8-set! out o (fxarithmetic-shift-right group 16))
                       (when (= pad 1)
                         (bytevector-u8-set! out (+ o 1) (fxand (fxarithmetic-shift-right group 8) 255)))))))
             out)))))
