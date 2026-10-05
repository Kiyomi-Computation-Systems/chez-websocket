#!r6rs
;;; The import audit (design §2), which `make check-imports` runs alone.
;;;
;;; A pure library imports R6RS's own libraries, (rnrs ...), and this
;;; project's other pure libraries, and nothing else: not (chezscheme), not
;;; (http-server), not the facade (websocket), and not (websocket private
;;; ...), where the binding will live.  Not (rnrs eval) either: an
;;; environment reaches any library.  Every library under src/ is pure until
;;; the binding arrives in M4, which this audit will then name.
;;;
;;; Each source file under src/ is read with Chez's own reader, so a comment
;;; or a string cannot pass for an import.  A source file is one whose name
;;; ends in an extension Chez looks for a library under, (library-extensions)
;;; (.ss before .sls, so one can shadow the other); a name that begins with
;;; "." is no library's, such as an editor's lock file.  A file must hold its
;;; library and nothing after it, since Chez runs what follows when the
;;; library is imported, with all of (chezscheme) bound.  An import must name
;;; its library plainly: one wrapped in only, except, prefix, rename, for or
;;; library is refused, since the audit holds what is written to the list
;;; above.
(import (chezscheme) (srfi :64) (ws-testing))

;; source? : String -> Boolean
;; Whether a file's name ends in an extension Chez looks for a library's
;; source under.
(define (source? name)
  (exists (lambda (extension)
            (let ((n (string-length name)) (k (string-length extension)))
              (and (> n k) (string=? (substring name (- n k) n) extension))))
          (map car (library-extensions))))

;; sources : String -> (Listof String)
;; Every source file under the directory, at any depth, sorted, passing over
;; names that begin with ".".
(define (sources dir)
  (list-sort string<?
    (apply append
      (map (lambda (name)
             (let ((path (string-append dir "/" name)))
               (cond ((char=? (string-ref name 0) #\.) '())
                     ((file-directory? path) (sources path))
                     ((source? name) (list path))
                     (else '()))))
           (directory-list dir)))))

;; pure-import? : Datum -> Boolean
;; Whether an import spec names (rnrs ...) other than (rnrs eval), or a pure
;; (websocket name ...), plainly.
(define (pure-import? spec)
  (and (pair? spec)
       (or (and (eq? (car spec) 'rnrs)
                (not (and (pair? (cdr spec)) (eq? (cadr spec) 'eval))))
           (and (eq? (car spec) 'websocket)
                (pair? (cdr spec))
                (not (eq? (cadr spec) 'private))))))

;; forms : String -> (Listof Datum)
;; Every datum in the file, in order.
(define (forms path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((acc '()))
        (let ((x (read port)))
          (if (eof-object? x) (reverse acc) (loop (cons x acc))))))))

;; impure-imports : String -> (Listof Datum)
;; The import specs of the file's library that are not pure.  A file whose
;; first datum is not a library with an import clause answers that, and so
;; does one with anything after its library.
(define (impure-imports path)
  (let ((all (forms path)))
    (cond ((not (and (pair? all) (list? (car all)) (>= (length (car all)) 4)
                     (eq? (car (car all)) 'library)
                     (pair? (cadddr (car all))) (eq? (car (cadddr (car all))) 'import)))
           '(not-a-library-with-an-import-clause))
          ((pair? (cdr all)) '(more-after-the-library))
          (else (filter (lambda (spec) (not (pure-import? spec))) (cdr (cadddr (car all))))))))

(run-suite "imports"
  (lambda ()
    (for-each
      (lambda (path)
        (test-equal (string-append path " is one library, importing only (rnrs ...) and pure (websocket ...) libraries")
          '()
          (impure-imports path)))
      (sources "src"))))
