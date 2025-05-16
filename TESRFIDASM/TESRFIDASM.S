;------------------------
; MFRC522 RFID Reader with Servo Control - Two State System
; ATmega328P (Arduino Uno)
;------------------------
#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

; Pin definitions for RFID
.equ SS,    2       ; PB2 (Slave Select)
.equ MOSI,  3       ; PB3
.equ MISO,  4       ; PB4
.equ SCK,   5       ; PB5

; Pin definitions for Servo
.equ SERVO_PIN, 1   ; PB1 (OC1A)
.equ BUTTON_PIN, 7  ; PD7

; Pin definitions for indicators
.equ GREEN_LED, 4   ; PC4 - Success indicator
.equ RED_LED, 3     ; PC3 - Failure indicator
.equ BUZZER, 2      ; PC2 - Sound indicator

; Sound pattern durations
.equ SUCCESS_BUZZ_LEN, 100    ; Length of success beep
.equ FAILURE_BUZZ_LEN, 50     ; Length of failure beep
.equ FAILURE_BUZZ_PAUSE, 50   ; Pause between failure beeps

; Servo pulse constants
.equ MIN_PULSE, 3000     ; 544 us / 0.5 us per tick 
.equ MAX_PULSE, 1000     ; 2400 us / 0.5 us per tick
.equ TOP_COUNT, 39999    ; 20 ms → 50Hz PWM
.equ DELAY_COUNT, 50     ; Delay for debouncing

; State definitions
.equ STATE_RFID, 0       ; State 1: Reading RFID
.equ STATE_BUTTON, 1     ; State 2: Monitoring button

; MFRC522 Register addresses
.equ PCD_CommandReg,    0x01
.equ PCD_ComIEnReg,     0x02
.equ PCD_ComIrqReg,     0x04
.equ PCD_DivIrqReg,     0x05
.equ PCD_ErrorReg,      0x06
.equ PCD_FIFODataReg,   0x09
.equ PCD_FIFOLevelReg,  0x0A
.equ PCD_ControlReg,    0x0C
.equ PCD_BitFramingReg, 0x0D
.equ PCD_ModeReg,       0x11
.equ PCD_TxModeReg,     0x12
.equ PCD_RxModeReg,     0x13
.equ PCD_TxControlReg,  0x14
.equ PCD_TxASKReg,      0x15
.equ PCD_TModeReg,      0x2A
.equ PCD_TPrescalerReg, 0x2B
.equ PCD_TReloadRegH,   0x2C
.equ PCD_TReloadRegL,   0x2D

; MFRC522 Commands
.equ PCD_IDLE,          0x00
.equ PCD_TRANSCEIVE,    0x0C
.equ PCD_AUTHENT,       0x0E
.equ PCD_SOFTRESET,     0x0F

; PICC Commands
.equ PICC_REQIDL,       0x26    ; Request command for cards in idle state
.equ PICC_ANTICOLL,     0x93    ; Anti-collision command

; Status codes
.equ STATUS_OK,         0
.equ STATUS_ERROR,      1
.equ STATUS_TIMEOUT,    2

; Reference Card ID
.equ REF_ID_BYTE0,     0x23    ; Expected UID bytes
.equ REF_ID_BYTE1,     0x46
.equ REF_ID_BYTE2,     0x02
.equ REF_ID_BYTE3,     0x52

; UART Baud-setting for 9600 baud at 16MHz
.equ UBRR_VALUE, 103  ; 16000000/(16*9600)-1 = 103.17

; String messages stored in program memory
msg_rfid_ready:
    .ascii "RFID Ready\r\n"
    .byte 0
msg_init:
    .ascii "Init\r\n"
    .byte 0
msg_ant_on:
    .ascii "Ant ON\r\n"
    .byte 0
msg_timeout:
    .ascii "Timeout\r\n"
    .byte 0
msg_error:
    .ascii "Error\r\n"
    .byte 0
msg_invalid_resp:
    .ascii "Invalid resp\r\n"
    .byte 0
msg_card_id:
    .ascii "Card ID: "
    .byte 0
