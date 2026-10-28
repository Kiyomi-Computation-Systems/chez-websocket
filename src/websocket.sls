#!r6rs
;;; (websocket) — the facade a handler imports.
;;;
;;; A handler of chez-http-server's takes a WebSocket by answering what
;;; websocket-accept returns; its procedure then reads with
;;; websocket-receive, which waits, and writes with websocket-send! and
;;; websocket-close!.  A host whose requests and responses are its own takes
;;; one through websocket-handshake, given what it reads of the request, and
;;; maps the answer onto its own: an accepted one's fields and take-over onto
;;; its 101, which the server's switch-protocols writes, and a refused one's
;;; status and fields onto its response.  A handler's settings, its
;;; subprotocols and origins, are made once with make-handshake-settings;
;;; its limits, if it gives any, with the limits' own constructors, and
;;; otherwise are the environment's, read as the program starts.  A host
;;; that reads its settings through a lookup of its own builds limits from
;;; that lookup with websocket-limits-from-environment.
;;;
;;;   websocket-accept : Request (WebSocket -> Any) [HandshakeSettings [WebsocketLimits]] -> Answer
;;;   websocket-handshake : Symbol (String -> (Listof String)) String (WebSocket -> Any)
;;;                         [HandshakeSettings [WebsocketLimits]] -> Handshake
;;;     Handshake = (U HandshakeAccepted HandshakeRefused)
;;;   handshake-accepted? : Any -> Boolean
;;;   handshake-accepted-headers : HandshakeAccepted -> (Listof (Pair String String))
;;;   handshake-accepted-take-over : HandshakeAccepted -> (Transport Bytevector -> Answer)
;;;   handshake-refused? : Any -> Boolean
;;;   handshake-refused-status : HandshakeRefused -> Nat
;;;   handshake-refused-headers : HandshakeRefused -> (Listof (Pair String String))
;;;   websocket-receive : WebSocket -> (U String Bytevector)
;;;   websocket-send! : WebSocket (U String Bytevector) -> Void
;;;   websocket-close! : WebSocket [Nat [String]] -> Void
;;;   websocket-subprotocol : WebSocket -> (U String #f)
;;;   &websocket-closed, raised by a receive or a send once the connection
;;;     has ended: its code, reason and whether it closed cleanly
;;;   environment-websocket-limits : WebsocketLimits
;;;   websocket-limits-from-environment : (String -> (U String #f)) -> WebsocketLimits
;;; and (websocket handshake)'s settings and (websocket limits)' record, each
;;; documented there.
(library (websocket)
  (export websocket-accept websocket-handshake
          handshake-accepted? handshake-accepted-headers handshake-accepted-take-over
          handshake-refused? handshake-refused-status handshake-refused-headers
          websocket-receive websocket-send! websocket-close!
          websocket-subprotocol websocket?
          &websocket-closed websocket-closed? websocket-closed-code
          websocket-closed-reason websocket-closed-clean?
          make-handshake-settings handshake-settings?
          make-websocket-limits websocket-limits? default-websocket-limits
          websocket-limits-with environment-websocket-limits
          websocket-limits-from-environment
          websocket-limits-max-message-bytes websocket-limits-max-queue
          websocket-limits-ping-interval-ms websocket-limits-ping-timeout-ms
          websocket-limits-close-timeout-ms websocket-limits-write-high-water
          websocket-limits-write-low-water websocket-limits-write-timeout-ms)
  (import (websocket private binding) (websocket handshake) (websocket limits)))
