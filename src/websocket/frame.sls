#!r6rs
;;; (websocket frame) — the frame codec (RFC 6455 §5.2): an incremental
;;; decoder of the frames a client sends, and the encoder of the server's.
;;;
;;; A frame arrives in pieces of any size, and its header can straddle two
;;; (design §4).  The decoder reads a header's bytes as they come, and
;;; answers the header once it is whole: its FIN, its kind and its payload's
;;; length, so the protocol can judge the frame before any of its payload is
;;; held.  Then it unmasks the payload as it arrives (§5.3), into a
;;; destination the caller gives it, and reads the next header once the
;;; payload is done.
;;;
;;; It refuses, with 1002, what no client may send (design §4): a reserved
;;; bit set, since no extension is ever negotiated; an unknown opcode; an
;;; unmasked frame (§5.1); a length not in its shortest form, or a 64-bit
;;; length with its top bit set (§5.2); and a control frame over 125 bytes,
;;; or not final (§5.5).  Like the UTF-8 checker, it refuses at the first
;;; byte that shows the fault: the first with which no frame a client may
;;; send begins.  A 64-bit length whose first six bytes are zero is under
;;; 65,536, so it is refused at the sixth.  A refusal is final.
;;;
;;; What a message may be is the protocol's to judge (M3): a continuation
;;; with no message begun, a message past its cap, text that is not UTF-8.
;;;
;;; A length is an exact integer: a fixnum below 2^60, and a bignum only past
;;; any cap the protocol could set.  A decoder's state is fixnums in a
;;; record, so reading allocates nothing.
;;; A payload is unmasked four bytes at a time, read as one word: a fixnum
;;; on any 64-bit Chez.  Chez 10.4.1 calls its 32-bit bytevector accessors
;;; out of line, and still a word at a time took 1.85 ns a byte, where a
;;; byte at a time took 4.6 (measured in M2.1).
;;;
;;; The encoder makes each of the server's frames whole, in a bytevector of
;;; its own: final, since each message is one frame (design §4), unmasked
;;; (§5.1), and its length in its shortest form (§5.2).  So a frame is one
;;; write, where a header and a payload apart would be two: the server's
;;; transport makes each write a libuv write of its own, copied at the call.
(library (websocket frame)
  (export make-frame-decoder frame-read-header! frame-read-payload!
          frame-fin? frame-kind frame-control? frame-length frame-left frame-refusal
          frame-encode)
  (import (rnrs))

  ;; kinds : (Vectorof (U Symbol #f))
  ;; Each opcode's kind (§5.2), or #f for one reserved: the decoder's and the
  ;; encoder's one table.
  (define kinds
    '#(continuation text binary #f #f #f #f #f close ping pong #f #f #f #f #f))

  ;; control-max : Nat
  ;; The most bytes a control frame's payload holds (§5.5), read and written.
  (define control-max 125)

  ;; A decoder.  `stage` is where in a header its next byte falls: 0 and 1
  ;; for the first two bytes, 2 and 3 for a 16-bit length's, 4 to 11 for a
  ;; 64-bit length's, and 12 to 15 for the masking key's.  `first` is the
  ;; header's first byte, `length` its payload's length (as much of it as
  ;; has been read), and `key` its masking key.  `left` is the payload's
  ;; bytes not yet unmasked, and `offset` the key's index for the next of
  ;; them (§5.3).  `refusal` is why the decoder refused, or #f.
  (define-record-type (decoder new-decoder decoder?)
    (fields (mutable stage) (mutable first) (mutable length) (immutable key)
            (mutable left) (mutable offset) (mutable refusal)))

  ;; make-frame-decoder : -> FrameDecoder
  ;; A decoder before any byte, which reads a header first.
  (define (make-frame-decoder)
    (new-decoder 0 0 0 (make-bytevector 4 0) 0 0 #f))

  ;; check-range : Symbol Any Any Any -> Unspecified
  ;; An assertion violation, naming `who`, unless bv is a bytevector and
  ;; start to end a range of it.
  (define (check-range who bv start end)
    (unless (and (bytevector? bv) (fixnum? start) (fixnum? end)
                 (fx<=? 0 start) (fx<=? start end) (fx<=? end (bytevector-length bv)))
      (assertion-violation who "not a range of a bytevector" start end)))

  ;; control? : Byte -> Boolean
  ;; Whether a header's first byte has a control frame's opcode (§5.5).
  (define (control? first)
    (fx>=? (fxand first 15) 8))

  ;; next! : FrameDecoder Nat -> #f
  ;; Moves the decoder to the header's next stage.
  (define (next! d stage)
    (decoder-stage-set! d stage)
    #f)

  ;; refuse! : FrameDecoder Symbol -> 'refused
  (define (refuse! d why)
    (decoder-refusal-set! d why)
    'refused)

  ;; header-byte! : FrameDecoder Byte -> (U #f 'header 'refused)
  ;; Reads one byte of a header: #f when the header goes on, 'header when it
  ;; is whole, and 'refused when no frame a client may send goes on with it.
  (define (header-byte! d b)
    (let ((stage (decoder-stage d)))
      (cond
        ((fx=? stage 0)
         (cond ((not (fx=? 0 (fxand b #x70))) (refuse! d 'reserved-bit))
               ((not (vector-ref kinds (fxand b 15))) (refuse! d 'unknown-opcode))
               ((and (control? b) (fx=? 0 (fxand b #x80))) (refuse! d 'control-not-final))
               (else (decoder-first-set! d b) (next! d 1))))
        ((fx=? stage 1)
         (let ((n (fxand b 127)))
           (cond ((fx=? 0 (fxand b #x80)) (refuse! d 'unmasked))
                 ((and (control? (decoder-first d)) (fx>? n control-max)) (refuse! d 'control-too-long))
                 ((fx=? n 126) (decoder-length-set! d 0) (next! d 2))
                 ((fx=? n 127) (decoder-length-set! d 0) (next! d 4))
                 (else (decoder-length-set! d n) (next! d 12)))))
        ((fx<? stage 4)                 ; a 16-bit length
         (let ((n (fx+ (fx* (decoder-length d) 256) b)))
           (decoder-length-set! d n)
           (cond ((fx=? stage 2) (next! d 3))
                 ((fx<? n 126) (refuse! d 'not-shortest))
                 (else (next! d 12)))))
        ((fx<? stage 12)                ; a 64-bit length
         (if (and (fx=? stage 4) (fx>=? b 128))
             (refuse! d 'length-top-bit)
             (let ((n (+ (* (decoder-length d) 256) b)))
               (decoder-length-set! d n)
               (if (and (fx=? stage 9) (eqv? n 0))
                   (refuse! d 'not-shortest)
                   (next! d (fx+ stage 1))))))
        (else                           ; the masking key
         (bytevector-u8-set! (decoder-key d) (fx- stage 12) b)
         (if (fx<? stage 15)
             (next! d (fx+ stage 1))
             (begin
               (decoder-stage-set! d 0)
               (decoder-left-set! d (decoder-length d))
               (decoder-offset-set! d 0)
               'header))))))

  ;; frame-read-header! : FrameDecoder Bytevector Nat Nat -> (Values (U 'more 'header 'refused) Nat)
  ;; Reads a header's bytes from start toward end, and answers what came of
  ;; them, and the index of the first byte it did not read:
  ;;   'more     the bytes ended before the header was whole;
  ;;   'header   the header is whole: frame-fin?, frame-kind and
  ;;             frame-length tell it, and its payload, if it has one, is
  ;;             read next, with frame-read-payload!;
  ;;   'refused  the byte before the index refused the frame, and
  ;;             frame-refusal says why.
  ;; Once refused, it reads nothing more.  A range outside the bytevector,
  ;; or a call while a payload is unfinished, is an assertion violation.
  (define (frame-read-header! d bv start end)
    (check-range 'frame-read-header! bv start end)
    (unless (eqv? 0 (decoder-left d))
      (assertion-violation 'frame-read-header! "a payload is unfinished" (decoder-left d)))
    (if (decoder-refusal d)
        (values 'refused start)
        (let loop ((i start))
          (if (fx=? i end)
              (values 'more i)
              (let ((what (header-byte! d (bytevector-u8-ref bv i))))
                (if what
                    (values what (fx+ i 1))
                    (loop (fx+ i 1))))))))

  ;; key-word : Bytevector Nat -> Fixnum
  ;; The masking key from its byte `offset` on, round to the start, as four
  ;; bytes read little-endian: the word that four payload bytes, read the
  ;; same way, are xored with (§5.3).
  (define (key-word key offset)
    (fxior (bytevector-u8-ref key offset)
           (fx* (bytevector-u8-ref key (fxand (fx+ offset 1) 3)) 256)
           (fx* (bytevector-u8-ref key (fxand (fx+ offset 2) 3)) 65536)
           (fx* (bytevector-u8-ref key (fxand (fx+ offset 3) 3)) 16777216)))

  ;; frame-read-payload! : FrameDecoder Bytevector Nat Nat Bytevector Nat -> Nat
  ;; Unmasks the payload's next bytes, from start toward end, into the
  ;; destination from `at` (§5.3): as many as both the bytes and the payload
  ;; have.  Answers how many.  frame-left then says how many the payload
  ;; still has; at 0, the frame is done.  A range outside the bytevector, a
  ;; destination without room for them from `at`, or a call with no payload
  ;; left, is an assertion violation, and nothing is read or written.
  (define (frame-read-payload! d bv start end dst at)
    (check-range 'frame-read-payload! bv start end)
    (let ((left (decoder-left d)))
      (when (eqv? left 0)
        (assertion-violation 'frame-read-payload! "no payload is left to read"))
      (let ((n (if (< (fx- end start) left) (fx- end start) left)))
        (unless (and (fixnum? at) (fx<=? 0 at) (fx<=? (fx+ at n) (bytevector-length dst)))
          (assertion-violation 'frame-read-payload! "no room for the payload's bytes" at n))
        (let* ((key (decoder-key d))
               (offset (decoder-offset d))
               (whole (fx- n (fxand n 3))))
          ;; Whole words of four bytes first: four bytes bring the key back
          ;; to `offset`, so each is xored with the same word.
          (unless (fx=? whole 0)
            (let ((word (key-word key offset)))
              (do ((i 0 (fx+ i 4)))
                  ((fx=? i whole))
                (bytevector-u32-set! dst (fx+ at i)
                  (fxxor (bytevector-u32-ref bv (fx+ start i) (endianness little)) word)
                  (endianness little)))))
          ;; Then the bytes left, one at a time.
          (do ((i whole (fx+ i 1)))
              ((fx=? i n))
            (bytevector-u8-set! dst (fx+ at i)
              (fxxor (bytevector-u8-ref bv (fx+ start i))
                     (bytevector-u8-ref key (fxand (fx+ offset i) 3)))))
          (decoder-offset-set! d (fxand (fx+ offset n) 3))
          (decoder-left-set! d (- left n))
          n))))

  ;; frame-fin? : FrameDecoder -> Boolean
  ;; Whether the frame whose header was answered last ends its message
  ;; (§5.2's FIN).  This and the next three hold from the header's answer
  ;; until the next header is begun.
  (define (frame-fin? d)
    (fx=? 128 (fxand (decoder-first d) 128)))

  ;; frame-kind : FrameDecoder -> (U 'continuation 'text 'binary 'close 'ping 'pong)
  ;; The kind of the frame whose header was answered last, by its opcode.
  (define (frame-kind d)
    (vector-ref kinds (fxand (decoder-first d) 15)))

  ;; frame-control? : FrameDecoder -> Boolean
  ;; Whether the frame whose header was answered last is a control frame: a
  ;; close, a ping or a pong (§5.5).
  (define (frame-control? d)
    (control? (decoder-first d)))

  ;; frame-length : FrameDecoder -> Nat
  ;; The payload length of the frame whose header was answered last.
  (define (frame-length d)
    (decoder-length d))

  ;; frame-left : FrameDecoder -> Nat
  ;; How many of that frame's payload bytes are still to be read.
  (define (frame-left d)
    (decoder-left d))

  ;; frame-refusal : FrameDecoder -> (U #f (List 1002 Symbol))
  ;; The close code and the reason the decoder refused, or #f: reserved-bit,
  ;; unknown-opcode, control-not-final, unmasked, control-too-long,
  ;; not-shortest or length-top-bit.
  (define (frame-refusal d)
    (let ((why (decoder-refusal d)))
      (and why (list 1002 why))))

  ;; opcode : Any -> (U Byte #f)
  ;; The opcode of a kind of frame the server sends, as `kinds` has it, or
  ;; #f.  The search starts past 0, a continuation's: each of the server's
  ;; messages is one frame.
  (define (opcode kind)
    (and (symbol? kind)
         (let find ((op 1))
           (cond ((fx=? op (vector-length kinds)) #f)
                 ((eq? (vector-ref kinds op) kind) op)
                 (else (find (fx+ op 1)))))))

  ;; frame-encode : (U 'text 'binary 'close 'ping 'pong) Bytevector [Nat Nat] -> Bytevector
  ;; The server's frame of that kind, its payload the bytevector's bytes
  ;; from start to end, the whole bytevector by default: final, unmasked
  ;; (§5.1), and its length in its shortest form (§5.2).  The bytevector is
  ;; left as it was.  A kind not one of these five, a control frame's
  ;; payload over 125 bytes (§5.5), a close's of one byte (§5.5.1: a close's
  ;; body begins with its two-byte code), or anything but a range of a
  ;; bytevector, is an assertion violation.  What else a payload holds is
  ;; the protocol's to make: text in UTF-8, or a close's code and reason.
  (define frame-encode
    (case-lambda
      ((kind bv)
       (frame-encode kind bv 0 (if (bytevector? bv) (bytevector-length bv) 0)))
      ((kind bv start end)
       (check-range 'frame-encode bv start end)
       (let ((op (opcode kind))
             (n (fx- end start)))
         (unless op
           (assertion-violation 'frame-encode "not a kind of frame the server sends" kind))
         (when (and (control? op) (fx>? n control-max))
           (assertion-violation 'frame-encode "a control frame's payload is over 125 bytes" kind n))
         (when (and (eq? kind 'close) (fx=? n 1))
           (assertion-violation 'frame-encode "a close's payload begins with a two-byte code" n))
         ;; The length's form, decided once (§5.2): the second byte's seven
         ;; bits, and how many bytes of length follow them.
         (let*-values (((code k) (cond ((fx<? n 126) (values n 0))
                                       ((fx<? n 65536) (values 126 2))
                                       (else (values 127 8))))
                       ((h) (fx+ 2 k)))
           (let ((out (make-bytevector (fx+ h n))))
             (bytevector-u8-set! out 0 (fxior 128 op))
             (bytevector-u8-set! out 1 code)
             (unless (fx=? k 0)
               (bytevector-uint-set! out 2 n (endianness big) k))
             (bytevector-copy! bv start out h n)
             out)))))))