msg_card_correct:
    .ascii "Card ID is correct\r\n"
    .byte 0
msg_card_wrong:
    .ascii "Card ID is wrong\r\n"
    .byte 0
msg_state_change:
    .ascii "Changing to state: "
    .byte 0
msg_unlocked:
    .ascii "Door unlocked\r\n"
    .byte 0
msg_locked:
    .ascii "Door locked\r\n"
    .byte 0

.text
;========================
;         STARTUP
;========================
main:
    ; Initialize stack pointer
    LDI   R16, hi8(RAMEND)
    OUT   SPH, R16
    LDI   R16, lo8(RAMEND)
    OUT   SPL, R16
    
    ; Initialize system state
    LDI   R30, STATE_RFID      ; R30 will be our state variable (0=RFID, 1=BUTTON)
    
    ; Initialize USART
    RCALL USART_Init
    
    ; Initialize SPI
    RCALL SPI_Master_Init
    
    ; Initialize RFID
    RCALL RC522_Init
    
    ; Initialize Servo
    RCALL Servo_Init
    
    ; Initialize indicator pins
    RCALL Indicator_Init
    
    ; Start in state 1 (RFID reading)
    RJMP  STATE_RFID_LOOP

;========================
;   Indicator Initialization
;========================
Indicator_Init:
    ; Set PC2 (BUZZER), PC3 (RED_LED), and PC4 (GREEN_LED) as outputs
    SBI   DDRC, BUZZER
    SBI   DDRC, RED_LED
    SBI   DDRC, GREEN_LED
    
    ; Ensure all indicators are initially off
    CBI   PORTC, BUZZER
    CBI   PORTC, RED_LED
    CBI   PORTC, GREEN_LED
    
    RET

;========================
;   Buzzer Sound Patterns
;========================
; Success sound - single long beep
Success_Sound:
    ; Turn on buzzer
    SBI   PORTC, BUZZER
    
    ; Wait for beep duration
    LDI   R20, SUCCESS_BUZZ_LEN
success_buzz:
    RCALL Delay_ms
    DEC   R20
    BRNE  success_buzz
    
    ; Turn off buzzer
    CBI   PORTC, BUZZER
    RET

; Failure sound - three short beeps
Failure_Sound:
    ; First beep
    SBI   PORTC, BUZZER
    LDI   R20, FAILURE_BUZZ_LEN
failure_buzz1:
    RCALL Delay_ms
    DEC   R20
    BRNE  failure_buzz1
    CBI   PORTC, BUZZER
    
    ; Pause
    LDI   R20, FAILURE_BUZZ_PAUSE
failure_pause1:
    RCALL Delay_ms
    DEC   R20
    BRNE  failure_pause1
    
    ; Second beep
    SBI   PORTC, BUZZER
    LDI   R20, FAILURE_BUZZ_LEN
failure_buzz2:
    RCALL Delay_ms
    DEC   R20
    BRNE  failure_buzz2
    CBI   PORTC, BUZZER
    
    ; Pause
    LDI   R20, FAILURE_BUZZ_PAUSE
failure_pause2:
    RCALL Delay_ms
    DEC   R20
    BRNE  failure_pause2
    
    ; Third beep
    SBI   PORTC, BUZZER
    LDI   R20, FAILURE_BUZZ_LEN
failure_buzz3:
    RCALL Delay_ms
    DEC   R20
    BRNE  failure_buzz3
    CBI   PORTC, BUZZER
    
    RET

;========================
;    MAIN STATE LOOPS
;========================
STATE_RFID_LOOP:
    ; Ensure indicators are off at the start of the state
    CBI   PORTC, GREEN_LED
    CBI   PORTC, RED_LED
    
    ; Small delay between reads
    LDI   R20, 50
