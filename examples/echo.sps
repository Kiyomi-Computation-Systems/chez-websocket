;;; echo.sps — an echo server, and a page in your browser that talks to it.
;;;
;;; /echo sends every message back.  / answers a page whose script opens a
;;; WebSocket to /echo on the page's own host.  The handshake's origin check,
;;; same-host unless you name others, lets that page in, and refuses a page
;;; from another site 403.
;;;
;;;   make run PROGRAM=examples/echo.sps
;;;   then open http://127.0.0.1:8080/ and type a line,
;;;   or: websocat ws://127.0.0.1:8080/echo
(import (rnrs) (http-server) (websocket))

;; The page: a line to type in, and what came back.
(define page "<!doctype html>
<meta charset=utf-8>
<title>echo</title>
<input id=line placeholder='type, then Enter' autofocus>
<pre id=log></pre>
<script>
  const log = (s) => document.getElementById('log').append(s + '\\n');
  const ws = new WebSocket('ws://' + location.host + '/echo');
  ws.onopen = () => log('open');
  ws.onmessage = (e) => log('< ' + e.data);
  ws.onclose = (e) => log('closed ' + e.code);
  document.getElementById('line').onkeydown = (e) => {
    if (e.key !== 'Enter') return;
    ws.send(e.target.value);
    log('> ' + e.target.value);
    e.target.value = '';
  };
</script>
")

;; echo : WebSocket -> Void — every message back, until the client goes.
(define (echo ws)
  (let loop ()
    (websocket-send! ws (websocket-receive ws))
    (loop)))

(serve
 (lambda (request)
   (let ((path (request-path request)))
     (cond ((string=? path "/")
            (make-response 200 #f
                           (list (cons (string->utf8 "content-type")
                                       (string->utf8 "text/html; charset=utf-8")))
                           (string->utf8 page)))
           ((string=? path "/echo") (websocket-accept request echo))
           (else (make-response 404 #f '() (string->utf8 "not found\n")))))))
