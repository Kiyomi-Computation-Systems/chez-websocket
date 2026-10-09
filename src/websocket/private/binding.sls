#!r6rs
;;; (websocket private binding) — the shell (design §6): the core over the
;;; server's transport, the waits, and the environment.
;;;
;;; `websocket-accept` checks the handshake ((websocket handshake)), reading
;;; every line of a field, joined with commas (RFC 9110 §5.3; decision 0004),
;;; and answers the server's door: a refusal, or `(switch-protocols headers
;;; take-over)`.  The take-over runs in place, inside the server's callbacks,
;;; and cannot wait: it makes the core's state, arms the deadline the state
;;; names, starts reading, feeds the core the bytes the server read past the
;;; request, and answers `(awaiting thunk)`, whose thunk runs the handler's
;;; procedure with the WebSocket, on the coroutine the server gives it.
;;;
;;; Every event the core is told, a read, its end, a deadline passing, a
;;; take, a send, a close, is stepped at once, and the actions performed at
;;; once, in order:
;;;   write            transport-write!, its bytes counted unsent until its
;;;                    done comes
;;;   deliver          the message queued for websocket-receive, which is
;;;                    woken if it waits
;;;   read-stop, read-start   the transport's verbs
;;;   arm-deadline     transport-deadline!, for the kind's time: ping the
;;;                    ping interval, pong the ping timeout, close the close
;;;                    timeout; its passing stepped as deadline-passed
;;;   disarm-deadline  transport-deadline! with #f
;;;   close-stream     transport-close!
;;;   closed           the WebSocket's end, &websocket-closed, kept; a
;;;                    receive or a send that waits is woken
;;;   log              a line on the current output port, as the server
;;;                    logs: its name prefixed websocket-, then each detail
;;;
;;; The stream's close, whoever closed it, raises &client-closed in the wait
;;; the procedure is in, or else its next (decision 0023).  A wait of the
;;; binding's, a receive's or a send's, steps it as the stream's end
;;; (`(end closed)`), so the core reads what waits for the queue and ends
;;; the connection, 1006, unless it has ended.  The binding registers no
;;; close call of its own: both of the server's shells tell the wait before
;;; they run one, so a call that woke the wait would come after the wait had
;;; ended, a late resume.  A send into a stream closed under it is told at
;;; its next wait.  The server's drain closes with 1001, "going away".
;;;
;;; The procedure's end: its return closes with 1000; a &websocket-closed it
;;; lets out does nothing more, nor a &client-closed, which is the stream's
;;; close; any other raise closes with 1011 and is logged
;;; `websocket-handler-failed`.  The thunk lets nothing out, so the server
;;; logs nothing for it.
;;;
;;; The limits are read from the environment once, as a program that
;;; imports the binding starts, so a malformed value stops it there (design
;;; §7): Chez runs a library's body before the program's.
(library (websocket private binding)
  (export websocket-accept websocket-receive websocket-send! websocket-close!
          websocket-subprotocol websocket?
          &websocket-closed websocket-closed? websocket-closed-code
          websocket-closed-reason websocket-closed-clean?
          environment-websocket-limits)
  (import (chezscheme) (http-server)
          (websocket protocol) (websocket handshake) (websocket limits))

  ;; environment-websocket-limits : WebsocketLimits
  ;; The defaults, with each CHEZ_WS_ variable the environment sets applied
  ;; over them, read as the program starts.
  (define environment-websocket-limits
    (websocket-limits-from-environment getenv))

  ;; &websocket-closed: the WebSocket has closed.  Its code and reason are
  ;; the close the client sent, or 1005 and "" for one with no code, or 1006
  ;; and "" when none came (RFC 6455 §7.1.5, §7.1.6); clean? is whether a
  ;; close went each way (§7.1.4).
  ;;   websocket-closed? : Any -> Boolean
  ;;   websocket-closed-code : WebsocketClosed -> Nat
  ;;   websocket-closed-reason : WebsocketClosed -> String
  ;;   websocket-closed-clean? : WebsocketClosed -> Boolean
  (define-condition-type &websocket-closed &error
    make-websocket-closed websocket-closed?
    (code websocket-closed-code)
    (reason websocket-closed-reason)
    (clean? websocket-closed-clean?))

  ;; A WebSocket.  `state` is the core's; `head` and `tail` the messages
  ;; delivered and not yet received, each (kind . payload), `tail` the last
  ;; pair or #f; `receiver` and `sender` the resume of a receive or a send
  ;; that waits, or #f; `unsent` the bytes written whose done has not come;
  ;; `closing?` whether a close has been stepped; `ended` the
  ;; &websocket-closed once the connection has ended, or #f.  The core's
  ;; callbacks are made once, here, so a read allocates no closure.
  ;;   websocket? : Any -> Boolean
  ;;   websocket-subprotocol : WebSocket -> (U String #f)
  (define-record-type (websocket new-websocket websocket?)
    (fields (immutable transport) (mutable state) (immutable limits)
            (immutable subprotocol)
            (mutable head) (mutable tail) (mutable receiver) (mutable sender)
            (mutable unsent) (mutable closing?) (mutable ended)
            (mutable on-bytes) (mutable on-end) (mutable passed)))

  ;; default-settings : HandshakeSettings — no subprotocols, the request's
  ;; own host as the one origin (decision 0003).
  (define default-settings (make-handshake-settings '()))

  ;; websocket-accept : Request (WebSocket -> Any) [HandshakeSettings [WebsocketLimits]] -> Answer
  ;; What the handler answers the request: its refusal, a response of the
  ;; status and fields (websocket-handshake's), with no body; or the switch,
  ;; whose take-over runs `proc` with the WebSocket.  The settings default to
  ;; no subprotocols and the request's own host as the one origin, and the
  ;; limits to the environment's.
  (define websocket-accept
    (case-lambda
      ((request proc) (websocket-accept request proc default-settings environment-websocket-limits))
      ((request proc settings) (websocket-accept request proc settings environment-websocket-limits))
      ((request proc settings limits)
       (unless (procedure? proc)
         (assertion-violation 'websocket-accept "not a procedure" proc))
       (unless (websocket-limits? limits)
         (assertion-violation 'websocket-accept "not limits" limits))
       (let ((answer (handshake-answer (request-method request)
                                       (lambda (name) (field-lines request name))
                                       (request-host request)
                                       settings)))
         (if (eq? (car answer) 'accept)
             (switch-protocols (cadr answer)
                               (lambda (transport retained)
                                 (take-over transport retained proc limits (caddr answer))))
             (make-response (cadr answer) #f (caddr answer) #f))))))

  ;; field-lines : Request String -> (U String #f)
  ;; Every line of the field, in order, joined with ", " (RFC 9110 §5.3), or
  ;; #f when the request has none.
  (define (field-lines request name)
    (let ((lines (request-header-values request name)))
      (and (pair? lines)
           (fold-left (lambda (all line) (string-append all ", " line)) (car lines) (cdr lines)))))

  ;; take-over : Transport Bytevector (WebSocket -> Any) WebsocketLimits (U String #f) -> Awaiting
  (define (take-over transport retained proc limits subprotocol)
    (let* ((state (make-ws-state limits))
           (ws (new-websocket transport state limits subprotocol
                              '() #f #f #f 0 #f #f #f #f #f)))
      (websocket-on-bytes-set! ws (lambda (bv start end) (step! ws (list 'bytes bv start end))))
      (websocket-on-end-set! ws (lambda (why) (step! ws (list 'end why))))
      (websocket-passed-set! ws (lambda () (step! ws '(deadline-passed))))
      (let ((kind (ws-deadline state)))
        (when kind (arm! ws kind)))
      (start-reading! ws)
      (let ((n (bytevector-length retained)))
        (when (fx>? n 0) (step! ws (list 'bytes retained 0 n))))
      (transport-on-drain! transport (lambda () (close-from! ws 1001 "going away")))
      (awaiting (lambda () (run ws proc)))))

  ;; run : WebSocket (WebSocket -> Any) -> Void
  ;; The procedure, and its end.
  (define (run ws proc)
    (guard (e ((or (websocket-closed? e) (client-closed? e)) (if #f #f))
              (else (log-line "websocket-handler-failed" (list e))
                    (close-from! ws 1011 "")))
      (proc ws)
      (close-from! ws 1000 "")))

  ;; step! : WebSocket Event -> Void
  ;; The event stepped, and the actions performed, in order.
  (define (step! ws event)
    (let-values (((state actions) (ws-step (websocket-state ws) event)))
      (websocket-state-set! ws state)
      (for-each (lambda (action) (perform! ws action)) actions)))

  ;; perform! : WebSocket Action -> Void
  (define (perform! ws action)
    (let ((t (websocket-transport ws)))
      (case (car action)
        ((write) (write! ws (cadr action)))
        ((deliver) (enqueue! ws (cons (cadr action) (caddr action))) (wake-receiver! ws))
        ((read-stop) (transport-read-stop! t))
        ((read-start) (start-reading! ws))
        ((arm-deadline) (arm! ws (cadr action)))
        ((disarm-deadline) (transport-deadline! t #f))
        ((close-stream) (transport-close! t))
        ((closed) (ended! ws (cadr action) (caddr action) (cadddr action)))
        ((log) (log-line (string-append "websocket-" (symbol->string (cadr action)))
                         (cddr action))))))

  ;; write! : WebSocket Bytevector -> Void
  ;; The bytes written, and counted unsent until their done comes, which
  ;; wakes a send that waits once no more than the low water is unsent.
  (define (write! ws bv)
    (let ((n (bytevector-length bv)))
      (websocket-unsent-set! ws (fx+ (websocket-unsent ws) n))
      (transport-write! (websocket-transport ws) bv 0 n
                        (lambda (why)
                          (websocket-unsent-set! ws (fx- (websocket-unsent ws) n))
                          (when (fx<=? (websocket-unsent ws)
                                       (websocket-limits-write-low-water (websocket-limits ws)))
                            (wake-sender! ws))))))

  ;; arm! : WebSocket Symbol -> Void — the deadline, for its kind's time.
  (define (arm! ws kind)
    (let ((limits (websocket-limits ws)))
      (transport-deadline! (websocket-transport ws)
                           (case kind
                             ((ping) (websocket-limits-ping-interval-ms limits))
                             ((pong) (websocket-limits-ping-timeout-ms limits))
                             (else (websocket-limits-close-timeout-ms limits)))
                           (websocket-passed ws))))

  ;; start-reading! : WebSocket -> Void
  (define (start-reading! ws)
    (transport-read-start! (websocket-transport ws) (websocket-on-bytes ws) (websocket-on-end ws)))

  ;; ended! : WebSocket Nat Bytevector Boolean -> Void
  ;; The connection's end, kept, and whatever waits woken.
  (define (ended! ws code reason clean?)
    (websocket-ended-set! ws (make-websocket-closed code (decode reason) clean?))
    (wake-receiver! ws)
    (wake-sender! ws))

  ;; The queue of messages delivered, oldest first.
  (define (enqueue! ws m)
    (let ((cell (list m)))
      (if (websocket-tail ws)
          (set-cdr! (websocket-tail ws) cell)
          (websocket-head-set! ws cell))
      (websocket-tail-set! ws cell)))

  (define (dequeue! ws)
    (let ((cell (websocket-head ws)))
      (websocket-head-set! ws (cdr cell))
      (when (null? (cdr cell)) (websocket-tail-set! ws #f))
      (car cell)))

  ;; The waits: a receive's and a send's, each woken once.
  (define (wake-receiver! ws)
    (let ((r (websocket-receiver ws)))
      (when r (websocket-receiver-set! ws #f) (r #t))))

  (define (wake-sender! ws)
    (let ((r (websocket-sender ws)))
      (when r (websocket-sender-set! ws #f) (r #t))))

  ;; park! : WebSocket (WebSocket (U Resume #f) -> Void) -> Void
  ;; Waits, its resume kept with `keep!`, until it is woken.  A wait that
  ;; raises lets go of its resume first: &client-closed, the stream's close,
  ;; is stepped as its end; anything else, a deadline the handler set, say,
  ;; goes on out.  No guard, which costs a waiting coroutine kilobytes.
  (define (park! ws keep!)
    (when (call/1cc
           (lambda (k)
             (with-exception-handler
              (lambda (e)
                (keep! ws #f)
                (if (client-closed? e) (k #t) (raise e)))
              (lambda ()
                (await (lambda (resume) (keep! ws resume)))
                #f))))
      (step! ws '(end closed))))

  ;; check : Any Symbol -> Void
  (define (check ws who)
    (unless (websocket? ws) (assertion-violation who "not a WebSocket" ws)))

  ;; websocket-receive : WebSocket -> (U String Bytevector)
  ;; The oldest message delivered and not yet received: a text's string, or
  ;; a binary's bytevector.  It waits until one comes.  Once the connection
  ;; has ended, the messages still queued are received first; then it raises
  ;; &websocket-closed, and again at every later call.
  (define (websocket-receive ws)
    (check ws 'websocket-receive)
    (let loop ()
      (cond ((pair? (websocket-head ws))
             (let* ((m (dequeue! ws)) (payload (cdr m)))
               (step! ws (list 'taken (bytevector-length payload)))
               (if (eq? (car m) 'text) (decode payload) payload)))
            ((websocket-ended ws) => raise)
            (else (park! ws websocket-receiver-set!) (loop)))))

  ;; websocket-send! : WebSocket (U String Bytevector) -> Void
  ;; Sends a text of the string, or a binary of the bytevector, as one
  ;; frame.  While more than the high water is unsent, it waits until no
  ;; more than the low water is.  Once the connection has ended it raises
  ;; &websocket-closed; while the server's close is under way it sends
  ;; nothing, waits for the end, and then raises it, as websockets does.
  (define (websocket-send! ws payload)
    (check ws 'websocket-send!)
    (let ((kind (cond ((string? payload) 'text)
                      ((bytevector? payload) 'binary)
                      (else (assertion-violation 'websocket-send! "not a string or a bytevector" payload)))))
      (cond ((websocket-ended ws) => raise)
            ((websocket-closing? ws)
             (let loop () (unless (websocket-ended ws) (park! ws websocket-sender-set!) (loop)))
             (raise (websocket-ended ws)))
            (else
             (step! ws (list 'send kind payload))
             (when (fx>? (websocket-unsent ws) (websocket-limits-write-high-water (websocket-limits ws)))
               (park! ws websocket-sender-set!)
               (cond ((websocket-ended ws) => raise)))))))

  ;; websocket-close! : WebSocket [Nat [String]] -> Void
  ;; Starts the closing handshake with the code, 1000 unless given, and the
  ;; reason, "" unless given, and returns; the handshake finishes on its own.
  ;; Once a close was sent, or the connection has ended, it does nothing.
  (define websocket-close!
    (case-lambda
      ((ws) (websocket-close! ws 1000 ""))
      ((ws code) (websocket-close! ws code ""))
      ((ws code reason)
       (check ws 'websocket-close!)
       (close-from! ws code reason))))

  ;; close-from! : WebSocket Nat String -> Void — the server's close, once.
  (define (close-from! ws code reason)
    (unless (or (websocket-closing? ws) (websocket-ended ws))
      (step! ws (list 'close code reason))
      (websocket-closing?-set! ws #t)))

  ;; decode : Bytevector -> String
  ;; Checked UTF-8 as its string, a leading U+FEFF kept: Chez 10.4.1's
  ;; utf8->string drops one leading byte-order mark (the design's §6), so
  ;; it is put back.
  (define (decode bv)
    (if (and (fx>=? (bytevector-length bv) 3)
             (fx=? (bytevector-u8-ref bv 0) #xEF)
             (fx=? (bytevector-u8-ref bv 1) #xBB)
             (fx=? (bytevector-u8-ref bv 2) #xBF))
        (string-append (string #\xFEFF) (utf8->string bv))
        (utf8->string bv)))

  ;; log-line : String (Listof Any) -> Void
  ;; One line on the current output port, flushed at once: `what`, then each
  ;; detail after a space, as the server logs.
  (define (log-line what details)
    (let ((out (current-output-port)))
      (put-string out what)
      (for-each (lambda (d) (put-char out #\space) (put-detail out d)) details)
      (newline out)
      (flush-output-port out)))

  ;; put-detail : OutputPort Any -> Void
  ;; A condition as display-condition shows it, on one line; a string,
  ;; symbol, number, boolean or character displayed; a record by its type's
  ;; name; anything else written.
  (define (put-detail out d)
    (cond ((condition? d)
           (put-string out (one-line (call-with-string-output-port (lambda (p) (display-condition d p))))))
          ((or (string? d) (symbol? d) (number? d) (boolean? d) (char? d)) (display d out))
          ((record? d)
           (put-string out "#<")
           (display (record-type-name (record-rtd d)) out)
           (put-string out ">"))
          (else (write d out))))

  ;; one-line : String -> String — its line breaks made spaces.
  (define (one-line s)
    (list->string (map (lambda (c) (if (memv c '(#\newline #\return)) #\space c)) (string->list s)))))
