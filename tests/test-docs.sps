#!r6rs
;;; The user docs (M6): what docs/ tells a user, held to what the library
;;; does.
;;;
;;; The oracles:
;;; - (websocket limits): the variables it reads, in its order, and its
;;;   defaults, which the limits suite holds to the design's §7.  The docs
;;;   agree with the library, and the library with the design.
;;; - The design's §7: durations given in whole seconds, sizes and counts in
;;;   their own unit; and the limits' fields, in make-websocket-limits' order.
;;; - (websocket): the names it exports, the names a handler may call.
;;; - RFC 6455: §1.3's handshake and its Sec-WebSocket-Accept; §5.7's frames,
;;;   a masked Hello and its unmasked echo; §5.5.1, a close answered with a
;;;   close that echoes its code.
;;; - The handlers page's own words: the echo example answers /echo, and
;;;   anything else 404; a closed connection's code is the client's.
;;;
;;; The pages are read as a user reads them: configuration.org's first table
;;; whose first column is Variable; every #+begin_src scheme block, in any
;;; case, with the #+name: line before it, if any; the names written in
;;; ~code~ or in a block; the fields the handlers page lists.  A block that
;;; begins with an import is a program: it is run with `serve` captured, and
;;; its handler played on the server's fake shell (decision 0004), as the
;;; binding suite plays its own.  Any other block is a fragment, and the
;;; suite knows each by its name: where it runs, a handler or a WebSocket's
;;; procedure, how it is played, and what that must give, from the page's
;;; words about it (`fragment-plays`).  A fragment the suite does not know,
;;; or one it knows that the page lost, is red.  The names a fragment takes
;;; from around it are `request`, `ws`, and the procedures `chat` and
;;; `upload`; the suite gives each one.  A body is a top-level program's:
;;; definitions and expressions in any order (R6RS §8.1).
(import (rnrs) (rnrs eval) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (chezscheme) getenv)
        (only (http-server limits) default-limits)
        (only (ws-autobahn) text-lines)
        (websocket) (websocket limits) (ws-play))

;; --- reading the pages ---------------------------------------------------------

;; slurp : String -> String — the file's text.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
    get-string-all))

