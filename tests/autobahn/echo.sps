#!r6rs
;;; The Autobahn lane's echo server: each message sent back as it came, text
;;; as text and binary as binary, until the connection ends.  `make autobahn`
;;; runs it with CHEZ_HTTP_HOST, CHEZ_HTTP_PORT and CHEZ_WS_MAX_MESSAGE_BYTES
;;; set, the last to 16 MiB, the suite's largest message, and every other
;;; setting its default.  /health and /health/ready answer 200, for the echo
;;; image's HEALTHCHECK.
(import (rnrs) (http-server) (websocket))

;; echo : WebSocket -> Void — every message back, until the connection ends.
(define (echo ws)
  (guard (e ((websocket-closed? e) #t))
    (let loop ()
      (websocket-send! ws (websocket-receive ws))
      (loop))))

(serve
 (lambda (request)
   (if (member (request-path request) '("/health" "/health/ready"))
       (make-response 200 #f '() (string->utf8 "ok\n"))
       (websocket-accept request echo))))
