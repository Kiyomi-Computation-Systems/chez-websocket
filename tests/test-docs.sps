#!r6rs
;;; The user docs (M6): what docs/ tells a user, held to what the library
;;; does.
;;;
;;; The oracles:
;;; - (websocket limits): the variables it reads, in its order, and its
;;;   defaults, which the limits suite holds to the design's §7.  The docs
;;;   agree with the library, and the library with the design.
;;; - (websocket): the names it exports, the names a handler may call.
;;; - RFC 6455: §1.3's handshake and its Sec-WebSocket-Accept; §5.7's frames,
;;;   a masked Hello and its unmasked echo; §5.5.1, a close answered with a
;;;   close that echoes its code.
;;; - The handlers page's own words: the echo example answers /echo, and
;;;   anything else 404.
;;;
;;; The pages are read as a user reads them: configuration.org's first table
;;; whose first column is Variable, each row's default the digits it starts
;;; with; every #+begin_src scheme block; the names written in ~code~ or in a
;;; block.  The handlers page's first program is run with `serve` captured,
;;; and its handler played on the server's fake shell (decision 0004), as the
;;; binding suite plays its own.
(import (rnrs) (rnrs eval) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (http-server limits) default-limits)
        (websocket limits) (ws-play))

;; --- reading the pages ---------------------------------------------------------

;; slurp : String -> String — the file's text.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
    get-string-all))

