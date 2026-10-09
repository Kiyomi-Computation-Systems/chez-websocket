#!r6rs
;;; A program the binding suite runs as a child (design §7).  It imports the
;;; facade, takes a connection on the server's fake shell through each of
;;; websocket-accept's forms that leave the limits out, and exits with the sum
;;; of the seconds each arms its first deadline for: the ping interval the
;;; binding read from the environment as the program started.  A malformed
;;; value stops it before its first line, Chez exiting 255.
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

(exit (+ (armed (lambda (r) (websocket-accept r proc)))
         (armed (lambda (r) (websocket-accept r proc (make-handshake-settings '()))))))
