#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

main:
    ; Inisialisasi stack pointer
    LDI   R16, lo8(RAMEND)
    OUT   SPL, R16
    LDI   R16, hi8(RAMEND)
    OUT   SPH, R16

    ; Inisialisasi serial
    RCALL init_serial

    ; Set PB5 (pin 13) sebagai output
    IN    R16, DDRB
    ORI   R16, (1<<5)
    OUT   DDRB, R16

    ; Jeda sejenak untuk memastikan serial siap
    RCALL delay_100ms

    ; FLUSH serial buffer terlebih dahulu
flush_serial:
    LDS   R16, UCSR0A
    SBRC  R16, RXC0
    LDS   R16, UDR0
    LDS   R16, UCSR0A
    SBRC  R16, RXC0
    RJMP  flush_serial

    ; Kirim pesan awal sebelum masuk ke main loop - ini CRUCIAL
    LDI   R30, lo8(msg_scan)
    LDI   R31, hi8(msg_scan)
    RCALL print_string_flush

    ; Tunggu transmisi selesai - pastikan pesan terlihat
    RCALL delay_100ms

main_loop:
    ; Reset buffer untuk input RFID
    LDI   R20, 0           ; count = 0
    LDI   R28, lo8(idbuf)  ; YL = idbuf (register Y low)
    LDI   R29, hi8(idbuf)  ; YH = idbuf (register Y high)

read_loop:
    ; Tunggu data serial masuk
wait_rx:
    LDS   R16, UCSR0A
    SBRS  R16, RXC0
    RJMP  wait_rx

    LDS   R16, UDR0
    ST    Y+, R16          ; simpan ke idbuf
    INC   R20              ; count++

    CPI   R20, 12
    BRLO  read_loop

    ; Bandingkan dengan validid
    LDI   R28, lo8(idbuf)  ; YL = idbuf (reset Y ke awal idbuf)
    LDI   R29, hi8(idbuf)  ; YH = idbuf
    LDI   R30, lo8(validid) ; ZL = validid
    LDI   R31, hi8(validid) ; ZH = validid
    LDI   R25, 12          ; cmp = 12

cmp_loop:
    LD    R16, Y+
    LPM   R17, Z+
    CP    R16, R17
    BRNE  not_valid
    DEC   R25
    BRNE  cmp_loop

    ; Jika valid
    IN    R16, PORTB
    ORI   R16, (1<<5)
    OUT   PORTB, R16       ; digitalWrite(13, HIGH)
    LDI   R30, lo8(msg_valid)
    LDI   R31, hi8(msg_valid)
    RCALL print_string_flush
    RJMP  delay_and_restart

not_valid:
    IN    R16, PORTB
    ANDI  R16, ~(1<<5)
    OUT   PORTB, R16       ; digitalWrite(13, LOW)
    LDI   R30, lo8(msg_invalid)
    LDI   R31, hi8(msg_invalid)
    RCALL print_string_flush

delay_and_restart:
    RCALL delay_500ms
    
    ; Tampilkan kembali pesan scan sebelum membaca RFID berikutnya
    LDI   R30, lo8(msg_scan)
    LDI   R31, hi8(msg_scan)
    RCALL print_string_flush
    
    ; Tunggu transmisi selesai
    RCALL delay_100ms
    
    RJMP  main_loop

;--------------------------
; Inisialisasi serial dengan baudrate 9600
init_serial:
    ; Clear UCSR0A
    LDI   R24, 0
    STS   UCSR0A, R24
    
    ; Set baud rate 9600 pada 16MHz clock
    LDI   R24, 0
    STS   UBRR0H, R24
    LDI   R24, 103
    STS   UBRR0L, R24
    
    ; Enable RX dan TX
    LDI   R24, (1<<RXEN0) | (1<<TXEN0)
    STS   UCSR0B, R24
    
    ; Set frame format: 8 data bits, 1 stop bit, no parity
    LDI   R24, (1<<UCSZ01) | (1<<UCSZ00)
    STS   UCSR0C, R24
    
    RET

;--------------------------
; Print string dan pastikan buffer sudah dikirim
print_string_flush:
    LPM   R18, Z+          ; Load karakter dari program memory
    CPI   R18, 0           ; Bandingkan dengan 0 (null terminator)
    BREQ  print_done       ; Jika sama, selesai

    ; Tunggu buffer TX kosong
wait_tx_empty:
    LDS   R16, UCSR0A
    SBRS  R16, UDRE0       ; Skip if UDRE0 (data register empty) is set
    RJMP  wait_tx_empty

    ; Kirim karakter
    STS   UDR0, R18
    
    RJMP  print_string_flush
    
print_done:
    ; Tunggu transmisi selesai
wait_tx_complete:
    LDS   R16, UCSR0A
    SBRS  R16, UDRE0       ; Tunggu sampai UDR0 kosong
    RJMP  wait_tx_complete
    
    RET

;--------------------------
; Delay ~500ms (kasar)
delay_500ms:
    LDI   R19, 100
d1: LDI   R20, 200
d2: LDI   R21, 200
d3: DEC   R21
    BRNE  d3
    DEC   R20
    BRNE  d2
    DEC   R19
    BRNE  d1
    RET

;--------------------------
; Delay ~100ms (kasar)
delay_100ms:
    LDI   R19, 20
d4: LDI   R20, 200
d5: LDI   R21, 200
d6: DEC   R21
    BRNE  d6
    DEC   R20
    BRNE  d5
    DEC   R19
    BRNE  d4
    RET

;--------------------------
; Data

idbuf:     .byte 12
validid:   .ascii "AB123456789A"
msg_scan:    .asciz "Please scan your RFID TAG\n\r"
msg_valid:   .asciz "Valid TAG\n\r"
msg_invalid: .asciz "Invalid TAG\n\r"