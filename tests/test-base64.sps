#!r6rs
;;; (websocket base64) against its oracles.
;;;
;;; - RFC 4648 §10's seven vectors, both ways.
;;; - The whole alphabet (§4's Table 1), both ways: the 48 bytes whose base64
;;;   is the 64 digits in order.  Those bytes are three peers', which agreed:
;;;   Python's binascii, Perl's MIME::Base64 and OpenSSL.
;;; - RFC 6455's keys.  §1.3's example decodes to sixteen bytes, the peers'.
;;;   §4.1's, as printed, decodes to the bytes 1 to 16 it names: its last
;;;   digit sets bits a conforming encoder leaves clear (erratum 3150), and a
;;;   decode ignores them, as four of five peers do.  The same bytes encode
;;;   as the erratum corrects the key.  A last digit before one "=" is read
;;;   the same way: "Zm/=" decodes to "fo", the three peers'.
;;; - RFC 6455 §4.2.2's accept value, of its example key.
;;; - A decode's refusals: a length that is not a multiple of four, a
;;;   character outside the alphabet, padding anywhere but the end, and more
;;;   than two padding characters.  The characters outside the alphabet
;;;   include each one beside a run of it in ASCII, and the last character of
;;;   ASCII and the first past it.
;;; - What each allocates: an encode its string and a decode its bytes, of
;;;   the lengths RFC 4648 §4 gives them, and nothing else.  The test
;;;   allocates those objects itself, so Chez's own sizes are the oracle.
(import (rnrs) (srfi :64) (ws-testing) (websocket base64) (websocket sha1))

;; decoded : String -> (U (Listof Byte) 'refused)
;; What a decode answers, as a value a check can compare.  It is never #f,
;; so a decode that raised cannot pass for one that refused.
(define (decoded s)
  (let ((bv (base64-decode s)))
    (if bv (bytevector->u8-list bv) 'refused)))

;; ascii : String -> (Listof Byte)
(define (ascii s) (bytevector->u8-list (string->utf8 s)))

(define alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
(define alphabet-bytes
  '(0 16 131 16 81 135 32 146 139 48 211 143 65 20 147 81 85 151 97 150 155 113 215 159
    130 24 163 146 89 167 162 154 171 178 219 175 195 28 179 211 93 183 227 158 187 243 223 191))
(define one-to-sixteen '(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16))

(run-suite "base64"
  (lambda ()
    (for-each
      (lambda (text code)
        (test-equal (string-append "RFC 4648: \"" text "\" encodes as \"" code "\"")
          code
          (base64-encode (string->utf8 text)))
        (test-equal (string-append "RFC 4648: \"" code "\" decodes to \"" text "\"")
          (ascii text)
          (decoded code)))
      '("" "f" "fo" "foo" "foob" "fooba" "foobar")
      '("" "Zg==" "Zm8=" "Zm9v" "Zm9vYg==" "Zm9vYmE=" "Zm9vYmFy"))

    (test-equal "the alphabet's 48 bytes encode as its 64 digits, in order"
      alphabet
      (base64-encode (u8-list->bytevector alphabet-bytes)))
    (test-equal "the alphabet's 64 digits decode to its 48 bytes"
      alphabet-bytes
      (decoded alphabet))

    (test-equal "RFC 6455's example key decodes to its sixteen bytes"
      (ascii "the sample nonce")
      (decoded "dGhlIHNhbXBsZSBub25jZQ=="))
    (test-equal "RFC 6455's client example, as printed, decodes to the bytes 1 to 16"
      one-to-sixteen
      (decoded "AQIDBAUGBwgJCgsMDQ4PEC=="))
    (test-equal "the bytes 1 to 16 encode as erratum 3150 corrects that example"
      "AQIDBAUGBwgJCgsMDQ4PEA=="
      (base64-encode (u8-list->bytevector one-to-sixteen)))
    (test-equal "a last digit before one \"=\" decodes with its unused bits set, too"
      (ascii "fo")
      (decoded "Zm/="))
    (test-equal "RFC 6455's example accept value"
      "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
      (base64-encode (sha1 (string->utf8 (string-append "dGhlIHNhbXBsZSBub25jZQ=="
                                                        "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))))

    (test-equal "a length that is not a multiple of four is refused"
      '(refused refused refused refused)
      (map decoded '("Z" "Zg=" "Zm9vY" "Zm9vYmF")))
    (test-equal "a character outside the alphabet is refused"
      '(refused refused refused refused refused)
      (map decoded (list "Zm9 " "Zm9-" "Zm9_" "Zm9." (string #\Z #\m #\9 (integer->char #xE9)))))
    ;; The alphabet's runs in ASCII are +, / to 9, A to Z and a to z.
    (test-equal "each character beside a run of the alphabet, and either side of ASCII's end, is refused"
      '(refused refused refused refused refused refused refused refused refused refused)
      (map (lambda (c) (decoded (string #\Z #\m #\9 c)))
           (list #\* #\, #\. #\: #\@ #\[ #\` #\{ (integer->char #x7F) (integer->char #x80))))
    (test-equal "padding anywhere but the end is refused"
      '(refused refused refused refused)
      (map decoded '("Zg==Zg==" "Z=g=" "Zm=v" "=Zm9")))
    (test-equal "more than two padding characters are refused"
      '(refused refused)
      (map decoded '("Z===" "====")))

    ;; RFC 4648 §4: n bytes encode as 4 x ceil(n / 3) characters, and 4k
    ;; characters, p of them padding, decode to 3k - p bytes.  Each list
    ;; reaches 3,000 bytes, a thousand groups.
    (let ((lengths '(0 1 2 3 16 20 48 3000))
          (codes (list (cons "" 0) (cons "AA==" 1) (cons "AAA=" 2) (cons "AAAA" 3)
                       (cons "dGhlIHNhbXBsZSBub25jZQ==" 16) (cons "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" 20)
                       (cons alphabet 48) (cons (make-string 4000 #\A) 3000))))
      (test-equal "an encode allocates its string, and a decode its bytes, and nothing else"
        (append (map (lambda (n) (allocated (lambda () (keep! (make-string (* 4 (div (+ n 2) 3))))))) lengths)
                (map (lambda (code) (allocated (lambda () (keep! (make-bytevector (cdr code)))))) codes))
        (append (map (lambda (n)
                       (let ((bytes (make-bytevector n 7)))
                         (allocated (lambda () (keep! (base64-encode bytes))))))
                     lengths)
                (map (lambda (code) (allocated (lambda () (keep! (base64-decode (car code)))))) codes))))))
