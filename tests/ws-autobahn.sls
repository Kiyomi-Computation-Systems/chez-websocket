#!r6rs
;;; (ws-autobahn) — the Autobahn lane's gate (M5, decision 0008).
;;;
;;; Autobahn's fuzzing client writes each case's verdict to an index.json and
;;; exits 0 whatever they are; a connection that fails ends its run there,
;;; still 0.  So the gate reads the index against the ratchet,
;;; tests/autobahn/verdicts.txt, a line a case:
;;;
;;;   <case> <behavior> <behaviorClose> <close code, or none>
;;;
;;; and holds it both ways: a verdict that differs either way is a difference,
;;; and so is a case only one of them has.  A promotion is a reviewed diff of
;;; the ratchet, as chez-http-server's ratchet holds its corpora (its decision
;;; 0008).  The close code is the one the server sent, which Autobahn reads as
;;; remoteCloseCode; none where it sent none.  A field may list alternatives,
;;; a | between them, for a case whose verdict was measured to vary with how
;;; the client's bytes fall into reads (decision 0008, by form: "List what was
;;; measured"); the case passes with any of them.
;;;
;;;   json-read : String -> Json
;;;   verdicts-parse : String -> (Listof Held)
;;;   spec-agent : Json -> String
;;;   index-verdicts : Json String -> (Listof Verdict)
;;;   verdict-differences : (Listof Verdict) (Listof Verdict) -> (Listof String)
;;;   autobahn-gate : String String String TextualOutputPort -> (U 0 1 2)
;;;
;;; Json is RFC 8259's value: an object a list of (name . value) pairs in
;;; order, an array a vector, a string, a number, #t, #f, or the symbol null.
;;; A Verdict is a list of four strings: the case, its behavior, its
;;; behaviorClose and its close code.  A Held is the ratchet's: the case, then
;;; each of the other three fields as a list of its alternatives.  Each
;;; procedure raises an &error with a message for a text it refuses.
(library (ws-autobahn)
  (export json-read verdicts-parse spec-agent index-verdicts verdict-differences
          autobahn-gate)
  (import (rnrs))

  ;; --- JSON (RFC 8259) --------------------------------------------------------

  ;; json-read : String -> Json
  ;; The one value the text holds, with whitespace around it.  A lone
  ;; surrogate's escape is refused too, since a string cannot hold it.
  (define (json-read text)
    (define n (string-length text))
    (define (fail-at i)
      (error 'json-read
             (string-append (if (< i n) "unexpected character at index " "unexpected end at index ")
                            (number->string i))))
    (define (at? i c) (and (< i n) (char=? (string-ref text i) c)))
    (define (digit-at? i) (and (< i n) (char<=? #\0 (string-ref text i) #\9)))
    (define (skip i)
      (if (and (< i n) (memv (string-ref text i) '(#\space #\tab #\newline #\return)))
          (skip (+ i 1))
          i))
    (define (expect i c) (if (at? i c) (+ i 1) (fail-at i)))
    ;; Each reader below takes the index its value starts at and answers the
    ;; value and the index just past it.
    (define (value i)
      (let ((i (skip i)))
        (cond ((at? i #\{) (object (+ i 1)))
              ((at? i #\[) (array (+ i 1)))
              ((at? i #\") (str (+ i 1)))
              ((or (at? i #\-) (digit-at? i)) (number i))
              (else (literal i)))))
    (define (object i)
      (let ((i (skip i)))
        (if (at? i #\})
            (values '() (+ i 1))
            (let loop ((i i) (members '()))
              (let ((i (skip i)))
                (unless (at? i #\") (fail-at i))
                (let*-values (((name i) (str (+ i 1)))
                              ((v i) (value (expect (skip i) #\:))))
                  (let ((i (skip i)) (members (cons (cons name v) members)))
                    (cond ((at? i #\,) (loop (+ i 1) members))
                          ((at? i #\}) (values (reverse members) (+ i 1)))
                          (else (fail-at i))))))))))
    (define (array i)
      (let ((i (skip i)))
        (if (at? i #\])
            (values '#() (+ i 1))
            (let loop ((i i) (elements '()))
              (let-values (((v i) (value i)))
                (let ((i (skip i)) (elements (cons v elements)))
                  (cond ((at? i #\,) (loop (+ i 1) elements))
                        ((at? i #\]) (values (list->vector (reverse elements)) (+ i 1)))
                        (else (fail-at i)))))))))
    (define (str i)
      (let-values (((out extract) (open-string-output-port)))
        (let loop ((i i))
          (cond ((>= i n) (fail-at i))
                ((char=? (string-ref text i) #\") (values (extract) (+ i 1)))
                ((char=? (string-ref text i) #\\) (loop (escape (+ i 1) out)))
                ((char<? (string-ref text i) #\x20) (fail-at i))
                (else (put-char out (string-ref text i)) (loop (+ i 1)))))))
    ;; escape : Nat TextualOutputPort -> Nat — the escape after a backslash,
    ;; its character written; the index past it.
    (define (escape i out)
      (define (put c next) (put-char out c) next)
      (if (>= i n)
          (fail-at i)
          (case (string-ref text i)
            ((#\" #\\ #\/) (put (string-ref text i) (+ i 1)))
            ((#\b) (put (integer->char 8) (+ i 1)))
            ((#\f) (put (integer->char 12) (+ i 1)))
            ((#\n) (put #\newline (+ i 1)))
            ((#\r) (put #\return (+ i 1)))
            ((#\t) (put #\tab (+ i 1)))
            ((#\u)
             (let ((u (hex4 (+ i 1))) (j (+ i 5)))
               (cond ((<= #xD800 u #xDBFF)
                      (unless (and (at? j #\\) (at? (+ j 1) #\u)) (fail-at j))
                      (let ((low (hex4 (+ j 2))))
                        (unless (<= #xDC00 low #xDFFF) (fail-at (+ j 2)))
                        (put (integer->char (+ #x10000 (* (- u #xD800) #x400) (- low #xDC00)))
                             (+ j 6))))
                     ((<= #xDC00 u #xDFFF) (fail-at (+ i 1)))
                     (else (put (integer->char u) j)))))
            (else (fail-at i)))))
    (define (hex4 i)
      (let loop ((j i) (v 0))
        (if (= j (+ i 4))
            v
            (let ((c (and (< j n) (string-ref text j))))
              (cond ((and c (char<=? #\0 c #\9)) (loop (+ j 1) (+ (* v 16) (- (char->integer c) 48))))
                    ((and c (char<=? #\a c #\f)) (loop (+ j 1) (+ (* v 16) (- (char->integer c) 87))))
                    ((and c (char<=? #\A c #\F)) (loop (+ j 1) (+ (* v 16) (- (char->integer c) 55))))
                    (else (fail-at j)))))))
    ;; number : §6's grammar, [ minus ] int [ frac ] [ exp ], read by
    ;; string->number once it has matched.
    (define (number i)
      (define (digits j) (if (digit-at? j) (digits (+ j 1)) j))
      (define (digits1 j) (if (digit-at? j) (digits (+ j 1)) (fail-at j)))
      (let* ((j (if (at? i #\-) (+ i 1) i))
             (j (cond ((at? j #\0) (+ j 1))
                      ((digit-at? j) (digits (+ j 1)))
                      (else (fail-at j))))
             (j (if (at? j #\.) (digits1 (+ j 1)) j))
             (j (if (or (at? j #\e) (at? j #\E))
                    (digits1 (if (or (at? (+ j 1) #\+) (at? (+ j 1) #\-)) (+ j 2) (+ j 1)))
                    j)))
        (values (string->number (substring text i j)) j)))
    (define (literal i)
      (define (word? w) (let ((m (string-length w)))
                          (and (<= (+ i m) n) (string=? (substring text i (+ i m)) w))))
      (cond ((word? "true") (values #t (+ i 4)))
            ((word? "false") (values #f (+ i 5)))
            ((word? "null") (values 'null (+ i 4)))
            (else (fail-at i))))
    (let-values (((v i) (value 0)))
      (let ((i (skip i)))
        (if (= i n) v (fail-at i)))))

  ;; member-ref : Json String -> (U Json #f)
  ;; The value of the object's member of that name, or #f when it is not an
  ;; object or has none.
  (define (member-ref obj name)
    (and (list? obj)
         (let ((m (assoc name obj))) (and m (cdr m)))))

  ;; --- the ratchet -------------------------------------------------------------

  ;; split : String Char -> (Listof String)
  (define (split s c)
    (let loop ((i 0) (start 0) (parts '()))
      (cond ((= i (string-length s)) (reverse (cons (substring s start i) parts)))
            ((char=? (string-ref s i) c) (loop (+ i 1) (+ i 1) (cons (substring s start i) parts)))
            (else (loop (+ i 1) start parts)))))

  ;; verdicts-parse : String -> (Listof Held)
  ;; The ratchet's verdicts in its order.  A line that is empty or begins
  ;; with # is skipped; every other holds four fields, a space between each,
  ;; the last three each one or more alternatives, a | between them.
  (define (verdicts-parse text)
    (define (refuse k why)
      (error 'verdicts-parse (string-append "line " (number->string k) ": " why)))
    (let loop ((lines (split text #\newline)) (k 1) (held '()))
      (cond ((null? lines) (reverse held))
            ((or (string=? (car lines) "") (char=? (string-ref (car lines) 0) #\#))
             (loop (cdr lines) (+ k 1) held))
            (else
             (let ((fields (split (car lines) #\space)))
               (unless (and (= (length fields) 4) (not (member "" fields)))
                 (refuse k "not a case, behavior, behaviorClose and close code"))
               (let ((alternatives (map (lambda (f) (split f #\|)) (cdr fields))))
                 (when (exists (lambda (as) (member "" as)) alternatives)
                   (refuse k "an alternative is empty"))
                 (unless (for-all code? (caddr alternatives))
                   (refuse k "a close code is digits or none"))
                 (when (assoc (car fields) held)
                   (refuse k (string-append "case " (car fields) " is named twice")))
                 (loop (cdr lines) (+ k 1) (cons (cons (car fields) alternatives) held))))))))

  ;; code? : String -> Boolean — "none", or ASCII digits.
  (define (code? s)
    (or (string=? s "none")
        (for-all (lambda (c) (char<=? #\0 c #\9)) (string->list s))))

  ;; --- the spec and the index ------------------------------------------------------

  ;; spec-agent : Json -> String
  ;; The agent of the one server a fuzzing client's spec names.
  (define (spec-agent spec)
    (let* ((servers (member-ref spec "servers"))
           (count (if (vector? servers) (vector-length servers) 0)))
      (unless (= count 1)
        (error 'spec-agent (string-append "it names " (number->string count) " servers, not one")))
      (let ((agent (member-ref (vector-ref servers 0) "agent")))
        (if (string? agent) agent (error 'spec-agent "its server names no agent")))))

  ;; index-verdicts : Json String -> (Listof Verdict)
  ;; The verdicts an index holds for the agent, in its order: the index must
  ;; hold that agent alone.
  (define (index-verdicts index agent)
    (define (refuse . parts) (error 'index-verdicts (apply string-append parts)))
    (unless (and (list? index) (assoc agent index))
      (refuse "the index holds no agent " agent))
    (unless (= (length index) 1)
      (refuse "the index holds " (number->string (length index)) " agents, not " agent " alone"))
    (let ((cases (member-ref index agent)))
      (unless (list? cases) (refuse "the agent " agent "'s cases are not an object"))
      (map (lambda (entry)
             (let ((id (car entry)) (fields (cdr entry)))
               (unless (list? fields) (refuse "case " id ": not an object"))
               (let ((behavior (member-ref fields "behavior"))
                     (close (member-ref fields "behaviorClose"))
                     (code (member-ref fields "remoteCloseCode")))
                 (unless (string? behavior) (refuse "case " id ": behavior is not a string"))
                 (unless (string? close) (refuse "case " id ": behaviorClose is not a string"))
                 (list id behavior close
                       (cond ((eq? code 'null) "none")
                             ((and (integer? code) (exact? code) (>= code 0)) (number->string code))
                             (else (refuse "case " id ": remoteCloseCode is not a code or null")))))))
           cases)))

  ;; --- the gate -----------------------------------------------------------------------

  ;; verdict-text : Verdict -> String — its behavior, behaviorClose and code.
  (define (verdict-text v)
    (string-append (cadr v) " " (caddr v) " " (cadddr v)))

  ;; held-text : Held -> String — its fields as the ratchet writes them.
  (define (held-text h)
    (define (alternatives as)
      (if (null? (cdr as)) (car as) (string-append (car as) "|" (alternatives (cdr as)))))
    (string-append (alternatives (cadr h)) " " (alternatives (caddr h)) " " (alternatives (cadddr h))))

  ;; holds? : Held Verdict -> Boolean — each of the run's fields is one the
  ;; ratchet lists.
  (define (holds? h v)
    (and (member (cadr v) (cadr h)) (member (caddr v) (caddr h)) (member (cadddr v) (cadddr h)) #t))

  ;; verdict-differences : (Listof Held) (Listof Verdict) -> (Listof String)
  ;; A line for each case of the ratchet the run differs on or lacks, in the
  ;; ratchet's order, then one for each case only the run has, in its order.
  (define (verdict-differences held run)
    (append
     (filter string?
             (map (lambda (h)
                    (let ((r (assoc (car h) run)))
                      (cond ((not r) (string-append (car h) ": ratchet " (held-text h) ", not in the run"))
                            ((holds? h r) #f)
                            (else (string-append (car h) ": ratchet " (held-text h)
                                                 ", run " (verdict-text r))))))
                  held))
     (map (lambda (r) (string-append (car r) ": not in the ratchet, run " (verdict-text r)))
          (filter (lambda (r) (not (assoc (car r) held))) run))))

  ;; tally : (Listof Verdict) -> String — "2 OK, 1 NON-STRICT": each behavior
  ;; a run has, with its count, in the order it first appears.
  (define (tally run)
    (let loop ((vs run) (seen '()))
      (if (null? vs)
          (let join ((behaviors (reverse seen)))
            (let ((b (car behaviors)))
              (string-append
               (number->string (length (filter (lambda (v) (string=? (cadr v) b)) run))) " " b
               (if (null? (cdr behaviors)) "" (string-append ", " (join (cdr behaviors)))))))
          (loop (cdr vs) (if (member (cadr (car vs)) seen) seen (cons (cadr (car vs)) seen))))))

  ;; harness-failure : what the gate could not read, and why.
  (define-record-type harness-failure (fields (immutable why harness-failure-why)))

  ;; autobahn-gate : String String String TextualOutputPort -> (U 0 1 2)
  ;; The spec's, ratchet's and index's texts held against each other: 0 when
  ;; the run's every verdict is the ratchet's, 1 when they differ, 2 when one
  ;; of them cannot be read or the ratchet holds no case.  Its report, a line
  ;; a difference and a closing line, goes to the port.
  (define (autobahn-gate spec-text ratchet-text index-text port)
    (define (say . parts)
      (put-string port (apply string-append "autobahn: " parts))
      (newline port))
    (define (reading what thunk)
      (guard (e ((and (error? e) (message-condition? e))
                 (make-harness-failure (string-append what ": " (condition-message e)))))
        (thunk)))
    (define (harness failure) (say (harness-failure-why failure)) 2)
    (let ((agent (reading "the spec" (lambda () (spec-agent (json-read spec-text))))))
      (if (harness-failure? agent)
          (harness agent)
          (let ((held (reading "the ratchet" (lambda () (verdicts-parse ratchet-text)))))
            (cond ((harness-failure? held) (harness held))
                  ((null? held) (say "the ratchet holds no case") 2)
                  (else
                   (let ((run (reading "the index"
                                       (lambda () (index-verdicts (json-read index-text) agent)))))
                     (if (harness-failure? run)
                         (harness run)
                         (let ((differences (verdict-differences held run))
                               (cases (number->string (length held))))
                           (cond ((null? differences)
                                  (say cases " cases as the ratchet holds them: " (tally run))
                                  0)
                                 (else
                                  (for-each (lambda (d) (put-string port d) (newline port)) differences)
                                  (say (number->string (length differences))
                                       (if (= (length differences) 1) " difference" " differences")
                                       " from the ratchet, of " cases " cases")
                                  (when (exists (lambda (h) (not (assoc (car h) run))) held)
                                    (say "a run ends at a connection that fails, and wstest still exits 0: see its log"))
                                  1))))))))))))
