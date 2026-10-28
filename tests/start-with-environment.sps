#!r6rs
;;; A program the binding suite runs as a child.  It imports the facade, takes
;;; a connection on the server's fake shell through each of websocket-accept's
;;; forms that leave the limits out, and exits with the sum of the seconds
;;; each arms its first deadline for: the ping interval the binding read from
;;; the environment as the program started.  A malformed value stops it before
;;; its first line, Chez exiting 255.  Given the argument `handshake`, it
;;; takes them through websocket-handshake's two such forms instead, as
;;; another host would, its answer mapped onto the server's own.
(import (rnrs) (websocket) (http-server) (fake-shell) (only (http-server limits) default-limits))

;; RFC 6455 §1.3's opening handshake.
(define handshake
  (string->utf8 (string-append "GET /chat HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\n"
                               "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                               "Sec-WebSocket-Version: 13\r\n\r\n")))

;; armed : (Request -> Answer) -> Nat
;; The seconds a connection the handler takes, its clock at 0, arms first.
(define (armed handler)
  (let ((sh (make-fake-connection default-limits handler #f 0)))
    (fake-shell-feed-input! sh handshake 4096)
    (fake-shell-settle! sh)
    (div (fake-shell-armed sh) 1000)))

(define (proc ws) (websocket-receive ws))

;; hosted : . Any -> (Request -> Answer)
;; websocket-handshake's answer, with the settings given, if any: its
;; take-over handed to switch-protocols, and anything else a 500.
(define (hosted . options)
  (lambda (r)
    (let ((h (apply websocket-handshake (request-method r) (lambda (name) (request-header-values r name))
                    (request-host r) proc options)))
      (if (handshake-accepted? h)
          (switch-protocols (map (lambda (f) (cons (string->utf8 (car f)) (string->utf8 (cdr f))))
                                 (handshake-accepted-headers h))
                            (handshake-accepted-take-over h))
          (make-response 500 #f '() #f)))))

(exit (if (member "handshake" (cdr (command-line)))
          (+ (armed (hosted)) (armed (hosted (make-handshake-settings '()))))
          (+ (armed (lambda (r) (websocket-accept r proc)))
             (armed (lambda (r) (websocket-accept r proc (make-handshake-settings '())))))))
