;;; chat.sps — a chat room: what one client says, everyone else hears.
;;;
;;; Each client of /chat joins the room and is told how many are in it,
;;; itself counted: "here: 3".  Each message it sends goes to every other
;;; WebSocket in the room.  When it goes, it leaves the room.  A procedure may
;;; send to any connection's WebSocket, not just its own, and every
;;; connection's procedure runs on the server's one loop, so the room is a
;;; plain list.  / answers a page to chat from.
;;;
;;;   make run PROGRAM=examples/chat.sps
;;;   then open http://127.0.0.1:8080/ in two tabs or more,
;;;   or: websocat ws://127.0.0.1:8080/chat
(import (rnrs) (http-server) (websocket))

;; The page: a line to type in, and what the room said.
(define page "<!doctype html>
<meta charset=utf-8>
<title>chat</title>
<input id=line placeholder='say something, then Enter' autofocus>
<pre id=log></pre>
<script>
  const log = (s) => document.getElementById('log').append(s + '\\n');
  const ws = new WebSocket('ws://' + location.host + '/chat');
  ws.onmessage = (e) => log(e.data);
  ws.onclose = (e) => log('closed ' + e.code);
  document.getElementById('line').onkeydown = (e) => {
    if (e.key !== 'Enter') return;
    ws.send(e.target.value);
    log('> ' + e.target.value);
    e.target.value = '';
  };
</script>
")

;; The room: the WebSocket of each client of /chat.
(define room '())

;; tell-others! : WebSocket (U String Bytevector) -> Void
;; Sends the message to each WebSocket in the room but the sender's.  One
;; that has closed, its procedure yet to take it out of the room, is passed
;; over: its &websocket-closed is not the sender's.
(define (tell-others! from message)
  (for-each (lambda (ws)
              (unless (eq? ws from)
                (guard (e ((websocket-closed? e) #f))
                  (websocket-send! ws message))))
            room))

;; chat : WebSocket -> Void
;; Joins the room, then passes on each message, until the client goes, or
;; anything else ends it: either way, out of the room first.
(define (chat ws)
  (set! room (cons ws room))
  (guard (e (#t (set! room (remq ws room)) (raise e)))
    (websocket-send! ws (string-append "here: " (number->string (length room))))
    (let loop ()
      (tell-others! ws (websocket-receive ws))
      (loop))))

(serve
 (lambda (request)
   (let ((path (request-path request)))
     (cond ((string=? path "/")
            (make-response 200 #f
                           (list (cons (string->utf8 "content-type")
                                       (string->utf8 "text/html; charset=utf-8")))
                           (string->utf8 page)))
           ((string=? path "/chat") (websocket-accept request chat))
           (else (make-response 404 #f '() (string->utf8 "not found\n")))))))
