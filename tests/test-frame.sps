#!r6rs
;;; (websocket frame)'s decoder against its oracles (M2.1).
;;;
;;; The oracles are RFC 6455's, read from its raw text: §5.2's framing,
;;; §5.1's rule that a client masks every frame, §5.5's control frames, and
;;; §5.7's examples.  A refusal's index is the first byte with which no
;;; frame a client may send begins.  The suite builds its own headers by
;;; §5.2, and stops with a provenance failure unless they are the length
;;; forms' written out by hand.  Node's ws 7.5.10, a server's decoder, was
;;; fed every case in its pieces (m2-mutations.md).
;;;
;;; - §5.7's unmasked examples are refused.
;;; - Headers of every kind at each length form's edges, whole and a byte at
;;;   a time, split at every byte and every pair of bytes, and with an empty
;;;   piece inside.
;;; - Each refusal of design §4 at its index, with its 1002: whole, a byte at
;;;   a time, and split at every byte.  A refusal is final.
(import (rnrs) (srfi :64) (ws-testing) (websocket frame))

;; range : Nat Nat -> (Listof Nat)
;; The naturals from `from` up to, but not including, `to`.
(define (range from to)
  (if (>= from to) '() (cons from (range (+ from 1) to))))

;; concat : (Listof (Listof Any)) -> (Listof Any)
;; The lists, one after another.
(define (concat lists)
  (fold-right append '() lists))

;; --- the suite's headers, by RFC 6455 §5.2 --------------------------------

;; §5.7's masking key.
(define key '(#x37 #xFA #x21 #x3D))

;; big-endian : Nat Nat -> (Listof Byte)
;; n as k bytes, the most significant first: §5.2's network byte order.
(define (big-endian n k)
  (let loop ((n n) (k k) (out '()))
    (if (= k 0) out (loop (div n 256) (- k 1) (cons (mod n 256) out)))))

;; header : Byte Nat -> (Listof Byte)
;; A masked frame's header: its first byte, the mask bit with the length in
;; its shortest form, and the key.
(define (header first n)
  (append (list first)
          (cond ((< n 126) (list (+ 128 n)))
                ((< n 65536) (cons 254 (big-endian n 2)))
                (else (cons 255 (big-endian n 8))))
          key))

;; RFC 6455 §5.7's examples, as its text prints them.
(define rfc-masked-text '(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
(define rfc-unmasked
  (list '(#x81 #x05 #x48 #x65 #x6C #x6C #x6F)    ; text, "Hello"
        '(#x01 #x03 #x48 #x65 #x6C)              ; text, "Hel", not final
        '(#x80 #x02 #x6C #x6F)                   ; its continuation, "lo"
        '(#x89 #x05 #x48 #x65 #x6C #x6C #x6F)    ; ping, "Hello"
        '(#x82 #x7E #x01 #x00)                   ; the 256-byte binary message's header
        '(#x82 #x7F #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00)))  ; the 64 KiB one's

;; The length forms' headers at their edges (§5.2), written out by hand.
(define length-edges
  (list (list 125 (append '(#x82 #xFD) key))
        (list 126 (append '(#x82 #xFE #x00 #x7E) key))
        (list 65535 (append '(#x82 #xFE #xFF #xFF) key))
        (list 65536 (append '(#x82 #xFF #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00) key))
        (list 9223372036854775807 (append '(#x82 #xFF #x7F #xFF #xFF #xFF #xFF #xFF #xFF #xFF) key))))

;; --- what a decoder answers -----------------------------------------------

;; in-pieces : (Listof Byte) (Listof Nat) -> (Listof (U (Listof Event) Stop))
;; The bytes fed to a fresh decoder as pieces of one bytevector, cut at each
;; point (ascending; a point given twice makes an empty piece), as the
;; protocol feeds it a header's bytes, to frame-read-header!.  For each
;; piece, what it answered, in order:
;;   (header Fin Kind Length)   a header, once whole;
;;   (refused Code Why Index)   a refusal, at the index of the byte that
;;                              showed it.
;; Then where the decoder stopped: between frames, in-header, or (left n)
;; before a payload.  A refusal ends the feeding: no later piece is fed, and
;; no stop follows.  So does a payload's first byte, which this suite does
;; not read, answering payload.  So that a decoder that reads nothing cannot
;; loop, a read that goes nowhere answers stuck, and ends the feeding too.
(define (in-pieces bytes cuts)
  (let ((bv (u8-list->bytevector bytes))
        (d (make-frame-decoder)))
    (let piece ((from 0) (ends (append cuts (list (length bytes)))) (out '()) (in-header? #f))
      (if (null? ends)
          (reverse (cons (cond ((> (frame-left d) 0) (list 'left (frame-left d)))
                               (in-header? 'in-header)
                               (else 'between))
                         out))
          (let go ((i from) (events '()) (in-header? in-header?))
            (define (end-with event)
              (reverse (cons (reverse (cons event events)) out)))
            (cond
              ((= i (car ends)) (piece i (cdr ends) (cons (reverse events) out) in-header?))
              ((> (frame-left d) 0) (end-with 'payload))
              (else
               (let-values (((what next) (frame-read-header! d bv i (car ends))))
                 (cond
                   ((eq? what 'refused)
                    (end-with (append '(refused) (frame-refusal d) (list (- next 1)))))
                   ((<= next i) (end-with 'stuck))
                   ((eq? what 'header)
                    (go next
                        (cons (list 'header (frame-fin? d) (frame-kind d) (frame-length d)) events)
                        #f))
                   (else (go next events #t)))))))))))

;; piece? : (U (Listof Event) Stop) -> Boolean
;; Whether in-pieces answered it for a piece: a list of events, each a pair,
;; and not a stop such as (left n).
(define (piece? p)
  (and (list? p) (or (null? p) (pair? (car p)))))

;; merged : (Listof (U (Listof Event) Stop)) -> (Listof (U Event Stop))
;; The pieces' events in order, and then the stop, if there is one.
(define (merged pieces)
  (concat (map (lambda (p) (if (piece? p) p (list p))) pieces)))

;; decoded : (Listof Byte) (Listof Nat) -> (Listof (U Event Stop))
;; What a decoder answers for the bytes in those pieces, in one list.
(define (decoded bytes cuts)
  (merged (in-pieces bytes cuts)))

;; but-last : (Listof Any) -> (Listof Any)
(define (but-last l)
  (reverse (cdr (reverse l))))

;; bytewise : (Listof Byte) -> (Listof Nat)
;; The cuts that make a piece of every byte.
(define (bytewise bytes)
  (range 1 (length bytes)))

;; --- the tables -------------------------------------------------------------

;; Each kind of frame a client may send, by its first byte (§5.2): (first fin kind).
(define kinds
  '((#x80 #t continuation) (#x00 #f continuation) (#x81 #t text) (#x01 #f text)
    (#x82 #t binary) (#x02 #f binary) (#x88 #t close) (#x89 #t ping) (#x8A #t pong)))

;; Each length form at its edges (§5.2), and a control frame's, which is 125
;; bytes or less (§5.5).  2^32's sixth length byte is zero, though its fifth
;; is not.
(define data-lengths '(0 1 125 126 127 65535 65536 4294967296 9223372036854775807))
(define control-lengths '(0 1 125))

;; Every header: each kind at each of its lengths, as (kind length).
(define headers
  (concat
    (map (lambda (k)
           (map (lambda (n) (list k n))
                (if (memq (caddr k) '(close ping pong)) control-lengths data-lengths)))
         kinds)))

;; header-bytes : (List Kind Nat) -> (Listof Byte)
(define (header-bytes h) (header (car (car h)) (cadr h)))

;; alone : (List Kind Nat) -> (Listof (U Event Stop))
;; What a decoder answers for a header fed with none of its payload.
(define (alone h)
  (list (list 'header (cadr (car h)) (caddr (car h)) (cadr h))
        (if (= (cadr h) 0) 'between (list 'left (cadr h)))))

;; The refusals of design §4, each case the index of the byte that shows it,
;; then the bytes: the reason, then the cases.
(define refusals
  `(("a reserved bit set is refused at the first byte, with 1002"
     reserved-bit
     (0 #xC1) (0 #xA1) (0 #x91) (0 #xF1) (0 #x41) (0 #x21) (0 #x11)
     (0 #xC0) (0 #xA2) (0 #x90) (0 #xC8) (0 #xA9) (0 #x9A))
    ("an unknown opcode is refused at the first byte, with 1002"
     unknown-opcode
     (0 #x83) (0 #x84) (0 #x85) (0 #x86) (0 #x87)
     (0 #x8B) (0 #x8C) (0 #x8D) (0 #x8E) (0 #x8F) (0 #x03) (0 #x07) (0 #x0B) (0 #x0F))
    ("a control frame not final is refused at the first byte, with 1002"
     control-not-final
     (0 #x08) (0 #x09) (0 #x0A))
    ("an unmasked frame is refused at its second byte, with 1002"
     unmasked
     (1 #x81 #x05) (1 #x82 #x00) (1 #x80 #x7D) (1 #x01 #x7E) (1 #x02 #x7F)
     (1 #x88 #x02) (1 #x89 #x00) (1 #x8A #x7D))
    ("a control frame over 125 bytes is refused at its second byte, with 1002"
     control-too-long
     (1 #x88 #xFE) (1 #x89 #xFE) (1 #x8A #xFE) (1 #x88 #xFF) (1 #x89 #xFF) (1 #x8A #xFF))
    ("a 16-bit length under 126 is refused at its second byte, with 1002"
     not-shortest
     (3 #x82 #xFE #x00 #x00) (3 #x82 #xFE #x00 #x7D ,@key) (3 #x01 #xFE #x00 #x01 ,@key))
    ("a 64-bit length under 65,536 is refused at its sixth byte, with 1002"
     not-shortest
     (7 #x82 #xFF #x00 #x00 #x00 #x00 #x00 #x00)
     (7 #x82 #xFF #x00 #x00 #x00 #x00 #x00 #x00 #xFF #xFF ,@key)
     (7 #x80 #xFF #x00 #x00 #x00 #x00 #x00 #x00 #x00 #x7E ,@key))
    ("a 64-bit length with its top bit set is refused at its first byte, with 1002"
     length-top-bit
     (2 #x82 #xFF #x80) (2 #x82 #xFF #x80 #x00 #x00 #x00 #x00 #x00 #x00 #x00 ,@key)
     (2 #x02 #xFF #xFF #xFF #xFF #xFF #xFF #xFF #xFF #xFF ,@key))))
(define refusal-cases
  (concat (map (lambda (kind) (map (lambda (c) (cons (cadr kind) c)) (cddr kind))) refusals)))

;; refused : Symbol Nat -> Event
(define (refused why at) (list 'refused 1002 why at))

(run-suite "frame"
  (lambda ()
    ;; The suite's headers must be RFC 6455's before any check reads them.
    (unless (for-all (lambda (edge) (equal? (header #x82 (car edge)) (cadr edge))) length-edges)
      (provenance-failure "the suite's headers are not RFC 6455's: the length forms' edges"))

    ;; RFC 6455 §5.7
    (test-equal "RFC 6455's unmasked frames are refused at their second byte, with 1002"
      (map (lambda (f) (list (refused 'unmasked 1))) rfc-unmasked)
      (map (lambda (f) (decoded f '())) rfc-unmasked))

    ;; Headers
    (test-equal "every kind of header, at each length form's edges, is answered once whole, fed whole and a byte at a time"
      (map (lambda (h) (list (alone h) (alone h) '(in-header))) headers)
      (map (lambda (h)
             (let ((bytes (header-bytes h)))
               (list (decoded bytes '()) (decoded bytes (bytewise bytes)) (decoded (but-last bytes) '()))))
           headers))
    (test-equal "the length forms at their edges: 125 in 7 bits, 126 and 65,535 in 16, 65,536 and 2^63 - 1 in 64"
      (map (lambda (edge) (list (list 'header #t 'binary (car edge)) (list 'left (car edge)))) length-edges)
      (map (lambda (edge) (decoded (cadr edge) '())) length-edges))
    (let ((cuts (concat
                  (map (lambda (h)
                         (map (lambda (k) (list h k)) (range 1 (length (header-bytes h)))))
                       headers))))
      (test-equal "a header split at every byte is answered once, in the piece that completes it"
        (map (lambda (c) (list '() (list (car (alone (car c)))) (cadr (alone (car c))))) cuts)
        (map (lambda (c) (in-pieces (header-bytes (car c)) (cdr c))) cuts))
      (test-equal "an empty piece inside a header changes nothing"
        (map (lambda (c) (list '() '() (list (car (alone (car c)))) (cadr (alone (car c))))) cuts)
        (map (lambda (c) (in-pieces (header-bytes (car c)) (list (cadr c) (cadr c)))) cuts)))
    (let ((cuts (concat
                  (map (lambda (h)
                         (let ((n (length (header-bytes h))))
                           (concat
                             (map (lambda (k1) (map (lambda (k2) (list h k1 k2)) (range (+ k1 1) n)))
                                  (range 1 n)))))
                       headers))))
      (test-equal "a header split at every pair of bytes is answered once, in the piece that completes it"
        (map (lambda (c) (list '() '() (list (car (alone (car c)))) (cadr (alone (car c))))) cuts)
        (map (lambda (c) (in-pieces (header-bytes (car c)) (cdr c))) cuts)))

    ;; Refusals
    (for-each
      (lambda (kind)
        (test-equal (car kind)
          (map (lambda (c) (list (list (refused (cadr kind) (car c))) (list (refused (cadr kind) (car c)))))
               (cddr kind))
          (map (lambda (c) (list (decoded (cdr c) '()) (decoded (cdr c) (bytewise (cdr c)))))
               (cddr kind))))
      refusals)
    (test-equal "each refusal split at every byte is refused at the same index"
      (concat
        (map (lambda (c) (map (lambda (k) (list (refused (car c) (cadr c)))) (range 1 (length (cddr c)))))
             refusal-cases))
      (concat
        (map (lambda (c) (map (lambda (k) (decoded (cddr c) (list k))) (range 1 (length (cddr c)))))
             refusal-cases)))
    (test-equal "a refusal is final: fed on, a decoder reads nothing and stays refused"
      '(refused 2 refused 4 (1002 unmasked) refused 9 (1002 unmasked))
      (let ((d (make-frame-decoder))
            (bv (u8-list->bytevector (append '(#x81 #x05) rfc-masked-text))))
        (let*-values (((what next) (frame-read-header! d bv 0 2))
                      ((what2 next2) (frame-read-header! d bv 4 9))
                      ((what3 next3) (frame-read-header! d bv 9 13)))
          (list what next what2 next2 (frame-refusal d) what3 next3 (frame-refusal d)))))))
