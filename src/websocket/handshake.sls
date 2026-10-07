#!r6rs
;;; (websocket handshake) — the opening handshake's check, and the 101's
;;; fields (RFC 6455 §4.2; the design's §3).
;;;
;;; Pure: the request is the server's, so this library is given what it
;;; reads of it.  The method is the symbol llhttp names.  A reader answers a
;;; field's value from its name, as the server's request-header reads a
;;; request's: the value of the first field of that name, without regard to
;;; ASCII case, or #f.  The host is the request's, as its request-host reads
;;; it.  A test gives it a table.
;;;
;;; A handler's settings, its subprotocols and its origins, are made once,
;;; with make-handshake-settings, and checked there, so a bad name stops the
;;; program where the settings are made, not at the first client.  They keep
;;; copies of what they were made with, and each answer's bytevectors and
;;; strings are its own.
;;;
;;; The checks, in order; the first that fails answers (§4.2.1):
;;;   the method is GET                                   400
;;;   Upgrade lists websocket, without regard to case     400
;;;   Connection lists upgrade, without regard to case    400
;;;   Sec-WebSocket-Version is 13                         400, with
;;;                                                       Sec-WebSocket-Version: 13
;;;   Sec-WebSocket-Key is the base64 of sixteen bytes    400
;;;   Origin is one the handler accepts                   403
;;; A wrong version is refused 400, as §4.4's example is, not with §4.2.2's
;;; 426: RFC 9110 has a 426 carry Upgrade, and Upgrade a Connection of
;;; upgrade, which the server lets no response but a 101 say (decision
;;; 0003).
;;; A list is a field's comma-separated elements, the OWS around each passed
;;; over, and an empty one none (RFC 9110 §5.6.1).  A key's last digit may
;;; set bits past its data, as RFC 6455 §4.1's own example does (erratum
;;; 3150).  A refusal carries no body, as the server's own refusals carry
;;; none: it writes the status's phrase.  It names the check that failed.
;;;
;;; Accepted, the 101 carries Upgrade: websocket and Sec-WebSocket-Accept,
;;; the base64 of the SHA-1 of the key as sent and RFC 6455's GUID (§4.2.2).
;;; The server adds Connection: upgrade.  Sec-WebSocket-Extensions is never
;;; answered, so permessage-deflate is declined (RFC 7692 §5).
;;;
;;; Subprotocols.  The handler names those it speaks, in its order of
;;; preference, each a token (RFC 6455 §4.1).  The first of them the client
;;; offered, as a whole element of its Sec-WebSocket-Protocol, compared
;;; exactly, is chosen, and the 101 names it.  When none is, none is named,
;;; and the handshake still succeeds (§4.2.2 /subprotocol/), as coder and
;;; gorilla do.
;;;
;;; Origin (decision 0003, and its amendment of 2026-10-06).  A request with
;;; no Origin is not a browser's (§4.2.1), and a client that is not a
;;; browser may send any Origin it likes, so one with none is accepted.
;;; Otherwise the handler's origins say, and a handler that names none gets
;;; (same-host):
;;;   any        every Origin is accepted;
;;;   a list     an Origin equal to one listed, without regard to ASCII case,
;;;              is accepted; and if the list holds same-host, an Origin of
;;;              the request's own host: one whose host and port, past the
;;;              first "://", are the request's host, letters without regard
;;;              to case, as coder and gorilla compare them.  When the
;;;              request's X-Forwarded-Proto names http or https, the scheme
;;;              its client used, as Caddy writes it and no browser can, the
;;;              Origin's scheme must be that one too; otherwise the scheme
;;;              is not compared.
;;; An empty Origin is no origin (RFC 6454 §7.1): it names no host, so
;;; same-host refuses it, as gorilla does.
(library (websocket handshake)
  (export make-handshake-settings handshake-settings? handshake-answer)
  (import (rnrs) (websocket sha1) (websocket base64))

  ;; RFC 6455 §1.3's GUID.
  (define guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

  ;; The record, as made: new-settings checks nothing.
  (define-record-type (handshake-settings new-settings handshake-settings?)
    (fields (immutable subprotocols settings-subprotocols)
            (immutable origins settings-origins)))

  ;; make-handshake-settings : (Listof String) [Origins] -> HandshakeSettings
  ;;   Origins = (U 'any (Listof (U String 'same-host)))
  ;; handshake-settings? : Any -> Boolean
  ;; A handler's subprotocols, in its order of preference, each a token
  ;; (RFC 6455 §4.1), and its origins, (same-host) when left out (decision
  ;; 0003), checked once, here.  The settings keep copies, so what the
  ;; handler changes afterwards changes nothing.  Anything else is an
  ;; assertion violation naming make-handshake-settings.
  (define make-handshake-settings
    (case-lambda
      ((subprotocols) (make-handshake-settings subprotocols '(same-host)))
      ((subprotocols origins)
       (unless (and (list? subprotocols) (for-all token? subprotocols))
         (refuse-setting "not a list of subprotocols, each a token" subprotocols))
       (unless (or (eq? origins 'any)
                   (and (list? origins)
                        (for-all (lambda (o) (or (string? o) (eq? o 'same-host))) origins)))
         (refuse-setting "not any, nor a list of origins and same-host" origins))
       (new-settings (map string-copy subprotocols)
                     (if (eq? origins 'any)
                         'any
                         (map (lambda (o) (if (string? o) (string-copy o) o)) origins))))))

  (define (refuse-setting message irritant)
    (assertion-violation 'make-handshake-settings message irritant))

  ;; handshake-answer :
  ;;   Symbol (String -> (U String #f)) String HandshakeSettings -> Answer
  ;;   Answer  = (List 'accept Headers (U String #f))
  ;;               the 101's fields, and the subprotocol chosen
  ;;           | (List 'refuse Nat Headers Symbol)
  ;;               the status, its fields, and the check that failed: method,
  ;;               upgrade, connection, version, key or origin
  ;;   Headers = (Listof (Pair Bytevector Bytevector)), as the server's
  ;;             make-response and switch-protocols take them, each made
  ;;             for its answer
  ;; What the server answers the request: the 101's fields, or a refusal.
  ;; Arguments outside the contract are an assertion violation naming
  ;; handshake-answer, and so is a field the reader answers with anything
  ;; but a string or #f.
  (define (handshake-answer method field host settings)
    (unless (symbol? method) (refuse-argument "not a method" method))
    (unless (procedure? field) (refuse-argument "not a reader of fields" field))
    (unless (string? host) (refuse-argument "not a host" host))
    (unless (handshake-settings? settings) (refuse-argument "not handshake settings" settings))
    (let ((value (lambda (name)
                   (let ((v (field name)))
                     (unless (or (not v) (string? v)) (refuse-argument "not a field's value" v))
                     v))))
      (cond ((not (eq? method 'GET)) (refusal 400 '() 'method))
            ((not (lists? (value "Upgrade") "websocket")) (refusal 400 '() 'upgrade))
            ((not (lists? (value "Connection") "upgrade")) (refusal 400 '() 'connection))
            ((not (equal? (value "Sec-WebSocket-Version") "13"))
             (refusal 400 (list (header "Sec-WebSocket-Version" "13")) 'version))
            (else
             (let ((key (value "Sec-WebSocket-Key")))
               (cond ((not (key? key)) (refusal 400 '() 'key))
                     ((not (origin-accepted? (value "Origin") host (settings-origins settings)
                                             (value "X-Forwarded-Proto")))
                      (refusal 403 '() 'origin))
                     (else
                      (let ((protocol (choose (settings-subprotocols settings)
                                              (value "Sec-WebSocket-Protocol"))))
                        (list 'accept
                              (cons* (header "Upgrade" "websocket")
                                     (header "Sec-WebSocket-Accept" (accept-value key))
                                     (if protocol
                                         (list (header "Sec-WebSocket-Protocol" protocol))
                                         '()))
                              (and protocol (string-copy protocol)))))))))))

  (define (refusal status headers why) (list 'refuse status headers why))

  ;; header : String String -> (Pair Bytevector Bytevector) — a field, made
  ;; for its answer.
  (define (header name value) (cons (string->utf8 name) (string->utf8 value)))

  (define (refuse-argument message irritant)
    (assertion-violation 'handshake-answer message irritant))

  ;; key? : (U String #f) -> Boolean — the base64 of sixteen bytes.
  (define (key? key)
    (and key
         (let ((bytes (base64-decode key)))
           (and bytes (fx=? (bytevector-length bytes) 16)))))

  ;; accept-value : String -> String
  ;; The base64 of the SHA-1 of the key as sent and the GUID (§4.2.2).  The
  ;; key is base64, so ASCII, and its UTF-8 its own bytes.
  (define (accept-value key)
    (base64-encode (sha1 (string->utf8 (string-append key guid)))))

  ;; choose : (Listof String) (U String #f) -> (U String #f)
  ;; The first of the subprotocols the offer lists, exactly, or #f.
  (define (choose subprotocols offer)
    (and offer (find (lambda (p) (has-element? offer p char=?)) subprotocols)))

  ;; origin-accepted? : (U String #f) String Origins (U String #f) -> Boolean
  (define (origin-accepted? origin host origins proto)
    (cond ((not origin) #t)
          ((eq? origins 'any) #t)
          (else
           (exists (lambda (o)
                     (if (eq? o 'same-host)
                         (same-host? origin host proto)
                         (range=? origin 0 (string-length origin) o ascii-ci=?)))
                   origins))))

  ;; same-host? : String String (U String #f) -> Boolean
  ;; Whether what follows the origin's first "://" is `host`, letters
  ;; without regard to case; and, when the request's X-Forwarded-Proto names
  ;; http or https, whether what precedes it is that scheme.
  (define (same-host? origin host proto)
    (let ((at (past-scheme origin)))
      (and at
           (or (not (scheme? proto)) (range=? origin 0 (fx- at 3) proto ascii-ci=?))
           (range=? origin at (string-length origin) host ascii-ci=?))))

  ;; scheme? : (U String #f) -> Boolean — http or https, without regard to
  ;; case.
  (define (scheme? proto)
    (and proto
         (or (range=? proto 0 (string-length proto) "http" ascii-ci=?)
             (range=? proto 0 (string-length proto) "https" ascii-ci=?))))

  ;; past-scheme : String -> (U Nat #f) — where the origin's first "://" ends.
  (define (past-scheme s)
    (let ((end (string-length s)))
      (let loop ((i 0))
        (cond ((fx>? (fx+ i 3) end) #f)
              ((range=? s i (fx+ i 3) "://" char=?) (fx+ i 3))
              (else (loop (fx+ i 1)))))))

  ;; lists? : (U String #f) String -> Boolean
  ;; Whether a field's list has the element `token`, without regard to
  ;; ASCII case; a field that is absent lists nothing.
  (define (lists? value token)
    (and value (has-element? value token ascii-ci=?)))

  ;; has-element? : String String (Char Char -> Boolean) -> Boolean
  ;; Whether an element of the comma-separated list in `s`, the OWS around it
  ;; passed over, is `token`, all of it, its characters compared by `same?`.
  (define (has-element? s token same?)
    (let ((end (string-length s)))
      (let loop ((i 0))
        (and (fx<=? i end)
             (let* ((comma (find-comma s i end))
                    (from (skip-ows s i comma))
                    (to (back-ows s from comma)))
               (or (range=? s from to token same?)
                   (loop (fx+ comma 1))))))))

  ;; find-comma : String Nat Nat -> Nat — the first comma in [i, end), or end.
  (define (find-comma s i end)
    (if (or (fx=? i end) (char=? (string-ref s i) #\,)) i (find-comma s (fx+ i 1) end)))

  ;; skip-ows : String Nat Nat -> Nat — past the OWS (SP, HTAB) from i.
  (define (skip-ows s i end)
    (if (and (fx<? i end) (ows? (string-ref s i))) (skip-ows s (fx+ i 1) end) i))

  ;; back-ows : String Nat Nat -> Nat — before the OWS that ends [from, to).
  (define (back-ows s from to)
    (if (and (fx>? to from) (ows? (string-ref s (fx- to 1)))) (back-ows s from (fx- to 1)) to))

  (define (ows? c) (or (char=? c #\space) (char=? c #\tab)))

  ;; range=? : String Nat Nat String (Char Char -> Boolean) -> Boolean
  ;; Whether s[from, to) is `token`, all of it, its characters compared by
  ;; `same?`.
  (define (range=? s from to token same?)
    (and (fx=? (fx- to from) (string-length token))
         (let loop ((i from) (j 0))
           (or (fx=? i to)
               (and (same? (string-ref s i) (string-ref token j))
                    (loop (fx+ i 1) (fx+ j 1)))))))

  ;; ascii-ci=? : Char Char -> Boolean — equal, ASCII letters without regard
  ;; to case.
  (define (ascii-ci=? a b)
    (char=? (ascii-downcase a) (ascii-downcase b)))

  (define (ascii-downcase c)
    (if (char<=? #\A c #\Z) (integer->char (fx+ (char->integer c) 32)) c))

  ;; token? : Any -> Boolean
  ;; A string of one or more of RFC 9110 §5.6.2's tchar.
  (define (token? s)
    (and (string? s)
         (fx>? (string-length s) 0)
         (let loop ((i 0))
           (or (fx=? i (string-length s))
               (and (tchar? (string-ref s i)) (loop (fx+ i 1)))))))

  (define (tchar? c)
    (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
        (and (memv c '(#\! #\# #\$ #\% #\& #\' #\* #\+ #\- #\. #\^ #\_ #\` #\| #\~)) #t))))