delay_loop_rfid:
    RCALL Delay_ms
    DEC   R20
    BRNE  delay_loop_rfid
    
    ; Send heartbeat character to show code is running
    LDI   R24, '.'
    RCALL USART_Send_Byte
    
    ; Check if card is present
    RCALL RC522_IsCardPresent  
    CPI   R24, STATUS_OK
    BRNE  STATE_RFID_LOOP      ; If no card, continue loop
    
    ; If card is present, read its UID
    RCALL RC522_ReadUID
    
    ; Check if we should transition to state 2 (button monitoring)
    CPI   R19, 1               ; R19 is our card match flag (1=match)
    BREQ  RFID_CORRECT         ; RFID is correct, light green LED and sound success
    
    ; RFID is incorrect, light red LED and sound failure
    SBI   PORTC, RED_LED       ; Turn on red LED
    RCALL Failure_Sound        ; Play failure sound
    
    ; Continue in state 1
    RJMP  STATE_RFID_LOOP

RFID_CORRECT:
    ; Card is correct, activate green LED and success sound
    SBI   PORTC, GREEN_LED     ; Turn on green LED
    RCALL Success_Sound        ; Play success sound
    
    ; Short delay to see the green LED
    LDI   R20, 100
rfid_correct_delay:
    RCALL Delay_ms
    DEC   R20
    BRNE  rfid_correct_delay
    
    ; Now transition to button state
    RJMP  TRANSITION_TO_STATE_BUTTON

TRANSITION_TO_STATE_BUTTON:
    ; Turn off all indicator LEDs
    CBI   PORTC, GREEN_LED
    CBI   PORTC, RED_LED
    
    ; Print state change message
    LDI   ZL, lo8(msg_state_change)
    LDI   ZH, hi8(msg_state_change)
    RCALL USART_Send_String
    LDI   R24, '2'
    RCALL USART_Send_Byte
    LDI   R24, '\r'
    RCALL USART_Send_Byte
    LDI   R24, '\n'
    RCALL USART_Send_Byte
    
    ; Print unlock message
    LDI   ZL, lo8(msg_unlocked)
    LDI   ZH, hi8(msg_unlocked)
    RCALL USART_Send_String
    
    ; Set state to BUTTON
    LDI   R30, STATE_BUTTON
    
    ; Set servo to MAX_PULSE to unlock
    LDI   R24, hi8(MAX_PULSE)
    LDI   R25, lo8(MAX_PULSE)
    RCALL SET_OCR1A
    
    ; Initialize button flag
    CLR   R29            ; R29 = button flag (0=not pressed, 1=pressed)
    
    ; Jump to button monitoring loop
    RJMP  STATE_BUTTON_LOOP

STATE_BUTTON_LOOP:
    ; Check button status (logic low when pressed due to pull-up)
    SBIC  PIND, BUTTON_PIN     ; Skip if bit high (button not pressed)
    RJMP  BUTTON_PRESSED_STATE2
    
    ; Button not pressed
    CLR   R29                  ; Reset button flag
    
    ; Continue in state 2
    RJMP  STATE_BUTTON_LOOP

BUTTON_PRESSED_STATE2:
    ; Check if button was already pressed
    TST   R29
    BRNE  STATE_BUTTON_LOOP    ; If already pressed, ignore
    
    ; Set button pressed flag
    LDI   R29, 1
    
    ; Provide feedback with buzzer and green LED
    SBI   PORTC, GREEN_LED     ; Turn on green LED
    RCALL Success_Sound        ; Play success sound
    
    ; Print state change message
    LDI   ZL, lo8(msg_state_change)
    LDI   ZH, hi8(msg_state_change)
    RCALL USART_Send_String
    LDI   R24, '1'
    RCALL USART_Send_Byte
    LDI   R24, '\r'
    RCALL USART_Send_Byte
    LDI   R24, '\n'
    RCALL USART_Send_Byte
    
    ; Print lock message
    LDI   ZL, lo8(msg_locked)
    LDI   ZH, hi8(msg_locked)
    RCALL USART_Send_String
    
    ; Set state back to RFID
    LDI   R30, STATE_RFID
    
    ; Set servo to MIN_PULSE to lock
    LDI   R24, hi8(MIN_PULSE)
    LDI   R25, lo8(MIN_PULSE)
    RCALL SET_OCR1A
    
    ; Turn off all indicators before switching states
    CBI   PORTC, GREEN_LED
    CBI   PORTC, RED_LED
    
    ; Jump to RFID state
    RJMP  STATE_RFID_LOOP

