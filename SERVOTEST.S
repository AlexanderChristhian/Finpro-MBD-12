#define __SFR_OFFSET 0x00
#include <avr/io.h>

; Definisi konstanta
.equ MIN_PULSE, 3000     ; 544 us / 0.5 us per tick 
.equ MAX_PULSE, 1000     ; 2400 us / 0.5 us per tick
.equ TOP_COUNT, 39999    ; 20 ms → 50Hz PWM
.equ DELAY_COUNT, 50    ; Delay untuk debouncing

.global main

.section .text

main:
    ; Setup stack pointer
    ldi r16, hi8(RAMEND)
    out _SFR_IO_ADDR(SPH), r16
    ldi r16, lo8(RAMEND)
    out _SFR_IO_ADDR(SPL), r16

    ; Set PB1 (OC1A) sebagai output
    sbi _SFR_IO_ADDR(DDRB), PB1

    ; Set PD7 sebagai input
    cbi _SFR_IO_ADDR(DDRD), PD7
    ; Set pull-up resistor untuk PD7
    sbi _SFR_IO_ADDR(PORTD), PD7

    ; Timer1 → Fast PWM mode (WGM13:0 = 14)
    ldi r16, (1<<WGM11)
    sts _SFR_MEM_ADDR(TCCR1A), r16
    ldi r16, (1<<WGM13)|(1<<WGM12)|(1<<CS11)   ; prescaler = 8
    sts _SFR_MEM_ADDR(TCCR1B), r16

    ; Non-inverting mode untuk OC1A
    lds r16, _SFR_MEM_ADDR(TCCR1A)
    ori r16, (1<<COM1A1)
    sts _SFR_MEM_ADDR(TCCR1A), r16

    ; Set ICR1 = 20ms (TOP)
    ldi r16, hi8(TOP_COUNT)
    sts _SFR_MEM_ADDR(ICR1H), r16
    ldi r16, lo8(TOP_COUNT)
    sts _SFR_MEM_ADDR(ICR1L), r16

    ; Mulai dengan pintu tertutup
    ldi r24, hi8(MIN_PULSE)
    ldi r25, lo8(MIN_PULSE)
    rcall SET_OCR1A
    
    ; Inisialisasi variabel state dan flag
    clr r23            ; r23 = state pintu (0 = tertutup, 1 = terbuka)
    clr r22            ; r22 = flag tombol (0 = tidak ditekan, 1 = ditekan)

MAIN_LOOP:
    ; Periksa status tombol (logika rendah ketika ditekan karena pull-up)
    sbis _SFR_IO_ADDR(PIND), PD7    ; Lewati jika bit high (tombol tidak ditekan)
    rjmp BUTTON_PRESSED
    rjmp BUTTON_RELEASED

BUTTON_PRESSED:
    ; Cek apakah tombol sudah ditekan sebelumnya untuk menghindari multiple trigger
    tst r22
    brne MAIN_LOOP    ; Jika sudah ditekan (r22=1), kembali ke loop utama
    
    ; Set flag tombol ditekan
    ldi r22, 1
    
    ; Toggle state pintu
    tst r23
    breq OPEN_THE_DOOR   ; Jika pintu tertutup (r23=0), buka pintu
    rjmp CLOSE_THE_DOOR  ; Jika pintu terbuka (r23=1), tutup pintu

BUTTON_RELEASED:
    ; Reset flag tombol ketika tombol dilepas
    clr r22
    rjmp MAIN_LOOP

OPEN_THE_DOOR:
    ; Update state menjadi terbuka
    ldi r23, 1
    
    ; Gerakkan servo ke posisi terbuka dalam beberapa langkah
    ldi r24, hi8(MIN_PULSE)
    ldi r25, lo8(MIN_PULSE)
    
OPEN_LOOP:
    ; Set posisi servo
    rcall SET_OCR1A
    rcall DELAY_MS
    
    ; Tambah posisi untuk langkah berikutnya
    adiw r24, 50    ; Langkah lebih besar untuk gerakan yang lebih cepat
    
    ; Periksa apakah sudah mencapai posisi maksimum
    cpi r25, lo8(MAX_PULSE)
    ldi r16, hi8(MAX_PULSE)
    cpc r24, r16
    brlo OPEN_LOOP    ; Jika belum maksimum, lanjutkan
    
    ; Pastikan posisi akhir tepat di MAX_PULSE
    ldi r24, hi8(MAX_PULSE)
    ldi r25, lo8(MAX_PULSE)
    rcall SET_OCR1A
    
    ; Kembali ke loop utama
    rjmp MAIN_LOOP

CLOSE_THE_DOOR:
    ; Update state menjadi tertutup
    clr r23
    
    ; Gerakkan servo ke posisi tertutup dalam beberapa langkah
    ldi r24, hi8(MAX_PULSE)
    ldi r25, lo8(MAX_PULSE)
    
CLOSE_LOOP:
    ; Set posisi servo
    rcall SET_OCR1A
    rcall DELAY_MS
    
    ; Kurangi posisi untuk langkah berikutnya
    sbiw r24, 50    ; Langkah lebih besar untuk gerakan yang lebih cepat
    
    ; Periksa apakah sudah mencapai posisi minimum
    cpi r25, lo8(MIN_PULSE)
    ldi r16, hi8(MIN_PULSE)
    cpc r24, r16
    brsh CLOSE_LOOP    ; Jika belum minimum, lanjutkan
    
    ; Pastikan posisi akhir tepat di MIN_PULSE
    ldi r24, hi8(MIN_PULSE)
    ldi r25, lo8(MIN_PULSE)
    rcall SET_OCR1A
    
    ; Kembali ke loop utama
    rjmp MAIN_LOOP

; ----------------------------
; Subrutin: SET_OCR1A
; ----------------------------
SET_OCR1A:
    sts _SFR_MEM_ADDR(OCR1AH), r24
    sts _SFR_MEM_ADDR(OCR1AL), r25
    ret

; ----------------------------
; Subrutin: DELAY_MS
; Delay sederhana
; ----------------------------
DELAY_MS:
    ldi r18, DELAY_COUNT
DELAY_LOOP1:
    ldi r19, 255
DELAY_LOOP2:
    nop
    nop
    dec r19
    brne DELAY_LOOP2
    dec r18
    brne DELAY_LOOP1
    ret