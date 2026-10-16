#!r6rs
;;; (ws-text) — a text's lines, for the suites and the Autobahn lane's gate,
;;; (ws-autobahn), which reads its ratchet by them.  Pure: (rnrs) alone.
;;;
;;;   text-split : String Char -> (Listof String)
;;;   text-lines : String -> (Listof String)
(library (ws-text)
  (export text-split text-lines)
  (import (rnrs))

  ;; text-split : String Char -> (Listof String)
  ;; The parts of the text between each c, in order: n of them make n + 1.
  (define (text-split s c)
    (let loop ((i 0) (start 0) (parts '()))
      (cond ((= i (string-length s)) (reverse (cons (substring s start i) parts)))
            ((char=? (string-ref s i) c) (loop (+ i 1) (+ i 1) (cons (substring s start i) parts)))
            (else (loop (+ i 1) start parts)))))

  ;; text-lines : String -> (Listof String)
  ;; Its lines, each ended by a LF, a CR before it dropped, so a CRLF checkout
  ;; reads as a LF one; text after the last LF is a line too.
  (define (text-lines text)
    (let ((parts (text-split text #\newline)))
      (map (lambda (l)
             (let ((n (string-length l)))
               (if (and (> n 0) (char=? (string-ref l (- n 1)) #\return)) (substring l 0 (- n 1)) l)))
           (if (string=? (car (last-pair parts)) "")
               (reverse (cdr (reverse parts)))
               parts))))

  ;; last-pair : (Listof Any) -> (Listof Any) — its last pair; it is not empty.
  (define (last-pair l) (if (null? (cdr l)) l (last-pair (cdr l)))))
