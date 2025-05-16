#define __SFR_OFFSET 0x00
#include "avr/io.h"

; Definisi konstanta untuk servo
.equ MIN_PULSE, 3000     ; 544 us / 0.5 us per tick (posisi tutup)
.equ MAX_PULSE, 1000     ; 2400 us / 0.5 us per tick (posisi buka)
.equ TOP_COUNT, 39999    ; 20 ms → 50Hz PWM
.equ DELAY_COUNT, 50     ; Delay untuk pergerakan servo

.global main

.section .text

main:
    ; Inisialisasi stack pointer
    LDI   R16, lo8(RAMEND)
    OUT   SPL, R16
    LDI   R16, hi8(RAMEND)
    OUT   SPH, R16

    ; Inisialisasi serial
    RCALL init_serial
    
    ; Set PC4 (A4) sebagai output (LED kuning - valid)
    IN    R16, DDRC
    ORI   R16, (1<<4)
    OUT   DDRC, R16
    
    ; Set PC3 (A3) sebagai output (LED merah - invalid)
    IN    R16, DDRC
    ORI   R16, (1<<3)
    OUT   DDRC, R16
    
    ; Set PC2 (A2) sebagai output (buzzer)
    IN    R16, DDRC
    ORI   R16, (1<<2)
    OUT   DDRC, R16
    
    ; Pastikan semua LED dan buzzer dalam keadaan mati di awal
    IN    R16, PORTC
    ANDI  R16, ~((1<<4) | (1<<3) | (1<<2))
    OUT   PORTC, R16
    
    ; Inisialisasi Servo
    ; Set PB1 (OC1A) sebagai output untuk servo
    SBI   DDRB, PB1
    
    ; Timer1 → Fast PWM mode (WGM13:0 = 14)
    LDI   R16, (1<<WGM11)
    STS   TCCR1A, R16
    LDI   R16, (1<<WGM13)|(1<<WGM12)|(1<<CS11)   ; prescaler = 8
    STS   TCCR1B, R16

    ; Non-inverting mode untuk OC1A
    LDS   R16, TCCR1A
    ORI   R16, (1<<COM1A1)
    STS   TCCR1A, R16

    ; Set ICR1 = 20ms (TOP)
    LDI   R16, hi8(TOP_COUNT)
    STS   ICR1H, R16
    LDI   R16, lo8(TOP_COUNT)
    STS   ICR1L, R16

    ; Mulai dengan pintu tertutup
    LDI   R24, hi8(MIN_PULSE)
    LDI   R25, lo8(MIN_PULSE)
    RCALL SET_OCR1A
    
    ; Inisialisasi variabel state
    CLR   R23            ; r23 = state pintu (0 = tertutup, 1 = terbuka)

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

    ; Kirim pesan awal sebelum masuk ke main loop
    LDI   R30, lo8(msg_scan)
    LDI   R31, hi8(msg_scan)
    RCALL print_string_flush

    ; Tunggu transmisi selesai
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
    ; Nyalakan LED kuning di PC4 (A4)
    IN    R16, PORTC
    ORI   R16, (1<<4)
    OUT   PORTC, R16
    
    ; Pastikan LED merah mati
    IN    R16, PORTC
    ANDI  R16, ~(1<<3)
    OUT   PORTC, R16
    
    ; Bunyikan buzzer untuk valid tag (sekali pendek)
    RCALL beep_valid
    
    LDI   R30, lo8(msg_valid)
    LDI   R31, hi8(msg_valid)
    RCALL print_string_flush
    
    ; Cek state pintu dan buka jika tertutup
    TST   R23
    BRNE  pintu_sudah_terbuka  ; Jika pintu sudah terbuka (r23=1), skip
    
    ; Buka pintu dengan servo
    LDI   R30, lo8(msg_open)
    LDI   R31, hi8(msg_open)
    RCALL print_string_flush
    
    RCALL OPEN_THE_DOOR
    
    RJMP  delay_and_restart

pintu_sudah_terbuka:
    LDI   R30, lo8(msg_already_open)
    LDI   R31, hi8(msg_already_open)
    RCALL print_string_flush
    RJMP  delay_and_restart

not_valid:
    ; Nyalakan LED merah di PC3 (A3)
    IN    R16, PORTC
    ORI   R16, (1<<3)
    OUT   PORTC, R16
    
    ; Pastikan LED kuning mati
    IN    R16, PORTC
    ANDI  R16, ~(1<<4)
    OUT   PORTC, R16
    
    ; Bunyikan buzzer untuk invalid tag (beep panjang)
    RCALL beep_invalid
    
    LDI   R30, lo8(msg_invalid)
    LDI   R31, hi8(msg_invalid)
    RCALL print_string_flush
    
    ; Jika pintu terbuka, tutup 
    TST   R23
    BREQ  delay_and_restart  ; Jika pintu tertutup (r23=0), skip
    
    ; Tutup pintu dengan servo
    LDI   R30, lo8(msg_close)
    LDI   R31, hi8(msg_close)
    RCALL print_string_flush
    
    RCALL CLOSE_THE_DOOR

