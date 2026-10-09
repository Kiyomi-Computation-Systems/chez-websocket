#!r6rs
;;; (ws-play) — what the binding's suites play: a client's frames, by RFC
;;; 6455 §5.2 and §5.3, and a handler that answers websocket-accept's
;;; switch.  The binding suite plays them on the server's fake shell, and the
;;; socket suite on its libuv shell (M4.3 step 3's review).
;;;
;;; NOT pure: `logged` takes the current output port for its thunk.
(library (ws-play)
  (export b bv big-endian length-bytes client-frame server-frame close-body
          rfc-masked-hello rfc-hello
          accepting wrapping logged limits closed)
  (import (rnrs)
          (only (chezscheme) parameterize)
          (rename (only (chezscheme) current-output-port) (current-output-port output-port-parameter))
          (http-server)
          (only (http-server switch) switch? switch-headers switch-take-over)
          (websocket))

  ;; b : String -> Bytevector — its UTF-8.
  (define (b s) (string->utf8 s))

  ;; bv : (Listof Byte) -> Bytevector
  (define bv u8-list->bytevector)

  ;; §5.7's masking key.
  (define key '(#x37 #xFA #x21 #x3D))

  ;; big-endian : Nat Nat -> (Listof Byte) — n as k bytes, most significant first.
  (define (big-endian n k)
    (let loop ((n n) (k k) (out '()))
      (if (= k 0) out (loop (div n 256) (- k 1) (cons (mod n 256) out)))))

  ;; length-bytes : Nat Byte -> (Listof Byte)
  ;; The second byte, the mask bit's value given, then the extended length,
  ;; in the shortest form.
  (define (length-bytes n mask)
    (cond ((< n 126) (list (+ mask n)))
          ((< n 65536) (cons (+ mask 126) (big-endian n 2)))
          (else (cons (+ mask 127) (big-endian n 8)))))

  ;; client-frame : Byte Bytevector -> Bytevector
  ;; A client's frame: its first byte, the length masked, the key, the payload
  ;; masked, byte i with the key's byte i mod 4.
  (define (client-frame first payload)
    (let ((p (bytevector->u8-list payload)))
      (bv (append (list first) (length-bytes (length p) 128) key
                  (let loop ((p p) (i 0) (out '()))
                    (if (null? p)
                        (reverse out)
                        (loop (cdr p) (+ i 1)
                              (cons (bitwise-xor (car p) (list-ref key (mod i 4))) out))))))))

  ;; server-frame : Byte Bytevector -> Bytevector
  ;; The server's frame: its first byte, the length unmasked, the payload.
  (define (server-frame first payload)
    (bv (append (list first) (length-bytes (bytevector-length payload) 0) (bytevector->u8-list payload))))

  ;; close-body : Nat String -> Bytevector — a close's code, then its reason.
  (define (close-body code reason)
    (bv (append (big-endian code 2) (bytevector->u8-list (b reason)))))

  ;; RFC 6455 §5.7's examples, as its text prints them.
  ;;   rfc-masked-hello : Bytevector
  ;;   rfc-hello : Bytevector
  (define rfc-masked-hello (bv '(#x81 #x85 #x37 #xFA #x21 #x3D #x7F #x9F #x4D #x51 #x58)))
  (define rfc-hello (bv '(#x81 #x05 #x48 #x65 #x6C #x6C #x6F)))

  ;; accepting : (WebSocket -> Any) . Any -> (Request -> Answer)
  ;; A handler answering what websocket-accept answers, with any settings and
  ;; limits given.
  (define (accepting proc . options)
    (lambda (request) (apply websocket-accept request proc options)))

  ;; wrapping : (Request -> Answer) (Transport -> Transport) -> (Request -> Answer)
  ;; The handler, its switch's take-over handed `(wrap t)` in place of the
  ;; shell's transport t.
  (define (wrapping handler wrap)
    (lambda (request)
      (let ((a (handler request)))
        (if (switch? a)
            (switch-protocols (switch-headers a)
                              (lambda (t retained) ((switch-take-over a) (wrap t) retained)))
            a))))

  ;; logged : (-> Any) -> (List Any String)
  ;; What the thunk answers, and what was written to the current output port
  ;; while it ran: the binding's log.  The port is Chez's parameter, which
  ;; (rnrs)'s current-output-port reads but cannot be given to parameterize.
  (define (logged thunk)
    (let-values (((port get) (open-string-output-port)))
      (let ((v (parameterize ((output-port-parameter port)) (thunk))))
        (list v (get)))))

  ;; limits : (Listof (Pair Symbol Nat)) -> WebsocketLimits — the defaults, these replaced.
  (define (limits overrides) (websocket-limits-with default-websocket-limits overrides))

  ;; closed : Condition -> (List 'closed Nat String Boolean)
  (define (closed e)
    (list 'closed (websocket-closed-code e) (websocket-closed-reason e) (websocket-closed-clean? e))))
