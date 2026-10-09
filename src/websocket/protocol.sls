#!r6rs
;;; (websocket protocol) — a connection's state machine (design §5): its
;;; messages, its control frames, its limits, its closing handshake, and
;;; its ping clock.
;;;
;;; `ws-step : WsState Event -> (values WsState (Listof Action))` is pure by
;;; contract, as the server's conn-step is: it allocates only Scheme data,
;;; reads no clock, and never raises on a well-formed event.  An event
;;; outside the vocabulary, or one the state says cannot have happened, such
;;; as a read while reading is stopped, is a caller's mistake and an
;;; assertion violation naming ws-step.  The state is linear: a step updates
;;; the state it is given and returns it.
;;;
;;;   events   (bytes bv start end)   a read's bytes; the bytevector the
;;;                                   core may keep, as the server's
;;;                                   transport hands a taker its reads
;;;            (send kind payload)    a message: text with a string, or
;;;                                   binary with a bytevector
;;;            (close code reason)    the server's close: a code an
;;;                                   endpoint may send, a reason a string
;;;            (end why)              the stream's end: 'eof, or the errno
;;;            (taken nbytes)         the handler took a delivered message
;;;                                   of nbytes
;;;            (deadline-passed)      the deadline armed has passed
;;;   actions  (write bv)  (deliver kind payload)  (read-stop)  (read-start)
;;;            (arm-deadline kind)  (disarm-deadline)  (close-stream)
;;;            (closed code reason clean?)  (log what . details)
;;;
;;; A delivered message is whole (0001): a text's payload is its UTF-8
;;; bytes, checked, which the binding decodes, and a binary's its bytes.  A
;;; closed's reason is bytes too.
;;;
;;; - Messages (§5.4).  A data frame with FIN set is a message.  One with FIN
;;;   clear begins a fragmented message, of its kind, which continuations
;;;   go on with until FIN.  A continuation with no message begun, or a new
;;;   message begun before the last has ended, fails 1002.
;;; - The cap (0001).  A data frame whose length would take its message
;;;   past the cap fails 1009 at its header, before any of its payload is
;;;   held.  A message's buffer grows as its bytes arrive, never with what a
;;;   header announces, doubling (room!); a message read whole in one frame
;;;   is read into the bytevector it is delivered in.
;;; - UTF-8 (§8.1).  Text is checked as it arrives, so a byte no character
;;;   can go on with fails 1007 at once; a message must end on a whole
;;;   character.
;;; - Control frames (§5.5) may come between a message's fragments.  A ping
;;;   is answered at once with a pong carrying its payload, a pong is
;;;   answered with nothing, and a close as below.
;;; - Failing (§7.1.7) writes a close with its code, unless the server's
;;;   close was sent, closes the stream, logs why, with the code of the
;;;   close it wrote, or #f if it wrote none, and tells 1006 and an empty
;;;   reason, since no close came (§7.1.5, §7.1.6).  The frame decoder's
;;;   refusals fail 1002 with its reason.
;;; - A client's close (§5.5.1; 0001's amendment of 2026-10-05, by form) is
;;;   answered with a close of its code, or with an empty close when it has
;;;   none, unless the server's close was sent, and the stream is closed: a
;;;   close has gone each way, so the close is clean, and the handler is
;;;   told its code, or 1005 (§7.4.1), and its reason.  Its code must be one
;;;   an endpoint may send, 1000 to 1003, 1007 to 1011 and 3000 to 4999
;;;   (§7.4.1, §7.4.2), and its body is not one byte, or it fails 1002; its
;;;   reason not UTF-8 fails 1007.
;;; - The server's close (§7.1.2) is written with its code and reason, and
;;;   arms the close deadline.  Its reason is measured in UTF-8, not
;;;   encoded, until the close is written.  Reading goes on as before: a
;;;   message that comes after it is delivered (decided by form,
;;;   2026-10-05), and a ping answered, since no close has been received
;;;   (§5.5.2).  The client's close ends the handshake.  If its deadline
;;;   passes first, the stream is closed anyway, and 1006 told.  Once a close
;;;   is sent, a send is the caller's mistake (§5.5.1), and another close
;;;   answers nothing.
;;; - The stream's end with no close received closes the stream and tells
;;;   1006 (§7.1.5).  Nothing is written, since nothing reads it.
;;; - At the stream's end, or when the close's deadline passes, no more
;;;   bytes will come, so what waits for the queue is read first, whatever
;;;   the queue holds: at most the rest of one read.  A client's close among it ends
;;;   the connection as any close does, cleanly, with its code.
;;; - Time is a deadline's kind: the step reads no clock, names the deadline
;;;   it needs, ping, pong or close, one at a time, as the transport has
;;;   one, and disarms it if the connection ends before it passes.  A new
;;;   connection's is ping, unless pinging is off: no step tells it, and
;;;   ws-deadline names it for the binding to arm as it starts.  A deadline
;;;   passing with none armed is the caller's mistake.
;;; - The ping clock (0001 item 2, and its amendment of 2026-10-06).  Any
;;;   bytes received re-arm ping, after the read's own actions, whether a
;;;   pong is awaited or not; a read of no bytes changes nothing.  When ping
;;;   passes, the client has sent nothing for its interval: a ping with no
;;;   payload is written, and pong armed.  When pong passes, nothing has
;;;   come since, and the connection fails with 1011, websockets'
;;;   keepalive's code.  The clock stops while reading is, since a pong the
;;;   server does not read is not the client's fault, and starts afresh, at
;;;   ping, when reading starts again.  The server's close takes the one
;;;   deadline for its own, and the clock does not run again.  A ping
;;;   interval of 0 turns it off.  Re-arming allocates nothing: a step ends
;;;   with a constant tail of actions.
;;; - Once the connection has ended, failed or closed, nothing more is read,
;;;   the rest of a read among it, and a ping is not answered (§5.5.2).  A
;;;   close or the stream's end then answers nothing.
;;; - Reading on (0001, and its amendment).  Each delivered message is
;;;   queued for the handler until it is taken.  Once the queue holds a
;;;   cap's worth of bytes, or max-queue messages, the step answers
;;;   read-stop and reads no further: the rest of the read waits, kept,
;;;   since the read's bytevector is the core's to keep.  A take that brings
;;;   the queue under both reads what waits, a message at a time as the
;;;   queue makes room, and then answers read-start.
(library (websocket protocol)
  (export make-ws-state ws-step ws-deadline ws-open? ws-sendable-close?)
  (import (rnrs) (websocket frame) (websocket utf8) (websocket limits))

  ;; A connection.  `phase` is open, closing once the server's close is
  ;; sent, or ended.  `message` is the kind of the message begun, or #f,
  ;; and `buffer` holds its `held` bytes, `utf8` the checker's state for a
  ;; text.  Between messages, `held` is 0 and `utf8` is utf8-start, since a
  ;; text ends whole or the connection fails.  `control` holds a control
  ;; frame's payload, `control-n` of it so far.  `queued-bytes` and
  ;; `queued-count` are the messages delivered and not taken; `reading?` is
  ;; whether the transport reads, as the step last told it; `waiting` is a
  ;; read's bytevector whose bytes from `waiting-start` to `waiting-end`
  ;; wait for the queue to make room, or #f.  `deadline` is the kind of the
  ;; deadline armed, as the steps have told the binding, or #f; a new
  ;; connection's, which no step tells, ws-deadline names.  `ping?` is
  ;; whether the ping clock runs at all.
  (define-record-type (ws-state new-state ws-state?)
    (fields (immutable decoder) (immutable cap) (immutable max-queue)
            (immutable ping?)
            (mutable phase) (mutable message) (mutable buffer) (mutable held)
            (mutable utf8) (immutable control) (mutable control-n)
            (mutable queued-bytes) (mutable queued-count) (mutable reading?)
            (mutable waiting) (mutable waiting-start) (mutable waiting-end)
            (mutable deadline)))

  ;; make-ws-state : WebsocketLimits -> WsState
  ;; A connection open, reading, with nothing queued, and its ping deadline
  ;; armed unless pinging is off.
  (define (make-ws-state limits)
    (unless (websocket-limits? limits)
      (assertion-violation 'make-ws-state "not limits" limits))
    (let ((ping? (fx>? (websocket-limits-ping-interval-ms limits) 0)))
      (new-state (make-frame-decoder)
                 (websocket-limits-max-message-bytes limits)
                 (websocket-limits-max-queue limits)
                 ping?
                 'open #f #f 0 utf8-start (make-bytevector 125 0) 0 0 0 #t #f 0 0
                 (and ping? 'ping))))

  ;; ws-deadline : WsState -> (U 'ping 'pong 'close #f)
  ;; The kind of the deadline armed, as the steps have told the binding.  A
  ;; new connection's is ping, unless pinging is off: no step tells it, and
  ;; the binding arms it as it starts.
  (define (ws-deadline s)
    (unless (ws-state? s)
      (assertion-violation 'ws-deadline "not a connection" s))
    (ws-state-deadline s))

  ;; ws-open? : WsState -> Boolean
  ;; Whether the connection is open: no close sent by the server, and not
  ;; ended.  A send is the caller's mistake once it is not.
  (define (ws-open? s)
    (unless (ws-state? s)
      (assertion-violation 'ws-open? "not a connection" s))
    (eq? (ws-state-phase s) 'open))

  ;; The deadline, one at a time, as the transport has one.  The record and
  ;; what the binding is told change together, here.

  ;; arm! : WsState Action -> Action
  ;; `(arm-deadline kind)`, its kind recorded as armed.
  (define (arm! s action)
    (ws-state-deadline-set! s (cadr action))
    action)

  ;; disarm! : WsState (Listof Action) -> (Listof Action)
  ;; The deadline armed let go: recorded so, and `(disarm-deadline)` told.
  (define (disarm! s acts)
    (ws-state-deadline-set! s #f)
    (cons '(disarm-deadline) acts))

  ;; The ping clock (0001 item 2).  A step's last actions, as constants, so
  ;; that re-arming at every read allocates nothing.
  (define ping-armed '((arm-deadline ping)))
  (define reading-started '((read-start)))
  (define reading-started-ping-armed '((read-start) (arm-deadline ping)))

  ;; clock? : WsState -> Boolean
  ;; Whether the ping clock may run: pinging on, and the connection open,
  ;; since the server's close takes the one deadline for its own.
  (define (clock? s)
    (and (ws-state-ping? s) (eq? (ws-state-phase s) 'open)))

  ;; reverse-onto : (Listof Action) (Listof Action) -> (Listof Action)
  ;; Actions accumulated newest first, in order, before `tail`.
  (define (reverse-onto acts tail)
    (if (null? acts) tail (reverse-onto (cdr acts) (cons (car acts) tail))))

  ;; A connection's end, as actions are accumulated: newest first.

  ;; end! : WsState (Listof Action) (Listof Action) -> (Listof Action)
  ;; Ends the connection with `last`, its last actions, in order, after
  ;; disarming the deadline armed, and lets go of an unfinished message's
  ;; bytes: a connection lives as long as its WebSocket, and nothing reads
  ;; it after its end.  Nothing waits for the queue by then: a read comes
  ;; only while reading, so with nothing waiting; a take, the close timeout
  ;; and the stream's end let go of what waits as they read it
  ;; (read-waiting!); and the pong's deadline cannot pass while anything
  ;; waits, since the clock stops whenever reading does.
  (define (end! s last acts)
    (let ((acts (if (ws-state-deadline s) (disarm! s acts) acts)))
      (ws-state-phase-set! s 'ended)
      (ws-state-buffer-set! s #f)
      (append (reverse last) acts)))

  ;; unclean : -> Action
  ;; The connection closed with no close received (§7.1.5, §7.1.6): 1006,
  ;; an empty reason, and not cleanly.
  (define (unclean)
    (list 'closed 1006 (make-bytevector 0) #f))

  ;; close-frame : Nat Bytevector -> Bytevector
  ;; The server's close (§5.5.1): its body the code, two bytes big-endian,
  ;; then the reason's bytes.
  (define (close-frame code reason)
    (let* ((n (bytevector-length reason)) (body (make-bytevector (fx+ 2 n))))
      (bytevector-u16-set! body 0 code (endianness big))
      (bytevector-copy! reason 0 body 2 n)
      (frame-encode 'close body)))

  ;; fail! : WsState Nat Symbol (Listof Action) -> (Listof Action)
  ;; Fails the connection (§7.1.7).
  (define (fail! s code why acts)
    (let ((open? (eq? (ws-state-phase s) 'open)))
      (end! s (append (if open? (list (list 'write (close-frame code #vu8()))) '())
                      (list '(close-stream) (list 'log 'failed (and open? code) why) (unclean)))
            acts)))

  ;; sendable? : Nat -> Boolean
  ;; Whether an endpoint may send the code (§7.4.1, §7.4.2).
  (define (sendable? code)
    (or (and (fx<=? 1000 code) (fx<=? code 1003))
        (and (fx<=? 1007 code) (fx<=? code 1011))
        (and (fx<=? 3000 code) (fx<=? code 4999))))

  ;; closing! : WsState (Listof Action) -> (Listof Action)
  ;; A client's close, whose body is the control buffer's.
  (define (closing! s acts)
    (let ((n (ws-state-control-n s)) (body (ws-state-control s)))
      ;; The close told as code and reason, its answer echoing k bytes of
      ;; its body, the code's or none, unless the server's was sent.
      (define (clean code reason k)
        (end! s (append (if (eq? (ws-state-phase s) 'open)
                            (list (list 'write (frame-encode 'close body 0 k)))
                            '())
                        (list '(close-stream) (list 'closed code reason #t)))
              acts))
      (cond
        ((fx=? n 0) (clean 1005 (make-bytevector 0) 0))
        ((fx=? n 1) (fail! s 1002 'close-body-one-byte acts))
        (else
         (let ((code (bytevector-u16-ref body 0 (endianness big))))
           (cond
             ((not (sendable? code)) (fail! s 1002 'close-code-not-sendable acts))
             ((not (utf8-whole? (utf8-feed utf8-start body 2 n)))
              (fail! s 1007 'close-reason-not-utf8 acts))
             (else
              (let ((reason (make-bytevector (fx- n 2))))
                (bytevector-copy! body 2 reason 0 (fx- n 2))
                (clean code reason 2)))))))))

  ;; control! : WsState (Listof Action) -> (Listof Action)
  ;; A control frame whose payload is whole.
  (define (control! s acts)
    (case (frame-kind (ws-state-decoder s))
      ((ping) (cons (list 'write (frame-encode 'pong (ws-state-control s) 0 (ws-state-control-n s)))
                    acts))
      ((pong) acts)
      (else (closing! s acts))))

  ;; full? : WsState -> Boolean
  ;; Whether the queue holds a cap's worth of bytes, or max-queue messages.
  (define (full? s)
    (or (>= (ws-state-queued-bytes s) (ws-state-cap s))
        (>= (ws-state-queued-count s) (ws-state-max-queue s))))

  ;; deliver! : WsState (Listof Action) -> (Listof Action)
  ;; The message begun, whole: delivered and queued, and reading stopped if
  ;; that fills the queue.
  (define (deliver! s acts)
    (let* ((n (ws-state-held s))
           (buffer (ws-state-buffer s))
           (payload (if (fx=? n (bytevector-length buffer))
                        buffer
                        (let ((out (make-bytevector n)))
                          (bytevector-copy! buffer 0 out 0 n)
                          out)))
           (acts (cons (list 'deliver (ws-state-message s) payload) acts)))
      (ws-state-message-set! s #f)
      (ws-state-buffer-set! s #f)
      (ws-state-held-set! s 0)
      (ws-state-queued-bytes-set! s (+ (ws-state-queued-bytes s) n))
      (ws-state-queued-count-set! s (+ (ws-state-queued-count s) 1))
      (if (and (ws-state-reading? s) (full? s))
          (begin (ws-state-reading?-set! s #f) (cons '(read-stop) acts))
          acts)))

  ;; data-end! : WsState (Listof Action) -> (Listof Action)
  ;; A data frame whose payload is whole: the message delivered if the frame
  ;; was its last, and a text ending mid-character failed.
  (define (data-end! s acts)
    (cond ((not (frame-fin? (ws-state-decoder s))) acts)
          ((and (eq? (ws-state-message s) 'text) (not (utf8-whole? (ws-state-utf8 s))))
           (fail! s 1007 'text-not-utf8 acts))
          (else (deliver! s acts))))

  ;; room! : WsState Nat -> Unspecified
  ;; Grows the buffer, if it must, to hold `avail` more bytes, which have
  ;; arrived.  A message's buffer grows with its bytes, never with what a
  ;; header announces, so what a client makes the server hold follows what
  ;; it sends.  It doubles, so a message read in many pieces is copied a
  ;; bounded number of times.  In a message's last frame, whose end is
  ;; known, once a doubling would reach half that end it takes the whole,
  ;; and no growth falls just short of it: under four times what has
  ;; arrived.  Before the last frame, it doubles up to the cap.
  (define (room! s avail)
    (let* ((d (ws-state-decoder s))
           (buffer (ws-state-buffer s))
           (held (ws-state-held s))
           (need (fx+ held avail)))
      (when (fx>? need (bytevector-length buffer))
        (let* ((doubled (max need (* 2 (bytevector-length buffer))))
               (bigger (make-bytevector
                        (if (frame-fin? d)
                            (let ((end (+ held (frame-left d))))
                              (if (>= (* 2 doubled) end) end doubled))
                            (min (ws-state-cap s) doubled)))))
          (bytevector-copy! buffer 0 bigger 0 held)
          (ws-state-buffer-set! s bigger)))))

  ;; header! : WsState (Listof Action) -> (Listof Action)
  ;; A frame's header, whole: the frame judged, and a frame of no payload
  ;; done at once.
  (define (header! s acts)
    (let* ((d (ws-state-decoder s))
           (kind (frame-kind d))
           (n (frame-length d)))
      (case kind
        ((ping pong close)
         (ws-state-control-n-set! s 0)
         (if (eqv? n 0) (control! s acts) acts))
        ((continuation)
         (cond ((not (ws-state-message s))
                (fail! s 1002 'continuation-without-message acts))
               ((> (+ (ws-state-held s) n) (ws-state-cap s))
                (fail! s 1009 'message-too-big acts))
               (else
                (if (eqv? n 0) (data-end! s acts) acts))))
        (else
         (cond ((ws-state-message s) (fail! s 1002 'message-unfinished acts))
               ((> n (ws-state-cap s)) (fail! s 1009 'message-too-big acts))
               (else
                (ws-state-message-set! s kind)
                (ws-state-buffer-set! s (make-bytevector 0))
                (if (eqv? n 0) (data-end! s acts) acts)))))))

  ;; read! : WsState Bytevector Nat Nat Boolean (Listof Action) -> (Listof Action)
  ;; Reads the bytes from start to end, until the connection ends, or, if
  ;; `bounded?`, the queue fills and the rest waits.
  (define (read! s bv start end bounded? acts)
    (let ((d (ws-state-decoder s)))
      (let loop ((i start) (acts acts))
        (cond
          ((eq? (ws-state-phase s) 'ended) acts)
          ((fx=? i end) acts)
          ((and bounded? (full? s))
           (ws-state-waiting-set! s bv)
           (ws-state-waiting-start-set! s i)
           (ws-state-waiting-end-set! s end)
           acts)
          ((eqv? (frame-left d) 0)
           (let-values (((what next) (frame-read-header! d bv i end)))
             (case what
               ((more) acts)
               ((refused)
                (let ((refusal (frame-refusal d)))
                  (fail! s (car refusal) (cadr refusal) acts)))
               (else (loop next (header! s acts))))))
          ((frame-control? d)
           (let ((n (frame-read-payload! d bv i end (ws-state-control s) (ws-state-control-n s))))
             (ws-state-control-n-set! s (fx+ (ws-state-control-n s) n))
             (loop (fx+ i n) (if (eqv? (frame-left d) 0) (control! s acts) acts))))
          (else
           (let* ((at (ws-state-held s))
                  (n (begin
                       (room! s (min (fx- end i) (frame-left d)))
                       (frame-read-payload! d bv i end (ws-state-buffer s) at))))
             (ws-state-held-set! s (fx+ at n))
             (if (and (eq? (ws-state-message s) 'text)
                      (let ((u (utf8-feed (ws-state-utf8 s) (ws-state-buffer s) at (fx+ at n))))
                        (ws-state-utf8-set! s u)
                        (not u)))
                 (fail! s 1007 'text-not-utf8 acts)
                 (loop (fx+ i n) (if (eqv? (frame-left d) 0) (data-end! s acts) acts)))))))))

  ;; event-of! : Any Nat -> Unspecified
  ;; An assertion violation unless the event is a list of k elements.
  (define (event-of! event k)
    (unless (and (list? event) (= (length event) k))
      (assertion-violation 'ws-step "not an event" event)))

  ;; bytes! : WsState Any Any Any -> (Listof Action)
  ;; A read's bytes read, then the ping clock told, if it may run: stopped,
  ;; if the read filled the queue, after its read-stop, the last action a
  ;; read that stops reading tells (ping or pong is armed whenever the
  ;; clock may run and reading does); else re-armed, if bytes came.
  (define (bytes! s bv start end)
    (unless (and (bytevector? bv) (fixnum? start) (fixnum? end)
                 (fx<=? 0 start) (fx<=? start end) (fx<=? end (bytevector-length bv)))
      (assertion-violation 'ws-step "not a range of a bytevector" start end))
    (when (eq? (ws-state-phase s) 'ended)
      (assertion-violation 'ws-step "a read after the connection has ended"))
    (unless (ws-state-reading? s)
      (assertion-violation 'ws-step "a read while reading is stopped"))
    (let ((acts (read! s bv start end #t '())))
      (cond ((not (clock? s)) (reverse acts))
            ((not (ws-state-reading? s)) (reverse (disarm! s acts)))
            ((fx<? start end) (arm! s (car ping-armed)) (reverse-onto acts ping-armed))
            (else (reverse acts)))))

  ;; send! : WsState Any Any -> (Listof Action)
  (define (send! s kind payload)
    (unless (eq? (ws-state-phase s) 'open)
      (assertion-violation 'ws-step "a send after a close was sent, or the connection ended" kind))
    (cond ((and (eq? kind 'text) (string? payload))
           (list (list 'write (frame-encode 'text (string->utf8 payload)))))
          ((and (eq? kind 'binary) (bytevector? payload))
           (list (list 'write (frame-encode 'binary payload))))
          (else (assertion-violation 'ws-step "not a message to send" kind payload))))

  ;; taken! : WsState Any -> (Listof Action)
  (define (taken! s n)
    (unless (and (fixnum? n) (fx>=? n 0)
                 (> (ws-state-queued-count s) 0)
                 (<= n (ws-state-queued-bytes s)))
      (assertion-violation 'ws-step "not a message queued" n))
    (ws-state-queued-bytes-set! s (- (ws-state-queued-bytes s) n))
    (ws-state-queued-count-set! s (- (ws-state-queued-count s) 1))
    (if (not (ws-state-reading? s))
        (let ((acts (read-waiting! s #t '())))
          (if (and (not (eq? (ws-state-phase s) 'ended)) (not (full? s)))
              (begin
                (ws-state-reading?-set! s #t)
                (if (clock? s)
                    (begin (arm! s (cadr reading-started-ping-armed))
                           (reverse-onto acts reading-started-ping-armed))
                    (reverse-onto acts reading-started)))
              (reverse acts)))
        '()))

  ;; fits-close? : String -> Boolean
  ;; Whether the string's UTF-8 is at most 123 bytes, the most a close holds
  ;; past its code (§5.5): its characters counted by RFC 3629 §3's rows,
  ;; reading no further than the 124th byte, and encoding nothing.
  (define (fits-close? reason)
    (let ((len (string-length reason)))
      (let loop ((i 0) (n 0))
        (cond ((fx>? n 123) #f)
              ((fx=? i len) #t)
              (else
               (let ((c (char->integer (string-ref reason i))))
                 (loop (fx+ i 1)
                       (fx+ n (cond ((fx<? c #x80) 1) ((fx<? c #x800) 2) ((fx<? c #x10000) 3) (else 4))))))))))

  ;; ws-sendable-close? : Any Any -> Boolean
  ;; Whether the server may send a close of the code and reason: a code an
  ;; endpoint may send (§7.4.1, §7.4.2), and a string whose UTF-8 fits a
  ;; close, 123 bytes past its code (§5.5).
  (define (ws-sendable-close? code reason)
    (and (fixnum? code) (sendable? code) (string? reason) (fits-close? reason)))

  ;; close! : WsState Any Any -> (Listof Action)
  ;; The server's close (§7.1.2): one ws-sendable-close? allows.  Sent while
  ;; open, it arms the close deadline; once a close was sent, or the
  ;; connection has ended, it answers nothing.
  (define (close! s code reason)
    (unless (ws-sendable-close? code reason)
      (assertion-violation 'ws-step "not a close the server may send" code reason))
    (if (eq? (ws-state-phase s) 'open)
        (begin
          (ws-state-phase-set! s 'closing)
          (list (list 'write (close-frame code (string->utf8 reason))) (arm! s '(arm-deadline close))))
        '()))

  ;; read-waiting! : WsState Boolean (Listof Action) -> (Listof Action)
  ;; Reads what waits for the queue, if anything does, letting go of it
  ;; first: at a take, bounded, as the queue makes room; at the stream's end
  ;; or the close timeout, whatever the queue holds, since no more bytes
  ;; will come, so a close the client sent is read, not lost.  It is the
  ;; rest of one read at most.
  (define (read-waiting! s bounded? acts)
    (let ((bv (ws-state-waiting s)))
      (if bv
          (begin
            (ws-state-waiting-set! s #f)
            (read! s bv (ws-state-waiting-start s) (ws-state-waiting-end s) bounded? acts))
          acts)))

  ;; lost! : WsState (Listof Action) -> (Listof Action)
  ;; What waits read, then the connection ended with no close received,
  ;; unless it has ended, by what waited or before: the stream closed, and
  ;; 1006 told.
  (define (lost! s acts)
    (let ((acts (read-waiting! s #f acts)))
      (if (eq? (ws-state-phase s) 'ended)
          acts
          (end! s (list '(close-stream) (unclean)) acts))))

  ;; stream-end! : WsState Any -> (Listof Action)
  ;; The stream's end, 'eof or the errno: what waits read, then, with no
  ;; close received, the stream closed and 1006 told (§7.1.5).  Nothing is
  ;; written for it, since nothing reads it.  After the connection has
  ;; ended, it answers nothing.
  (define (stream-end! s why)
    (unless (symbol? why)
      (assertion-violation 'ws-step "not why a stream ended" why))
    (reverse (lost! s '())))

  ;; passed! : WsState -> (Listof Action)
  ;; The deadline armed has passed, and the transport has let it go.  Ping:
  ;; the client has sent nothing for the interval, and is pinged, with no
  ;; payload, and pong armed.  Pong: nothing has come since, and the
  ;; connection fails with 1011.  Close: what waits read, then, if the close
  ;; sent was not answered there either, the stream closed anyway, and 1006
  ;; told.
  (define (passed! s)
    (let ((kind (ws-state-deadline s)))
      (unless kind
        (assertion-violation 'ws-step "a deadline passed with none armed"))
      ;; The transport has let it go: recorded so, with nothing told.
      (ws-state-deadline-set! s #f)
      (case kind
        ((ping)
         (list (list 'write (frame-encode 'ping (make-bytevector 0))) (arm! s '(arm-deadline pong))))
        ((pong) (reverse (fail! s 1011 'ping-timeout '())))
        (else (reverse (lost! s '()))))))

  ;; ws-step : WsState Event -> (values WsState (Listof Action))
  ;; The connection after the event, and what the binding is to do, in
  ;; order.
  (define (ws-step s event)
    (unless (pair? event)
      (assertion-violation 'ws-step "not an event" event))
    (case (car event)
      ((bytes)
       (event-of! event 4)
       (values s (bytes! s (cadr event) (caddr event) (cadddr event))))
      ((send)
       (event-of! event 3)
       (values s (send! s (cadr event) (caddr event))))
      ((taken)
       (event-of! event 2)
       (values s (taken! s (cadr event))))
      ((close)
       (event-of! event 3)
       (values s (close! s (cadr event) (caddr event))))
      ((end)
       (event-of! event 2)
       (values s (stream-end! s (cadr event))))
      ((deadline-passed)
       (event-of! event 1)
       (values s (passed! s)))
      (else (assertion-violation 'ws-step "not an event" event)))))
