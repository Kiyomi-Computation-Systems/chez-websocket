;;; clock.sps — the server speaks first: a tick each second, on its own
;;; schedule.
;;;
;;; /clock sends "tick 1", "tick 2", ... a second apart.  Between ticks it
;;; still reads, so the client's messages never pile up unread: it waits for
;;; them under a deadline, the end of the second, and a message that comes
;;; before then moves the next tick none.  "stop" closes the connection with
;;; 1000 "stopped".  / answers a page that shows the ticks, with a stop button.
;;;
;;;   make run PROGRAM=examples/clock.sps
;;;   then open http://127.0.0.1:8080/
;;;   or: websocat ws://127.0.0.1:8080/clock    (type stop to end it)
(import (rnrs) (http-server) (websocket))

;; The page: the ticks as they come, and a button that says stop.
(define page "<!doctype html>
<meta charset=utf-8>
<title>clock</title>
<button id=stop>stop</button>
<pre id=log></pre>
<script>
  const log = (s) => document.getElementById('log').append(s + '\\n');
  const ws = new WebSocket('ws://' + location.host + '/clock');
  ws.onmessage = (e) => log(e.data);
  ws.onclose = (e) => log('closed ' + e.code + ' ' + e.reason);
  document.getElementById('stop').onclick = () => ws.send('stop');
</script>
")

;; listen-a-second : WebSocket -> (U 'tick 'stop)
;; Reads the client's messages until a second has passed, 'tick, or one says
;; "stop", 'stop.  Any other message is passed over.
(define (listen-a-second ws)
  (guard (e ((deadline-passed? e) 'tick))
    (with-deadline 1000
      (lambda ()
        (let loop ()
          (if (equal? (websocket-receive ws) "stop") 'stop (loop)))))))

;; clock : WebSocket -> Void — a tick each second, until the client says stop.
(define (clock ws)
  (let loop ((n 1))
    (case (listen-a-second ws)
      ((tick)
       (websocket-send! ws (string-append "tick " (number->string n)))
       (loop (+ n 1)))
      ((stop)
       (websocket-close! ws 1000 "stopped")))))

(serve
 (lambda (request)
   (let ((path (request-path request)))
     (cond ((string=? path "/")
            (make-response 200 #f
                           (list (cons (string->utf8 "content-type")
                                       (string->utf8 "text/html; charset=utf-8")))
                           (string->utf8 page)))
           ((string=? path "/clock") (websocket-accept request clock))
           (else (make-response 404 #f '() (string->utf8 "not found\n")))))))
