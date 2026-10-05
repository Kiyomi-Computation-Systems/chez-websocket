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
(library (websocket base64)
  (export base64-encode base64-decode)
  (import (rnrs))

  (define digits "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  ;; digit-value : Char -> (U Nat #f)
  ;; A character's value in §4's Table 1, or #f when it is not one of its 64.
  (define (digit-value c)
    (cond ((char<=? #\A c #\Z) (- (char->integer c) (char->integer #\A)))
          ((char<=? #\a c #\z) (+ 26 (- (char->integer c) (char->integer #\a))))
          ((char<=? #\0 c #\9) (+ 52 (- (char->integer c) (char->integer #\0))))
          ((char=? c #\+) 62)
          ((char=? c #\/) 63)
          (else #f)))

  ;; base64-encode : Bytevector -> String
  ;; The bytes' base64, padded with "=" to a multiple of four characters (§4).
  (define (base64-encode bv)
    (let ((n (bytevector-length bv)))
      (call-with-string-output-port
        (lambda (port)
          (define (digit group shift)
            (string-ref digits (bitwise-and (bitwise-arithmetic-shift-right group shift) 63)))
          (let loop ((i 0))
            (when (< i n)
              (let* ((left (- n i))
                     (group (bitwise-ior
                              (bitwise-arithmetic-shift-left (bytevector-u8-ref bv i) 16)
                              (if (> left 1) (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ i 1)) 8) 0)
                              (if (> left 2) (bytevector-u8-ref bv (+ i 2)) 0))))
                (put-char port (digit group 18))
                (put-char port (digit group 12))
                (put-char port (if (> left 1) (digit group 6) #\=))
                (put-char port (if (> left 2) (digit group 0) #\=))
                (loop (+ i 3)))))))))

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
           (let* ((size (- (* 3 (div len 4)) pad))
                  (out (make-bytevector size)))
             (define (value i)
               (if (< i data) (digit-value (string-ref s i)) 0))
             (let loop ((i 0) (o 0))
               (when (< i len)
                 (let ((group (bitwise-ior
                                (bitwise-arithmetic-shift-left (value i) 18)
                                (bitwise-arithmetic-shift-left (value (+ i 1)) 12)
                                (bitwise-ior (bitwise-arithmetic-shift-left (value (+ i 2)) 6)
                                             (value (+ i 3))))))
                   (bytevector-u8-set! out o (bitwise-arithmetic-shift-right group 16))
                   (when (< (+ o 1) size)
                     (bytevector-u8-set! out (+ o 1) (bitwise-and (bitwise-arithmetic-shift-right group 8) 255)))
                   (when (< (+ o 2) size)
                     (bytevector-u8-set! out (+ o 2) (bitwise-and group 255)))
                   (loop (+ i 4) (+ o 3)))))
             out)))))
