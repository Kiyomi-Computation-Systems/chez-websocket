#!r6rs
;;; (websocket frame)'s decoder and encoder against their oracles.
;;;
;;; The oracles are RFC 6455's, read from its raw text: §5.2's framing,
;;; §5.3's masking, §5.1's rules that a client masks every frame and a
;;; server none, §5.5's control frames, and §5.7's examples.  A refusal's
;;; index is the first byte with which no frame a client may send begins.
;;; The suite builds its own frames by §5.2 and §5.3, and stops with a
;;; provenance failure unless they are §5.7's bytes and the length forms'
;;; written out by hand.  Node's ws 7.5.10, a server's decoder, was fed
;;; every case in its pieces, and its encoder was given every payload the
;;; suite encodes.
;;;
;;; - §5.7's examples: the masked ones decode, the unmasked ones are refused.
;;; - Headers of every kind at each length form's edges, whole and a byte at
;;;   a time, split at every byte and every pair of bytes, and with an empty
;;;   piece inside.
;;; - Each refusal at its index, with its 1002: whole, a byte at a time,
;;;   split at every byte, and after a whole frame in the same piece.
;;;   A refusal is final.
;;; - Payloads unmasked at every offset and into any place of a destination;
;;;   frames back to back split at every byte; §5.7's 256-byte and 64 KiB
;;;   messages, masked.
;;; - Which kinds are control frames: a close, a ping and a pong.
;;; - The API: ranges, reads out of turn, a destination's room, the bytes
;;;   left as they were, and two decoders at once.
;;; - What decoding allocates: nothing, per call or per byte.
;;; - The encoder: §5.7's unmasked frames a server sends, byte for byte, and
;;;   every kind it sends at each length form's edges, each one final frame,
;;;   unmasked, its length in its shortest form; a decode of each, masked
;;;   first; a payload from a range; what it refuses: a kind a server never
;;;   sends, a continuation among them, a control frame over 125 bytes, a
;;;   close of one byte, and anything but a range of a bytevector; the
;;;   payload left as it was; and what an encode allocates, whole or from a
;;;   range: its frame, and nothing else.
(import (rnrs) (srfi :64) (ws-testing) (websocket frame))