;========================
;   USART / Serial TX
;========================
USART_Init:
    ; Set baud rate registers
    LDI   R16, 0
    STS   UBRR0H, R16
    LDI   R16, UBRR_VALUE
    STS   UBRR0L, R16
    ; Enable transmitter only
    LDI   R16, (1<<TXEN0)
    STS   UCSR0B, R16
    ; 8 data bits, no parity, 1 stop bit
    LDI   R16, (1<<UCSZ01)|(1<<UCSZ00)
    STS   UCSR0C, R16
    
    ; Print initialization message
    LDI   ZL, lo8(msg_rfid_ready)
    LDI   ZH, hi8(msg_rfid_ready)
    RCALL USART_Send_String
    
    RET

USART_Send_Byte:
    ; Transmit byte in R24
    lds   r17, UCSR0A
    sbrs  r17, UDRE0
    rjmp  USART_Send_Byte
    sts   UDR0, r24
    RET

; Send a zero-terminated string from program memory
; Input: Z register points to string in flash
USART_Send_String:
    LPM   R24, Z+         ; Load byte from program memory and increment Z
    CPI   R24, 0          ; Check if end of string
    BREQ  .Lstring_end    ; If zero, we're done
    RCALL USART_Send_Byte ; Send the character
    RJMP  USART_Send_String ; Continue with next character
.Lstring_end:
    RET

; Convert binary in R16 → two ASCII hex chars via R17–R18
ByteToHex:
    PUSH  R16
    ; high nibble
    MOV   R18, R16
    ANDI  R18, 0xF0
    LSR   R18
    LSR   R18
    LSR   R18
    LSR   R18
    CPI   R18, 10
    BRCS  .Lhex_digit_lo
    ; For values A-F: Add ('A' - 10)
    LDI   R17, 'A' - 10
    ADD   R18, R17
    RJMP  .Lhex_send_hi
.Lhex_digit_lo:
    ; For values 0-9: Add '0'
    LDI   R17, '0'
    ADD   R18, R17
.Lhex_send_hi:
    MOV   R24, R18
    RCALL USART_Send_Byte

    ; low nibble
    POP   R16           ; original byte back
    ANDI  R16, 0x0F
    CPI   R16, 10
    BRCS  .Lhex_digit_lo2
    ; For values A-F: Add ('A' - 10)
    LDI   R17, 'A' - 10
    ADD   R16, R17
    RJMP  .Lhex_send_lo
.Lhex_digit_lo2:
    ; For values 0-9: Add '0'
    LDI   R17, '0'
    ADD   R16, R17
.Lhex_send_lo:
    MOV   R24, R16
    RCALL USART_Send_Byte
    RET

; Print decimal value (0-255)
; Input: R16 = byte to print
Print_Decimal:
    MOV   R24, R16
    CLR   R17                 ; Flag for leading zero suppression
    
    ; Hundreds place
    LDI   R18, '0'
hundreds_loop:
    CPI   R24, 100
    BRLO  hundreds_done
    INC   R18
    SUBI  R24, 100
    RJMP  hundreds_loop
hundreds_done:
    CPI   R18, '0'
    BREQ  skip_hundreds
    MOV   R19, R24            ; Save remainder
    MOV   R24, R18
    RCALL USART_Send_Byte
    MOV   R24, R19            ; Restore remainder
    LDI   R17, 1              ; Mark that we've printed something
    
skip_hundreds:
    ; Tens place
    LDI   R18, '0'
tens_loop:
    CPI   R24, 10
    BRLO  tens_done
    INC   R18
    SUBI  R24, 10
    RJMP  tens_loop
tens_done:
    ; Only print if not leading zero or we have printed hundreds
    CPI   R17, 0
    BRNE  print_tens
    CPI   R18, '0'
    BREQ  skip_tens
print_tens:
    MOV   R19, R24            ; Save remainder
    MOV   R24, R18
    RCALL USART_Send_Byte
    MOV   R24, R19            ; Restore remainder
    LDI   R17, 1              ; Mark that we've printed something
    
