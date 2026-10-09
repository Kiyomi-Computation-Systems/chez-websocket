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
;;; take, a write's done, a send, a close, is stepped at once, and the
;;; actions performed at once, in order:
;;;   write            transport-write!, in writes of 64 KiB at most, each
;;;                    done stepped as written, whatever it says, and one
;;;                    that tells a failure as the stream's end too
;;;                    (decision 0006, and its amendment by form: "In 64 KiB
;;;                    writes")
;;;   deliver          the message queued for websocket-receive, which is
;;;                    woken if it waits
;;;   read-stop, read-start   the transport's verbs
;;;   arm-deadline     transport-deadline!, for the kind's time: ping the
;;;                    ping interval, pong the ping timeout, close the close
;;;                    timeout, write the write timeout; its passing stepped
;;;                    as deadline-passed
;;;   disarm-deadline  transport-deadline! with #f
;;;   close-stream     the deadline armed for the close timeout, its call
;;;                    transport-abort!, then transport-close!: a client that
;;;                    has not read what was written by then is aborted
;;;                    (0006; timed from here, as peers time a close, by
;;;                    form: "From queueing, as peers do")
;;;   abort-stream     transport-abort!: the close timeout, or the write
;;;                    timeout, has passed
;;;   closed           the WebSocket's end, &websocket-closed, kept; a
;;;                    receive or a send that waits is woken
;;;   log              a line on the current output port, as the server
;;;                    logs: its name prefixed websocket-, then each detail
;;;
;;; The waits (decision 0005).  A receive or a send waits on `await`, its
;;; waiter kept on the WebSocket, with the WebSocket whose procedure runs on
;;; the coroutine that waits, if any (`current-websocket`, set around each
;;; procedure).  Any number of coroutines may wait to send while the core
;;; says the client is behind (ws-behind?, 0006): a send waits before it
;;; writes, and after a write that puts the client behind (by form: "Wait
;;; before writing too"), so what one client makes the server hold is the
;;; high water and the one frame that passed it, however many send.  All
;;; that wait are woken at the done that ends it, and each goes on in turn
;;; while the client is not behind.  One receive may wait, and a second
;;; while it does is refused, as websockets refuses it.  Waking lets the
;;; waiter go.
;;;
;;; The stream's close, whoever closed it (decision 0023).  The server tells
;;; the wait the procedure is in, or else its next, raising &client-closed
;;; there, and then runs the transport's close call: both of its shells, in
;;; that order.  The close call marks the wait the WebSocket's procedure is
;;; in, wherever it waits, as ended, so nothing wakes it, which would be a
;;; late resume; then steps the stream's end, `(end closed)`, so the core
;;; reads what waits for the queue and ends the connection, 1006, unless it
;;; has ended, waking whatever else waits.  A wait's &client-closed is its
;;; own coroutine's stream's: on its own WebSocket it ends the wait, and the
;;; receive or send sees the end; on another's it goes on out, to the
;;; procedure whose stream closed.  The server's drain closes with 1001,
;;; "going away".
;;;
;;; The procedure's end: its return closes with 1000; its own WebSocket's
;;; &websocket-closed let out does nothing more, nor a &client-closed, which
;;; is its stream's close; any other raise, another WebSocket's end among
;;; them, closes with 1011 and is logged `websocket-handler-failed`.  The
;;; thunk lets nothing out, so the server logs nothing for it.
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
  ;; pair or #f; `receiver` the waiter of the receive that waits, or #f;
  ;; `senders` the waiters of the sends that wait; `parked` the waiter its
  ;; own procedure last waited in, on this WebSocket or another, or #f;
  ;; `ended` the &websocket-closed once the connection has ended, or #f.
  ;; What is unsent is the core's to count (0006).  The core's callbacks are
  ;; made once, here, and its read, take and done events too, each filled in
  ;; before it is stepped, so none allocates (the core keeps no event).
  ;;   websocket? : Any -> Boolean
  ;;   websocket-subprotocol : WebSocket -> (U String #f)
  (define-record-type (websocket new-websocket websocket?)
    (fields (immutable transport) (mutable state) (immutable limits)
            (immutable subprotocol)
            (mutable head) (mutable tail) (mutable receiver) (mutable senders)
            (mutable parked) (mutable ended)
            (mutable on-bytes) (mutable on-end) (mutable passed)
            (immutable read-event) (immutable taken-event) (immutable written-event)))

  ;; A wait: its resume, the WebSocket whose procedure waits in it, or #f,
  ;; and whether the stream's close has ended it.
  (define-record-type waiter
    (fields (mutable resume) (immutable owner) (mutable dead?)))

  ;; current-websocket : (Parameter (U WebSocket #f))
  ;; The WebSocket whose procedure runs on this coroutine.  The server's
  ;; scheduler runs a parameterize's winders as a coroutine parks and
  ;; resumes, so each coroutine sees its own.
  (define current-websocket (make-parameter #f))

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
       (unless (handshake-settings? settings)
         (assertion-violation 'websocket-accept "not handshake settings" settings))
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
                              '() #f #f '() #f #f #f #f #f
                              (list 'bytes #f 0 0) (list 'taken 0) (list 'written 0))))
      (websocket-on-bytes-set! ws
        (lambda (bv start end)
          (let ((event (websocket-read-event ws)))
            (set-car! (cdr event) bv)
            (set-car! (cddr event) start)
            (set-car! (cdddr event) end)
            (step! ws event)
            (set-car! (cdr event) #f))))
      (websocket-on-end-set! ws (lambda (why) (step! ws (list 'end why))))
      (websocket-passed-set! ws (lambda () (step! ws '(deadline-passed))))
      (let ((kind (ws-deadline state)))
        (when kind (arm! ws kind)))
      (start-reading! ws)
      (let ((n (bytevector-length retained)))
        (when (fx>? n 0) (step! ws (list 'bytes retained 0 n))))
      (transport-on-close! transport
        (lambda ()
          (let ((w (websocket-parked ws)))
            (when w (waiter-dead?-set! w #t)))
          (step! ws '(end closed))))
      (transport-on-drain! transport (lambda () (close-from! ws 1001 "going away")))
      (awaiting (lambda () (run ws proc)))))

  ;; run : WebSocket (WebSocket -> Any) -> Void
  ;; The procedure, and its end.
  (define (run ws proc)
    (guard (e ((or (client-closed? e) (own-end? ws e)) (if #f #f))
              (else (log-line "websocket-handler-failed" (list e))
                    (close-from! ws 1011 "")))
      (parameterize ((current-websocket ws)) (proc ws))
      (close-from! ws 1000 "")))

  ;; own-end? : WebSocket Any -> Boolean — the WebSocket's own end, raised.
  (define (own-end? ws e)
    (let ((end (websocket-ended ws)))
      (and end (eq? e end))))

  ;; step! : WebSocket Event -> Void
  ;; The event stepped, and the actions performed, in order.
  (define (step! ws event)
    (let-values (((state actions) (ws-step (websocket-state ws) event)))
      (websocket-state-set! ws state)
      (let loop ((actions actions))
        (unless (null? actions)
          (perform! ws (car actions))
          (loop (cdr actions))))))

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
        ((close-stream) (close-stream! ws))
        ((abort-stream) (transport-abort! t))
        ((closed) (ended! ws (cadr action) (caddr action) (cadddr action)))
        ((log) (log-line (string-append "websocket-" (symbol->string (cadr action)))
                         (cddr action))))))

  ;; write-piece : Nat — the most bytes one transport write carries (by
  ;; form, "In 64 KiB writes"): a frame past it goes in several, each done
  ;; its own, so a client that reads a large message steadily is seen to
  ;; read it, as nginx's send_timeout runs between two writes.
  (define write-piece 65536)

  ;; write! : WebSocket Bytevector -> Void
  ;; The bytes written, in writes of write-piece at most, each done
  ;; stepped (wrote!).
  (define (write! ws bv)
    (let ((t (websocket-transport ws)) (n (bytevector-length bv)))
      (let loop ((start 0))
        (let* ((end (fxmin n (fx+ start write-piece))) (k (fx- end start)))
          (transport-write! t bv start end (lambda (why) (wrote! ws k why)))
          (when (fx<? end n) (loop end))))))

  ;; wrote! : WebSocket Nat (U #f Symbol) -> Void
  ;; A write's n bytes done, stepped, whatever its done says; one that tells
  ;; a failure, the errno, then stepped as the stream's end, which after
  ;; the end answers nothing, as for a cancel at the close.  The sends that
  ;; wait woken once the client is no longer behind.
  (define (wrote! ws n why)
    (let ((event (websocket-written-event ws)))
      (set-car! (cdr event) n)
      (step! ws event)
      (when why (step! ws (list 'end why)))
      (unless (ws-behind? (websocket-state ws)) (wake-senders! ws))))

  ;; close-stream! : WebSocket -> Void
  ;; The stream closed once what is written has gone, unless the client has
  ;; not read it within the close timeout: then aborted (0006).  The deadline
  ;; goes first: a close that begins at once, nothing unsent, disarms it, in
  ;; both of the server's shells.
  (define (close-stream! ws)
    (let ((t (websocket-transport ws)))
      (transport-deadline! t (websocket-limits-close-timeout-ms (websocket-limits ws))
                           (lambda () (transport-abort! t)))
      (transport-close! t)))

  ;; arm! : WebSocket Symbol -> Void — the deadline, for its kind's time.
  (define (arm! ws kind)
    (let ((limits (websocket-limits ws)))
      (transport-deadline! (websocket-transport ws)
                           (case kind
                             ((ping) (websocket-limits-ping-interval-ms limits))
                             ((pong) (websocket-limits-ping-timeout-ms limits))
                             ((write) (websocket-limits-write-timeout-ms limits))
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
    (wake-senders! ws))

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

  ;; The waits, each woken once, and let go as it is.

  ;; resume! : Waiter -> Void
  ;; The waiter woken, unless the stream's close has ended its wait.  Its
  ;; owner's `parked` may go on naming it: woken, or raised, a waiter is out
  ;; of every list, and the close call marking it ended changes nothing.
  (define (resume! w)
    (unless (waiter-dead? w)
      ((waiter-resume w) #t)))

  (define (wake-receiver! ws)
    (let ((w (websocket-receiver ws)))
      (when w (websocket-receiver-set! ws #f) (resume! w))))

  (define (wake-senders! ws)
    (let ((waiting (websocket-senders ws)))
      (unless (null? waiting)
        (websocket-senders-set! ws '())
        (for-each resume! (reverse waiting)))))

  ;; park! : WebSocket Boolean -> Void
  ;; Waits, to send or to receive, until it is woken.  A wait that raises
  ;; lets go of its waiter first: a &client-closed on the procedure's own
  ;; WebSocket is its stream's close, which the close call has stepped, so
  ;; the wait ends; anything else goes on out, another stream's close, or a
  ;; deadline the handler set.  The way back out of the wait is a full
  ;; continuation: a one-shot one, call/1cc, held a stack segment of its own
  ;; for as long as the procedure waited, 2.8 to 4.3 KB a connection on a
  ;; real socket (decision 0005's amendment, by form: "call/cc").
  (define (park! ws send?)
    (let* ((owner (current-websocket))
           (w (make-waiter #f owner #f)))
      (call/cc
       (lambda (k)
         (with-exception-handler
          (lambda (e)
            (if (eq? (websocket-receiver ws) w)
                (websocket-receiver-set! ws #f)
                (websocket-senders-set! ws (remq w (websocket-senders ws))))
            (if (and (client-closed? e) (eq? owner ws)) (k #f) (raise e)))
          (lambda ()
            (await (lambda (resume)
                     (waiter-resume-set! w resume)
                     (when owner (websocket-parked-set! owner w))
                     (if send?
                         (websocket-senders-set! ws (cons w (websocket-senders ws)))
                         (websocket-receiver-set! ws w))))))))))

  ;; check : Any Symbol -> Void
  (define (check ws who)
    (unless (websocket? ws) (assertion-violation who "not a WebSocket" ws)))

  ;; websocket-receive : WebSocket -> (U String Bytevector)
  ;; The oldest message delivered and not yet received: a text's string, or
  ;; a binary's bytevector.  It waits until one comes; a receive while
  ;; another waits on the WebSocket is refused (decision 0005).  Once the
  ;; connection has ended, the messages still queued are received first;
  ;; then it raises &websocket-closed, and again at every later call.
  (define (websocket-receive ws)
    (check ws 'websocket-receive)
    (let loop ()
      (cond ((pair? (websocket-head ws))
             (let* ((m (dequeue! ws)) (payload (cdr m)) (event (websocket-taken-event ws)))
               (set-car! (cdr event) (bytevector-length payload))
               (step! ws event)
               (if (eq? (car m) 'text) (decode payload) payload)))
            ((websocket-ended ws) => raise)
            ((websocket-receiver ws)
             (assertion-violation 'websocket-receive "another receive waits on this WebSocket" ws))
            (else (park! ws #f) (loop)))))

  ;; websocket-send! : WebSocket (U String Bytevector) -> Void
  ;; Sends a text of the string, or a binary of the bytevector, as one
  ;; frame.  While the client is behind, more than the high water unsent, it
  ;; waits until a done brings that to the low water, beside any other send
  ;; that waits (decisions 0005 and 0006): before it writes, and after a
  ;; write that puts the client behind.  Once the connection has ended it
  ;; raises &websocket-closed; while the server's close is under way it
  ;; sends nothing, waits for the end, and then raises it, as websockets
  ;; does.
  (define (websocket-send! ws payload)
    (check ws 'websocket-send!)
    (let ((kind (cond ((string? payload) 'text)
                      ((bytevector? payload) 'binary)
                      (else (assertion-violation 'websocket-send! "not a string or a bytevector" payload)))))
      (let loop ()
        (cond ((websocket-ended ws) => raise)
              ((or (not (ws-open? (websocket-state ws))) (ws-behind? (websocket-state ws)))
               (park! ws #t)
               (loop))
              (else
               (step! ws (list 'send kind payload))
               (when (ws-behind? (websocket-state ws))
                 (park! ws #t)
                 (cond ((websocket-ended ws) => raise))))))))

  ;; websocket-close! : WebSocket [Nat [String]] -> Void
  ;; Starts the closing handshake with the code, 1000 unless given, and the
  ;; reason, "" unless given, and returns; the handshake finishes on its own.
  ;; A code an endpoint may not send, or a reason past 123 bytes, is refused
  ;; (ws-sendable-close?).  Once a close was sent, or the connection has
  ;; ended, it does nothing.
  (define websocket-close!
    (case-lambda
      ((ws) (websocket-close! ws 1000 ""))
      ((ws code) (websocket-close! ws code ""))
      ((ws code reason)
       (check ws 'websocket-close!)
       (unless (ws-sendable-close? code reason)
         (assertion-violation 'websocket-close! "not a close the server may send" code reason))
       (close-from! ws code reason))))

  ;; close-from! : WebSocket Nat String -> Void
  ;; The server's close, while the connection is open: the core's phase says.
  (define (close-from! ws code reason)
    (when (ws-open? (websocket-state ws))
      (step! ws (list 'close code reason))))

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
