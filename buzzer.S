#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

main:
    ; Inisialisasi stack pointer
    ldi r16, hi8(RAMEND)
    out SPH, r16
    ldi r16, lo8(RAMEND)
    out SPL, r16

    ; Set LED pins and buzzer as output
    sbi DDRC, 4     ; PC4 = green LED
    sbi DDRC, 3     ; PC3 = red LED
    sbi DDRC, 2     ; PC2 = buzzer

    ; Set PD2 as input (button)
    cbi DDRD, 2     ; PD2 input
    sbi PORTD, 2    ; Enable pull-up resistor on PD2

    ; Init: all off
    cbi PORTC, 2    ; Buzzer off
    cbi PORTC, 3    ; Red LED off
    cbi PORTC, 4    ; Green LED off

    ; Clear counter (r20) to track button presses (0 = green LED, 1 = red LED + buzzer, 2 = all off)
    ldi r20, 0

main_loop:
    ; Wait for button press (active low)
wait_press:
    sbic PIND, 2      ; If PD2 high (not pressed), skip next
    rjmp wait_press   ; Loop until pressed

    rcall debounce

    ; Increment counter (r20)
    inc r20

    ; Check counter and act accordingly
    cpi r20, 1
    breq one_press    ; First press: Green LED on
    cpi r20, 2
    breq two_press    ; Second press: Red LED + buzzer
    cpi r20, 3
    breq reset_all    ; Third press: Turn everything off, reset counter

    ; Reset counter after 3
    ldi r20, 0
    rjmp main_loop

one_press:
    ; Green LED on, Red LED off, Buzzer off
    sbi PORTC, 4     ; Green LED on
    cbi PORTC, 3     ; Red LED off
    cbi PORTC, 2     ; Buzzer off
    rjmp wait_release

two_press:
    ; Red LED on, Green LED off, Buzzer on (sound)
    sbi PORTC, 3     ; Red LED on
    cbi PORTC, 4     ; Green LED off
    sbi PORTC, 2     ; Buzzer on
    rcall buzz_sound ; Call buzzer sound function
    rjmp wait_release

reset_all:
    ; Turn off everything: Green LED, Red LED, and Buzzer
    cbi PORTC, 4     ; Green LED off
    cbi PORTC, 3     ; Red LED off
    cbi PORTC, 2     ; Buzzer off
    ldi r20, 0       ; Reset counter
    rjmp wait_release

wait_release:
    ; Wait for button release (debounce again)
wait_rel:
    sbis PIND, 2      ; Skip if PD2 is low (still pressed)
    rjmp wait_rel     ; Loop until released
    rcall debounce
    rjmp main_loop

; ~10ms debounce delay
debounce:
    ldi r18, 20
outer:
    ldi r19, 255
inner:
    dec r19
    brne inner
    dec r18
    brne outer
    ret

; Buzzer sound function for red LED
buzz_sound:
    ; Toggle PC2 → make frequency sound
    ldi r18, 100    ; Adjust frequency duration (longer is better)
buzz_loop:
    sbi PORTC, 2     ; Turn on buzzer
    rcall delay
    cbi PORTC, 2     ; Turn off buzzer
    rcall delay
    dec r18          ; Decrease loop counter
    brne buzz_loop   ; Continue if counter > 0
    ret

; Delay function to control sound frequency
delay:
    ldi r18, 100
loop1:
    ldi r19, 255
loop2:
    dec r19
    brne loop2
    dec r18
    brne loop1
    ret
