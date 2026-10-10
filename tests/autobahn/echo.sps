#!r6rs
;;; The Autobahn lane's echo server (M5, decision 0008): each message sent
;;; back as it came, text as text and binary as binary, until the connection
;;; ends.  `make autobahn` runs it with CHEZ_HTTP_HOST, CHEZ_HTTP_PORT and
;;; CHEZ_WS_MAX_MESSAGE_BYTES set, the last to 16 MiB, the suite's largest
;;; message, and every other setting its default.
(import (rnrs) (http-server) (websocket))

(serve
 (lambda (request)
   (websocket-accept request
     (lambda (ws)
       (guard (e ((websocket-closed? e) #t))
         (let echo ()
           (websocket-send! ws (websocket-receive ws))
           (echo)))))))