;; lines : String -> (Listof String)
(define (lines s)
  (let loop ((cs (string->list s)) (line '()) (out '()))
    (cond ((null? cs) (reverse (cons (list->string (reverse line)) out)))
          ((char=? (car cs) #\newline) (loop (cdr cs) '() (cons (list->string (reverse line)) out)))
          (else (loop (cdr cs) (cons (car cs) line) out)))))

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
;; A table row's cells, trimmed, each ~code~ unwrapped.
(define (split-bars row)
  (let loop ((cs (cdr (string->list (trim row)))) (cell '()) (out '()))
    (cond ((null? cs) (reverse out))
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
;; cell is `first`; rules left out.
(define (table text first)
  (let find ((ls (lines text)))
    (cond ((null? ls) '())
          ((and (starts? (trim (car ls)) "|")
                (equal? (car (split-bars (car ls))) first))
           (let rows ((ls (cdr ls)) (out '()))
             (cond ((or (null? ls) (not (starts? (trim (car ls)) "|"))) (reverse out))
                   ((starts? (trim (car ls)) "|-") (rows (cdr ls) out))
                   (else (rows (cdr ls) (cons (split-bars (car ls)) out))))))
          (else (find (cdr ls))))))

;; blocks : String -> (Listof String) — every #+begin_src scheme block's text.
(define (blocks text)
  (let loop ((ls (lines text)) (in #f) (out '()))
    (cond ((null? ls) (reverse out))
          ((and (not in) (starts? (trim (car ls)) "#+begin_src scheme")) (loop (cdr ls) '() out))
          ((and in (starts? (trim (car ls)) "#+end_src"))
           (loop (cdr ls) #f (cons (apply string-append (map (lambda (l) (string-append l "\n")) (reverse in))) out)))
          (in (loop (cdr ls) (cons (car ls) in) out))
          (else (loop (cdr ls) #f out)))))

;; data : String -> (Listof Datum) — every datum the text reads as.
(define (data text)
  (let ((p (open-string-input-port text)))
    (let loop ((out '()))
      (let ((d (read p)))
        (if (eof-object? d) (reverse out) (loop (cons d out)))))))

;; leading-digits : String -> String — the digits the string starts with.
(define (leading-digits s)
  (let loop ((cs (string->list s)) (out '()))
    (if (and (pair? cs) (char<=? #\0 (car cs)) (char<=? (car cs) #\9))
        (loop (cdr cs) (cons (car cs) out))
        (list->string (reverse out)))))

;; --- the names a page writes ---------------------------------------------------

;; name-char? : Char -> Boolean — a character of a Scheme name as the pages write them.
(define (name-char? c)
  (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\- #\! #\? #\& #\> #\*))))

;; names : String -> (Listof String)
;; Each word of the text, a run of name characters, that names the library's
;; own: one beginning websocket-, make-websocket-, make-handshake-,
;; default-websocket- or environment-websocket-.  In order, each once.
(define (names text)
  (let loop ((cs (string->list text)) (word '()) (out '()))
    (let ((flush (lambda ()
                   (let ((w (list->string (reverse word))))
                     (if (and (exists (lambda (p) (starts? w p))
                                      '("websocket-" "make-websocket-" "make-handshake-"
                                        "default-websocket-" "environment-websocket-"))
                              (not (member w out)))
                         (cons w out)
                         out)))))
      (cond ((null? cs) (reverse (flush)))
            ((name-char? (car cs)) (loop (cdr cs) (cons (car cs) word) out))
            (else (loop (cdr cs) '() (flush)))))))

;; unbound : (Listof String) -> (Listof String)
;; The names (websocket) does not export, in order.
(define (unbound ns)
  (let ((env (environment '(websocket))))
    (filter (lambda (n) (guard (e (#t #t)) (eval (string->symbol n) env) #f)) ns)))

;; --- the example, run --------------------------------------------------------

;; program-handler : String -> (Request -> Answer)
;; The program's handler: its import form's libraries made an environment,
;; its other forms run there with `serve` bound to a procedure that keeps
;; what it is handed.
(define (program-handler text)
  (let* ((forms (data text))
         (env (apply environment (cdar forms)))
         (kept #f))
    ((eval `(lambda (serve) ,@(cdr forms)) env)
     (lambda (handler . _) (set! kept handler)))
    kept))

;; concat : (Listof Bytevector) -> Bytevector
(define (concat bvs)
  (let ((out (make-bytevector (fold-left (lambda (n bv) (+ n (bytevector-length bv))) 0 bvs))))
    (fold-left (lambda (at bv) (bytevector-copy! bv 0 out at (bytevector-length bv)) (+ at (bytevector-length bv)))
               0 bvs)
    out))

;; copy : Bytevector Nat Nat -> Bytevector — bv[from, to), copied.
(define (copy bv from to)
  (let ((o (make-bytevector (- to from)))) (bytevector-copy! bv from o 0 (- to from)) o))

;; connect : (Request -> Answer) Bytevector -> FakeShell
;; A fake connection, its clock at 5,000 ms, read `input` and settled.
(define (connect handler input)
  (let ((sh (make-fake-connection default-limits handler #f 5000)))
    (fake-shell-feed-input! sh input 4096)
    (fake-shell-settle! sh)
    sh))

;; heard : FakeShell -> (List (U Nat Datum) (U String #f) Bytevector)
;; What the client read: the head's status, as the server's (response-reader)
;; reads that head alone, its Sec-WebSocket-Accept, and every byte after it.
(define (heard sh)
  (let* ((all (concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head #f all))
            ((equal? (copy all i (+ i 4)) blank)
             (let* ((r (read-response (copy all 0 (+ i 4)) #f #f))
                    (accept (find (lambda (f) (string-ci=? (car f) "Sec-WebSocket-Accept")) (list-ref r 2))))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (and accept (cdr accept))
                     (copy all (+ i 4) n))))
            (else (scan (+ i 1)))))))

;; played : String Bytevector (U Bytevector #f) (FakeShell -> Any) -> Any
;; What `hear` makes of the program's handler on a fake connection that read
;; `input`, then `later`, if given, in a read of its own.  A program that
;; raises as it loads, as one naming a library it does not import does, or a
;; fake that raises, answers (raised message) in a check's place.
(define (played program input later hear)
  (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e))))
    (let ((sh (connect (program-handler program) input)))
      (when later
        (fake-shell-deliver! sh (list 'bytes-arrived later 0 (bytevector-length later)))
        (fake-shell-settle! sh))
      (hear sh))))

;; RFC 6455 §1.3's opening handshake, to the path given.
(define (handshake path)
  (b (string-append "GET " path " HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\n"
                    "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                    "Sec-WebSocket-Version: 13\r\n\r\n")))

;; The limits' fields, in (websocket limits)' order.
(define (values-of L)
  (map (lambda (get) (get L))
       (list websocket-limits-max-message-bytes websocket-limits-max-queue
             websocket-limits-ping-interval-ms websocket-limits-ping-timeout-ms
             websocket-limits-close-timeout-ms websocket-limits-write-high-water
             websocket-limits-write-low-water websocket-limits-write-timeout-ms)))

(run-suite "docs"
  (lambda ()
    (let* ((configuration (slurp "docs/configuration.org"))
           (handlers (slurp "docs/handlers.org"))
           (rows (table configuration "Variable"))
           (programs (filter (lambda (t)
                               (let ((d (guard (e (#t '())) (data t))))
                                 (and (pair? d) (pair? (car d)) (eq? (caar d) 'import))))
                             (blocks handlers)))
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

      (test-equal "configuration.org's defaults, read as the environment, are (websocket limits)' defaults, each in its variable's unit"
        (values-of default-websocket-limits)
        (guard (e ((assertion-violation? e) (list 'refused (condition-irritants e))))
          (values-of (websocket-limits-from-environment
                      (lambda (name)
                        (let ((row (assoc name rows)))
                          (and row (leading-digits (cadr row)))))))))

      ;; --- the names, and the blocks ---

      (test-equal "every name of the library's that docs/ writes is one (websocket) exports"
        '() (unbound written))

      (test-equal "every Scheme block in docs/ reads as Scheme"
        (map (lambda (t) 'read) (append (blocks configuration) (blocks handlers)))
        (map (lambda (t) (guard (e (#t (list 'unread t))) (data t) 'read))
             (append (blocks configuration) (blocks handlers))))

      ;; --- handlers.org's example, run ---

      ;; The close comes in a read of its own, once the echo is out: one that
      ;; came with the Hello would be answered before the procedure ran, and a
      ;; send while the server's close is under way sends nothing.
      (test-equal "handlers.org's first program takes RFC 6455's handshake to /echo with §1.3's accept, echoes a masked Hello as §5.7's frame, and answers the client's close 1000 with 1000"
        (list 101 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" (concat (list rfc-hello (server-frame #x88 (close-body 1000 "")))))
        (played (car programs) (concat (list (handshake "/echo") rfc-masked-hello))
                (client-frame #x88 (close-body 1000 "")) heard))

      (test-equal "handlers.org's first program answers any other path 404"
        404
        (played (car programs) (b "GET /other HTTP/1.1\r\nHost: server.example.com\r\n\r\n") #f
                (lambda (sh) (car (read-response (concat (fake-shell-writes sh)) #f #f))))))))
