#!r6rs
;;; The import audit (design §2), which `make check-imports` runs alone.
;;;
;;; A pure library imports R6RS's own libraries, (rnrs ...), and this
;;; project's other pure libraries, and nothing else: not (chezscheme), not
;;; (http-server), not the facade (websocket), and not (websocket private
;;; ...), where the binding will live.  Every library under src/ is pure
;;; until the binding arrives in M4, which this audit will then name.
;;;
;;; Each src/**/*.sls is read with Chez's own reader, so a comment or a
;;; string cannot pass for an import.  An import must name its library
;;; plainly: one wrapped in only, except, prefix, rename, for or library is
;;; refused, since the audit holds what is written to the list above.
(import (chezscheme) (srfi :64) (ws-testing))

;; sources : String -> (Listof String)
;; Every .sls file under the directory, at any depth, sorted.
(define (sources dir)
  (list-sort string<?
    (apply append
      (map (lambda (name)
             (let ((path (string-append dir "/" name)))
               (cond ((file-directory? path) (sources path))
                     ((string=? (path-extension name) "sls") (list path))
                     (else '()))))
           (directory-list dir)))))

;; pure-import? : Datum -> Boolean
;; Whether an import spec names (rnrs ...) or a pure (websocket name ...),
;; plainly.
(define (pure-import? spec)
  (and (pair? spec)
       (or (eq? (car spec) 'rnrs)
           (and (eq? (car spec) 'websocket)
                (pair? (cdr spec))
                (not (eq? (cadr spec) 'private))))))

;; impure-imports : String -> (Listof Datum)
;; The import specs of the file's library that are not pure.  A file whose
;; first datum is not a library with an import clause answers that.
(define (impure-imports path)
  (let ((form (call-with-input-file path read)))
    (if (and (list? form) (>= (length form) 4) (eq? (car form) 'library)
             (pair? (cadddr form)) (eq? (car (cadddr form)) 'import))
        (filter (lambda (spec) (not (pure-import? spec))) (cdr (cadddr form)))
        '(not-a-library-with-an-import-clause))))

(run-suite "imports"
  (lambda ()
    (for-each
      (lambda (path)
        (test-equal (string-append path " imports only (rnrs ...) and pure (websocket ...) libraries")
          '()
          (impure-imports path)))
      (sources "src"))))
