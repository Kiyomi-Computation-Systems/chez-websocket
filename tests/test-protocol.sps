#!r6rs
;;; (websocket protocol)'s step against its oracles (M3.1): messages, control
;;; frames, the cap, UTF-8, failing, a client's close, sending, and reading on.
;;;
;;; The oracles:
;;; - RFC 6455, read from its raw text: §5.4's fragments, §5.5's control
;;;   frames, §5.5.1's close, answered with a close, its body empty or a
;;;   two-byte code first; §5.5.2's ping, answered with a pong carrying its
;;;   payload; §5.6's text, UTF-8; §5.7's examples; §7.1.7's failing, a close
;;;   with a code and then the stream closed, nothing read after it;
;;;   §7.1.5 and §7.1.6, a connection that closed with no close received is
;;;   told 1006 and an empty reason; §7.1.4, a close each way before the
;;;   stream closes is clean; §7.4.1's codes, 1000 to 1003 and 1007 to 1011
;;;   an endpoint may send, 1005 told for a close with no code; §7.4.2's
;;;   3000 to 4999; and §8.1, text not UTF-8 failed with 1007.
;;; - RFC 3629 §4's grammar, the rows at their edges and where a byte is
;;;   refused, as M1.3's suite has them.
;;; - Decision 0001: the cap, 1 MiB, a frame past it failed with 1009 before
;;;   its payload is held; reading on, stopped once a cap's worth is queued.
;;;   Its amendment of 2026-10-05, by form: reading stops at 16 queued
;;;   messages too.  The same form moved a client's close from M3.2 to here
;;;   (the milestone plan's amendment).
;;; - The design's §5: the events and actions, a message's kind its first
;;;   frame's, and the failures' codes.
;;; The suite builds a client's frames by §5.2 and §5.3, and the server's by
;;; §5.2, and stops with a provenance failure unless they are §5.7's bytes.
;;; Node's ws 7.5.10 was fed every case in its pieces (m3-mutations.md).
;;;
;;; A step is fed pieces of one bytevector, cut at points; a step that ends
;;; the connection ends the feeding, as the binding closes the stream.
(import (rnrs) (srfi :64) (ws-testing) (websocket limits) (websocket protocol)
        (only (chezscheme) make-guardian collect collect-maximum-generation))

;; range : Nat Nat -> (Listof Nat)
;; The naturals from `from` up to, but not including, `to`.
(define (range from to)
  (let loop ((k (- to 1)) (out '()))
    (if (< k from) out (loop (- k 1) (cons k out)))))

;; repeat : Nat Any -> (Listof Any)
(define (repeat n x)
  (let loop ((n n) (out '()))
    (if (= n 0) out (loop (- n 1) (cons x out)))))

;; concat : (Listof (Listof Any)) -> (Listof Any)
(define (concat lists)
  (fold-right append '() lists))

;; ascii : String -> (Listof Byte)
(define (ascii s)
  (map char->integer (string->list s)))

;; pattern : Nat -> (Listof Byte)
;; n bytes, byte i being i x 37 mod 256: every value, in no simple order.
(define (pattern n)
  (map (lambda (i) (mod (* i 37) 256)) (range 0 n)))

;; text-pattern : Nat -> (Listof Byte)
;; n bytes of ASCII, byte i being i x 37 mod 128: UTF-8 whatever its length.
(define (text-pattern n)
  (map (lambda (i) (mod (* i 37) 128)) (range 0 n)))

;; take : (Listof Any) Nat -> (Listof Any)
(define (take l k)
  (if (= k 0) '() (cons (car l) (take (cdr l) (- k 1)))))

;; big-endian : Nat Nat -> (Listof Byte)
;; n as k bytes, the most significant first: §5.2's network byte order.
(define (big-endian n k)
  (let loop ((n n) (k k) (out '()))
    (if (= k 0) out (loop (div n 256) (- k 1) (cons (mod n 256) out)))))

;; bv : (Listof Byte) -> Bytevector
(define bv u8-list->bytevector)

;; --- the frames, by RFC 6455 §5.2 and §5.3 ----------------------------------

;; §5.7's masking key, and the "Hello" its examples carry.
(define key '(#x37 #xFA #x21 #x3D))
(define hello (ascii "Hello"))

;; length-bytes : Nat Byte -> (Listof Byte)
;; The second byte with the length in its shortest form, the mask bit's
;; value given, then the extended length.
(define (length-bytes n mask)
  (cond ((< n 126) (list (+ mask n)))
        ((< n 65536) (cons (+ mask 126) (big-endian n 2)))
        (else (cons (+ mask 127) (big-endian n 8)))))

;; masked : (Listof Byte) -> (Listof Byte)
;; The bytes masked with the key: byte i xor the key's byte i mod 4.
(define (masked bytes)
  (let loop ((bytes bytes) (i 0) (out '()))
    (if (null? bytes)
        (reverse out)
        (loop (cdr bytes) (+ i 1)
              (cons (bitwise-xor (car bytes) (list-ref key (mod i 4))) out)))))

;; frame : Byte (Listof Byte) -> (Listof Byte)
;; A client's frame: its first byte, the length masked, the key, the payload
;; masked.
(define (frame first payload)
  (append (list first) (length-bytes (length payload) 128) key (masked payload)))

;; header : Byte Nat -> (Listof Byte)
;; A client's frame's header alone, for a payload of n bytes.
(define (header first n)
  (append (list first) (length-bytes n 128) key))

;; server-frame : Byte (Listof Byte) -> (Listof Byte)
;; The server's frame: its first byte, the length unmasked, the payload.
(define (server-frame first payload)
  (append (list first) (length-bytes (length payload) 0) payload))

;; RFC 6455 §5.7's examples, as its text prints them.
(define rfc-masked-text '(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
(define rfc-masked-pong '(#x8A #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58))
(define rfc-text '(#x81 #x05 #x48 #x65 #x6C #x6C #x6F))
(define rfc-hel '(#x01 #x03 #x48 #x65 #x6C))
(define rfc-lo '(#x80 #x02 #x6C #x6F))
(define rfc-ping '(#x89 #x05 #x48 #x65 #x6C #x6C #x6F))
(define rfc-256-header '(#x82 #x7E #x01 #x00))
(define rfc-64k-header '(#x82 #x7F #x00 #x00 #x00 #x00 #x00 #x01 #x00 #x00))

;; --- what a connection answers ----------------------------------------------

;; lim : Nat Nat -> WebsocketLimits
;; The default limits with this cap and this many messages queued.
(define (lim cap queue)
  (websocket-limits-with default-websocket-limits
    (list (cons 'max-message-bytes cap) (cons 'max-queue queue))))

;; The default cap, and a queue no message check fills by count.
(define open (lim 1048576 100000))

;; closed? : (Listof Action) -> Boolean
;; Whether the actions end the connection.
(define (closed? actions)
  (exists (lambda (a) (eq? (car a) 'closed)) actions))

;; run : Limits (Listof Byte) (Listof Nat) -> (Listof Action)
;; The bytes fed to a new connection as reads of one bytevector, cut at each
;; point (ascending; a point given twice makes an empty read): every step's
;; actions, in order.  A step that ends the connection ends the feeding.
(define (run limits bytes cuts)
  (let ((v (bv bytes)))
    (let loop ((s (make-ws-state limits)) (from 0)
               (ends (append cuts (list (length bytes)))) (out '()))
      (if (null? ends)
          (concat (reverse out))
          (let-values (((s actions) (ws-step s (list 'bytes v from (car ends)))))
            (if (closed? actions)
                (concat (reverse (cons actions out)))
                (loop s (car ends) (cdr ends) (cons actions out))))))))

;; bytewise : (Listof Byte) -> (Listof Nat)
;; The cuts that make a read of every byte.
(define (bytewise bytes)
  (range 1 (length bytes)))

;; any-pieces : Limits (Listof Byte) -> (Listof (Listof Action))
;; The actions for the bytes read whole, a byte at a time, and cut once at
;; every point, the first and last among them.
(define (any-pieces limits bytes)
  (append (list (run limits bytes '()) (run limits bytes (bytewise bytes)))
          (map (lambda (k) (run limits bytes (list k))) (range 0 (+ 1 (length bytes))))))

;; as-any-pieces : (Listof Action) (Listof Byte) -> (Listof (Listof Action))
;; What any-pieces should answer: the same actions, each way.
(define (as-any-pieces expected bytes)
  (repeat (+ 3 (length bytes)) expected))

;; ended-at : Limits (Listof Byte) -> (U Nat 'never)
;; Fed a byte at a time: the index of the byte whose step ends the
;; connection.
(define (ended-at limits bytes)
  (let ((v (bv bytes)))
    (let loop ((s (make-ws-state limits)) (i 0))
      (if (= i (length bytes))
          'never
          (let-values (((s actions) (ws-step s (list 'bytes v i (+ i 1)))))
            (if (closed? actions) i (loop s (+ i 1))))))))

;; What a connection should answer.
(define (deliver kind bytes) (list 'deliver kind (bv bytes)))
(define (wrote first payload) (list 'write (bv (server-frame first payload))))
(define (pong payload) (wrote #x8A payload))
(define no-bytes (bv '()))

;; failed : Nat Symbol -> (Listof Action)
;; Failing (§7.1.7): a close with the code, the stream closed, the reason
;; logged, and 1006 told, since no close came (§7.1.5).
(define (failed code why)
  (list (wrote #x88 (big-endian code 2)) '(close-stream)
        (list 'log 'failed code why) (list 'closed 1006 no-bytes #f)))

;; answered : Nat (Listof Byte) -> (Listof Action)
;; A close received with a code, answered with that code (§5.5.1), the
;; stream closed, and the code and reason told, cleanly.
(define (answered code reason)
  (list (wrote #x88 (big-endian code 2)) '(close-stream)
        (list 'closed code (bv reason) #t)))

;; An empty close received, answered with an empty close, and 1005 told.
(define answered-empty
  (list (wrote #x88 '()) '(close-stream) (list 'closed 1005 no-bytes #t)))

;; step* : WsState (Listof Event) -> (Listof (Listof Action))
;; Each event stepped in turn on the state: each step's actions.
(define (step* s events)
  (if (null? events)
      '()
      (let-values (((s actions) (ws-step s (car events))))
        (cons actions (step* s (cdr events))))))

;; read-event : (Listof Byte) -> Event
(define (read-event bytes)
  (let ((v (bv bytes))) (list 'bytes v 0 (bytevector-length v))))

;; refusal : (-> Any) -> (U 'accepted (List 'refused Symbol))
;; (refused who) if the thunk raised an assertion violation, and accepted if it
;; returned, with however many values: a step answers two.
(define (refusal thunk)
  (guard (e ((assertion-violation? e)
             (list 'refused (and (who-condition? e) (condition-who e)))))
    (call-with-values thunk (lambda answers 'accepted))))

;; RFC 3629 §4's rows at their edges: each code point's bytes.
(define utf8-edges
  '((#x00) (#x7F) (#xC2 #x80) (#xDF #xBF) (#xE0 #xA0 #x80) (#xE0 #xBF #xBF)
    (#xE1 #x80 #x80) (#xEC #xBF #xBF) (#xED #x80 #x80) (#xED #x9F #xBF)
    (#xEE #x80 #x80) (#xEF #xBF #xBF) (#xF0 #x90 #x80 #x80) (#xF0 #xBF #xBF #xBF)
    (#xF1 #x80 #x80 #x80) (#xF3 #xBF #xBF #xBF) (#xF4 #x80 #x80 #x80) (#xF4 #x8F #xBF #xBF)))

;; Bytes no character can go on with, each with the index of the byte that
;; is refused (§4): a lone tail; C0, C1 and F5 to FF, which begin nothing;
;; an overlong, a surrogate and a code point past U+10FFFF, each refused at
;; its second byte.
(define utf8-refusals
  '(((#x80) 0) ((#xC0 #x80) 0) ((#xC1 #xBF) 0) ((#xF5 #x80) 0) ((#xFF) 0)
    ((#xE0 #x9F #xBF) 1) ((#xED #xA0 #x80) 1) ((#xF0 #x8F #xBF #xBF) 1) ((#xF4 #x90 #x80 #x80) 1)))

;; The codes an endpoint may send (§7.4.1, §7.4.2), and some it may not.
(define sendable-codes '(1000 1001 1002 1003 1007 1008 1009 1010 1011 3000 3999 4000 4999))
(define unsendable-codes '(0 999 1004 1005 1006 1012 1013 1014 1015 1016 2999 5000 65535))

(run-suite "protocol"
  (lambda ()
    (unless (and (equal? (frame #x81 hello) rfc-masked-text)
                 (equal? (frame #x8A hello) rfc-masked-pong)
                 (equal? (server-frame #x81 hello) rfc-text)
                 (equal? (server-frame #x01 (ascii "Hel")) rfc-hel)
                 (equal? (server-frame #x80 (ascii "lo")) rfc-lo)
                 (equal? (server-frame #x89 hello) rfc-ping)
                 (equal? (take (server-frame #x82 (pattern 256)) 4) rfc-256-header)
                 (equal? (take (server-frame #x82 (pattern 65536)) 10) rfc-64k-header))
      (provenance-failure "the suite's frames are not RFC 6455 §5.7's"))

    ;; --- messages (§5.4, §5.6) ---
    (test-equal "RFC 6455's masked Hello is delivered whole, as text: its UTF-8 bytes"
                (list (deliver 'text hello)) (run open rfc-masked-text '()))
    (test-equal "a message in one frame, text or binary, at each length form's edges, is delivered whole"
                (map (lambda (n) (list (deliver 'text (text-pattern n)) (deliver 'binary (pattern n))))
                     '(0 1 125 126 65535 65536))
                (map (lambda (n)
                       (run open (append (frame #x81 (text-pattern n)) (frame #x82 (pattern n))) '()))
                     '(0 1 125 126 65535 65536)))
    (test-equal "§5.7's fragmented Hello, masked, is delivered whole once its final frame comes, and not before"
                (list '() (list (deliver 'text hello)))
                (list (run open (frame #x01 (ascii "Hel")) '())
                      (run open (append (frame #x01 (ascii "Hel")) (frame #x80 (ascii "lo"))) '())))
    (test-equal "a fragmented message is delivered whole, of its first frame's kind, whatever its fragments: empty ones, one byte each, and the length forms' edges"
                (list (list (deliver 'binary '(1 2 3)))
                      (list (deliver 'text (ascii "abcdefghij")))
                      (list (deliver 'binary (append (pattern 125) (pattern 126) (pattern 65535) (pattern 65536)))))
                (list (run open (append (frame #x02 '()) (frame #x00 '(1 2)) (frame #x00 '())
                                        (frame #x00 '(3)) (frame #x80 '()))
                           '())
                      (run open (append (frame #x01 (ascii "a"))
                                        (concat (map (lambda (c) (frame #x00 (list c))) (ascii "bcdefghi")))
                                        (frame #x80 (ascii "j")))
                           '())
                      (run open (append (frame #x02 (pattern 125)) (frame #x00 (pattern 126))
                                        (frame #x00 (pattern 65535)) (frame #x80 (pattern 65536)))
                           '())))
    (let* ((stream (append (frame #x81 hello)
                           (frame #x02 '(1 2)) (frame #x89 '(9)) (frame #x80 '(3))
                           (frame #x8A '(7 7)) (frame #x89 '())
                           (frame #x01 (ascii "Hel")) (frame #x8A '()) (frame #x00 '())
                           (frame #x89 hello) (frame #x80 (ascii "lo"))
                           (frame #x81 '())))
           (expected (list (deliver 'text hello) (pong '(9)) (deliver 'binary '(1 2 3))
                           (pong '()) (pong hello) (deliver 'text hello) (deliver 'text '()))))
      (test-equal "messages back to back, with control frames alone and between fragments, read whole, a byte at a time, and cut at every point"
                  (as-any-pieces expected stream) (any-pieces open stream))
      (let ((short (append (frame #x01 (ascii "He")) (frame #x89 '(1)) (frame #x80 (ascii "y")))))
        (test-equal "a fragmented message with a ping between, cut at every pair of points"
                    (map (lambda (c) (list (pong '(1)) (deliver 'text (ascii "Hey"))))
                         (concat (map (lambda (i) (map (lambda (j) (list i j)) (range i (+ 1 (length short)))))
                                      (range 0 (+ 1 (length short))))))
                    (map (lambda (c) (run open short c))
                         (concat (map (lambda (i) (map (lambda (j) (list i j)) (range i (+ 1 (length short)))))
                                      (range 0 (+ 1 (length short)))))))))

    ;; --- a message's frames in order (§5.4) ---
    (test-equal "a continuation with no message begun fails 1002, at its header: first, or after a message has ended, final or not"
                (list (failed 1002 'continuation-without-message)
                      (append (list (deliver 'text hello)) (failed 1002 'continuation-without-message))
                      (failed 1002 'continuation-without-message)
                      (- (length (header #x80 3)) 1))
                (list (run open (frame #x80 '(1 2 3)) '())
                      (run open (append (frame #x81 hello) (frame #x80 (ascii "lo"))) '())
                      (run open (frame #x00 '(1 2 3)) '())
                      (ended-at open (frame #x80 '(1 2 3)))))
    (test-equal "a text or binary frame while a message is unfinished fails 1002, at its header"
                (list (failed 1002 'message-unfinished)
                      (failed 1002 'message-unfinished)
                      (failed 1002 'message-unfinished)
                      (+ (length (frame #x01 (ascii "Hel"))) (length (header #x81 2)) -1))
                (list (run open (append (frame #x01 (ascii "Hel")) (frame #x81 (ascii "lo"))) '())
                      (run open (append (frame #x02 '(1)) (frame #x01 '(2))) '())
                      (run open (append (frame #x01 '(65)) (frame #x00 '(66)) (frame #x02 '(1))) '())
                      (ended-at open (append (frame #x01 (ascii "Hel")) (frame #x81 (ascii "lo"))))))

    ;; --- control frames (§5.5) ---
    (test-equal "a ping is answered at once with a pong carrying its payload: §5.7's Hello, and 0, 1 and 125 bytes"
                (list (list (pong hello)) (list (pong '())) (list (pong '(0))) (list (pong (pattern 125))))
                (list (run open (frame #x89 hello) '()) (run open (frame #x89 '()) '())
                      (run open (frame #x89 '(0)) '()) (run open (frame #x89 (pattern 125)) '())))
    (test-equal "a pong is answered with nothing, alone or between fragments: §5.7's masked pong"
                (list '() (list (deliver 'text hello)))
                (list (run open rfc-masked-pong '())
                      (run open (append (frame #x01 (ascii "Hel")) rfc-masked-pong (frame #x80 (ascii "lo"))) '())))
    (test-equal "a ping between a message's fragments is answered before the message is delivered"
                (list (pong '(1 2)) (deliver 'binary '(5 6)))
                (run open (append (frame #x02 '(5)) (frame #x89 '(1 2)) (frame #x80 '(6))) '()))

    ;; --- the cap (0001) ---
    (let ((L (lim 1000 100000)))
      (test-equal "a message of the cap's bytes is delivered; a frame one byte past it fails 1009 at its header, before its payload comes"
                  (list (list (deliver 'binary (pattern 1000)) '(read-stop))
                        (failed 1009 'message-too-big)
                        (- (length (header #x82 1001)) 1))
                  (list (run L (frame #x82 (pattern 1000)) '())
                        (run L (header #x82 1001) '())
                        (ended-at L (frame #x82 (pattern 1001)))))
      (test-equal "fragments that take a message past the cap fail 1009 at that fragment's header; up to it, the message is delivered; control frames between them do not count"
                  (list (list (deliver 'binary (pattern 1000)) '(read-stop))
                        (failed 1009 'message-too-big)
                        (+ (length (frame #x02 (pattern 600))) (length (header #x80 401)) -1)
                        (list (pong (pattern 125)) (deliver 'text (text-pattern 1000)) '(read-stop)))
                  (list (run L (append (frame #x02 (take (pattern 1000) 600))
                                       (frame #x80 (list-tail (pattern 1000) 600)))
                             '())
                        (run L (append (frame #x02 (pattern 600)) (header #x80 401)) '())
                        (ended-at L (append (frame #x02 (pattern 600)) (frame #x80 (pattern 401))))
                        (run L (append (frame #x01 (take (text-pattern 1000) 600)) (frame #x89 (pattern 125))
                                       (frame #x80 (list-tail (text-pattern 1000) 600)))
                             '()))))
    (test-equal "the default cap, 1 MiB: 1,048,576 bytes are delivered, and reading stops with a cap's worth queued; a frame announcing 1,048,577 fails 1009 at its header"
                (list (list (deliver 'binary (pattern 1048576)) '(read-stop))
                      (failed 1009 'message-too-big))
                (list (run default-websocket-limits (frame #x82 (pattern 1048576)) '())
                      (run default-websocket-limits (header #x82 1048577) '())))
    (test-equal "a frame announcing 2^63 - 1 bytes fails 1009 at its header"
                (failed 1009 'message-too-big)
                (run open (append '(#x82 #xFF #x7F #xFF #xFF #xFF #xFF #xFF #xFF #xFF) key) '()))

    ;; --- UTF-8 (§5.6, §8.1) ---
    (test-equal "every row of RFC 3629 §4 at its edges, as text, is delivered; and U+FEFF first is delivered with it"
                (list (list (deliver 'text (concat utf8-edges)))
                      (list (deliver 'text '(#xEF #xBB #xBF #x41))))
                (list (run open (frame #x81 (concat utf8-edges)) '())
                      (run open (frame #x81 '(#xEF #xBB #xBF #x41)) '())))
    (test-equal "a byte no character can go on with fails 1007 at once, at the step that brings it, though the message has not ended"
                (map (lambda (r)
                       (list (failed 1007 'text-not-utf8)
                             (+ (length (header #x01 (+ 2 (length (car r))))) 1 (cadr r))))
                     utf8-refusals)
                (map (lambda (r)
                       (let ((stream (frame #x01 (append '(#x41) (car r) '(#x42)))))
                         (list (run open stream '()) (ended-at open stream))))
                     utf8-refusals))
    (test-equal "a character split between fragments is whole: € and U+10FFFF, split at every byte"
                (append (map (lambda (k) (list (deliver 'text '(#x41 #xE2 #x82 #xAC)))) '(0 1 2 3))
                        (map (lambda (k) (list (deliver 'text '(#xF4 #x8F #xBF #xBF)))) '(0 1 2 3 4)))
                (append (map (lambda (k)
                               (let ((c '(#x41 #xE2 #x82 #xAC)))
                                 (run open (append (frame #x01 (take c (+ k 1))) (frame #x80 (list-tail c (+ k 1)))) '())))
                             '(0 1 2 3))
                        (map (lambda (k)
                               (let ((c '(#xF4 #x8F #xBF #xBF)))
                                 (run open (append (frame #x01 (take c k)) (frame #x80 (list-tail c k))) '())))
                             '(0 1 2 3 4))))
    (test-equal "a text message that ends mid-character fails 1007 at its final frame's end"
                (list (failed 1007 'text-not-utf8)
                      (- (length (frame #x81 '(#x41 #xE2 #x82))) 1)
                      (failed 1007 'text-not-utf8)
                      (+ (length (frame #x01 '(#xE2 #x82))) (length (header #x80 0)) -1))
                (list (run open (frame #x81 '(#x41 #xE2 #x82)) '())
                      (ended-at open (frame #x81 '(#x41 #xE2 #x82)))
                      (run open (append (frame #x01 '(#xE2 #x82)) (frame #x80 '())) '())
                      (ended-at open (append (frame #x01 '(#xE2 #x82)) (frame #x80 '())))))
    (test-equal "binary is not checked: bytes no text may hold are delivered"
                (list (deliver 'binary '(#xFF #xC0 #x80 #xED #xA0 #x80 #xE2)))
                (run open (frame #x82 '(#xFF #xC0 #x80 #xED #xA0 #x80 #xE2)) '()))

    ;; --- failing (§7.1.7) ---
    (test-equal "each refusal of the frame decoder fails 1002, its reason logged"
                (list (failed 1002 'reserved-bit) (failed 1002 'unknown-opcode)
                      (failed 1002 'control-not-final) (failed 1002 'unmasked)
                      (failed 1002 'control-too-long) (failed 1002 'not-shortest)
                      (failed 1002 'length-top-bit))
                (map (lambda (bytes) (run open bytes '()))
                     (list (frame #xC1 hello) (frame #x83 hello) (frame #x09 hello)
                           rfc-text (header #x89 126)
                           (append '(#x82 #xFE #x00 #x7D) key)
                           (append '(#x82 #xFF #x80 #x00 #x00 #x00 #x00 #x00 #x00 #x00) key))))
    (test-equal "after failing, nothing more is read: the rest of the read answers nothing"
                (list (failed 1002 'unknown-opcode) (failed 1009 'message-too-big)
                      (failed 1007 'text-not-utf8))
                (list (run open (append (frame #x83 '()) (frame #x89 hello) (frame #x81 hello)) '())
                      (run (lim 10 100) (append (frame #x82 (pattern 11)) (frame #x89 hello)) '())
                      (run open (append (frame #x81 '(#xFF)) (frame #x89 hello)) '())))

    ;; --- a client's close (§5.5.1; 0001's amendment) ---
    (test-equal "a close is answered with a close of its code and the stream closed, and the code and reason are told, cleanly: each code an endpoint may send"
                (map (lambda (code) (answered code (ascii "bye"))) sendable-codes)
                (map (lambda (code) (run open (frame #x88 (append (big-endian code 2) (ascii "bye"))) '()))
                     sendable-codes))
    (test-equal "a close of a code alone, and of a reason of 123 bytes, the most a close holds, told whole"
                (list (answered 1000 '()) (answered 4000 (concat (repeat 41 '(#xE2 #x82 #xAC)))))
                (list (run open (frame #x88 '(#x03 #xE8)) '())
                      (run open (frame #x88 (append '(#x0F #xA0) (concat (repeat 41 '(#xE2 #x82 #xAC))))) '())))
    (test-equal "an empty close is answered with an empty close, and 1005 is told"
                answered-empty (run open (frame #x88 '()) '()))
    (test-equal "a close of one byte fails 1002"
                (failed 1002 'close-body-one-byte) (run open (frame #x88 '(#x03)) '()))
    (test-equal "a close with a code an endpoint may not send fails 1002"
                (map (lambda (code) (failed 1002 'close-code-not-sendable)) unsendable-codes)
                (map (lambda (code) (run open (frame #x88 (big-endian code 2)) '())) unsendable-codes))
    (test-equal "a close whose reason is not UTF-8 fails 1007: a byte no character goes on with, or a reason ending mid-character"
                (list (failed 1007 'close-reason-not-utf8) (failed 1007 'close-reason-not-utf8))
                (list (run open (frame #x88 '(#x03 #xE8 #x41 #xFF)) '())
                      (run open (frame #x88 '(#x03 #xE8 #x41 #xE2 #x82)) '())))
    (test-equal "a close between a message's fragments: the message unfinished is not delivered, and nothing after the close is read, a ping among it (§5.5.2)"
                (answered 1001 '())
                (run open (append (frame #x01 (ascii "Hel")) (frame #x88 '(#x03 #xE9))
                                  (frame #x89 hello) (frame #x80 (ascii "lo")))
                     '()))

    ;; --- sending ---
    (let ((s (make-ws-state open)))
      (test-equal "a send writes its message as one frame: text in UTF-8 from its string, as §5.7's Hello; binary as given, as §5.7's 256-byte and 64 KiB messages"
                  (list (list (list 'write (bv rfc-text)))
                        (list (wrote #x82 (pattern 256)))
                        (list (wrote #x82 (pattern 65536))))
                  (step* s (list '(send text "Hello")
                                 (list 'send 'binary (bv (pattern 256)))
                                 (list 'send 'binary (bv (pattern 65536)))))))
    (test-equal "U+FEFF first is sent with it, and an empty text and an empty binary are frames of no payload"
                (list (list (wrote #x81 '(#xEF #xBB #xBF #x41))) (list (wrote #x81 '())) (list (wrote #x82 '())))
                (step* (make-ws-state open)
                       (list (list 'send 'text (string (integer->char #xFEFF) #\A))
                             '(send text "")
                             (list 'send 'binary no-bytes))))
    (test-equal "a send between a message's fragments leaves the message whole"
                (list '() (list (wrote #x82 '(9))) (list (deliver 'text hello)))
                (step* (make-ws-state open)
                       (list (read-event (frame #x01 (ascii "Hel")))
                             (list 'send 'binary (bv '(9)))
                             (read-event (frame #x80 (ascii "lo"))))))
    (test-equal "a send of another kind, or a payload not of its kind, or after the connection has ended, is an assertion naming ws-step"
                '((refused ws-step) (refused ws-step) (refused ws-step) (refused ws-step) (refused ws-step))
                (list (refusal (lambda () (ws-step (make-ws-state open) (list 'send 'ping (bv '(1))))))
                      (refusal (lambda () (ws-step (make-ws-state open) (list 'send 'text (bv '(65))))))
                      (refusal (lambda () (ws-step (make-ws-state open) '(send binary "A"))))
                      (refusal (lambda ()
                                 (let ((s (make-ws-state open)))
                                   (step* s (list (read-event (frame #x83 '()))))
                                   (ws-step s '(send text "A")))))
                      (refusal (lambda ()
                                 (let ((s (make-ws-state open)))
                                   (step* s (list (read-event (frame #x88 '()))))
                                   (ws-step s '(send text "A")))))))

    ;; --- reading on (0001, and its amendment) ---
    (let ((L (lim 1000 100)))
      (test-equal "reading stops once a cap's worth is queued, and starts again once a take brings the queue under it; under the cap, it goes on, and a take answers nothing"
                  (list (list (list (deliver 'binary (pattern 600)) (deliver 'binary (pattern 400)) '(read-stop))
                              '((read-start)))
                        (list (list (deliver 'binary (pattern 600)) (deliver 'binary (pattern 399)))
                              '()))
                  (list (step* (make-ws-state L)
                               (list (read-event (append (frame #x82 (pattern 600)) (frame #x82 (pattern 400))))
                                     '(taken 600)))
                        (step* (make-ws-state L)
                               (list (read-event (append (frame #x82 (pattern 600)) (frame #x82 (pattern 399))))
                                     '(taken 600)))))
      (test-equal "a take that leaves a cap's worth queued leaves reading stopped"
                  (list (list (deliver 'binary (pattern 100)) (deliver 'binary (pattern 500))
                              (deliver 'binary (pattern 600)) '(read-stop))
                        '() '((read-start)))
                  (step* (make-ws-state L)
                         (list (read-event (append (frame #x82 (pattern 100)) (frame #x82 (pattern 500))
                                                   (frame #x82 (pattern 600))))
                               '(taken 100) '(taken 500)))))
    (test-equal "by default, reading stops at 16 queued messages, and starts again once one is taken; at 15 it goes on"
                (list (list (append (repeat 16 (deliver 'text '())) '((read-stop))) '((read-start)))
                      (list (repeat 15 (deliver 'text '()))))
                (list (step* (make-ws-state default-websocket-limits)
                             (list (read-event (concat (repeat 16 (frame #x81 '())))) '(taken 0)))
                      (step* (make-ws-state default-websocket-limits)
                             (list (read-event (concat (repeat 15 (frame #x81 '()))))))))
    (test-equal "once reading stops, the rest of the read waits, and is read a message a take, before reading starts again"
                (list (list (deliver 'binary '(1)) (deliver 'binary '(2)) (deliver 'binary '(3)) '(read-stop))
                      (list (deliver 'binary '(4)))
                      (list (deliver 'binary '(5)))
                      '((read-start)))
                (step* (make-ws-state (lim 1048576 3))
                       (list (read-event (concat (map (lambda (b) (frame #x82 (list b))) '(1 2 3 4 5))))
                             '(taken 1) '(taken 1) '(taken 1))))
    (test-equal "what waits is read as it would have been: a ping answered at the take that reads it, a frame the read cut off finished by the next read"
                (list (list (deliver 'binary '(1)) '(read-stop))
                      (list (pong '(7)) '(read-start))
                      (list (deliver 'text hello) '(read-stop)))
                (let ((stream (append (frame #x82 '(1)) (frame #x89 '(7)) (frame #x81 hello))))
                  (step* (make-ws-state (lim 1048576 1))
                         (list (read-event (take stream (- (length stream) 3)))
                               '(taken 1)
                               (read-event (list-tail stream (- (length stream) 3)))))))
    (test-equal "what waits may end the connection at the take that reads it, and then reading does not start: a refusal, a close"
                (list (list (list (deliver 'binary '(1)) '(read-stop)) (failed 1002 'unknown-opcode))
                      (list (list (deliver 'binary '(1)) '(read-stop)) (answered 1000 '())))
                (list (step* (make-ws-state (lim 1048576 1))
                             (list (read-event (append (frame #x82 '(1)) (frame #x83 '()))) '(taken 1)))
                      (step* (make-ws-state (lim 1048576 1))
                             (list (read-event (append (frame #x82 '(1)) (frame #x88 '(#x03 #xE8)))) '(taken 1)))))
    (test-equal "after the connection has ended, a take answers nothing, though reading had stopped"
                (list (list (deliver 'binary '(1)) (deliver 'binary '(2)) '(read-stop))
                      (answered 1000 '()) '())
                (step* (make-ws-state (lim 1048576 2))
                       (list (read-event (append (frame #x82 '(1)) (frame #x82 '(2)) (frame #x88 '(#x03 #xE8))))
                             '(taken 1) '(taken 1))))
    (test-equal "a take of more than is queued, or with nothing queued, or a read while reading is stopped or after the connection has ended, is an assertion naming ws-step"
                '((refused ws-step) (refused ws-step) (refused ws-step) (refused ws-step))
                (list (refusal (lambda () (ws-step (make-ws-state open) '(taken 0))))
                      (refusal (lambda ()
                                 (let ((s (make-ws-state open)))
                                   (step* s (list (read-event (frame #x82 '(1 2)))))
                                   (ws-step s '(taken 3)))))
                      (refusal (lambda ()
                                 (let ((s (make-ws-state (lim 1048576 1))))
                                   (step* s (list (read-event (frame #x82 '(1)))))
                                   (ws-step s (read-event (frame #x82 '(2)))))))
                      (refusal (lambda ()
                                 (let ((s (make-ws-state open)))
                                   (step* s (list (read-event (frame #x83 '()))))
                                   (ws-step s (read-event (frame #x82 '(2)))))))))

    ;; --- the API ---
    (test-equal "an event outside the vocabulary or of the wrong shape, or a read outside its bytevector, is an assertion naming ws-step; limits that are not, naming make-ws-state"
                '((refused ws-step) (refused ws-step) (refused ws-step) (refused ws-step) (refused ws-step)
                  (refused ws-step) (refused ws-step) (refused make-ws-state))
                (list (refusal (lambda () (ws-step (make-ws-state open) '(no-such-event))))
                      (refusal (lambda () (ws-step (make-ws-state open) 'bytes)))
                      (refusal (lambda () (ws-step (make-ws-state open) '(taken))))
                      (refusal (lambda () (ws-step (make-ws-state open) (list 'bytes (bv '(1)) 0))))
                      (refusal (lambda () (ws-step (make-ws-state open) (list 'bytes (bv '(1 2)) 0 3))))
                      (refusal (lambda () (ws-step (make-ws-state open) (list 'bytes (bv '(1 2)) 2 1))))
                      (refusal (lambda () (ws-step (make-ws-state open) (list 'bytes "ab" 0 1))))
                      (refusal (lambda () (make-ws-state 1048576)))))
    (test-equal "the bytes a step reads are left as they were, read at once or after waiting"
                (let ((stream (append (frame #x82 '(1)) (frame #x89 '(7)) (frame #x81 hello))))
                  (list stream stream))
                (let* ((stream (append (frame #x82 '(1)) (frame #x89 '(7)) (frame #x81 hello)))
                       (a (bv stream)) (b (bv stream)))
                  (ws-step (make-ws-state open) (list 'bytes a 0 (bytevector-length a)))
                  (step* (make-ws-state (lim 1048576 1))
                         (list (list 'bytes b 0 (bytevector-length b)) '(taken 1) '(taken 1)))
                  (list (bytevector->u8-list a) (bytevector->u8-list b))))
    ;; --- what reading allocates ---
    ;; A message in one frame is read into the bytevector it is delivered
    ;; in, so its step allocates that bytevector, and the same as an empty
    ;; message's for the rest.  A fragmented one is read into a buffer that
    ;; doubles, never past the cap, so one-byte fragments allocate each
    ;; doubling's bytevector and nothing a fragment: 4,096 of them the
    ;; bytevectors of 1, 2, 4 ... 2,048 bytes more than one frame of 4,096
    ;; does; and 1,000 under a cap of 1,000, those of 1 ... 512, the last
    ;; buffer being the cap's, delivered whole.  A buffer that grew by each
    ;; fragment alone would copy the message once a fragment.  The sizes are
    ;; Chez's own, measured here.
    (let* ((cost (lambda (limits bytes)
                   (let* ((v (bv bytes)) (event (list 'bytes v 0 (bytevector-length v))))
                     (allocated (lambda ()
                                  (let-values (((s actions) (ws-step (make-ws-state limits) event)))
                                    (keep! actions)))))))
           (bytes-cost (lambda (n) (allocated (lambda () (keep! (make-bytevector n))))))
           (ones (lambda (n) (append (frame #x02 '(1)) (concat (repeat (- n 2) (frame #x00 '(1))))
                                     (frame #x80 '(1)))))
           (doublings (lambda (k) (fold-left + 0 (map (lambda (j) (bytes-cost (expt 2 j))) (range 0 k)))))
           (L (lim 1000 100000)))
      (test-equal "a message in one frame is read into the bytevector it is delivered in, and one in fragments into a buffer that doubles up to the cap, allocating nothing a fragment"
                  (append (map (lambda (n) (- (bytes-cost n) (bytes-cost 0))) '(1 125 126 65535 65536))
                          (list (doublings 12) (doublings 10)))
                  (append (map (lambda (n) (- (cost open (frame #x82 (pattern n))) (cost open (frame #x82 '()))))
                               '(1 125 126 65535 65536))
                          (list (- (cost open (ones 4096)) (cost open (frame #x82 (repeat 4096 1))))
                                (- (cost L (ones 1000)) (cost L (frame #x82 (repeat 1000 1))))))))

    ;; A connection lives as long as its WebSocket, idle or not, so what it
    ;; is done with it lets go: a guardian hands back what nothing else
    ;; holds once collected.
    (test-equal "a connection keeps no message once it is delivered, and no read once its bytes are read"
                (list (bv (pattern 1000)) (bv (append (frame #x82 '(1)) (frame #x82 '(2)))))
                (let ((let-go (lambda (limits feed!)
                                (let ((g (make-guardian)) (s (make-ws-state limits)))
                                  (feed! g s)
                                  (collect (collect-maximum-generation))
                                  (let ((got (g))) (keep! s) got)))))
                  (list (let-go open
                          (lambda (g s)
                            (let-values (((s actions) (ws-step s (read-event (frame #x82 (pattern 1000))))))
                              (g (caddr (car actions))))))
                        (let-go (lim 1048576 1)
                          (lambda (g s)
                            (let ((r (bv (append (frame #x82 '(1)) (frame #x82 '(2))))))
                              (g r)
                              (ws-step s (list 'bytes r 0 (bytevector-length r)))
                              (ws-step s '(taken 1))))))))

    (test-equal "two connections at once are each their own: their messages and their control frames read in turns"
                (list '() '() (list (deliver 'text hello)) (list (deliver 'binary '(1 2 3)))
                      '() '() (list (pong '(1 2 3))) (list (pong '(9 8 7))))
                (let ((a (make-ws-state open)) (b (make-ws-state open))
                      (step (lambda (s bytes) (let-values (((s actions) (ws-step s (read-event bytes)))) actions)))
                      (sa (frame #x81 hello)) (sb (frame #x82 '(1 2 3)))
                      (pa (frame #x89 '(1 2 3))) (pb (frame #x89 '(9 8 7))))
                  (list (step a (take sa 5)) (step b (take sb 5))
                        (step a (list-tail sa 5)) (step b (list-tail sb 5))
                        (step a (take pa 7)) (step b (take pb 7))
                        (step a (list-tail pa 7)) (step b (list-tail pb 7)))))))