skip_tens:
    ; Units place (always print)
    SUBI  R24, -'0'           ; Convert to ASCII
    RCALL USART_Send_Byte
    RET

;========================
;   Servo Initialization
;========================
Servo_Init:
    ; Set PB1 (OC1A) as output
    SBI   DDRB, SERVO_PIN
    
    ; Set PD7 as input
    CBI   DDRD, BUTTON_PIN
    ; Set pull-up resistor for PD7
    SBI   PORTD, BUTTON_PIN
    
    ; Timer1 → Fast PWM mode (WGM13:0 = 14)
    LDI   R16, (1<<WGM11)
    STS   TCCR1A, R16
    LDI   R16, (1<<WGM13)|(1<<WGM12)|(1<<CS11)   ; prescaler = 8
    STS   TCCR1B, R16
    
    ; Non-inverting mode for OC1A
    LDS   R16, TCCR1A
    ORI   R16, (1<<COM1A1)
    STS   TCCR1A, R16
    
    ; Set ICR1 = 20ms (TOP)
    LDI   R16, hi8(TOP_COUNT)
    STS   ICR1H, R16
    LDI   R16, lo8(TOP_COUNT)
    STS   ICR1L, R16
    
    ; Start with door locked (MIN_PULSE)
    LDI   R24, hi8(MIN_PULSE)
    LDI   R25, lo8(MIN_PULSE)
    RCALL SET_OCR1A
    
    RET

; Set OCR1A register for servo control
; Input: R24:R25 = pulse width
SET_OCR1A:
    STS   OCR1AH, R24
    STS   OCR1AL, R25
    RET

;========================
;   SPI Master Init
;========================
SPI_Master_Init:
    ; MOSI, SCK, SS as outputs
    LDI   R16, (1<<MOSI)|(1<<SCK)|(1<<SS)
    OUT   DDRB, R16
    ; Set MISO as input with pullup
    CBI   DDRB, MISO
    SBI   PORTB, MISO         ; Enable pullup
    ; Enable SPI, Master, fosc/16
    LDI   R16, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    OUT   SPCR, R16
    ; SS idle high
    SBI   PORTB, SS
    RET

;========================
;   RC522 Initialization
;========================
RC522_Init:
    ; Send initialization message
    LDI   ZL, lo8(msg_init)
    LDI   ZH, hi8(msg_init)
    RCALL USART_Send_String

    ; Wait for power stabilization
    LDI   R20, 100
.Lwait_start:
    RCALL Delay_ms
    DEC   R20
    BRNE  .Lwait_start

    ; Soft reset
    LDI   R24, PCD_CommandReg
    LDI   R25, PCD_SOFTRESET
    RCALL RC522_WriteReg

    ; Wait ~100ms for reset to complete
    LDI   R20, 100
.Lwait_reset:
    RCALL Delay_ms
    DEC   R20
    BRNE  .Lwait_reset

    ; --- Additional initialization steps ---
    
    ; Set the timer
    LDI   R24, PCD_TModeReg
    LDI   R25, 0x8D           ; TAuto=1; f(Timer) = 6.78MHz/TPreScaler
    RCALL RC522_WriteReg
    
    ; Set timer prescaler
    LDI   R24, PCD_TPrescalerReg
    LDI   R25, 0x3E           ; TModeReg[3..0] + TPrescalerReg = ~40kHz timer frequency
    RCALL RC522_WriteReg
    
    ; Set timer reload value
    LDI   R24, PCD_TReloadRegL
    LDI   R25, 30             ; Reload timer every 30 ticks
    RCALL RC522_WriteReg
    
    LDI   R24, PCD_TReloadRegH
    LDI   R25, 0              ; MSB = 0
    RCALL RC522_WriteReg
    
    ; Set 100% ASK modulation
    LDI   R24, PCD_TxASKReg
    LDI   R25, 0x40           ; Default 0x00 - Force 100% ASK modulation
    RCALL RC522_WriteReg
    
    ; Set CRC preset value to 0x6363
    LDI   R24, PCD_ModeReg
    LDI   R25, 0x3D           ; CRC preset 0x6363 and enable CRC
    RCALL RC522_WriteReg
    
    ; Configure Tx and Rx modes
    LDI   R24, PCD_TxModeReg
    LDI   R25, 0x00           ; Regular data transmission
    RCALL RC522_WriteReg
    
    LDI   R24, PCD_RxModeReg
    LDI   R25, 0x00           ; Regular data reception
    RCALL RC522_WriteReg

    ; Enable antenna (Tx1 & Tx2)
    LDI   R24, PCD_TxControlReg
    RCALL RC522_ReadReg       ; data→R24
    ORI   R24, 0x03           ; Enable both Tx1 and Tx2 (00000011)
    MOV   R25, R24
    LDI   R24, PCD_TxControlReg
    RCALL RC522_WriteReg
    
    ; Debug message to confirm initialization
    LDI   ZL, lo8(msg_ant_on)
    LDI   ZH, hi8(msg_ant_on)
    RCALL USART_Send_String
    
    RET

