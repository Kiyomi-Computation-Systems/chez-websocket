#!r6rs
;;; The Autobahn lane's gate (M5, decision 0008):
;;;
;;;   gate.sps SPEC RATCHET INDEX
;;;
;;; holds the index.json a fuzzing client's run wrote against the ratchet
;;; (ws-autobahn), and exits with its status: 0 every verdict as the ratchet
;;; holds it, 1 a difference, 2 a file it cannot read.
(import (rnrs) (ws-autobahn))

;; slurp : String -> (U String #f) — the file's text, or #f when it cannot be read.
(define (slurp path)
  (guard (e ((i/o-error? e) #f))
    (let ((text (call-with-port
                 (open-file-input-port path (file-options) (buffer-mode block) (native-transcoder))
                 get-string-all)))
      (if (eof-object? text) "" text))))

(define paths (cdr (command-line)))

(exit
 (if (not (= (length paths) 3))
     (begin (put-string (current-error-port) "usage: gate.sps SPEC RATCHET INDEX\n") 2)
     (let ((texts (map slurp paths)))
       (if (memq #f texts)
           (let find ((ps paths) (ts texts))
             (if (car ts)
                 (find (cdr ps) (cdr ts))
                 (begin (put-string (current-output-port)
                                    (string-append "autobahn: " (car ps) " cannot be read\n"))
                        2)))
           (apply autobahn-gate (append texts (list (current-output-port))))))))
