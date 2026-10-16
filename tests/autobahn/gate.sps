#!r6rs
;;; The Autobahn lane's gate:
;;;
;;;   gate.sps SPEC RATCHET INDEX
;;;
;;; holds the index.json a fuzzing client's run wrote against the ratchet, and
;;; exits with gate-main's status (ws-autobahn): 0 every verdict as the ratchet
;;; holds it, 1 a difference, 2 a file it cannot read, or anything else amiss.
(import (rnrs) (ws-autobahn))

;; slurp : String -> (U String #f) — the file's text, or #f when it cannot be read.
(define (slurp path)
  (guard (e ((i/o-error? e) #f))
    (let ((text (call-with-port
                 (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
                 get-string-all)))
      (if (eof-object? text) "" text))))

(exit (gate-main (cdr (command-line)) slurp (current-output-port)))