;========================
;   SPI Transfer Routines
;========================
RC522_WriteReg:
    ; R24=addr, R25=data
    CBI   PORTB, SS           ; SS low to select the chip
    LSL   R24                 ; Shift address
    ANDI  R24, 0x7E           ; Clear MSB for write
    MOV   R16, R24
    RCALL SPI_TransferByte
    MOV   R16, R25
    RCALL SPI_TransferByte
    SBI   PORTB, SS           ; SS high to deselect the chip
    RET

RC522_ReadReg:
    ; R24=addr → data returned in R24
    CBI   PORTB, SS           ; SS low to select the chip
    LSL   R24                 ; Shift address
    ORI   R24, 0x80           ; Set MSB for read
    MOV   R16, R24
    RCALL SPI_TransferByte
    LDI   R16, 0x00
    RCALL SPI_TransferByte    ; Dummy write to clock data out
    MOV   R24, R16
    SBI   PORTB, SS           ; SS high to deselect the chip
    RET

SPI_TransferByte:
    ; send/receive in R16
    OUT   SPDR, R16
.Lspi_wait:
    IN    R17, SPSR
    SBRS  R17, SPIF
    RJMP  .Lspi_wait
    IN    R16, SPDR
    RET

;========================
;   Card Detection
;========================
RC522_IsCardPresent:
    ; Returns STATUS_OK in R24 if card is detected
    
    ; Clear all interrupt flags
    LDI   R24, PCD_ComIrqReg
    LDI   R25, 0x7F           ; Clear all interrupt requests
    RCALL RC522_WriteReg
    
    ; Clear the FIFO
    LDI   R24, PCD_FIFOLevelReg
    LDI   R25, 0x80           ; Flush the FIFO buffer
    RCALL RC522_WriteReg
    
    ; Prepare REQA command
    LDI   R24, PCD_FIFODataReg
    LDI   R25, PICC_REQIDL    ; Request command for IDLE cards
    RCALL RC522_WriteReg

    ; Configure bit framing
    LDI   R24, PCD_BitFramingReg
    LDI   R25, 0x07           ; 7 bits for last byte
    RCALL RC522_WriteReg

    ; Start transmission
    LDI   R24, PCD_CommandReg
    LDI   R25, PCD_TRANSCEIVE ; Start transmission of data
    RCALL RC522_WriteReg
    
    ; Start the transmission
    LDI   R24, PCD_BitFramingReg
    LDI   R25, 0x87           ; Start transmission (0x80) + 7 bits (0x07)
    RCALL RC522_WriteReg
    
    ; Wait for completion or timeout
    LDI   R20, 30             ; Timeout counter
    
.Lwait_presence:
    RCALL Delay_ms
    LDI   R24, PCD_ComIrqReg
    RCALL RC522_ReadReg       ; Read interrupt register
    ANDI  R24, 0x30           ; Check for RxIRq or IdleIRq
    BRNE  .Lgot_presence_response
    DEC   R20
    BRNE  .Lwait_presence
    
    ; Timeout occurred
    LDI   R24, STATUS_TIMEOUT
    RET
    
