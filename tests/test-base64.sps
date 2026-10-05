#!r6rs
;;; (websocket base64) against its oracles (M1.2).
;;;
;;; - RFC 4648 §10's seven vectors, both ways.
;;; - The whole alphabet (§4's Table 1), both ways: the 48 bytes whose base64
;;;   is the 64 digits in order.  Those bytes are three peers', which agreed:
;;;   Python's binascii, Perl's MIME::Base64 and OpenSSL (m1-mutations.md).
;;; - RFC 6455's keys.  §1.3's example decodes to sixteen bytes, the peers'.
;;;   §4.1's, as printed, decodes to the bytes 1 to 16 it names: its last
;;;   digit sets bits a conforming encoder leaves clear (erratum 3150), and a
;;;   decode ignores them, as four of five peers do (the ledger).  The same
;;;   bytes encode as the erratum corrects the key.
;;; - RFC 6455 §4.2.2's accept value, of its example key.
;;; - A decode's refusals: a length that is not a multiple of four, a
;;;   character outside the alphabet, padding anywhere but the end, and more
;;;   than two padding characters.
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
    (test-equal "padding anywhere but the end is refused"
      '(refused refused refused refused)
      (map decoded '("Zg==Zg==" "Z=g=" "Zm=v" "=Zm9")))
    (test-equal "more than two padding characters are refused"
      '(refused refused)
      (map decoded '("Z===" "====")))))
