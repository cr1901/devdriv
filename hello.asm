; Approximate DOS Crash Count when developing this: 28 times.

struc header
  next: resd 1
  attr: resw 1
  strat: resw 1
  intr: resw 1
  name: resb 8
endstruc

struc drivereq
  .len: resb 1
  .unit: resb 1
  .cmd: resb 1
  .status: resw 1
  .dosq: resd 1
  .devq: resd 1
endstruc

struc wrreq
  .hdr: resb drivereq_size
  .desc: resb 1
  .xferaddr: resd 1
  .count: resw 1
  .start: resw 1
endstruc

struc initreq
  .hdr: resb drivereq_size
  .numunits: resb 1
  .brkaddr: resd 1
  .bpbaddr: resd 1
endstruc

; Status return bits- high
%define STATUS_ERROR      (1 << 15)
%define STATUS_BUSY       (1 << 9)
%define STATUS_DONE       (1 << 8)

; Error codes (Status return bits- low)
%define WRITE_PROTECT     0
%define UNKNOWN_UNIT      1
%define DRIVE_NOT_READY   2
%define UNKNOWN_COMMAND   3
%define CRC_ERROR         4
%define BAD_DRIVE_REQ     5
%define SEEK_ERROR        6
%define UNKNOWN_MEDIA     7
%define SECTOR_NOT_FOUND  8
%define OUT_OF_PAPER      9
%define WRITE_FAULT     0xA
%define READ_FAULT      0xB
%define GENERAL_FAILURE 0xC

hdr:
istruc header
  at next, dd -1
  at attr, dw 0x8000
  at strat, dw strategy
  at intr, dw interrupt
  at name, db 'HELLO   '
iend

; Driver data
packet_ptr dd 0
msg db 'HELLO, WORLD!!', 0xD, 0xA, 26, 0 ; Use 26 so fake EOF is sent
                                         ; for TYPE command.
msg_end:
msg_ptr dw msg

lookahead_char: db 0
got_lookahead: db 0 ; Many MS-DOS drivers use "0" as a "buffer is empty" value,
                    ; and null values discarded. This works fine for cooked,
                    ; i.e. ASCII mode buffers, but might as well use an extra
                    ; byte as an "option" type.

strategy:
  mov cs:[packet_ptr], bx
  mov cs:[packet_ptr+2], es
  retf

interrupt:
  push ax
  push cx
  push dx
  push bx
  push si
  push di
  push bp
  push ds
  push es

  les di, cs:[packet_ptr]
  mov si, es:[di + drivereq.cmd]
  cmp si, 11
  ja .bad_cmd

  shl si, 1
  jmp [.fntab + si]

.bad_cmd:
  mov word es:[di + drivereq.status], STATUS_DONE | UNKNOWN_COMMAND

.end:
  pop es
  pop ds
  pop bp
  pop di
  pop si
  pop bx
  pop dx
  pop cx
  pop ax
  retf

.fntab:
  dw init   ;  0      INIT
  dw .exit  ;  1      MEDIA CHECK (Block only, NOP for character)
  dw .exit  ;  2      BUILD BPB      "    "     "    "   "
  dw .exit  ;  3      IOCTL INPUT (Only called if device has IOCTL)
  dw read   ;  4      INPUT (read)
  dw .exit  ;  5      NON-DESTRUCTIVE INPUT NO WAIT (Char devs only)
  dw .exit  ;  6      INPUT STATUS                    "     "    "
  dw .exit  ;  7      INPUT FLUSH                     "     "    "
  dw .exit  ;  8      OUTPUT (write)
  dw .exit  ;  9      OUTPUT (Write) with verify
  dw .exit  ; 10      OUTPUT STATUS                   "     "    "
  dw .exit  ; 11      OUTPUT FLUSH                    "     "    "
  dw .exit  ; 12      IOCTL OUTPUT (Only called if device has IOCTL)

.exit:
  mov word es:[di + drivereq.status], STATUS_DONE
  jmp interrupt.end

read:
  push es
  pop ds
  mov si, di
  les di, [si + wrreq.xferaddr]
  mov cx, [si + wrreq.count]

  ; call get_buf ; If buffered char exists, take it now.
  ; je .nothing
  ; dec cx ; One less char to grab from device
  ; stosb
.nothing:
  mov bx, si
  call read_msg
;.done:
;  call clear_buf ; Buffer should only be filled during non-destructive read.

  mov [bx + wrreq.count], ax

  mov di, si ; Make sure ES:DI points at the right place to set status.
  push ds
  pop es
  jmp interrupt.exit

; Helper Routines

; ES:DI- Buf destination (buf source implicit).
; CX- Number of characters
;
; Return:
; AX- Chars read
;
; CX zero, DX, SI, DI trashed
read_msg:
  mov dx, ds
  mov ax, cs
  mov ds, ax

  mov ax, cx ; Xfer will succeed, so save the count for AX.
  mov si, [msg_ptr] ; Prepare device source buffer.

.next:
  cmp si, msg_end ; The HELLO char device infinitely streams "HELLO, WORLD!!\n,^Z"
  jb .no_wrap     ; over and over. When we get to the end of the message,
  mov si, msg     ; wrap around and grab more chars.
.no_wrap:
  movsb
  loop .next

  mov [msg_ptr], si ; Restore DS
  mov ds, ax
  ret

; Returns:
; ZF == 0, there was a char in buffer
; AL: char read
; Assumes: CS == DS
get_buf:
  cmp byte [got_lookahead], 0
  mov al, [lookahead_char]
  ret

; Assumes: CS == DS
clear_buf:
  mov byte [got_lookahead], 0
  ret

; Init data does not need to be kept, so it goes last.
res_end:
init:
  push cs
  pop ds
  mov dx, install_msg
  mov ah, 0x09
  int 0x21
  mov word es:[di + initreq.brkaddr], res_end
  mov word es:[di + initreq.brkaddr + 2], cs
  jmp interrupt.exit

install_msg db 'Hello World driver installed.', 0xD, 0xA, '$'