;; trim : String -> String — without the spaces around it.
(define (trim s)
  (let* ((cs (string->list s))
         (drop (lambda (cs) (let loop ((cs cs)) (if (and (pair? cs) (char=? (car cs) #\space)) (loop (cdr cs)) cs)))))
    (list->string (reverse (drop (reverse (drop cs)))))))

;; starts? : String String -> Boolean
(define (starts? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; split-bars : String -> (Listof String)
;; A table row's cells, trimmed, each ~code~ unwrapped.  A row may leave its
;; last bar out, as org lets it; a row of no cells is '().
(define (split-bars row)
  (let loop ((cs (cdr (string->list (trim row)))) (cell '()) (out '()))
    (cond ((null? cs)
           (let ((last (trim (list->string (reverse cell)))))
             (reverse (if (string=? last "") out (cons (unwrap last) out)))))
          ((char=? (car cs) #\|)
           (loop (cdr cs) '() (cons (unwrap (trim (list->string (reverse cell)))) out)))
          (else (loop (cdr cs) (cons (car cs) cell) out)))))

;; unwrap : String -> String — ~x~ as x; anything else as it is.
(define (unwrap s)
  (let ((n (string-length s)))
    (if (and (>= n 2) (char=? (string-ref s 0) #\~) (char=? (string-ref s (- n 1)) #\~))
        (substring s 1 (- n 1))
        s)))

;; table : String String -> (Listof (Listof String))
;; The rows, past its header, of the page's first table whose header's first
;; cell is `first`; rules, and rows of no cells, left out.
(define (table text first)
  (let find ((ls (text-lines text)))
    (cond ((null? ls) '())
          ((and (starts? (trim (car ls)) "|")
                (let ((cells (split-bars (car ls)))) (and (pair? cells) (equal? (car cells) first))))
           (let rows ((ls (cdr ls)) (out '()))
             (cond ((or (null? ls) (not (starts? (trim (car ls)) "|"))) (reverse out))
                   ((or (starts? (trim (car ls)) "|-") (null? (split-bars (car ls)))) (rows (cdr ls) out))
                   (else (rows (cdr ls) (cons (split-bars (car ls)) out))))))
          (else (find (cdr ls))))))

;; directive? : String String -> Boolean — the line is the org directive, in any case.
(define (directive? line directive)
  (starts? (string-downcase (trim line)) directive))

;; A #+begin_src scheme block: its #+name, or #f; its text; and whether the
;; page ends it.
(define-record-type block (fields name text ended?))

;; blocks : String -> (Listof Block)
;; Every #+begin_src scheme block, in order.  Its name is the #+name: line
;; just before it.
(define (blocks text)
  (let ((joined (lambda (in) (apply string-append (map (lambda (l) (string-append l "\n")) (reverse in))))))
    ;; `in`, while a block is open: its name, then its lines, newest first.
    (let loop ((ls (text-lines text)) (name #f) (in #f) (out '()))
      (cond ((null? ls) (reverse (if in (cons (make-block (car in) (joined (cdr in)) #f) out) out)))
            ((and (not in) (directive? (car ls) "#+name:"))
             (loop (cdr ls) (trim (substring (trim (car ls)) 7 (string-length (trim (car ls))))) #f out))
            ((and (not in) (directive? (car ls) "#+begin_src scheme")) (loop (cdr ls) #f (list name) out))
            ((and in (directive? (car ls) "#+end_src"))
             (loop (cdr ls) #f #f (cons (make-block (car in) (joined (cdr in)) #t) out)))
            (in (loop (cdr ls) #f (cons (car in) (cons (car ls) (cdr in))) out))
            (else (loop (cdr ls) #f #f out))))))

;; data : String -> (Listof Datum) — every datum the text reads as.
(define (data text)
  (let ((p (open-string-input-port text)))
    (let loop ((out '()))
      (let ((d (read p)))
        (if (eof-object? d) (reverse out) (loop (cons d out)))))))

;; readable : (Listof Block) -> (Listof Block) — the blocks that end and read.
(define (readable bs)
  (filter (lambda (k) (and (block-ended? k) (guard (e (#t #f)) (data (block-text k)) #t))) bs))

;; program? : Block -> Boolean — the block begins with an import.
(define (program? k)
  (let ((d (data (block-text k)))) (and (pair? d) (pair? (car d)) (eq? (caar d) 'import))))

;; leading-digits : String -> String — the digits the string starts with.
(define (leading-digits s)
  (let loop ((cs (string->list s)) (out '()))
    (if (and (pair? cs) (char<=? #\0 (car cs)) (char<=? (car cs) #\9))
        (loop (cdr cs) (cons (car cs) out))
        (list->string (reverse out)))))

;; code-spans : String -> (Listof String) — the text of each ~code~ span, in order.
(define (code-spans text)
  (let loop ((cs (string->list text)) (in #f) (out '()))
    (cond ((null? cs) (reverse out))
          ((char=? (car cs) #\~)
           (if in (loop (cdr cs) #f (cons (list->string (reverse in)) out)) (loop (cdr cs) '() out)))
          (in (loop (cdr cs) (cons (car cs) in) out))
          (else (loop (cdr cs) #f out)))))

;; paragraph : String String -> String
;; The paragraph of the text that begins with `words`, up to its blank line;
;; "" when none does.
(define (paragraph text words)
  (let find ((ls (text-lines text)))
    (cond ((null? ls) "")
          ((starts? (car ls) words)
           (let take ((ls ls) (out '()))
             (if (or (null? ls) (string=? (trim (car ls)) ""))
                 (apply string-append (reverse out))
                 (take (cdr ls) (cons (string-append (car ls) "\n") out)))))
          (else (find (cdr ls))))))

;; --- the defaults ----------------------------------------------------------------

;; The design's §7: these are given in whole seconds; the rest in their own unit.
(define in-seconds
  '("CHEZ_WS_PING_INTERVAL" "CHEZ_WS_PING_TIMEOUT" "CHEZ_WS_CLOSE_TIMEOUT" "CHEZ_WS_WRITE_TIMEOUT"))

;; given : (Listof String) -> (U String (List 'unreadable (Listof String)))
;; A row's default as its variable's value: digits, then " s" for one given in
;; seconds and nothing for the rest.  Anything else, a word, another unit, an
;; empty cell or none, is (unreadable row).
(define (given row)
  (let* ((cell (if (pair? (cdr row)) (cadr row) ""))
         (digits (leading-digits cell))
         (rest (substring cell (string-length digits) (string-length cell))))
    (if (and (> (string-length digits) 0)
             (string=? rest (if (member (car row) in-seconds) " s" "")))
        digits
        (list 'unreadable row))))

;; The limits' fields, in (websocket limits)' order.
(define (values-of L)
  (map (lambda (get) (get L))
       (list websocket-limits-max-message-bytes websocket-limits-max-queue
             websocket-limits-ping-interval-ms websocket-limits-ping-timeout-ms
             websocket-limits-close-timeout-ms websocket-limits-write-high-water
             websocket-limits-write-low-water websocket-limits-write-timeout-ms)))

;; The fields' names, in make-websocket-limits' order: the design's §7.
(define field-names
  '(max-message-bytes max-queue ping-interval-ms ping-timeout-ms
    close-timeout-ms write-high-water write-low-water write-timeout-ms))

;; field? : Symbol -> Boolean
;; Whether websocket-limits-with takes the name as a field: it refuses any
;; other naming itself, and a value it does not take naming make-websocket-limits.
(define (field? name)
  (guard (e ((assertion-violation? e) (not (eq? (condition-who e) 'websocket-limits-with))))
    (websocket-limits-with default-websocket-limits (list (cons name 1)))
    #t))

;; --- the names a page writes ---------------------------------------------------

;; name-char? : Char -> Boolean — a character of a Scheme name as the pages write them.
(define (name-char? c)
  (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\- #\! #\? #\& #\> #\*))))

;; library-name? : String -> Boolean
;; Whether the word is written as one of the library's names: websocket?, or
;; one beginning websocket-, &websocket-, make-websocket-, make-handshake-,
;; handshake-settings, default-websocket- or environment-websocket-.
(define (library-name? w)
  (or (string=? w "websocket?")
      (exists (lambda (p) (starts? w p))
              '("websocket-" "&websocket-" "make-websocket-" "make-handshake-"
                "handshake-settings" "default-websocket-" "environment-websocket-"))))

;; names : String -> (Listof String)
;; Each word of the text, a run of name characters, that is written as one of
;; the library's names.  In order, each once.
(define (names text)
  (let loop ((cs (string->list text)) (word '()) (out '()))
    (let ((flush (lambda ()
                   (let ((w (list->string (reverse word))))
                     (if (and (library-name? w) (not (member w out))) (cons w out) out)))))
      (cond ((null? cs) (reverse (flush)))
            ((name-char? (car cs)) (loop (cdr cs) (cons (car cs) word) out))
            (else (loop (cdr cs) '() (flush)))))))

;; unbound : (Listof String) -> (Listof String)
;; The names (websocket) does not export, in order.  A condition type's name,
;; &..., is syntax, so it is asked for its record type.
(define (unbound ns)
  (let ((env (environment '(rnrs) '(websocket))))
    (filter (lambda (n)
              (let ((s (string->symbol n)))
                (guard (e (#t #t))
                  (eval (if (char=? (string-ref n 0) #\&) `(record-type-descriptor ,s) s) env)
                  #f)))
            ns)))

;; --- running a block -------------------------------------------------------------

;; definition? : Datum -> Boolean
(define (definition? d)
  (and (pair? d) (memq (car d) '(define define-syntax define-record-type define-condition-type define-enumeration))))

;; defined : (Listof Datum) -> (Listof Symbol) — the names a body's definitions define.
(define (defined forms)
  (fold-right (lambda (d out)
                (cond ((not (and (pair? d) (eq? (car d) 'define) (pair? (cdr d)))) out)
                      ((symbol? (cadr d)) (cons (cadr d) out))
                      ((pair? (cadr d)) (cons (caadr d) out))
                      (else out)))
              '() forms))

;; body : (Listof Datum) -> (Listof Datum)
;; A top-level program's forms as a lambda's body (R6RS §8.1): each
;; expression but the last a definition of a name of its own, so definitions
;; and expressions may come in any order; the last expression's value is the
;; body's, or #f when the forms end with a definition.
(define (body forms)
  (let loop ((fs forms) (i 0) (out '()))
    (cond ((null? fs) (reverse (cons #f out)))
          ((definition? (car fs)) (loop (cdr fs) (+ i 1) (cons (car fs) out)))
          ((null? (cdr fs)) (reverse (cons (car fs) out)))
          (else (loop (cdr fs) (+ i 1)
                      (cons `(define ,(string->symbol (string-append "%form-" (number->string i)))
                               (begin ,(car fs) #f))
                            out))))))

;; program-handler : String -> (Request -> Answer)
;; The program's handler: its import form's libraries made an environment,
;; its other forms run there with `serve` bound to a procedure that keeps
;; what it is handed.
(define (program-handler text)
  (let* ((forms (data text))
         (env (apply environment (cdar forms)))
         (kept #f))
    ((eval `(lambda (serve) ,@(body (cdr forms))) env)
     (lambda (handler . _) (set! kept handler)))
    kept))

;; The echo, the procedure the suite gives a fragment's `chat` and `upload`.
(define (echo ws)
  (guard (e ((websocket-closed? e) #t))
    (let loop () (websocket-send! ws (websocket-receive ws)) (loop))))

;; The names a fragment may take from around it, each with what the suite
;; gives it, from the request and the WebSocket.
(define surroundings
  (list (cons 'request (lambda (request ws) request))
        (cons 'ws (lambda (request ws) ws))
        (cons 'chat (lambda (request ws) echo))
        (cons 'upload (lambda (request ws) echo))))

;; fragment : String -> (Request (U WebSocket #f) -> Any)
;; The fragment as a procedure of the request and the WebSocket: its forms a
;; body in the environment a handler's program imports, (rnrs), (http-server)
;; and (websocket), each name it takes from around it given by the suite,
;; unless it defines that name itself.  A name it neither defines nor takes,
;; nor the libraries export, is refused as it is evaluated.
(define (fragment text)
  (let* ((forms (data text))
         (own (defined forms))
         (taken (filter (lambda (s) (not (memq (car s) own))) surroundings))
         (proc (eval `(lambda ,(map car taken) ,@(body forms))
                     (environment '(rnrs) '(http-server) '(websocket)))))
    (lambda (request ws)
      (apply proc (map (lambda (s) ((cdr s) request ws)) taken)))))

;; --- playing a handler ---------------------------------------------------------

;; connect : (Request -> Answer) Bytevector -> FakeShell
;; A fake connection, its clock at 5,000 ms, read `input` and settled.
(define (connect handler input)
  (let ((sh (make-fake-connection default-limits handler #f 5000)))
    (fake-shell-feed-input! sh input 4096)
    (fake-shell-settle! sh)
    sh))

;; read-head : FakeShell -> (List (U Nat Datum) (Listof (Pair String String)) Bytevector)
;; What the client read: the head's status, as the server's (response-reader)
;; reads that head alone, its fields, and every byte after it.
(define (read-head sh)
  (let* ((all (concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head '() all))
            ((equal? (copy all i (+ i 4)) blank)
             (let ((r (read-response (copy all 0 (+ i 4)) #f #f)))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (list-ref r 2)
                     (copy all (+ i 4) n))))
            (else (scan (+ i 1)))))))

;; field : (Listof (Pair String String)) String -> (U String #f)
(define (field fields name)
  (let ((f (find (lambda (f) (string-ci=? (car f) name)) fields)))
    (and f (cdr f))))

;; heard : FakeShell -> (List (U Nat Datum) (U String #f) Bytevector)
;; The head's status, its Sec-WebSocket-Accept, and every byte after it.
(define (heard sh)
  (let ((h (read-head sh)))
    (list (car h) (field (cadr h) "Sec-WebSocket-Accept") (caddr h))))

;; head-field : String -> (FakeShell -> (List (U Nat Datum) (U String #f)))
;; The head's status, and the named field of it.
(define (head-field name)
  (lambda (sh) (let ((h (read-head sh))) (list (car h) (field (cadr h) name)))))

;; played : (-> (Request -> Answer)) Bytevector (U Bytevector #f) (FakeShell -> Any) -> Any
;; What `hear` makes of the handler `make` gives, on a fake connection that
;; read `input`, then `later`, if given, in a read of its own.  A handler
;; that raises as it is made, as a program naming a library it does not
;; import does, or a fake that raises, answers (raised message) in a check's
;; place.
(define (played make input later hear)
  (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
    (let ((sh (connect (make) input)))
      (when later
        (fake-shell-deliver! sh (list 'bytes-arrived later 0 (bytevector-length later)))
        (fake-shell-settle! sh))
      (hear sh))))

;; RFC 6455 §1.3's opening handshake, to the path given, with any more
;; fields given, each a line.
(define (handshake path . fields)
  (b (apply string-append
            "GET " path " HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            (append (map (lambda (f) (string-append f "\r\n")) fields) '("\r\n")))))

;; What the client reads of an echo: the 101 with §1.3's accept, §5.7's Hello,
;; then the server's close answering the client's 1000 with 1000 (§5.5.1).
(define echo-heard
  (list 101 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" (concat (list rfc-hello (server-frame #x88 (close-body 1000 ""))))))

;; The echo's input: the handshake to the path and a masked Hello; then, in a
;; read of its own once the echo is out, the client's close.  A close that
;; came with the Hello would be answered before the procedure ran, and a send
;; while the server's close is under way sends nothing.
(define (echo-input path) (concat (list (handshake path) rfc-masked-hello)))
(define client-close (client-frame #x88 (close-body 1000 "")))

;; A client's binary frame announcing 2,000,000 bytes, its header and masking
;; key alone (§5.2): past the default cap, 1 MiB, which fails it 1009 before
;; its payload is held (decision 0001), and short of the 16 MiB the limits
;; fragment gives.
(define big-header (bv (append (list #x82) (length-bytes 2000000 128) '(#x37 #xFA #x21 #x3D))))

;; fragment-handler : Block Symbol -> (-> (Request -> Answer))
;; A maker of the fragment's handler: a handler's fragment is one; a
;; procedure's runs in the WebSocket websocket-accept gives, with its defaults.
(define (fragment-handler k role)
  (lambda ()
    (let ((f (fragment (block-text k))))
      (if (eq? role 'handler)
          (lambda (request) (f request #f))
          (lambda (request) (websocket-accept request (lambda (ws) (f #f ws))))))))

;; The fragments handlers.org names, each with where it runs, how it is
;; played, given its handler's maker, and what that must give, from the
;; page's words about it:
;; - closed-code: a procedure that echoes until the connection closes, then
;;   displays its code, the client's (§5.5.1's 1000);
;; - chat-settings: of the subprotocols a client offers, the first in the
;;   handler's list is chosen (§4.2.2), so chat.v2 of "chat.v1, chat.v2"; a
;;   page from the origin listed is accepted, one from another site refused
;;   403;
;; - upload-limits: a message the default cap refuses is taken, so a frame
;;   announcing 2,000,000 bytes gets no close.
(define fragment-plays
  (list (list "closed-code" 'procedure
              (lambda (make) (logged (lambda () (played make (echo-input "/") client-close heard))))
              (list echo-heard "1000"))
        (list "chat-settings" 'handler
              (lambda (make)
                (list (played make (handshake "/" "Sec-WebSocket-Protocol: chat.v1, chat.v2"
                                              "Origin: https://app.example.com")
                              #f (head-field "Sec-WebSocket-Protocol"))
                      (played make (handshake "/" "Origin: https://elsewhere.example")
                              #f (head-field "Sec-WebSocket-Protocol"))))
              '((101 "chat.v2") (403 #f)))
        (list "upload-limits" 'handler
              (lambda (make) (played make (concat (list (handshake "/") big-header)) #f heard))
              (list 101 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" (make-bytevector 0)))))

(run-suite "docs"
  (lambda ()
    ;; Its echoes are the defaults': the binding reads CHEZ_WS_ variables as
    ;; the program starts, and make test runs the suites with none set.
    (let ((set (filter getenv websocket-limits-environment-variables)))
      (unless (null? set)
        (assertion-violation 'docs-suite "a CHEZ_WS_ variable is set; make test unsets them" set)))
    (let* ((configuration (slurp "docs/configuration.org"))
           (handlers (slurp "docs/handlers.org"))
           (rows (table configuration "Variable"))
           (all-blocks (append (blocks configuration) (blocks handlers)))
           (programs (filter program? (readable (blocks handlers))))
           (fragments (filter (lambda (k) (not (program? k))) (readable (blocks handlers))))
           (written (names (string-append configuration handlers))))
      ;; The suite's own frames are §5.7's, and the pages name what a handler
      ;; calls first, so a scan that finds nothing cannot pass.
      (unless (and (equal? (client-frame #x81 (b "Hello")) rfc-masked-hello)
                   (equal? (server-frame #x81 (b "Hello")) rfc-hello))
        (provenance-failure "the suite's frames are not RFC 6455 §5.7's"))
      (unless (for-all (lambda (n) (member n written))
                       '("websocket-accept" "websocket-receive" "websocket-send!" "websocket-close!"))
        (provenance-failure "the pages' names were not found: the scan reads nothing"))
      (when (null? programs)
        (provenance-failure "handlers.org holds no program"))

      ;; --- configuration.org ---

      (test-equal "configuration.org's table names the variables (websocket limits) reads, in its order"
        websocket-limits-environment-variables
        (map car rows))

      (test-equal "configuration.org's defaults are (websocket limits)' defaults, each written in its variable's unit: whole seconds for a duration, its own unit for a size or a count"
        (values-of default-websocket-limits)
        (let* ((cells (map (lambda (row) (cons (car row) (given row))) rows))
               (unreadable (filter (lambda (p) (pair? (cdr p))) cells)))
          (if (pair? unreadable)
              (map cdr unreadable)
              (guard (e ((assertion-violation? e) (list 'refused (condition-irritants e))))
                (values-of (websocket-limits-from-environment
                            (lambda (name) (let ((p (assoc name cells))) (and p (cdr p))))))))))

      ;; --- the names, the fields, and the blocks ---

      (test-equal "every name of the library's that docs/ writes is one (websocket) exports"
        '() (unbound written))

      (test-equal "the fields handlers.org lists are the limits' fields, each one websocket-limits-with takes, in their order"
        field-names
        (map (lambda (s) (let ((name (string->symbol s))) (if (field? name) name (list 'not-a-field name))))
             (code-spans (paragraph handlers "The fields are"))))

      (test-equal "every Scheme block in docs/ ends, and reads as Scheme"
        (map (lambda (k) 'read) all-blocks)
        (map (lambda (k)
               (cond ((not (block-ended? k)) (list 'unterminated (block-text k)))
                     (else (guard (e (#t (list 'unread (block-text k)))) (data (block-text k)) 'read))))
             all-blocks))

      ;; --- handlers.org's program and fragments, run ---

      (test-equal "handlers.org's first program takes RFC 6455's handshake to /echo with §1.3's accept, echoes a masked Hello as §5.7's frame, and answers the client's close 1000 with 1000"
        echo-heard
        (played (lambda () (program-handler (block-text (car programs)))) (echo-input "/echo") client-close heard))

      (test-equal "handlers.org's first program answers any other path 404"
        404
        (played (lambda () (program-handler (block-text (car programs))))
                (b "GET /other HTTP/1.1\r\nHost: server.example.com\r\n\r\n") #f
                (lambda (sh) (car (read-response (concat (fake-shell-writes sh)) #f #f)))))

      ;; Each fragment the suite knows, by name, and what its play gave, or
      ;; (missing) when the page has no readable fragment of that name; then
      ;; any fragment the page has that the suite does not know.
      (test-equal "every fragment of handlers.org is one the suite knows, by its #+name, and does what the page says of it"
        (map (lambda (p) (list (car p) (cadddr p))) fragment-plays)
        (append
         (map (lambda (p)
                (let ((k (find (lambda (k) (equal? (block-name k) (car p))) fragments)))
                  (list (car p) (if k ((caddr p) (fragment-handler k (cadr p))) '(missing)))))
              fragment-plays)
         (map (lambda (k) (list 'unknown (block-name k)))
              (filter (lambda (k) (not (assoc (block-name k) fragment-plays))) fragments)))))))