.Lgot_presence_response:
    ; Read error register
    LDI   R24, PCD_ErrorReg
    RCALL RC522_ReadReg
    ANDI  R24, 0x1B           ; Check for Protocol, Parity, CRC error
    BREQ  .Lno_error          ; No error
    
    ; Error occurred
    LDI   R24, STATUS_ERROR
    RET
    
.Lno_error:
    ; Read FIFO level
    LDI   R24, PCD_FIFOLevelReg
    RCALL RC522_ReadReg
    CPI   R24, 0              ; Check if any data is available
    BREQ  .Lno_response
    
    ; Read FIFO data (should be 2 bytes ATQA)
    LDI   R24, PCD_FIFODataReg
    RCALL RC522_ReadReg       ; Read first byte
    LDI   R24, PCD_FIFODataReg
    RCALL RC522_ReadReg       ; Read second byte
    
    ; Card detected
    LDI   R24, STATUS_OK
    RET
    
.Lno_response:
    LDI   R24, STATUS_ERROR
    RET

;========================
;   Read UID & Print
;========================
RC522_ReadUID:
    ; Clear all interrupt flags
    LDI   R24, PCD_ComIrqReg
    LDI   R25, 0x7F           ; Clear all interrupt requests
    RCALL RC522_WriteReg
    
    ; Clear the FIFO
    LDI   R24, PCD_FIFOLevelReg
    LDI   R25, 0x80           ; Flush the FIFO buffer
    RCALL RC522_WriteReg

    ; Send anti-collision command
    LDI   R24, PCD_FIFODataReg
    LDI   R25, PICC_ANTICOLL  ; Anti-collision command
    RCALL RC522_WriteReg
    
    LDI   R24, PCD_FIFODataReg
    LDI   R25, 0x20           ; 4 byte UID - byte count
    RCALL RC522_WriteReg

    ; Configure bit framing
    LDI   R24, PCD_BitFramingReg
    LDI   R25, 0x00           ; Regular framing
    RCALL RC522_WriteReg

    ; Start transmission
    LDI   R24, PCD_CommandReg
    LDI   R25, PCD_TRANSCEIVE ; Transmit and receive
    RCALL RC522_WriteReg
    
    ; Start the transmission
    LDI   R24, PCD_BitFramingReg
    LDI   R25, 0x80           ; Start transmission
    RCALL RC522_WriteReg

    ; Wait for completion or timeout
    LDI   R20, 30             ; Timeout counter
    
.Lwait_uid:
    RCALL Delay_ms
    LDI   R24, PCD_ComIrqReg
    RCALL RC522_ReadReg       ; Read interrupt register
    ANDI  R24, 0x30           ; Check for RxIRq or IdleIRq
    BRNE  .Lgot_uid_response
    DEC   R20
    BRNE  .Lwait_uid
    
    ; Timeout occurred
    LDI   ZL, lo8(msg_timeout)
    LDI   ZH, hi8(msg_timeout)
    RCALL USART_Send_String
    RET

.Lgot_uid_response:
    ; Check for errors
    LDI   R24, PCD_ErrorReg
    RCALL RC522_ReadReg
    ANDI  R24, 0x1B           ; Check for Protocol, Parity, CRC error
    BREQ  .Lno_uid_error
    
    ; Error occurred
    LDI   ZL, lo8(msg_error)
    LDI   ZH, hi8(msg_error)
    RCALL USART_Send_String
    RET
    
.Lno_uid_error:
    ; Read FIFO level
    LDI   R24, PCD_FIFOLevelReg
    RCALL RC522_ReadReg
    MOV   R22, R24            ; R22 = byte count
    
    ; Check if we have valid data (should be at least 5 bytes: byteCnt + 4 bytes UID)
    CPI   R22, 5
    BRGE  .Lvalid_uid_data
    
    ; Not enough data
    LDI   ZL, lo8(msg_invalid_resp)
    LDI   ZH, hi8(msg_invalid_resp)
    RCALL USART_Send_String
    RET
    
