#!r6rs
;;; (ws-autobahn): the Autobahn lane's gate (M5, decision 0008).
;;;
;;; Autobahn's fuzzing client exits 0 whatever its cases show, and when a
;;; connection fails it ends its run there, still 0 (its fuzzing.py).  So the
;;; lane is gated on the index.json it writes, read against the ratchet,
;;; tests/autobahn/verdicts.txt: every case's behavior, behaviorClose and the
;;; close code the server sent, held both ways, as chez-http-server's ratchet
;;; holds its corpora (its decision 0008): a verdict that changes either way
;;; is a difference, and so is a case only one side has.  A case whose
;;; verdict was measured to vary with how the client's bytes fall into reads
;;; lists each whole verdict seen, " | " between them (decision 0008, by form:
;;; "List what was measured"), and passes with any one of them, not with a
;;; pairing of their fields never seen.  This suite holds the gate on texts of
;;; its own, so it runs without Docker.
;;;
;;; The oracles are RFC 8259's grammar and its examples (§7, §13), and the
;;; index as Autobahn 25.10.1 writes it: an object holding the agent the spec
;;; names, its cases' ids sorted as strings, each case's fields sorted, three
;;; spaces a level, and null for a close code the server did not send (case
;;; 7.3.1 in the lane's run, which the fixture below copies).
;;;
;;; - JSON: RFC 8259's examples, every escape of §7, the G clef's surrogate
;;;   pair, the number grammar at its edges, and texts it refuses.
;;; - Lines: a CR before a LF is dropped, so a CRLF checkout reads alike.
;;; - The ratchet's lines: comments, blanks, a case and its verdicts; malformed
;;;   lines, a verdict listed twice and a case named twice refused, naming the
;;;   line.
;;; - The index: the one agent the spec names, its verdicts in the run's order.
;;; - The gate: a run as the ratchet holds passes, in any order, with any of a
;;;   case's verdicts; each kind of difference fails naming its case; a run that
;;;   lacks cases, an empty index among them (wstest's when no connection
;;;   opened), says how many and why runs end short; anything it cannot read
;;;   is a harness error, status 2.
;;; - gate-main, gate.sps's body: its three paths in order; a wrong count, an
;;;   unreadable path, or any raise at all, status 2.
(import (rnrs) (srfi :64) (ws-testing) (ws-text) (ws-autobahn))

;; raised : (-> Any) -> (U (List 'refused String) (List 'returned Any))
;; What a thunk did: the message of the &error it raised, or what it gave.
(define (raised thunk)
  (guard (e ((and (error? e) (message-condition? e)) (list 'refused (condition-message e))))
    (list 'returned (thunk))))

;; refused? : (-> Any) -> (U 'refused (List 'returned Any))
(define (refused thunk)
  (let ((r (raised thunk)))
    (if (eq? (car r) 'refused) 'refused r)))

;; repeat : Nat Any -> (Listof Any)
(define (repeat n x) (if (= n 0) '() (cons x (repeat (- n 1) x))))

;; gate-run : String String String -> (List Status (Listof String))
;; The gate's status and the lines it wrote.
(define (gate-run spec ratchet index)
  (let-values (((port extract) (open-string-output-port)))
    (let ((status (autobahn-gate spec ratchet index port)))
      (list status (text-lines (extract))))))

;; main-run : (Listof String) (String -> (U String #f)) -> (List Status (Listof String))
;; gate-main's status and the lines it wrote.
(define (main-run paths read)
  (let-values (((port extract) (open-string-output-port)))
    (let ((status (gate-main paths read port)))
      (list status (text-lines (extract))))))

(define spec
  "{\n  \"outdir\": \"/reports\",\n  \"servers\": [{\"agent\": \"chez-websocket\", \"url\": \"ws://127.0.0.1:9001\"}],\n  \"cases\": [\"*\"],\n  \"exclude-cases\": [\"12.*\", \"13.*\"],\n  \"exclude-agent-cases\": {}\n}\n")

;; case-text : String String String String -> String — one case as Autobahn writes it.
(define (case-text id behavior close code)
  (string-append
   "      \"" id "\": {\n"
   "         \"behavior\": \"" behavior "\",\n"
   "         \"behaviorClose\": \"" close "\",\n"
   "         \"duration\": 3,\n"
   "         \"remoteCloseCode\": " code ",\n"
   "         \"reportfile\": \"chez_websocket_case_" id ".json\"\n"
   "      }"))

;; index-text : String (Listof String) -> String — an index of one agent.
(define (index-text agent cases)
  (string-append
   "{\n   \"" agent "\": {\n"
   (let join ((cs cases))
     (cond ((null? cs) "")
           ((null? (cdr cs)) (car cs))
           (else (string-append (car cs) ",\n" (join (cdr cs))))))
   "\n   }\n}"))

(define ok-111 (case-text "1.1.1" "OK" "OK" "1000"))
(define ns-32 (case-text "3.2" "NON-STRICT" "OK" "1002"))
(define ok-731 (case-text "7.3.1" "OK" "OK" "null"))
(define ok-34 (case-text "3.4" "OK" "OK" "1002"))
(define run (index-text "chez-websocket" (list ok-111 ns-32 ok-34 ok-731)))

(define ratchet
  "# A comment, then a blank line.\n\n1.1.1 OK OK 1000\n3.2 NON-STRICT OK 1002\n3.4 OK OK 1002 | NON-STRICT OK 1002 | NON-STRICT OK none\n7.3.1 OK OK none\n")

;; held : the ratchet's verdicts, as verdicts-parse gives them.
(define held
  '(("1.1.1" ("OK" "OK" "1000")) ("3.2" ("NON-STRICT" "OK" "1002"))
    ("3.4" ("OK" "OK" "1002") ("NON-STRICT" "OK" "1002") ("NON-STRICT" "OK" "none"))
    ("7.3.1" ("OK" "OK" "none"))))

;; crlf : String -> String — each LF preceded by a CR.
(define (crlf s)
  (let-values (((port extract) (open-string-output-port)))
    (string-for-each (lambda (c) (when (char=? c #\newline) (put-char port #\return)) (put-char port c)) s)
    (extract)))

(define held-34 "3.4: ratchet OK OK 1002 | NON-STRICT OK 1002 | NON-STRICT OK none")

;; no-case-ran : -> (List Status (Listof String)) — the gate on a run of no case.
(define (no-case-ran)
  (list 1 (list "1.1.1: ratchet OK OK 1000, not in the run"
                "3.2: ratchet NON-STRICT OK 1002, not in the run"
                (string-append held-34 ", not in the run")
                "7.3.1: ratchet OK OK none, not in the run"
                "autobahn: 4 differences from the ratchet, of 4 cases"
                "autobahn: 4 cases of the ratchet did not run: wstest ends a run at a connection that fails, and still exits 0, so its log says whether one did")))

;; run-with : String -> String — the run, with case 3.4's text replaced.
(define (run-with c34) (index-text "chez-websocket" (list ok-111 ns-32 c34 ok-731)))

(run-suite "autobahn"
  (lambda ()
    ;; --- JSON (RFC 8259) ---------------------------------------------------

    (test-equal "RFC 8259 §13's object, members in order, an array as a vector"
      '(("Image" ("Width" . 800) ("Height" . 600) ("Title" . "View from 15th Floor")
         ("Thumbnail" ("Url" . "http://www.example.com/image/481989943") ("Height" . 125) ("Width" . 100))
         ("Animated" . #f) ("IDs" . #(116 943 234 38793))))
      (json-read "{\n  \"Image\": {\n      \"Width\":  800,\n      \"Height\": 600,\n      \"Title\":  \"View from 15th Floor\",\n      \"Thumbnail\": {\n          \"Url\":    \"http://www.example.com/image/481989943\",\n          \"Height\": 125,\n          \"Width\":  100\n      },\n      \"Animated\" : false,\n      \"IDs\": [116, 943, 234, 38793]\n    }\n}"))

    (test-equal "RFC 8259 §13's array of two objects, its fractions read as decimals"
      '#((("precision" . "zip") ("Latitude" . 37.7668) ("Longitude" . -122.3959) ("Address" . "")
          ("City" . "SAN FRANCISCO") ("State" . "CA") ("Zip" . "94107") ("Country" . "US"))
         (("precision" . "zip") ("Latitude" . 37.371991) ("Longitude" . -122.02602) ("Address" . "")
          ("City" . "SUNNYVALE") ("State" . "CA") ("Zip" . "94085") ("Country" . "US")))
      (json-read "[\n {\n  \"precision\": \"zip\",\n  \"Latitude\":  37.7668,\n  \"Longitude\": -122.3959,\n  \"Address\":   \"\",\n  \"City\":      \"SAN FRANCISCO\",\n  \"State\":     \"CA\",\n  \"Zip\":       \"94107\",\n  \"Country\":   \"US\"\n },\n {\n  \"precision\": \"zip\",\n  \"Latitude\":  37.371991,\n  \"Longitude\": -122.026020,\n  \"Address\":   \"\",\n  \"City\":      \"SUNNYVALE\",\n  \"State\":     \"CA\",\n  \"Zip\":       \"94085\",\n  \"Country\":   \"US\"\n }\n]"))

    (test-equal "RFC 8259 §13's three texts of a value alone, and the other literals, in §2's whitespace"
      '("Hello world!" 42 #t #f null #() ())
      (map json-read '("\"Hello world!\"" "42" "true" "\t\r\n false\t\r\n " "null" "[ ]" "{ }")))

    (test-equal "every escape of §7, \\u in either case, and the G clef as a surrogate pair"
      (list (string #\" #\\ #\/ (integer->char 8) (integer->char 12) #\newline #\return #\tab)
            "\\" "\\" (string #\x1D11E) (string #\x1D11E #\A) (string #\xE9))
      (map json-read '("\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"" "\"\\u005C\"" "\"\\u005c\""
                       "\"\\uD834\\uDD1E\"" "\"\\ud834\\udd1eA\"" "\"\\u00e9\"")))

    (test-equal "§6's numbers: zero, a minus, a fraction, exponents of every form"
      '(0 -0 -12 2.5 100.0 100.0 100.0 0.01 1.5e300)
      (map json-read '("0" "-0" "-12" "2.5" "1e2" "1E2" "1e+2" "1e-2" "1.5e300")))

    (test-equal "texts RFC 8259 refuses, and a lone surrogate, are refused"
      (repeat 28 'refused)
      (map (lambda (text) (refused (lambda () (json-read text))))
           '("" "   " "{" "[1,]" "{\"a\":1,}" "{\"a\" 1}" "{1:2}" "[1 2]" "01" "-" "1." ".5" "1e"
             "+1" "\"open" "\"\\x\"" "\"\\u12G4\"" "\"a\tb\"" "tru" "nul" "1 2" "\"\\uDD1E\"" "\"\\uD834A\""
             "{x\": 2}" "{\"a\"x1}" "\"\\uD834xuDD1E\"" "\"\\uD834\\u0041\"" "[1]x")))

    (test-equal "a refusal says where it stopped"
      '(refused "unexpected character at index 4")
      (raised (lambda () (json-read "[1, }"))))

    ;; --- lines and the ratchet ---------------------------------------------------

    (test-equal "text-lines: a line a LF, a CR before it dropped, no line after the last LF"
      '(("a" "b" "" "c") ("a") () ("a" ""))
      (map text-lines (list "a\r\nb\n\nc" "a\n" "" "a\r\n\r\n")))

    (test-equal "the ratchet: comments and blank lines skipped, a case and its verdicts, \" | \" between them"
      held
      (verdicts-parse ratchet))

    (test-equal "and read alike from a CRLF checkout"
      held
      (verdicts-parse (crlf ratchet)))

    (test-equal "a line not a case and whole verdicts, a code not digits, a verdict or a case twice, refused by line"
      '((refused "line 2: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: a close code is digits or none")
        (refused "line 1: a close code is digits or none")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: not a case and its verdicts")
        (refused "line 1: a verdict is listed twice")
        (refused "line 3: case 1.1.1 is named twice"))
      (map (lambda (text) (raised (lambda () (verdicts-parse text))))
           '("1.1.1 OK OK 1000\n1.1.2 OK OK\n" "1.1.1 OK OK 1000 x\n" "1.1.1  OK OK 1000\n"
             "1.1.1 OK OK 10a0\n" "1.1.1 OK OK 1000 | OK OK x\n" "1.1.1 OK OK 1000 |\n"
             "1.1.1 OK OK 1000 | OK OK\n" "1.1.1 OK OK 1000 || OK OK 1000\n" "1.1.1 OK OK 1000 x OK OK 1000\n"
             " OK OK 1000\n" "1.1.1 OK OK 1000 | OK OK 1000\n" "1.1.1 OK OK 1000\n# again\n1.1.1 OK OK 1000\n")))

    ;; --- the index --------------------------------------------------------------------

    (test-equal "the spec's agent, and its verdicts in the run's order, null as none"
      '("chez-websocket"
        (("1.1.1" "OK" "OK" "1000") ("3.2" "NON-STRICT" "OK" "1002") ("3.4" "OK" "OK" "1002")
         ("7.3.1" "OK" "OK" "none")))
      (list (spec-agent (json-read spec))
            (index-verdicts (json-read run) "chez-websocket")))

    (test-equal "an index not of the spec's one agent, or a case missing a field, refused"
      '((refused "the index holds no agent chez-websocket")
        (refused "the index holds 2 agents, not chez-websocket alone")
        (refused "case 1.1.1: behavior is not a string")
        (refused "case 1.1.1: behaviorClose is not a string")
        (refused "case 1.1.1: remoteCloseCode is not a code or null")
        (refused "case 1.1.1: remoteCloseCode is not a code or null")
        (refused "case 1.1.1: not an object")
        (refused "the agent chez-websocket's cases are not an object"))
      (map (lambda (text) (raised (lambda () (index-verdicts (json-read text) "chez-websocket"))))
           (list (index-text "other" (list ok-111))
                 (string-append "{\"chez-websocket\": {}, \"other\": {}}")
                 "{\"chez-websocket\": {\"1.1.1\": {\"behaviorClose\": \"OK\", \"remoteCloseCode\": 1000}}}"
                 "{\"chez-websocket\": {\"1.1.1\": {\"behavior\": \"OK\", \"behaviorClose\": 5, \"remoteCloseCode\": 1000}}}"
                 "{\"chez-websocket\": {\"1.1.1\": {\"behavior\": \"OK\", \"behaviorClose\": \"OK\", \"remoteCloseCode\": \"1000\"}}}"
                 "{\"chez-websocket\": {\"1.1.1\": {\"behavior\": \"OK\", \"behaviorClose\": \"OK\", \"remoteCloseCode\": 1000.5}}}"
                 "{\"chez-websocket\": {\"1.1.1\": 5}}"
                 "{\"chez-websocket\": []}")))

    ;; --- the gate -----------------------------------------------------------------------

    (test-equal "a run as the ratchet holds passes, tallied by behavior"
      '(0 ("autobahn: 4 cases as the ratchet holds them: 3 OK, 1 NON-STRICT"))
      (gate-run spec ratchet run))

    (test-equal "and in any order"
      '(0 ("autobahn: 4 cases as the ratchet holds them: 3 OK, 1 NON-STRICT"))
      (gate-run spec ratchet (index-text "chez-websocket" (list ok-731 ok-34 ok-111 ns-32))))

    (test-equal "a case of measured verdicts passes with each of them, tallied as the run has it"
      '((0 ("autobahn: 4 cases as the ratchet holds them: 2 OK, 2 NON-STRICT"))
        (0 ("autobahn: 4 cases as the ratchet holds them: 2 OK, 2 NON-STRICT")))
      (list (gate-run spec ratchet (run-with (case-text "3.4" "NON-STRICT" "OK" "1002")))
            (gate-run spec ratchet (run-with (case-text "3.4" "NON-STRICT" "OK" "null")))))

    (test-equal "and fails with any other, a pairing of their fields never measured too"
      (map (lambda (run) (list 1 (list (string-append held-34 ", run " run)
                                       "autobahn: 1 difference from the ratchet, of 4 cases")))
           '("FAILED OK 1002" "OK UNCLEAN 1002" "OK OK 1000" "OK OK none"))
      (list (gate-run spec ratchet (run-with (case-text "3.4" "FAILED" "OK" "1002")))
            (gate-run spec ratchet (run-with (case-text "3.4" "OK" "UNCLEAN" "1002")))
            (gate-run spec ratchet (run-with (case-text "3.4" "OK" "OK" "1000")))
            (gate-run spec ratchet (run-with (case-text "3.4" "OK" "OK" "null")))))

    (test-equal "a verdict changed either way, or a close code, fails naming the case"
      '(1 ("3.2: ratchet NON-STRICT OK 1002, run OK OK 1002"
           "7.3.1: ratchet OK OK none, run OK OK 1000"
           "autobahn: 2 differences from the ratchet, of 4 cases"))
      (gate-run spec ratchet
                (index-text "chez-websocket"
                            (list ok-111 (case-text "3.2" "OK" "OK" "1002") ok-34 (case-text "7.3.1" "OK" "OK" "1000")))))

    (test-equal "a behaviorClose changed fails"
      '(1 ("1.1.1: ratchet OK OK 1000, run OK UNCLEAN 1000"
           "autobahn: 1 difference from the ratchet, of 4 cases"))
      (gate-run spec ratchet (index-text "chez-websocket" (list (case-text "1.1.1" "OK" "UNCLEAN" "1000") ns-32 ok-34 ok-731))))

    (test-equal "a case the run lacks, or the ratchet lacks, fails; a short run says how many, and why runs end short"
      '(1 ("3.2: ratchet NON-STRICT OK 1002, not in the run"
           "11.1.1: not in the ratchet, run OK OK 1000"
           "autobahn: 2 differences from the ratchet, of 4 cases"
           "autobahn: 1 case of the ratchet did not run: wstest ends a run at a connection that fails, and still exits 0, so its log says whether one did"))
      (gate-run spec ratchet
                (index-text "chez-websocket" (list ok-111 ok-34 ok-731 (case-text "11.1.1" "OK" "OK" "1000")))))

    (test-equal "a run of no case fails, every case missing"
      (no-case-ran)
      (gate-run spec ratchet "{\"chez-websocket\": {}}"))

    (test-equal "an empty index, wstest's when no connection opened, fails as a run of no case"
      (no-case-ran)
      (gate-run spec ratchet "{}"))

    (test-equal "what the gate cannot read is a harness error, status 2, naming the file"
      '((2 ("autobahn: the ratchet: line 1: not a case and its verdicts"))
        (2 ("autobahn: the ratchet holds no case"))
        (2 ("autobahn: the index: unexpected end at index 22"))
        (2 ("autobahn: the index: the index holds no agent chez-websocket"))
        (2 ("autobahn: the spec: it names 0 servers, not one"))
        (2 ("autobahn: the spec: it names 2 servers, not one"))
        (2 ("autobahn: the spec: its server names no agent")))
      (list (gate-run spec "1.1.1 OK\n" run)
            (gate-run spec "# nothing\n" run)
            (gate-run spec ratchet "{\"chez-websocket\": {\"1")
            (gate-run spec ratchet (index-text "other" (list ok-111)))
            (gate-run "{\"servers\": []}" ratchet run)
            (gate-run "{\"servers\": [{\"agent\": \"a\"}, {\"agent\": \"b\"}]}" ratchet run)
            (gate-run "{\"servers\": [{\"url\": \"ws://127.0.0.1:9001\"}]}" ratchet run)))

    ;; --- gate-main ----------------------------------------------------------------------

    (test-equal "gate-main reads its three paths in order; a wrong count, a path it cannot read, or any raise is status 2"
      '((0 ("autobahn: 4 cases as the ratchet holds them: 3 OK, 1 NON-STRICT"))
        (2 ("autobahn: usage: gate.sps SPEC RATCHET INDEX"))
        (2 ("autobahn: usage: gate.sps SPEC RATCHET INDEX"))
        (2 ("autobahn: idx cannot be read"))
        (2 ("autobahn: the spec: unexpected character at index 0"))
        (2 ("autobahn: the gate raised: boom")))
      (let ((read (lambda (path) (let ((f (assoc path (list (cons "spec" spec) (cons "ratchet" ratchet) (cons "index" run)))))
                                   (and f (cdr f))))))
        (list (main-run '("spec" "ratchet" "index") read)
              (main-run '("spec" "ratchet") read)
              (main-run '("spec" "ratchet" "index" "index") read)
              (main-run '("spec" "ratchet" "idx") read)
              (main-run '("ratchet" "spec" "index") read)
              (main-run '("spec" "ratchet" "index") (lambda (path) (assertion-violation 'read "boom"))))))))
