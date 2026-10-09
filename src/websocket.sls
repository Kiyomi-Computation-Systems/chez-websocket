#!r6rs
;;; (websocket) — the facade a handler imports (design §1, §2).
;;;
;;; A handler of chez-http-server's takes a WebSocket by answering what
;;; websocket-accept returns; its procedure then reads with
;;; websocket-receive, which waits, and writes with websocket-send! and
;;; websocket-close!.  A handler's settings, its subprotocols and origins,
;;; are made once with make-handshake-settings; its limits, if it gives any,
;;; with the limits' own constructors, and otherwise are the environment's,
;;; read as the program starts.
;;;
;;;   websocket-accept : Request (WebSocket -> Any) [HandshakeSettings [WebsocketLimits]] -> Answer
;;;   websocket-receive : WebSocket -> (U String Bytevector)
;;;   websocket-send! : WebSocket (U String Bytevector) -> Void
;;;   websocket-close! : WebSocket [Nat [String]] -> Void
;;;   websocket-subprotocol : WebSocket -> (U String #f)
;;;   &websocket-closed, raised by a receive or a send once the connection
;;;     has ended: its code, reason and whether it closed cleanly
;;;   environment-websocket-limits : WebsocketLimits
;;; and (websocket handshake)'s settings and (websocket limits)' record, each
;;; documented there.
(library (websocket)
  (export websocket-accept websocket-receive websocket-send! websocket-close!
          websocket-subprotocol websocket?
          &websocket-closed websocket-closed? websocket-closed-code
          websocket-closed-reason websocket-closed-clean?
          make-handshake-settings handshake-settings?
          make-websocket-limits websocket-limits? default-websocket-limits
          websocket-limits-with environment-websocket-limits
          websocket-limits-max-message-bytes websocket-limits-max-queue
          websocket-limits-ping-interval-ms websocket-limits-ping-timeout-ms
          websocket-limits-close-timeout-ms websocket-limits-write-high-water
          websocket-limits-write-low-water websocket-limits-write-timeout-ms)
  (import (websocket private binding) (websocket handshake) (websocket limits)))
