#!r6rs
;;; tests/autobahn/run.sh, the Autobahn lane's driver, held without Docker
;;; (M5's review).  tests/autobahn/fake/docker stands in for docker and plays
;;; the fuzzing client's run, so each check run.sh makes on its host path is
;;; watched to fail on its own: the echo server it starts, on a port of its
;;; own, in an environment of its own; an index no run wrote; a server that
;;; ends before it listens, or without stopping; a docker that fails.  The
;;; container path, on macOS and Windows, shares all of it but the echo
;;; server's start and stop.
;;;
;;; Each run is a process of its own, as `make autobahn` starts one, on the
;;; Chez that runs the suites: CHEZ names it, as the Makefile's CHEZ does
;;; (CI's is `scheme`); unset, it is `chez`.  Its files go under
;;; build/test-autobahn-run, which `make clean` removes.
(import (rnrs) (srfi :64) (ws-testing) (ws-autobahn)
        (only (chezscheme) system current-directory))

(define out (string-append (current-directory) "/build/test-autobahn-run"))

;; read-text : String -> String — a file's text, "" when there is none.
(define (read-text path)
  (guard (e ((i/o-error? e) ""))
    (let ((text (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                                      (native-transcoder))
                  get-string-all)))
      (if (eof-object? text) "" text))))

;; lane-command : String String String -> String
;; The shell command of a run, docker played as `mode`, the caller's
;; environment holding `extra` too, its files in out/name and out/name.log.
(define (lane-command name mode extra)
  (let ((dir (string-append out "/" name)))
    (string-append
     "mkdir -p '" dir "' && env PATH=\"$PWD/tests/autobahn/fake:$PATH\""
     " FAKE_DOCKER=" mode " FAKE_RATCHET=tests/autobahn/verdicts.txt ECHO_AT=host"
     " CHEZ=\"${CHEZ:-chez}\" LIBDIRS=\"$CHEZSCHEMELIBDIRS\" IMAGE=fake OUT='" dir "'"
     " " extra " sh tests/autobahn/run.sh > '" dir ".log' 2>&1")))

;; lane : String String String -> (List Status (Listof String))
;; A run's status and the lines it wrote.
(define (lane name mode extra)
  (let ((status (system (lane-command name mode extra))))
    (list status (text-lines (read-text (string-append out "/" name ".log"))))))

;; said : (List Status (Listof String)) String -> (List Status (U String #f))
;; The status, and the first line that begins with `prefix`, or #f.
(define (said result prefix)
  (list (car result)
        (let find ((ls (cadr result)))
          (cond ((null? ls) #f)
                ((and (>= (string-length (car ls)) (string-length prefix))
                      (string=? (substring (car ls) 0 (string-length prefix)) prefix))
                 (car ls))
                (else (find (cdr ls)))))))

(define passed "autobahn: 301 cases as the ratchet holds them: 291 OK, 7 NON-STRICT, 3 INFORMATIONAL")

(run-suite "autobahn-run"
  (lambda ()
    (system (string-append "rm -f '" out "'/*.log '" out "'/*/reports/index.json"))

    (test-equal "a run as the ratchet holds passes, its echo server on a port of its own the URL names"
      (list 0 passed)
      (said (lane "pass" "pass" "") passed))

    (test-equal "and its echo server, whose pid it records, stopped once the run is over"
      '(#t 1)
      (list (file-exists? (string-append out "/pass/echo.pid"))
            (system (string-append "kill -0 \"$(cat '" out "/pass/echo.pid')\" 2>/dev/null"))))

    (test-equal "the caller's CHEZ_HTTP_ and CHEZ_WS_ variables never reach the echo server"
      (list 0 passed)
      (said (lane "env" "pass" "CHEZ_HTTP_MAX_HEADER_BYTES=512 CHEZ_WS_MAX_MESSAGE_BYTES=1") passed))

    (test-equal "an index no run wrote is not gated: the last run's is gone"
      (list 2 (string-append "autobahn: " out "/stale/reports/index.json cannot be read"))
      (begin
        (system (string-append "mkdir -p '" out "/stale/reports' && cp '" out "/pass/reports/index.json' '"
                               out "/stale/reports/index.json'"))
        (said (lane "stale" "nothing" "") "autobahn: ")))

    (test-equal "an echo server that ends without stopping is a harness error"
      (list 2 "autobahn: the echo server ended without stopping:")
      (said (lane "kill" "kill" "") "autobahn: the echo server ended without stopping:"))

    (test-equal "an echo server that ends before it listens is a harness error"
      (list 2 "autobahn: the echo server ended before it listened:")
      (said (lane "nostart" "pass" "CHEZ=false") "autobahn: the echo server ended before it listened:"))

    (test-equal "two runs at once each pass, each echo server on a port of its own"
      '(passed passed)
      (begin
        (system (string-append "(" (lane-command "two-a" "pass" "") ") & (" (lane-command "two-b" "pass" "") ") & wait"))
        (map (lambda (name)
               (if (member passed (text-lines (read-text (string-append out "/" name ".log")))) 'passed name))
             '("two-a" "two-b"))))

    (test-equal "a run told to stop takes its echo server with it"
      '(#t 1)
      (begin
        (lane "term" "term" "")
        (let ((alive (system (string-append "kill -0 \"$(cat '" out "/term/echo.pid')\" 2>/dev/null"))))
          (system (string-append "kill -9 \"$(cat '" out "/term/echo.pid')\" 2>/dev/null"))
          (list (file-exists? (string-append out "/term/echo.pid")) alive))))

    (test-equal "a docker that fails is a harness error, its status named"
      (list 2 "autobahn: docker run exited 125:")
      (said (lane "docker" "fail" "") "autobahn: docker run exited 125:"))))