.Lvalid_uid_data:
    ; Print "Card ID: "
    LDI   ZL, lo8(msg_card_id)
    LDI   ZH, hi8(msg_card_id)
    RCALL USART_Send_String
    
    ; First byte is number of bytes in UID (should be 4)
    LDI   R24, PCD_FIFODataReg
    RCALL RC522_ReadReg
    DEC   R22                 ; Decrement byte count
    
    ; Initialize match flag to 1 (assume match)
    LDI   R19, 1              ; R19 = match flag (1=match, 0=no match)
    
    ; Now read all the UID bytes and store for comparison
    CLR   R21                 ; Counter for UID bytes
    
    ; Store UID bytes in R10-R13 for comparison
.Lread_uid_loop:
    LDI   R24, PCD_FIFODataReg
    RCALL RC522_ReadReg       ; Read one byte of UID from FIFO
    
    ; Store byte in appropriate register (R10-R13) based on position
    CPI   R21, 0
    BRNE  .Lcheck_byte1
    MOV   R10, R24            ; First byte in R10
    CPI   R24, REF_ID_BYTE0   ; Compare with reference
    BREQ  .Lstore_and_print   ; If equal, continue
    CLR   R19                 ; If not equal, clear match flag
    RJMP  .Lstore_and_print
    
.Lcheck_byte1:
    CPI   R21, 1
    BRNE  .Lcheck_byte2
    MOV   R11, R24            ; Second byte in R11
    CPI   R24, REF_ID_BYTE1   ; Compare with reference
    BREQ  .Lstore_and_print   ; If equal, continue
    CLR   R19                 ; If not equal, clear match flag
    RJMP  .Lstore_and_print
    
.Lcheck_byte2:
    CPI   R21, 2
    BRNE  .Lcheck_byte3
    MOV   R12, R24            ; Third byte in R12
    CPI   R24, REF_ID_BYTE2   ; Compare with reference
    BREQ  .Lstore_and_print   ; If equal, continue
    CLR   R19                 ; If not equal, clear match flag
    RJMP  .Lstore_and_print
    
.Lcheck_byte3:
    MOV   R13, R24            ; Fourth byte in R13
    CPI   R24, REF_ID_BYTE3   ; Compare with reference
    BREQ  .Lstore_and_print   ; If equal, continue
    CLR   R19                 ; If not equal, clear match flag
    
.Lstore_and_print:
    ; Print the byte as hex (regardless of match)
    MOV   R16, R24            ; Move to R16 for ByteToHex
    RCALL ByteToHex           ; Print as hex
    
    ; Print space between bytes
    LDI   R24, ' '
    RCALL USART_Send_Byte
    
    INC   R21                 ; Increment byte counter
    CPI   R21, 4              ; Check if we've read all 4 UID bytes
    BRGE  .Luid_done
    
    DEC   R22                 ; Decrement total byte count
    BRNE  .Lread_uid_loop
    
.Luid_done:
    ; Print newline
    LDI   R24, '\r'
    RCALL USART_Send_Byte
    LDI   R24, '\n'
    RCALL USART_Send_Byte
    
    ; Now print the result of the comparison
    CPI   R19, 1              ; Check if match flag is still set
    BRNE  .Lcard_id_wrong
    
    ; Card ID is correct
    LDI   ZL, lo8(msg_card_correct)
    LDI   ZH, hi8(msg_card_correct)
    RCALL USART_Send_String
    RJMP  .Lprint_final_newline
    
.Lcard_id_wrong:
    ; Card ID is wrong
    LDI   ZL, lo8(msg_card_wrong)
    LDI   ZH, hi8(msg_card_wrong)
    RCALL USART_Send_String
    
.Lprint_final_newline:
    RET

;========================
;     Simple Delay
;========================
Delay_ms:
    ; ~1 ms at 16 MHz
    LDI   R22, 16
.Ldelay_outer:
    LDI   R23, 250
.Ldelay_inner:
    NOP
    NOP
    DEC   R23
    BRNE  .Ldelay_inner
    DEC   R22
    BRNE  .Ldelay_outer
    RET