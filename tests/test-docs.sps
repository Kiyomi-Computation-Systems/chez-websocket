#!r6rs
;;; The user docs: what docs/ tells a user, held to what the library does.
;;;
;;; The oracles:
;;; - (websocket limits): the variables it reads, in its order, and its
;;;   defaults, which the limits suite holds; the docs agree with the library.
;;; - Durations given in whole seconds, sizes and counts in their own unit;
;;;   and the limits' fields, in make-websocket-limits' order.
;;; - (websocket): the names it exports, the names a handler may call, as
;;;   Chez's library-exports lists them; and what each one is, as Chez
;;;   evaluates it: syntax, a procedure and the counts of arguments it takes,
;;;   or a value.
;;; - websocket-limits-with: the fields it takes, each setting the limit of
;;;   its name and no other.
;;; - RFC 6455: §1.3's handshake and its Sec-WebSocket-Accept; §5.7's frames,
;;;   a masked Hello and its unmasked echo; §5.5.1, a close answered with a
;;;   close that echoes its code.
;;; - The pages' own words: the echo program answers /echo, and anything else
;;;   404; a closed connection's code is the client's.
;;; - The checkout: the targets the Makefile documents, the files a link
;;;   names, and the numbers CHANGELOG.md, README.org and
;;;   tests/autobahn/verdicts.txt record, which the measured pages may repeat
;;;   and may not invent.
;;;
;;; The pages are docs/*.md, read as a user reads them, CommonMark with
;;; GitHub's tables: configuration.md's first table whose first column is
;;; Variable; every fenced block, of backticks or tildes, indented or not, up
;;; to the fence that closes it, its language its info string's first word,
;;; in any case, and its name the word name=NAME after it, which a static
;;; site's renderer drops; the names written in `code` or in a block; the
;;; fields the handlers page lists; each link's target; and the reference
;;; page's entries, each a ### heading naming it in `code`, its kind after
;;; it, and its call form, the first `code` beneath it that begins with its
;;; name.  Each block is read once, as the page is split into blocks.
;;;
;;; A Scheme block is known by its name: the suite knows, for each name,
;;; where the block runs, a program, a handler or a WebSocket's procedure,
;;; how it is played, and what that must give, from the page's words about it
;;; (`known-blocks`).  A program, a block that begins with an import, is run
;;; with `serve` captured, and its handler played on the server's fake shell,
;;; as the binding suite plays its own.  A Scheme block the suite does not
;;; know, or one it knows that the pages lost, is red.  The names a fragment
;;; takes from around it are `request`, `ws`, and the procedures `chat` and
;;; `upload`; the suite gives each one.  A body is a top-level program's:
;;; definitions and expressions in any order (R6RS §8.1).
(import (rnrs) (rnrs eval) (srfi :64) (ws-testing) (http-server) (fake-shell) (response-reader)
        (only (chezscheme) getenv library-exports directory-list procedure-arity-mask)
        (only (http-server limits) default-limits)
        (only (ws-text) text-lines)
        (websocket) (websocket limits) (ws-play))

;; --- reading text ----------------------------------------------------------------

;; slurp : String -> String — the file's text.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
    get-string-all))

;; blank? : Char -> Boolean — a space or a tab, which Markdown reads alike.
(define (blank? c) (or (char=? c #\space) (char=? c #\tab)))

;; trim : String -> String — without the blanks around it.
(define (trim s)
  (let* ((cs (string->list s))
         (drop (lambda (cs) (let loop ((cs cs)) (if (and (pair? cs) (blank? (car cs))) (loop (cdr cs)) cs)))))
    (list->string (reverse (drop (reverse (drop cs)))))))

;; words : String -> (Listof String) — the runs of characters between blanks.
(define (words s)
  (let loop ((cs (string->list s)) (word '()) (out '()))
    (let ((flush (lambda () (if (null? word) out (cons (list->string (reverse word)) out)))))
      (cond ((null? cs) (reverse (flush)))
            ((blank? (car cs)) (loop (cdr cs) '() (flush)))
            (else (loop (cdr cs) (cons (car cs) word) out))))))

;; starts? : String String -> Boolean
(define (starts? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

;; ends? : String String -> Boolean
(define (ends? s suffix)
  (let ((n (string-length s)) (k (string-length suffix)))
    (and (>= n k) (string=? (substring s (- n k) n) suffix))))

;; search : String String Nat -> (U Nat #f) — where `pat` first begins in s, at i or after.
(define (search s pat i)
  (let ((n (string-length s)) (k (string-length pat)))
    (let loop ((i i))
      (cond ((> (+ i k) n) #f)
            ((string=? (substring s i (+ i k)) pat) i)
            (else (loop (+ i 1)))))))

;; run : String Nat Char -> Nat — how many c the string has in a row from i.
(define (run s i c)
  (let loop ((j i))
    (if (and (< j (string-length s)) (char=? (string-ref s j) c)) (loop (+ j 1)) (- j i))))

;; joined : (Listof String) -> String — the lines, each ended by a LF.
(define (joined lines) (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

;; --- fenced blocks -------------------------------------------------------------

;; fence : String -> (U (List Char Nat String) #f)
;; The line as a fence that opens a block (CommonMark §4.5): its character,
;; a backtick or a tilde, how many, three or more, and its info string; #f
;; for any other line.  Indented or not, as a fence in a list item is.  A
;; backtick fence's info string has no backtick.
(define (fence line)
  (let ((s (trim line)))
    (and (> (string-length s) 0)
         (memv (string-ref s 0) '(#\` #\~))
         (let* ((c (string-ref s 0))
                (n (run s 0 c))
                (info (trim (substring s n (string-length s)))))
           (and (>= n 3)
                (not (and (char=? c #\`) (memv #\` (string->list info))))
                (list c n info))))))

;; closes? : String (List Char Nat String) -> Boolean
;; The line closes the open fence: its character, as many or more, and
;; blanks alone.
(define (closes? line open)
  (let ((s (trim line)))
    (and (>= (string-length s) (cadr open))
         (= (run s 0 (car open)) (string-length s)))))

;; language : String -> String — the info string's first word, in lower case; "" for none.
(define (language info)
  (let ((w (words info))) (if (pair? w) (string-downcase (car w)) "")))

;; named : String -> (U String #f)
;; The info string's name: the first word after its language that begins
;; name=, in any case, without it; #f for none.
(define (named info)
  (let* ((ws (words info))
         (w (and (pair? ws) (find (lambda (w) (starts? (string-downcase w) "name=")) (cdr ws)))))
    (and w (substring w 5 (string-length w)))))

;; A fenced block: its page; its language and name; its text; whether a
;; fence closes it; and, for a Scheme block that is closed, the data its text
;; reads as, or #f when it does not read.
(define-record-type block (fields page language name text ended? forms))

;; read-block : String (List Char Nat String) (Listof String) Boolean -> Block
;; The block, its text read once.
(define (read-block page open lines ended?)
  (let ((text (joined lines)) (lang (language (caddr open))))
    (make-block page lang (named (caddr open)) text ended?
                (and ended? (string=? lang "scheme") (guard (e (#t #f)) (data text))))))

;; blocks : String String -> (Listof Block) — the page's fenced blocks, in order.
(define (blocks page text)
  (let loop ((ls (text-lines text)) (open #f) (in '()) (out '()))
    (cond ((null? ls) (reverse (if open (cons (read-block page open (reverse in) #f) out) out)))
          ((and open (closes? (car ls) open))
           (loop (cdr ls) #f '() (cons (read-block page open (reverse in) #t) out)))
          (open (loop (cdr ls) open (cons (car ls) in) out))
          ((fence (car ls)) => (lambda (f) (loop (cdr ls) f '() out)))
          (else (loop (cdr ls) #f '() out)))))

;; prose : String -> String — the page's lines outside its fenced blocks and their fences.
(define (prose text)
  (let loop ((ls (text-lines text)) (open #f) (out '()))
    (cond ((null? ls) (joined (reverse out)))
          (open (loop (cdr ls) (if (closes? (car ls) open) #f open) out))
          ((fence (car ls)) => (lambda (f) (loop (cdr ls) f out)))
          (else (loop (cdr ls) #f (cons (car ls) out))))))

;; data : String -> (Listof Datum) — every datum the text reads as.
(define (data text)
  (let ((p (open-string-input-port text)))
    (let loop ((out '()))
      (let ((d (read p)))
        (if (eof-object? d) (reverse out) (loop (cons d out)))))))

;; scheme? : Block -> Boolean
(define (scheme? k) (string=? (block-language k) "scheme"))

;; readable : (Listof Block) -> (Listof Block) — the Scheme blocks that end and read.
(define (readable bs) (filter (lambda (k) (and (scheme? k) (block-forms k))) bs))

;; program? : Block -> Boolean — the block begins with an import.
(define (program? k)
  (let ((d (block-forms k))) (and (pair? d) (pair? (car d)) (eq? (caar d) 'import))))

;; --- code, tables and links -------------------------------------------------------

;; span-text : String -> String
;; A code span's text (CommonMark §6.1): its line endings read as spaces,
;; and one space each side dropped when both are there and it is not all
;; spaces.
(define (span-text s)
  (let* ((s (list->string (map (lambda (c) (if (char=? c #\newline) #\space c)) (string->list s))))
         (n (string-length s)))
    (if (and (>= n 2) (char=? (string-ref s 0) #\space) (char=? (string-ref s (- n 1)) #\space)
             (not (for-all (lambda (c) (char=? c #\space)) (string->list s))))
        (substring s 1 (- n 1))
        s)))

;; code-spans : String -> (Listof String)
;; The text of each `code` span, in order: a run of backticks opens one, and
;; the next run of as many closes it; a run that none closes is text, and so
;; is a backtick after a backslash.
(define (code-spans text)
  (let ((n (string-length text)))
    ;; closer : Nat Nat -> (U Nat #f) — where the next run of exactly k backticks from i begins.
    (define (closer i k)
      (cond ((>= i n) #f)
            ((char=? (string-ref text i) #\`)
             (let ((m (run text i #\`))) (if (= m k) i (closer (+ i m) k))))
            (else (closer (+ i 1) k))))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((and (char=? (string-ref text i) #\\) (< (+ i 1) n)) (loop (+ i 2) out))
            ((char=? (string-ref text i) #\`)
             (let* ((k (run text i #\`)) (j (closer (+ i k) k)))
               (if j
                   (loop (+ j k) (cons (span-text (substring text (+ i k) j)) out))
                   (loop (+ i k) out))))
            (else (loop (+ i 1) out))))))

;; unwrap : String -> String — `x` as x; anything else as it is.
(define (unwrap s)
  (let ((spans (code-spans s)))
    (if (and (starts? s "`") (ends? s "`") (= (length spans) 1)) (car spans) s)))

;; has-bar? : String -> Boolean
(define (has-bar? line) (and (memv #\| (string->list line)) #t))

;; cells : String -> (Listof String)
;; A table row's cells (GitHub's tables): the row split at each bar not
;; escaped, its outer bars optional; each cell trimmed, \| read as |, and
;; `code` unwrapped.
(define (cells row)
  (let* ((s (trim row))
         (parts (let loop ((cs (string->list s)) (cell '()) (out '()))
                  (cond ((null? cs) (reverse (cons (list->string (reverse cell)) out)))
                        ((and (char=? (car cs) #\\) (pair? (cdr cs)) (char=? (cadr cs) #\|))
                         (loop (cddr cs) (cons #\| cell) out))
                        ((char=? (car cs) #\|) (loop (cdr cs) '() (cons (list->string (reverse cell)) out)))
                        (else (loop (cdr cs) (cons (car cs) cell) out)))))
         (inner (let ((p (if (starts? s "|") (cdr parts) parts)))
                  (if (and (ends? s "|") (not (ends? s "\\|")) (pair? p)) (reverse (cdr (reverse p))) p))))
    (map (lambda (c) (unwrap (trim c))) inner)))

;; delimiter-row? : String -> Boolean — a row of cells each -, any number, a colon either side or not.
(define (delimiter-row? line)
  (and (has-bar? line)
       (let ((cs (cells line)))
         (and (pair? cs)
              (for-all (lambda (c)
                         (let* ((c (if (starts? c ":") (substring c 1 (string-length c)) c))
                                (c (if (ends? c ":") (substring c 0 (- (string-length c) 1)) c)))
                           (and (> (string-length c) 0)
                                (for-all (lambda (ch) (char=? ch #\-)) (string->list c)))))
                       cs)))))

;; table : String String -> (Listof (Listof String))
;; The body rows of the page's first table whose header's first cell is
;; `first`: a row with a bar over a delimiter row of as many cells, then each
;; row up to a blank line or a line with no bar.
(define (table text first)
  (let scan ((ls (text-lines (prose text))))
    (cond ((or (null? ls) (null? (cdr ls))) '())
          ((and (has-bar? (car ls)) (delimiter-row? (cadr ls))
                (= (length (cells (car ls))) (length (cells (cadr ls))))
                (let ((cs (cells (car ls)))) (and (pair? cs) (equal? (car cs) first))))
           (let rows ((ls (cddr ls)) (out '()))
             (if (or (null? ls) (string=? (trim (car ls)) "") (not (has-bar? (car ls))))
                 (reverse out)
                 (rows (cdr ls) (cons (cells (car ls)) out)))))
          (else (scan (cdr ls))))))

;; leading-digits : String -> String — the digits the string starts with.
(define (leading-digits s)
  (let loop ((cs (string->list s)) (out '()))
    (if (and (pair? cs) (char<=? #\0 (car cs)) (char<=? (car cs) #\9))
        (loop (cdr cs) (cons (car cs) out))
        (list->string (reverse out)))))

;; paragraph : String String -> String
;; The paragraph of the text that begins with `words`, up to its blank line;
;; "" when none does.
(define (paragraph text words)
  (let find-start ((ls (text-lines text)))
    (cond ((null? ls) "")
          ((starts? (car ls) words)
           (let take ((ls ls) (out '()))
             (if (or (null? ls) (string=? (trim (car ls)) ""))
                 (joined (reverse out))
                 (take (cdr ls) (cons (car ls) out)))))
          (else (find-start (cdr ls))))))

;; links : String -> (Listof String)
;; The target of each inline link and image, [text](target), in the page's
;; prose: what follows "](" up to a blank or the ")" that ends it.
(define (links text)
  (let ((s (prose text)))
    (let loop ((i 0) (out '()))
      (let ((j (search s "](" i)))
        (if (not j)
            (reverse out)
            (let end ((k (+ j 2)))
              (if (or (>= k (string-length s)) (memv (string-ref s k) '(#\) #\space #\newline)))
                  (loop k (cons (substring s (+ j 2) k) out))
                  (end (+ k 1)))))))))

;; local-path : String -> (U String #f)
;; A link's file, without its #fragment or a leading ./; #f for a link out of
;; the checkout, or to a place on its own page.
(define (local-path target)
  (and (not (exists (lambda (p) (starts? target p)) '("http://" "https://" "mailto:" "#")))
       (let* ((hash (search target "#" 0))
              (path (if hash (substring target 0 hash) target)))
         (if (starts? path "./") (substring path 2 (string-length path)) path))))

;; org-file-links : String -> (Listof String) — the target of each [[file:...]] link of an Org text.
(define (org-file-links text)
  (let loop ((i 0) (out '()))
    (let ((j (search text "[[file:" i)))
      (if (not j)
          (reverse out)
          (let end ((k (+ j 7)))
            (if (or (>= k (string-length text)) (char=? (string-ref text k) #\]))
                (loop k (cons (substring text (+ j 7) k) out))
                (end (+ k 1))))))))

;; --- the Makefile --------------------------------------------------------------

;; target-name? : String -> Boolean — written as a make target is: letters, digits, - _ and .
(define (target-name? w)
  (and (> (string-length w) 0)
       (for-all (lambda (c) (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\- #\_ #\.))))
                (string->list w))))

;; documented-targets : String -> (Listof String)
;; The targets `make help` lists: each line that begins with a target's
;; name, a colon, and later "## ", its description.
(define (documented-targets makefile)
  (fold-right (lambda (l out)
                (let ((colon (search l ":" 0)))
                  (if (and colon (target-name? (substring l 0 colon)) (search l "## " colon))
                      (cons (substring l 0 colon) out)
                      out)))
              '() (text-lines makefile)))

;; make-targets : String -> (Listof String)
;; The targets a shell block asks make for: each word written as a target
;; that follows `make`, past its options and its variables, up to a word
;; that is none of these, such as && or a # comment.
(define (make-targets text)
  (fold-right
   (lambda (line out)
     (let loop ((ws (words line)) (after-make #f))
       (cond ((null? ws) out)
             ((starts? (car ws) "#") out)
             ((string=? (car ws) "make") (loop (cdr ws) #t))
             ((and after-make (or (starts? (car ws) "-") (memv #\= (string->list (car ws)))))
              (loop (cdr ws) #t))
             ((and after-make (target-name? (car ws))) (cons (car ws) (loop (cdr ws) #t)))
             (else (loop (cdr ws) #f)))))
   '() (text-lines text)))

;; --- the numbers a page writes ---------------------------------------------------

;; numbers : String -> (Listof String)
;; Each number the text writes: a digit, then digits, commas and points, any
;; comma or point that ends it left out.  So 5,281 and 10.4.1 are one each.
(define (numbers text)
  (let ((n (string-length text))
        (digit? (lambda (c) (and (char<=? #\0 c) (char<=? c #\9)))))
    (let loop ((i 0) (out '()))
      (cond ((>= i n) (reverse out))
            ((digit? (string-ref text i))
             (let* ((j (let more ((j i))
                         (if (and (< j n) (let ((c (string-ref text j))) (or (digit? c) (memv c '(#\, #\.)))))
                             (more (+ j 1))
                             j)))
                    (k (let back ((k j)) (if (digit? (string-ref text (- k 1))) k (back (- k 1))))))
               (loop j (cons (substring text i k) out))))
            (else (loop (+ i 1) out))))))

;; --- the defaults ----------------------------------------------------------------

;; These are given in whole seconds; the rest in their own unit.
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

;; The fields' names, in make-websocket-limits' order.
(define field-names
  '(max-message-bytes max-queue ping-interval-ms ping-timeout-ms
    close-timeout-ms write-high-water write-low-water write-timeout-ms))

;; A value every field takes, and no field's default: neither water refuses
;; it, at least the low water's default and at most the high water's.  The
;; suite checks it is no default, as it starts.
(define set-to 100000)

;; field-set : Symbol -> (U Symbol (List 'not-a-field Symbol) (List 'sets Symbol (Listof Symbol)))
;; The name, when websocket-limits-with takes it as a field and the one limit
;; set-to changes is the field of that name: else (not-a-field name), when
;; it raises anything, or (sets name changed), the fields it changed.
(define (field-set name)
  (guard (e (#t (list 'not-a-field name)))
    (let ((changed (let loop ((ns field-names)
                              (now (values-of (websocket-limits-with default-websocket-limits (list (cons name set-to)))))
                              (was (values-of default-websocket-limits))
                              (out '()))
                     (cond ((null? ns) (reverse out))
                           ((equal? (car now) (car was)) (loop (cdr ns) (cdr now) (cdr was) out))
                           (else (loop (cdr ns) (cdr now) (cdr was) (cons (car ns) out)))))))
      (if (equal? changed (list name)) name (list 'sets name changed)))))

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

;; The names (websocket) exports, a condition type's &... among them.
(define exported (map symbol->string (library-exports '(websocket))))

;; unbound : (Listof String) -> (Listof String) — the names (websocket) does not export, in order.
(define (unbound ns) (filter (lambda (n) (not (member n exported))) ns))

;; --- the reference page --------------------------------------------------------

;; entries : String -> (Listof (List String String (U Datum #f)))
;; The reference page's entries, in order: each ### heading's first `code`,
;; its name; the words after that code, without parentheses, its kind; and
;; its call form, the first `code` beneath it, before the next heading, that
;; reads as its name or as a list that begins with it, read; or #f.
(define (entries text)
  (let ((finish (lambda (entry lines)
                  (let* ((name (car entry))
                         (form (find (lambda (d) (or (eq? d (string->symbol name))
                                                     (and (pair? d) (eq? (car d) (string->symbol name)))))
                                     (map (lambda (s) (guard (e (#t #f)) (read (open-string-input-port s))))
                                          (code-spans (joined (reverse lines)))))))
                    (list name (cadr entry) form)))))
    (let loop ((ls (text-lines (prose text))) (entry #f) (lines '()) (out '()))
      (let ((done (lambda () (if entry (cons (finish entry lines) out) out))))
        (cond ((null? ls) (reverse (done)))
              ((starts? (car ls) "### ")
               (let* ((h (car ls))
                      (spans (code-spans h))
                      (close (and (pair? spans) (search h "`" (+ 1 (search h "`" 0)))))
                      (after (if close
                                 (trim (substring h (+ close (run h close #\`)) (string-length h)))
                                 ""))
                      (kind (if (and (starts? after "(") (ends? after ")"))
                                (substring after 1 (- (string-length after) 1))
                                after)))
                 (loop (cdr ls) (list (if (pair? spans) (car spans) h) kind) '() (done))))
              ((starts? (car ls) "#") (loop (cdr ls) #f '() (done)))
              (else (loop (cdr ls) entry (if entry (cons (car ls) lines) lines) out)))))))

;; call-mask : (Listof Datum) Nat -> Nat
;; The arity mask of a call form's arguments, past n already taken: a name
;; is one argument, and a bracketed list, [x [y]], is ones a call may stop
;; before.  Chez reads [ ] as ( ).
(define (call-mask args n)
  (cond ((null? args) (bitwise-arithmetic-shift-left 1 n))
        ((pair? (car args))
         (bitwise-ior (bitwise-arithmetic-shift-left 1 n) (call-mask (append (car args) (cdr args)) n)))
        (else (call-mask (cdr args) (+ n 1)))))

;; claim : (List String String (U Datum #f)) -> Any
;; What an entry says its name is: syntax for a condition type; for a
;; procedure or a predicate, (takes mask), the arguments its call form
;; takes; value for a value; else (unread kind form).
(define (claim entry)
  (let ((kind (cadr entry)) (form (caddr entry)))
    (cond ((string=? kind "condition type") 'syntax)
          ((and (member kind '("procedure" "predicate")) (pair? form)) (list 'takes (call-mask (cdr form) 0)))
          ((and (string=? kind "value") (symbol? form)) 'value)
          (else (list 'unread kind form)))))

;; is : String -> Any
;; What (websocket)'s name is, as Chez evaluates it: syntax, when it does
;; not evaluate, as a condition type's name does not; (takes mask) for a
;; procedure; else value.
(define (is name)
  (guard (e (#t 'syntax))
    (let ((v (eval (string->symbol name) (environment '(websocket)))))
      (if (procedure? v) (list 'takes (procedure-arity-mask v)) 'value))))

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

;; program-handler : (Listof Datum) -> (Request -> Answer)
;; The program's handler: its import form's libraries made an environment,
;; its other forms run there with `serve` bound to a procedure that keeps
;; what it is handed.
(define (program-handler forms)
  (let* ((env (apply environment (cdar forms)))
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

;; fragment : (Listof Datum) -> (Request (U WebSocket #f) -> Any)
;; The fragment as a procedure of the request and the WebSocket: its forms a
;; body in the environment a handler's program imports, (rnrs), (http-server)
;; and (websocket), each name it takes from around it given by the suite,
;; unless it defines that name itself.  A name it neither defines nor takes,
;; nor the libraries export, is refused as it is evaluated.
(define (fragment forms)
  (let* ((own (defined forms))
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
  (let* ((all (bv-concat (fake-shell-writes sh)))
         (n (bytevector-length all))
         (blank (b "\r\n\r\n")))
    (let scan ((i 0))
      (cond ((> (+ i 4) n) (list 'no-head '() all))
            ((equal? (bv-slice all i (+ i 4)) blank)
             (let ((r (read-response (bv-slice all 0 (+ i 4)) #f #f)))
               (list (if (eq? (list-ref r 4) 'complete) (car r) (list 'unread (list-ref r 4)))
                     (list-ref r 2)
                     (bv-slice all (+ i 4) n))))
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

;; status : FakeShell -> (U Nat Datum) — the status of what the client read, as a whole response.
(define (status sh) (car (read-response (bv-concat (fake-shell-writes sh)) #f #f)))

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
  (list 101 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" (bv-concat (list rfc-hello (server-frame #x88 (close-body 1000 ""))))))

;; The echo's input: the handshake to the path and a masked Hello; then, in a
;; read of its own once the echo is out, the client's close.  A close that
;; came with the Hello would be answered before the procedure ran, and a send
;; while the server's close is under way sends nothing.
(define (echo-input path) (bv-concat (list (handshake path) rfc-masked-hello)))
(define client-close (client-frame #x88 (close-body 1000 "")))

;; A client's binary frame announcing 2,000,000 bytes, its header and masking
;; key alone (§5.2): past the default cap, 1 MiB, which fails it 1009 before
;; its payload is held, and short of the 16 MiB the limits fragment gives.
(define big-header (bv (append (list #x82) (length-bytes 2000000 128) '(#x37 #xFA #x21 #x3D))))

;; maker : Block Symbol -> (-> (Request -> Answer))
;; A maker of the block's handler: a program's is the handler it serves; a
;; handler's fragment is one; a procedure's runs in the WebSocket
;; websocket-accept gives, with its defaults.
(define (maker k role)
  (lambda ()
    (if (eq? role 'program)
        (program-handler (block-forms k))
        (let ((f (fragment (block-forms k))))
          (if (eq? role 'handler)
              (lambda (request) (f request #f))
              (lambda (request) (websocket-accept request (lambda (ws) (f #f ws)))))))))

;; The Scheme blocks docs/ names, each with where it runs, how it is played,
;; given its handler's maker, and what that must give, from the page's words
;; about it:
;; - echo: a program whose handler takes a WebSocket at /echo and sends each
;;   message back, until the client closes; any other path is 404;
;; - closed-code: a procedure that echoes until the connection closes, then
;;   displays its code, the client's (§5.5.1's 1000);
;; - chat-settings: of the subprotocols a client offers, the first in the
;;   handler's list is chosen (§4.2.2), so chat.v2 of "chat.v1, chat.v2"; a
;;   page from the origin listed is accepted, one from another site refused
;;   403;
;; - upload-limits: a message the default cap refuses is taken, so a frame
;;   announcing 2,000,000 bytes gets no close.
(define known-blocks
  (list (list "echo" 'program
              (lambda (make)
                (list (played make (echo-input "/echo") client-close heard)
                      (played make (b "GET /other HTTP/1.1\r\nHost: server.example.com\r\n\r\n") #f status)))
              (list echo-heard 404))
        (list "closed-code" 'procedure
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
              (lambda (make) (played make (bv-concat (list (handshake "/") big-header)) #f heard))
              (list 101 "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" (make-bytevector 0)))))

;; --- the pages -------------------------------------------------------------------

;; docs/'s files, but its dotfiles, in order.
(define files (list-sort string<? (filter (lambda (f) (not (starts? f "."))) (directory-list "docs"))))

;; page : String -> String — docs/'s page of that name.
(define (page name) (slurp (string-append "docs/" name)))

(run-suite "docs"
  (lambda ()
    ;; Its echoes are the defaults': the binding reads CHEZ_WS_ variables as
    ;; the program starts, and make test runs the suites with none set.
    (let ((set (filter getenv websocket-limits-environment-variables)))
      (unless (null? set)
        (assertion-violation 'docs-suite "a CHEZ_WS_ variable is set; make test unsets them" set)))
    (let* ((pages (filter (lambda (f) (ends? f ".md")) files))
           (texts (map (lambda (p) (cons p (page p))) pages))
           (configuration (page "configuration.md"))
           (handlers (page "handlers.md"))
           (reference (page "reference.md"))
           (all-blocks (apply append (map (lambda (t) (blocks (car t) (cdr t))) texts)))
           (scheme-blocks (filter scheme? all-blocks))
           (rows (table configuration "Variable"))
           (written (names (apply string-append (map cdr texts))))
           (known-names (map car known-blocks)))
      ;; The suite's own frames are §5.7's, and the pages name what a handler
      ;; calls first, so a scan that finds nothing cannot pass.
      (unless (and (equal? (client-frame #x81 (b "Hello")) rfc-masked-hello)
                   (equal? (server-frame #x81 (b "Hello")) rfc-hello))
        (provenance-failure "the suite's frames are not RFC 6455 §5.7's"))
      (unless (for-all (lambda (n) (member n written))
                       '("websocket-accept" "websocket-receive" "websocket-send!" "websocket-close!"))
        (provenance-failure "the pages' names were not found: the scan reads nothing"))
      (when (null? (filter program? (readable scheme-blocks)))
        (provenance-failure "docs/ holds no program"))
      (when (member set-to (values-of default-websocket-limits))
        (provenance-failure "the value the fields are set to is a default: a field set to it changes nothing"))

      ;; --- the pages, their blocks and their links ---

      (test-equal "docs/ is Markdown alone: every file but a dotfile is a .md page"
        '() (filter (lambda (f) (not (ends? f ".md"))) files))

      (test-equal "docs/README.md, the home page, links every other page"
        '()
        (let ((linked (map local-path (links (page "README.md")))))
          (filter (lambda (p) (not (or (string=? p "README.md") (member p linked)))) pages)))

      (test-equal "every link in docs/ to a file in the checkout names one there"
        '()
        (apply append
               (map (lambda (t)
                      (map (lambda (path) (list (car t) path))
                           (filter (lambda (path) (not (file-exists? (string-append "docs/" path))))
                                   (filter (lambda (p) (and p (not (string=? p "")))) (map local-path (links (cdr t)))))))
                    texts)))

      (test-equal "every file README.org links names one in the checkout"
        '() (filter (lambda (path) (not (file-exists? path))) (org-file-links (slurp "README.org"))))

      (test-equal "every fenced block in docs/ says its language: scheme, sh or text"
        '()
        (map (lambda (k) (list (block-page k) (block-language k)))
             (filter (lambda (k) (not (member (block-language k) '("scheme" "sh" "text")))) all-blocks)))

      (test-equal "every make target docs/ runs is one the Makefile documents"
        '()
        (let ((documented (documented-targets (slurp "Makefile"))))
          (filter (lambda (t) (not (member t documented)))
                  (apply append (map (lambda (k) (make-targets (block-text k)))
                                     (filter (lambda (k) (string=? (block-language k) "sh")) all-blocks))))))

      (test-equal "every number performance.md and testing.md write is one the repository records: CHANGELOG.md, README.org or tests/autobahn/verdicts.txt"
        '()
        (let ((recorded (numbers (string-append (slurp "CHANGELOG.md") (slurp "README.org")
                                                (slurp "tests/autobahn/verdicts.txt")))))
          (filter (lambda (n) (not (member n recorded)))
                  (numbers (string-append (page "performance.md") (page "testing.md"))))))

      ;; --- configuration.md ---

      (test-equal "configuration.md's table names the variables (websocket limits) reads, in its order"
        websocket-limits-environment-variables
        (map car rows))

      (test-equal "configuration.md's defaults are (websocket limits)' defaults, each written in its variable's unit: whole seconds for a duration, its own unit for a size or a count"
        (values-of default-websocket-limits)
        (let* ((cells (map (lambda (row) (cons (car row) (given row))) rows))
               (unreadable (filter (lambda (p) (pair? (cdr p))) cells)))
          (if (pair? unreadable)
              (map cdr unreadable)
              (guard (e ((assertion-violation? e) (list 'refused (condition-irritants e))))
                (values-of (websocket-limits-from-environment
                            (lambda (name) (let ((p (assoc name cells))) (and p (cdr p))))))))))

      ;; --- the names, the fields, and the reference ---

      (test-equal "every name of the library's that docs/ writes is one (websocket) exports"
        '() (unbound written))

      (test-equal "the fields handlers.md lists are the limits' fields, each one websocket-limits-with takes and sets in its own place, in their order"
        field-names
        (map (lambda (s) (field-set (string->symbol s))) (code-spans (paragraph handlers "The fields are"))))

      (test-equal "reference.md has one entry for each name (websocket) exports, and no other"
        (list-sort string<? exported)
        (list-sort string<? (map car (entries reference))))

      (test-equal "each entry of reference.md says what its name is: a condition type, a value, or a procedure whose call form takes the arguments the procedure takes"
        (map (lambda (n) (list n (is n))) (list-sort string<? exported))
        (map (lambda (n) (list n (let ((e (assoc n (entries reference)))) (if e (claim e) 'missing))))
             (list-sort string<? exported)))

      ;; --- the Scheme blocks, read and run ---

      (test-equal "every Scheme block in docs/ ends, and reads as Scheme"
        (map (lambda (k) 'read) scheme-blocks)
        (map (lambda (k)
               (cond ((not (block-ended? k)) (list 'unterminated (block-page k) (block-text k)))
                     ((not (block-forms k)) (list 'unread (block-page k) (block-text k)))
                     (else 'read)))
             scheme-blocks))

      (test-equal "every Scheme block in docs/ has a name the suite knows"
        '()
        (map (lambda (k) (list (block-page k) (block-name k)))
             (filter (lambda (k) (not (member (block-name k) known-names))) scheme-blocks)))

      (test-equal "every block the suite knows is in docs/"
        '()
        (filter (lambda (n) (not (exists (lambda (k) (equal? (block-name k) n)) (readable scheme-blocks))))
                known-names))

      ;; Each known block, its page, its name and what its play gave.
      (let ((runnable (filter (lambda (k) (member (block-name k) known-names)) (readable scheme-blocks))))
        (test-equal "each Scheme block in docs/ does what its page says of it"
          (map (lambda (k) (list (block-page k) (block-name k) (cadddr (assoc (block-name k) known-blocks))))
               runnable)
          (map (lambda (k)
                 (let ((known (assoc (block-name k) known-blocks)))
                   (list (block-page k) (block-name k) ((caddr known) (maker k (cadr known))))))
               runnable))))))