;; range : Nat Nat -> (Listof Nat)
;; The naturals from `from` up to, but not including, `to`.
(define (range from to)
  (if (>= from to) '() (cons from (range (+ from 1) to))))

;; sub : Bytevector Nat Nat -> Bytevector
;; A copy of the bytes from `from` up to `to`.
(define (sub bv from to)
  (let ((out (make-bytevector (- to from))))
    (bytevector-copy! bv from out 0 (- to from))
    out))

;; repeat : Nat Any -> (Listof Any)
;; A list of n of x.
(define (repeat n x)
  (if (= n 0) '() (cons x (repeat (- n 1) x))))

;; concat : (Listof (Listof Any)) -> (Listof Any)
;; The lists, one after another.
(define (concat lists)
  (fold-right append '() lists))

;; ascii : String -> (Listof Byte)
(define (ascii s)
  (map char->integer (string->list s)))

;; pattern : Nat -> (Listof Byte)
;; n bytes, byte i being i x 37 mod 256: every value, in no simple order.
(define (pattern n)
  (map (lambda (i) (mod (* i 37) 256)) (range 0 n)))

;; --- the suite's frames, by RFC 6455 §5.2 and §5.3 --------------------------

;; §5.7's masking key, and the "Hello" its examples carry.
(define key '(#x37 #xFA #x21 #x3D))
(define hello '(#x48 #x65 #x6C #x6C #x6F))

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

;; masked : (Listof Byte) -> (Listof Byte)
;; The bytes masked with the key: byte i xor the key's byte i mod 4.
(define (masked bytes)
  (let loop ((bytes bytes) (i 0) (out '()))
    (if (null? bytes)
        (reverse out)
        (loop (cdr bytes) (+ i 1) (cons (bitwise-xor (car bytes) (list-ref key (mod i 4))) out)))))

;; A spec is a frame as the suite knows it: (first fin kind payload), its
;; first byte, what a decoder answers for that byte, and its payload bytes.

;; frame : Spec -> (Listof Byte)
;; The spec's whole frame, masked.
(define (frame spec)
  (append (header (car spec) (length (cadddr spec))) (masked (cadddr spec))))

;; stream : (Listof Spec) -> (Listof Byte)
;; The frames back to back.
(define (stream specs)
  (concat (map frame specs)))

;; RFC 6455 §5.7's examples, as its text prints them.
(define rfc-masked-text '(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
(define rfc-masked-pong '(#x8A #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
(define rfc-unmasked
  (list '(#x81 #x05 #x48 #x65 #x6C #x6C #x6F)    ; text, "Hello"
        '(#x01 #x03 #x48 #x65 #x6C)              ; text, "Hel", not final
        '(#x80 #x02 #x6C #x6F)                   ; its continuation, "lo"
        '(#x89 #x05 #x48 #x65 #x6C #x6C #x6F)    ; ping, "Hello"
        '(#x82 #x7E #x01 #x00)                   ; the 256-byte binary message's header
        '(#x82 #x7F #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00)))  ; the 64 KiB one's
(define text-hello (list #x81 #t 'text hello))
(define pong-hello (list #x8A #t 'pong hello))

;; The length forms' headers at their edges (§5.2), written out by hand.
(define length-edges
  (list (list 125 (append '(#x82 #xFD) key))
        (list 126 (append '(#x82 #xFE #x00 #x7E) key))
        (list 65535 (append '(#x82 #xFE #xFF #xFF) key))
        (list 65536 (append '(#x82 #xFF #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00) key))
        (list 9223372036854775807 (append '(#x82 #xFF #x7F #xFF #xFF #xFF #xFF #xFF #xFF #xFF) key))))

;; plain-header : Byte Nat -> (Listof Byte)
;; A server's frame's header (§5.1): its first byte, then the length in its
;; shortest form, the mask bit clear and no key.
(define (plain-header first n)
  (cons first
        (cond ((< n 126) (list n))
              ((< n 65536) (cons 126 (big-endian n 2)))
              (else (cons 127 (big-endian n 8))))))

;; The same edges unmasked, as a server sends them, written out by hand.
(define plain-edges
  (list (list 125 '(#x82 #x7D))
        (list 126 '(#x82 #x7E #x00 #x7E))
        (list 65535 '(#x82 #x7E #xFF #xFF))
        (list 65536 '(#x82 #x7F #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00))))

;; --- what a decoder answers -----------------------------------------------

;; in-pieces : (Listof Byte) (Listof Nat) -> (Listof (U (Listof Event) Stop))
;; The bytes fed to a fresh decoder as pieces of one bytevector, cut at each
;; point (ascending; a point given twice makes an empty piece), as the
;; protocol feeds it: a header's bytes to frame-read-header!, and a
;; payload's to frame-read-payload!, unmasked into a destination at 3.  For
;; each piece, what it answered, in order:
;;   (header Fin Kind Length)   a header, once whole;
;;   (payload Bytevector)       the payload's bytes the piece carried;
;;   (refused Code Why Index)   a refusal, at the index of the byte that
;;                              showed it.
;; Then where the decoder stopped: between frames, in-header, or (left n)
;; in a payload.  A refusal ends the feeding: no later piece is fed, and no
;; stop follows.  So that a decoder that reads nothing cannot loop, a read
;; that goes nowhere answers stuck, and ends the feeding too.
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
              ((> (frame-left d) 0)
               (let* ((dst (make-bytevector (+ 3 (- (car ends) i)) 0))
                      (n (frame-read-payload! d bv i (car ends) dst 3)))
                 (if (<= n 0)
                     (end-with 'stuck)
                     (go (+ i n) (cons (list 'payload (sub dst 3 (+ 3 n))) events) #f))))
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

;; payload? : Any -> Boolean
(define (payload? x)
  (and (pair? x) (eq? (car x) 'payload)))

;; joined : (Listof Bytevector) -> Bytevector
;; The bytevectors, one after another.
(define (joined parts)
  (let ((out (make-bytevector (fold-left + 0 (map bytevector-length parts)))))
    (let loop ((parts parts) (at 0))
      (if (null? parts)
          out
          (begin
            (bytevector-copy! (car parts) 0 out at (bytevector-length (car parts)))
            (loop (cdr parts) (+ at (bytevector-length (car parts)))))))))

;; piece? : (U (Listof Event) Stop) -> Boolean
;; Whether in-pieces answered it for a piece: a list of events, each a pair,
;; and not a stop such as (left n).
(define (piece? p)
  (and (list? p) (or (null? p) (pair? (car p)))))

;; merged : (Listof (U (Listof Event) Stop)) -> (Listof (U Event Stop))
;; The pieces' events in order, each run of payload pieces joined into one,
;; and then the stop, if there is one.
(define (merged pieces)
  (let loop ((items (concat (map (lambda (p) (if (piece? p) p (list p))) pieces))) (out '()))
    (cond ((null? items) (reverse out))
          ((payload? (car items))
           (let run ((items items) (parts '()))
             (if (and (pair? items) (payload? (car items)))
                 (run (cdr items) (cons (cadar items) parts))
                 (loop items (cons (list 'payload (joined (reverse parts))) out)))))
          (else (loop (cdr items) (cons (car items) out))))))

;; decoded : (Listof Byte) (Listof Nat) -> (Listof (U Event Stop))
;; What a decoder answers for the bytes in those pieces, joined.
(define (decoded bytes cuts)
  (merged (in-pieces bytes cuts)))

;; but-last : (Listof Any) -> (Listof Any)
(define (but-last l)
  (reverse (cdr (reverse l))))

;; bytewise : (Listof Byte) -> (Listof Nat)
;; The cuts that make a piece of every byte.
(define (bytewise bytes)
  (range 1 (length bytes)))

;; take : (Listof Any) Nat -> (Listof Any)
;; The list's first k elements.
(define (take l k)
  (if (= k 0) '() (cons (car l) (take (cdr l) (- k 1)))))

;; --- what a decoder should answer, from the specs -------------------------

;; header-event : Spec -> Event
(define (header-event spec)
  (list 'header (cadr spec) (caddr spec) (length (cadddr spec))))

;; positioned : (Listof Spec) -> (Listof (Pair Nat Event))
;; Each event the frames back to back should answer, with the index of the
;; byte that makes it: a header at its last byte, and each payload byte at
;; itself, as (payload Byte).
(define (positioned specs)
  (let loop ((specs specs) (at 0) (out '()))
    (if (null? specs)
        (reverse out)
        (let* ((spec (car specs))
               (h (length (header (car spec) (length (cadddr spec)))))
               (bytes (cadddr spec)))
          (loop (cdr specs)
                (+ at h (length bytes))
                (append (reverse (map (lambda (b i) (cons (+ at h i) (list 'payload b)))
                                      bytes (range 0 (length bytes))))
                        (list (cons (+ at h -1) (header-event spec)))
                        out))))))

;; expected-pieces : (Listof Spec) (Listof Nat) -> (Listof (U (Listof Event) Stop))
;; What in-pieces should answer for the frames back to back, cut at each
;; point: each event in the piece that holds its byte, a piece's payload bytes
;; joined, and then between, since every frame is whole.
(define (expected-pieces specs cuts)
  (let piece ((events (positioned specs))
              (ends (append cuts (list (length (stream specs)))))
              (out '()))
    (if (null? ends)
        (reverse (cons 'between out))
        (let take ((events events) (acc '()))
          (if (and (pair? events) (< (caar events) (car ends)))
              (take (cdr events) (cons (cdar events) acc))
              (piece events (cdr ends) (cons (join-payload (reverse acc)) out)))))))

;; join-payload : (Listof Event) -> (Listof Event)
;; The events, each run of (payload Byte) made one (payload Bytevector).
(define (join-payload events)
  (let loop ((events events) (out '()))
    (cond ((null? events) (reverse out))
          ((eq? (caar events) 'payload)
           (let run ((events events) (bytes '()))
             (if (and (pair? events) (eq? (caar events) 'payload))
                 (run (cdr events) (cons (cadar events) bytes))
                 (loop events (cons (list 'payload (u8-list->bytevector (reverse bytes))) out)))))
          (else (loop (cdr events) (cons (car events) out))))))

;; expected : (Listof Spec) -> (Listof (U Event Stop))
;; What decoded should answer for the frames back to back, however cut.
(define (expected specs)
  (merged (expected-pieces specs '())))

;; expected-events : (Listof Spec) -> (Listof Event)
;; The same, without the stop.
(define (expected-events specs)
  (filter pair? (expected specs)))

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

;; The refusals, each case the index of the byte that shows it, then the
;; bytes: the reason, then the cases.
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

;; The frames of a stream, back to back: every kind, the 7- and 16-bit
;; length forms, and payloads whose lengths are not multiples of four, as
;; two whole messages between control frames.
(define back-to-back
  (list text-hello
        (list #x89 #t 'ping '())
        (list #x02 #f 'binary (pattern 126))
        (list #x80 #t 'continuation '(#xFF))
        pong-hello
        (list #x01 #f 'text (ascii "Hello, world!"))
        (list #x00 #f 'continuation '())
        (list #x80 #t 'continuation (ascii "goodbye"))
        (list #x88 #t 'close '(#x03 #xE8))))

;; §5.7's 256-byte and 64 KiB binary messages, masked.
(define rfc-256 (list #x82 #t 'binary (pattern 256)))
(define rfc-64k (list #x82 #t 'binary (pattern 65536)))

;; Each kind of frame a server sends, as `kinds` has it: final, since each
;; message is one frame, so never a continuation.
(define sent-kinds
  (filter (lambda (k) (and (cadr k) (not (eq? (caddr k) 'continuation)))) kinds))

;; sent-lengths : Symbol -> (Listof Nat)
;; The lengths a kind is encoded at: a data frame's at the length forms'
;; edges but 2^32 and over, whose payload would not fit in a test's memory;
;; a control frame's at its own; and a close's with two bytes for one, since
;; a close's body is empty or begins with its two-byte code (§5.5.1).
(define (sent-lengths kind)
  (case kind
    ((text binary) (filter (lambda (n) (< n 4294967296)) data-lengths))
    ((close) (map (lambda (n) (if (= n 1) 2 n)) control-lengths))
    (else control-lengths)))

;; Every frame the suite encodes, as (first kind length), its payload that
;; many bytes of the pattern.
(define sent
  (concat
    (map (lambda (k) (map (lambda (n) (list (car k) (caddr k) n)) (sent-lengths (caddr k))))
         sent-kinds)))

;; encoded : (List Byte Symbol Nat) -> (Listof Byte)
;; What frame-encode answers for the kind and its payload.
(define (encoded s)
  (bytevector->u8-list (frame-encode (cadr s) (u8-list->bytevector (pattern (caddr s))))))

;; plain : (List Byte Symbol Nat) -> (Listof Byte)
;; The frame a server sends for it, by §5.2.
(define (plain s)
  (append (plain-header (car s) (caddr s)) (pattern (caddr s))))

;; masked-first : (Listof Byte) -> (Listof Byte)
;; A server's frame masked as a client masks its own (§5.3), so that a
;; decoder, which refuses an unmasked frame (§5.1), reads it: the mask bit
;; set, the key after the length, and the payload masked with it.  The
;; length's form is read from the frame's own second byte.
(define (masked-first bytes)
  (let* ((n (bitwise-and (cadr bytes) 127))
         (h (cond ((< n 126) 2) ((= n 126) 4) (else 10))))
    (append (list (car bytes) (bitwise-ior 128 (cadr bytes)))
            (take (cddr bytes) (- h 2))
            key
            (masked (list-tail bytes h)))))

;; assertion-by : (-> Any) -> (U Symbol 'accepted 'not-an-assertion)
;; Who an assertion violation names, when the thunk raises one.
(define (assertion-by thunk)
  (guard (e ((assertion-violation? e) (if (who-condition? e) (condition-who e) 'no-who))
            (#t 'not-an-assertion))
    (thunk)
    'accepted))

(run-suite "frame"
  (lambda ()
    ;; The suite's frames must be RFC 6455's before any check reads them.
    (unless (and (equal? (frame text-hello) rfc-masked-text)
                 (equal? (frame pong-hello) rfc-masked-pong)
                 (for-all (lambda (edge) (equal? (header #x82 (car edge)) (cadr edge))) length-edges)
                 (equal? (append (plain-header #x81 5) hello) (list-ref rfc-unmasked 0))
                 (equal? (append (plain-header #x89 5) hello) (list-ref rfc-unmasked 3))
                 (equal? (plain-header #x82 256) (list-ref rfc-unmasked 4))
                 (equal? (plain-header #x82 65536) (list-ref rfc-unmasked 5))
                 (for-all (lambda (edge) (equal? (plain-header #x82 (car edge)) (cadr edge))) plain-edges))
      (provenance-failure "the suite's frames are not RFC 6455's: §5.7's examples, or the length forms' edges"))

    ;; RFC 6455 §5.7
    (test-equal "RFC 6455's masked text and pong decode to their Hello"
      (list (expected (list text-hello)) (expected (list pong-hello)))
      (list (decoded rfc-masked-text '()) (decoded rfc-masked-pong '())))
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
    (test-equal "after a whole frame in the same piece, each refusal comes a frame later"
      (map (lambda (c) (append (expected-events (list text-hello)) (list (refused (car c) (+ 11 (cadr c))))))
           refusal-cases)
      (map (lambda (c) (decoded (append rfc-masked-text (cddr c)) '())) refusal-cases))
    (test-equal "a refusal is final: fed on, a decoder reads nothing and stays refused"
      '(refused 2 refused 4 (1002 unmasked) refused 9 (1002 unmasked))
      (let ((d (make-frame-decoder))
            (bv (u8-list->bytevector (append '(#x81 #x05) rfc-masked-text))))
        (let*-values (((what next) (frame-read-header! d bv 0 2))
                      ((what2 next2) (frame-read-header! d bv 4 9))
                      ((what3 next3) (frame-read-header! d bv 9 13)))
          (list what next what2 next2 (frame-refusal d) what3 next3 (frame-refusal d)))))

    ;; Payloads
    (let* ((spec (list #x82 #t 'binary (pattern 13)))
           (bytes (frame spec))
           (n (length bytes))
           (ones (map list (range 0 (+ n 1))))
           (pairs (concat (map (lambda (k1) (map (lambda (k2) (list k1 k2)) (range k1 (+ n 1))))
                                     (range 0 (+ n 1))))))
      (test-equal "a payload is unmasked at every offset: split at every byte, and at every pair of bytes"
        (map (lambda (cuts) (expected-pieces (list spec) cuts)) (append ones pairs))
        (map (lambda (cuts) (in-pieces bytes cuts)) (append ones pairs)))
      (test-equal "a frame fed a byte at a time answers each payload byte in its own piece"
        (expected-pieces (list spec) (bytewise bytes))
        (in-pieces bytes (bytewise bytes))))
    (test-equal "a payload is unmasked into any place of its destination, and nothing else there is written"
      (map (lambda (at) (append (repeat at #xEE) hello '(#xEE #xEE))) (range 0 4))
      (map (lambda (at)
             (let ((d (make-frame-decoder))
                   (bv (u8-list->bytevector rfc-masked-text))
                   (dst (make-bytevector (+ at 7) #xEE)))
               (frame-read-header! d bv 0 6)
               (frame-read-payload! d bv 6 11 dst at)
               (bytevector->u8-list dst)))
           (range 0 4)))
    (let* ((bytes (stream back-to-back))
           (cuts (map list (range 0 (+ (length bytes) 1)))))
      (test-equal "frames back to back, of every kind, decode whole and split at every byte"
        (cons (expected back-to-back) (map (lambda (c) (expected-pieces back-to-back c)) cuts))
        (cons (decoded bytes '()) (map (lambda (c) (in-pieces bytes c)) cuts)))
      (test-equal "frames back to back fed a byte at a time"
        (expected-pieces back-to-back (bytewise bytes))
        (in-pieces bytes (bytewise bytes))))
    (let* ((specs (list rfc-256 rfc-64k))
           (bytes (stream specs))
           (edges (append (range 1 20) (range 262 290) (range (- (length bytes) 20) (length bytes)))))
      (test-equal "RFC 6455's 256-byte and 64 KiB binary messages, masked, decode whole, split near each edge, and a byte at a time"
        (list (expected specs)
              (map (lambda (k) (expected-pieces specs (list k))) edges)
              (expected-pieces specs (bytewise bytes)))
        (list (decoded bytes '())
              (map (lambda (k) (in-pieces bytes (list k))) edges)
              (in-pieces bytes (bytewise bytes)))))

    ;; The API
    (let ((bv (u8-list->bytevector rfc-masked-text)))
      (test-equal "a range outside its bytevector, or no bytevector, is an assertion naming frame-read-header!, or frame-read-payload!"
        (append (repeat 7 'frame-read-header!) (repeat 7 'frame-read-payload!))
        (append
          (map (lambda (r) (assertion-by (lambda () (frame-read-header! (make-frame-decoder) (car r) (cadr r) (caddr r)))))
               (list (list bv 1 0) (list bv 0 12) (list bv -1 2) (list bv 12 12)
                     (list bv 0.0 2) (list bv 0 2.0) (list "Hello" 0 5)))
          (map (lambda (r)
                 (let ((d (make-frame-decoder)))
                   (frame-read-header! d bv 0 6)
                   (assertion-by (lambda () (frame-read-payload! d (car r) (cadr r) (caddr r) (make-bytevector 16) 0)))))
               (list (list bv 7 6) (list bv 6 12) (list bv -1 7) (list bv 12 12)
                     (list bv 6.0 11) (list bv 6 11.0) (list "Hello" 0 5)))))
      (test-equal "reading a header with a payload unfinished, or a payload with none left, is an assertion naming the read"
        '(frame-read-header! frame-read-payload! frame-read-payload!)
        (list (let ((d (make-frame-decoder)))
                (frame-read-header! d bv 0 6)
                (assertion-by (lambda () (frame-read-header! d bv 6 11))))
              (assertion-by (lambda () (frame-read-payload! (make-frame-decoder) bv 0 11 (make-bytevector 16) 0)))
              (let ((d (make-frame-decoder)))
                (frame-read-header! d bv 0 6)
                (frame-read-payload! d bv 6 11 (make-bytevector 5) 0)
                (assertion-by (lambda () (frame-read-payload! d bv 11 11 (make-bytevector 5) 0))))))
      (test-equal "a destination without room is an assertion naming frame-read-payload!, and nothing is read or written"
        (list 'frame-read-payload! 'frame-read-payload! 'frame-read-payload! 5 '(#xEE #xEE #xEE #xEE) hello)
        (let ((d (make-frame-decoder))
              (dst (make-bytevector 4 #xEE)))
          (frame-read-header! d bv 0 6)
          (let* ((short (assertion-by (lambda () (frame-read-payload! d bv 6 11 dst 0))))
                 (late (assertion-by (lambda () (frame-read-payload! d bv 6 7 dst 4))))
                 (negative (assertion-by (lambda () (frame-read-payload! d bv 6 7 dst -1))))
                 (left (frame-left d))
                 (untouched (bytevector->u8-list dst))
                 (whole (make-bytevector 5 0)))
            (frame-read-payload! d bv 6 11 whole 0)
            (list short late negative left untouched (bytevector->u8-list whole))))))
    (test-equal "the bytes a decoder reads are left as they were"
      (list rfc-masked-text (stream back-to-back))
      (map (lambda (bytes)
             (let ((bv (u8-list->bytevector bytes))
                   (d (make-frame-decoder))
                   (dst (make-bytevector 200)))
               (let loop ((i 0))
                 (cond ((= i (bytevector-length bv)) (bytevector->u8-list bv))
                       ((> (frame-left d) 0)
                        (let ((n (frame-read-payload! d bv i (bytevector-length bv) dst 0)))
                          (if (> n 0) (loop (+ i n)) 'stuck)))
                       (else (let-values (((what next) (frame-read-header! d bv i (bytevector-length bv))))
                               (if (and (eq? what 'header) (> next i)) (loop next) (bytevector->u8-list bv))))))))
           (list rfc-masked-text (stream back-to-back))))
    ;; The pong is masked with a key of its own, 01 02 03 04, by hand.
    (test-equal "frame-control? answers, of every kind of header, a close's, a ping's and a pong's (§5.5)"
      '(close ping pong)
      (let loop ((ks kinds) (out '()))
        (if (null? ks)
            (reverse out)
            (let ((d (make-frame-decoder)) (bv (u8-list->bytevector (header (car (car ks)) 0))))
              (frame-read-header! d bv 0 (bytevector-length bv))
              (loop (cdr ks) (if (frame-control? d) (cons (caddr (car ks)) out) out))))))
    (test-equal "two decoders at once are each their own"
      (list (list '(header #t text 5) hello) (list '(header #t pong 5) hello))
      (let ((a (make-frame-decoder)) (b (make-frame-decoder))
            (text (u8-list->bytevector rfc-masked-text))
            (pong (u8-list->bytevector '(#x8A #x85 #x01 #x02 #x03 #x04 #x49 #x67 #x6F #x68 #x6E)))
            (from-a (make-bytevector 5 0)) (from-b (make-bytevector 5 0)))
        (frame-read-header! a text 0 3)
        (frame-read-header! b pong 0 4)
        (frame-read-header! a text 3 6)
        (let ((a-header (list 'header (frame-fin? a) (frame-kind a) (frame-length a))))
          (frame-read-header! b pong 4 6)
          (frame-read-payload! a text 6 8 from-a 0)
          (frame-read-payload! b pong 6 9 from-b 0)
          (frame-read-payload! a text 8 11 from-a 2)
          (frame-read-payload! b pong 9 11 from-b 3)
          (list (list a-header (bytevector->u8-list from-a))
                (list (list 'header (frame-fin? b) (frame-kind b) (frame-length b)) (bytevector->u8-list from-b))))))

    ;; What decoding allocates: §5.7's text, a 16-bit and a 64-bit binary
    ;; frame, a ping and a close, 16 times over, about a mebibyte.
    (let* ((specs (concat (repeat 16 (list text-hello (list #x82 #t 'binary (pattern 126)) rfc-64k
                                                    (list #x89 #t 'ping '()) (list #x88 #t 'close '(#x03 #xE8))))))
           (bv (u8-list->bytevector (stream specs)))
           (n (bytevector-length bv))
           (d (make-frame-decoder))
           (dst (make-bytevector 65536))
           ;; feed : Nat -> Integer
           ;; Feeds the stream in pieces of `step` bytes: answers the headers
           ;; read, times 2^30, plus the sum of the payload bytes unmasked;
           ;; or, at a refusal or a read that goes nowhere, -1.
           (feed (lambda (step)
                   (let loop ((i 0) (headers 0) (sum 0))
                     (if (= i n)
                         (+ (* headers 1073741824) sum)
                         (let ((end (min n (+ i step))))
                           (let piece ((j i) (headers headers) (sum sum))
                             (cond ((= j end) (loop end headers sum))
                                   ((> (frame-left d) 0)
                                    (let ((k (frame-read-payload! d bv j end dst 0)))
                                      (let add ((m 0) (sum sum))
                                        (cond ((<= k 0) -1)
                                              ((= m k) (piece (+ j k) headers sum))
                                              (else (add (+ m 1) (+ sum (bytevector-u8-ref dst m))))))))
                                   (else
                                    (let-values (((what next) (frame-read-header! d bv j end)))
                                      (cond ((or (eq? what 'refused) (<= next j)) -1)
                                            ((eq? what 'header) (piece next (+ headers 1) sum))
                                            (else (piece next headers sum))))))))))))
           (whole (lambda () (feed n)))
           (one-by-one (lambda () (feed 1))))
      (test-equal "decoding allocates nothing, per call or per byte"
        (let ((answer (+ (* (length specs) 1073741824)
                         (fold-left + 0 (concat (map cadddr specs))))))
          (list answer answer 0 0))
        (list (whole) (one-by-one) (allocated whole) (allocated one-by-one))))

    ;; The encoder.  §5.7's fragmented message is the one unmasked example a
    ;; server never sends: each of its messages is one frame.
    (test-equal "RFC 6455's unmasked frames a server sends are encoded byte for byte: Hello as text and as a ping, and the 256-byte and 64 KiB binary messages"
      (list (list-ref rfc-unmasked 0) (list-ref rfc-unmasked 3)
            (append (list-ref rfc-unmasked 4) (pattern 256))
            (append (list-ref rfc-unmasked 5) (pattern 65536)))
      (map (lambda (kind bytes) (bytevector->u8-list (frame-encode kind (u8-list->bytevector bytes))))
           '(text ping binary binary)
           (list hello hello (pattern 256) (pattern 65536))))
    (test-equal "the length forms at their edges, unmasked: 125 in 7 bits, 126 and 65,535 in 16, 65,536 in 64"
      (map (lambda (edge) (list (cadr edge) (+ (length (cadr edge)) (car edge)))) plain-edges)
      (map (lambda (edge)
             (let ((bytes (bytevector->u8-list (frame-encode 'binary (make-bytevector (car edge) 0)))))
               (list (take bytes (length (cadr edge))) (length bytes))))
           plain-edges))
    (test-equal "every kind a server sends, at each length form's edges, is one final frame, unmasked, its length in its shortest form"
      (map plain sent)
      (map encoded sent))
    (test-equal "a decode of each encode, masked first, answers its kind, its length and its payload"
      (map (lambda (s) (expected (list (list (car s) #t (cadr s) (pattern (caddr s)))))) sent)
      (map (lambda (s) (decoded (masked-first (encoded s)) '())) sent))
    (let ((bv (u8-list->bytevector (pattern 12))))
      (test-equal "a payload from a range of its bytevector is encoded from those bytes alone"
        (list (append (plain-header #x82 5) (take (list-tail (pattern 12) 3) 5))
              (plain-header #x82 0)
              (plain-header #x81 0)
              (append (plain-header #x82 12) (pattern 12)))
        (map (lambda (args) (bytevector->u8-list (apply frame-encode args)))
             (list (list 'binary bv 3 8) (list 'binary bv 0 0) (list 'text bv 12 12) (list 'binary bv 0 12))))
      (test-equal "a continuation, or any kind but the five a server sends, is an assertion naming frame-encode: each message is one final frame"
        '(frame-encode frame-encode frame-encode frame-encode)
        (map (lambda (kind) (assertion-by (lambda () (frame-encode kind bv))))
             '(continuation reserved #f 1)))
      (test-equal "a control frame over 125 bytes is an assertion naming frame-encode"
        '(frame-encode frame-encode frame-encode frame-encode)
        (map (lambda (kind n) (assertion-by (lambda () (frame-encode kind (make-bytevector n 0)))))
             '(close ping pong close)
             '(126 126 126 65536)))
      (test-equal "a close of one byte is an assertion naming frame-encode: a close's body begins with its two-byte code"
        '(frame-encode frame-encode)
        (list (assertion-by (lambda () (frame-encode 'close (make-bytevector 1 0))))
              (assertion-by (lambda () (frame-encode 'close bv 3 4)))))
      (test-equal "a range outside its bytevector, or no bytevector, is an assertion naming frame-encode"
        (repeat 8 'frame-encode)
        (append (map (lambda (r) (assertion-by (lambda () (frame-encode 'binary bv (car r) (cadr r)))))
                     '((1 0) (0 13) (-1 2) (13 13) (0.0 2) (0 2.0)))
                (list (assertion-by (lambda () (frame-encode 'text "Hello")))
                      (assertion-by (lambda () (frame-encode 'text "Hello" 0 0)))))))
    (test-equal "an encode leaves its payload's bytevector as it was"
      (map (lambda (s) (pattern (caddr s))) sent)
      (map (lambda (s)
             (let ((bv (u8-list->bytevector (pattern (caddr s)))))
               (frame-encode (cadr s) bv)
               (bytevector->u8-list bv)))
           sent))
    ;; Each frame's size is its header's and its payload's, by §5.2.  The
    ;; range is the payload with three bytes before it and one after.
    (test-equal "an encode allocates its frame, and nothing else, from a whole bytevector or a range of one"
      (let ((sizes (map (lambda (s)
                          (let ((size (+ (length (plain-header (car s) (caddr s))) (caddr s))))
                            (allocated (lambda () (keep! (make-bytevector size))))))
                        sent)))
        (append sizes sizes))
      (append
        (map (lambda (s)
               (let ((bv (u8-list->bytevector (pattern (caddr s)))))
                 (allocated (lambda () (keep! (frame-encode (cadr s) bv))))))
             sent)
        (map (lambda (s)
               (let ((bv (u8-list->bytevector (append '(1 2 3) (pattern (caddr s)) '(4)))))
                 (allocated (lambda () (keep! (frame-encode (cadr s) bv 3 (+ 3 (caddr s))))))))
             sent)))))
