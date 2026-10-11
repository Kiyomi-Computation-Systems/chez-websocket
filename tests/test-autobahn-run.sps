#!r6rs
;;; tests/autobahn/run.sh, the Autobahn lane's driver, held without Docker
;;; (M5's review).  tests/autobahn/fake/docker stands in for docker and plays
;;; the fuzzing client's run, so each check run.sh makes on its host path is
;;; watched to fail on its own: the echo server it starts, on a port of its
;;; own, in an environment of its own; an index no run wrote; a server that
;;; ends before it listens, or without stopping; a docker that fails; a run
;;; told to stop while its server has ended but cannot yet be reaped, which
;;; tests/autobahn/fake/ps shows as Linux does (R-TERM's probe).  The
;;; container path, on macOS and Windows, shares all of it but the echo
;;; server's start and stop.  There the fake plays the echo server's container
;;; too, so the wait is held to that container's own log, never the one the
;;; last run left, and a run that ends as its container starts, by a failed
;;; start or a signal, is held to remove the network it made.
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

;; run-command : String String String String -> String
;; The shell command of a run, its echo server where `at` says (run.sh's
;; ECHO_AT), docker played as `mode`, the caller's environment holding `extra`
;; too, its files in out/name and out/name.log.
(define (run-command at name mode extra)
  (let ((dir (string-append out "/" name)))
    (string-append
     "mkdir -p '" dir "' && env PATH=\"$PWD/tests/autobahn/fake:$PATH\""
     " FAKE_DOCKER=" mode " FAKE_RATCHET=tests/autobahn/verdicts.txt ECHO_AT=" at
     " CHEZ=\"${CHEZ:-chez}\" LIBDIRS=\"$CHEZSCHEMELIBDIRS\" IMAGE=fake OUT='" dir "'"
     " " extra " sh tests/autobahn/run.sh > '" dir ".log' 2>&1")))

;; run-lane : String String String String -> (List Status (Listof String))
;; A run's status and the lines it wrote.
(define (run-lane at name mode extra)
  (let ((status (system (run-command at name mode extra))))
    (list status (text-lines (read-text (string-append out "/" name ".log"))))))

;; lane-command : String String String -> String — a run on the host path.
(define (lane-command name mode extra) (run-command "host" name mode extra))

;; lane : String String String -> (List Status (Listof String)) — a run on
;; the host path.
(define (lane name mode extra) (run-lane "host" name mode extra))

;; The log a container run leaves, which the next run on its tree finds: its
;; first line and its last two, as `make autobahn` left them (macOS,
;; 2026-10-11).
(define last-runs-log "listening 0.0.0.0 9001\ndraining 0\nstopped\n")

;; container-lane : String String (U String #f) -> (List Status (Listof String))
;; A run on the container path, in out/name made anew: its echo server's
;; container played as `echo` (the fake's FAKE_ECHO), the fuzzing client as
;; `pass`, and out/name/server.log holding `log` before the run, when given.
(define (container-lane name echo log)
  (let ((dir (string-append out "/" name)))
    (system (string-append "rm -rf '" dir "' && mkdir -p '" dir "'"))
    (when log
      (call-with-port (open-file-output-port (string-append dir "/server.log") (file-options)
                                             (buffer-mode block) (native-transcoder))
        (lambda (port) (put-string port log))))
    (run-lane "container" name "pass"
              (string-append "ECHO_IMAGE=fake FAKE_ECHO=" echo " FAKE_STATE='" dir "/docker'"))))

;; docker-left : String -> (List (Listof String) (Listof String))
;; What the fake docker of the container run in out/name made, each a
;; "network" or a "container", in the order it made them, and those of them
;; still there.
(define (docker-left name)
  (let* ((state (string-append out "/" name "/docker"))
         (made (map (lambda (line)
                      (let find ((i 0))
                        (cond ((= i (string-length line)) (list line ""))
                              ((char=? (string-ref line i) #\space)
                               (list (substring line 0 i) (substring line (+ i 1) (string-length line))))
                              (else (find (+ i 1))))))
                    (text-lines (read-text (string-append state "/made"))))))
    (list (map car made)
          (map car (filter (lambda (m)
                             (file-exists? (string-append state (if (string=? (car m) "network") "/networks/" "/")
                                                          (cadr m))))
                           made)))))

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
      (said (lane "docker" "fail" "") "autobahn: docker run exited 125:"))

    (test-equal "on the container path a run waits until its own container listens, though the last run's log says it did"
      (list 0 passed)
      (said (container-lane "wait" "listens" last-runs-log) passed))

    (test-equal "and a container that ends before it listens is a harness error, no fuzzing client run, though the last run's log says it listened"
      (list 2 "autobahn: the echo server ended before it listened:" #f)
      (let ((result (container-lane "ends" "ends" last-runs-log)))
        (append (said result "autobahn: the echo server ended before it listened:")
                (list (file-exists? (string-append out "/ends/reports/index.json"))))))

    (test-equal "and a container run on a tree with no log yet says nothing but the gate's line"
      (list 0 (list passed))
      (container-lane "fresh" "listens" #f))

    (test-equal "and a container that cannot start is a harness error, its network and the container removed"
      (list 2 '("fake docker: the container cannot start") '("network" "container") '())
      (let ((result (container-lane "fails" "fails" #f)))
        (append result (docker-left "fails"))))

    (test-equal "and a run told to stop as its container starts takes the network and the container with it"
      (list 143 '() '("network" "container") '())
      (let ((result (container-lane "cterm" "term" #f)))
        (append result (docker-left "cterm"))))))
