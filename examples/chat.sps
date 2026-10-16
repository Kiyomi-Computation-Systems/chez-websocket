;;; chat.sps — a chat room: what one client says, everyone else hears.
;;;
;;; Each client of /chat joins the room and is told how many are in it,
;;; itself counted: "here: 3".  Each message it sends goes to every other
;;; WebSocket in the room.  When it goes, it leaves the room.  A procedure may
;;; send to any connection's WebSocket, not just its own, and every
;;; connection's procedure runs on the server's one loop, so the room is a
;;; plain list.
;;;
;;;   make run PROGRAM=examples/chat.sps
;;;   then, in two terminals or more: websocat ws://127.0.0.1:8080/chat
(import (rnrs) (http-server) (websocket))

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
   (if (string=? (request-path request) "/chat")
       (websocket-accept request chat)
       (make-response 404 #f '() (string->utf8 "not found\n")))))