delay_and_restart:
    RCALL delay_500ms
    
    ; Matikan semua LED dan buzzer sebelum scan berikutnya
    IN    R16, PORTC
    ANDI  R16, ~((1<<4) | (1<<3) | (1<<2))
    OUT   PORTC, R16
    
    ; Tampilkan kembali pesan scan sebelum membaca RFID berikutnya
    LDI   R30, lo8(msg_scan)
    LDI   R31, hi8(msg_scan)
    RCALL print_string_flush
    
    ; Tunggu transmisi selesai
    RCALL delay_100ms
    
    RJMP  main_loop

;--------------------------
; Fungsi servo dari kode kedua
;--------------------------
OPEN_THE_DOOR:
    ; Update state menjadi terbuka
    LDI   R23, 1
    
    ; Gerakkan servo ke posisi terbuka dalam beberapa langkah
    LDI   R24, hi8(MIN_PULSE)
    LDI   R25, lo8(MIN_PULSE)
    
OPEN_LOOP:
    ; Set posisi servo
    RCALL SET_OCR1A
    RCALL DELAY_MS
    
    ; Tambah posisi untuk langkah berikutnya
    ADIW  R24, 50    ; Langkah lebih besar untuk gerakan yang lebih cepat
    
    ; Periksa apakah sudah mencapai posisi maksimum
    CPI   R25, lo8(MAX_PULSE)
    LDI   R16, hi8(MAX_PULSE)
    CPC   R24, R16
    BRLO  OPEN_LOOP    ; Jika belum maksimum, lanjutkan
    
    ; Pastikan posisi akhir tepat di MAX_PULSE
    LDI   R24, hi8(MAX_PULSE)
    LDI   R25, lo8(MAX_PULSE)
    RCALL SET_OCR1A
    
    RET

CLOSE_THE_DOOR:
    ; Update state menjadi tertutup
    CLR   R23
    
    ; Gerakkan servo ke posisi tertutup dalam beberapa langkah
    LDI   R24, hi8(MAX_PULSE)
    LDI   R25, lo8(MAX_PULSE)
    
CLOSE_LOOP:
    ; Set posisi servo
    RCALL SET_OCR1A
    RCALL DELAY_MS
    
    ; Kurangi posisi untuk langkah berikutnya
    SBIW  R24, 50    ; Langkah lebih besar untuk gerakan yang lebih cepat
    
    ; Periksa apakah sudah mencapai posisi minimum
    CPI   R25, lo8(MIN_PULSE)
    LDI   R16, hi8(MIN_PULSE)
    CPC   R24, R16
    BRSH  CLOSE_LOOP    ; Jika belum minimum, lanjutkan
    
    ; Pastikan posisi akhir tepat di MIN_PULSE
    LDI   R24, hi8(MIN_PULSE)
    LDI   R25, lo8(MIN_PULSE)
    RCALL SET_OCR1A
    
    RET

; ----------------------------
; Subrutin: SET_OCR1A
; ----------------------------
SET_OCR1A:
    STS   OCR1AH, R24
    STS   OCR1AL, R25
    RET

; ----------------------------
; Subrutin: DELAY_MS
; Delay sederhana untuk pergerakan servo
; ----------------------------
DELAY_MS:
    LDI   R18, DELAY_COUNT
DELAY_LOOP1:
    LDI   R19, 255
DELAY_LOOP2:
    NOP
    NOP
    DEC   R19
    BRNE  DELAY_LOOP2
    DEC   R18
    BRNE  DELAY_LOOP1
    RET

;--------------------------
; Beep untuk tag valid (beep sekali pendek)
beep_valid:
    ; Nyalakan buzzer
    IN    R16, PORTC
    ORI   R16, (1<<2)
    OUT   PORTC, R16
    
    ; Delay pendek
    LDI   R19, 10
bv1: LDI   R20, 200
bv2: LDI   R21, 50
bv3: DEC   R21
    BRNE  bv3
    DEC   R20
    BRNE  bv2
    DEC   R19
    BRNE  bv1
    
    ; Matikan buzzer
    IN    R16, PORTC
    ANDI  R16, ~(1<<2)
    OUT   PORTC, R16
    
    RET

;--------------------------
; Beep untuk tag invalid (beep panjang)
beep_invalid:
    ; Nyalakan buzzer
    IN    R16, PORTC
    ORI   R16, (1<<2)
    OUT   PORTC, R16
    
    ; Delay panjang
    LDI   R19, 30
bi1: LDI   R20, 200
bi2: LDI   R21, 100
bi3: DEC   R21
    BRNE  bi3
    DEC   R20
    BRNE  bi2
    DEC   R19
    BRNE  bi1
    
    ; Matikan buzzer
    IN    R16, PORTC
    ANDI  R16, ~(1<<2)
    OUT   PORTC, R16
    
    RET

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
msg_open:    .asciz "Opening door...\n\r"
msg_close:   .asciz "Closing door...\n\r"
msg_already_open: .asciz "Door already open\n\r"