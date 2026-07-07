;===========================================
; ATmega328P – 2-digit + / - calculator
; LCD 8-bit on PORTB, keypad on PORTD
; Software delays only
;===========================================

.include "m328pdef.inc"

;-------------------------------------------
; Data section: store operands/state in SRAM
;-------------------------------------------
.dseg
OP1:    .byte 1      ; first operand  (0..99)
OP2:    .byte 1      ; second operand (0..99)
STATE:  .byte 1      ; 0=enter OP1, 1=enter OP2, 2=result
OPER:   .byte 1      ; '+' or '-'

;-------------------------------------------
; Code section
;-------------------------------------------
.cseg
.org 0x0000
    jmp RESET        ; use absolute jump (no range issue)

; general-purpose registers
.def Rtmp0 = r16
.def Rtmp1 = r17
.def Rtmp2 = r18
.def Rtmp3 = r19
.def Rval  = r20     ; used for value/result
.def Rdel0 = r21
.def Rdel1 = r22

;-------------------------------------------
; RESET
;-------------------------------------------
RESET:
    ; init stack
    ldi Rtmp0, HIGH(RAMEND)
    out SPH, Rtmp0
    ldi Rtmp0, LOW(RAMEND)
    out SPL, Rtmp0

    rcall Init_Ports
    rcall Delay_ms20
    rcall Init_LCD

    rcall ClearLCD
    rcall ResetCalc

MainLoop:
    rcall GetKeyBlocking          ; ASCII key returned in Rtmp0

    ; ----- CLEAR (C) -----
    cpi Rtmp0, 'C'
    breq Handle_Clear

    ; ----- PLUS -----
    cpi Rtmp0, '+'
    breq Handle_Plus

    ; ----- MINUS -----
    cpi Rtmp0, '-'
    breq Handle_Minus

    ; ----- EQUAL (=) -----
    cpi Rtmp0, '='
    breq Equal_Near              ; short branch ? allowed
                                 ; then jump to real handler

    ; ---------- DIGIT 0..9 ? ----------
    cpi Rtmp0, '0'
    brlo NotDigit

    cpi Rtmp0, '9' + 1
    brsh NotDigit

    ; It IS a digit
    rcall Handle_Digit
    rcall WaitKeyRelease
    rjmp MainLoop


;-------------------------------------
; This label is near the branch target
; So breq Rtmp0,'=' will always reach it
;-------------------------------------
Equal_Near:
    rjmp Handle_Equal            ; long-range jump OK


;-------------------------------------
NotDigit:
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; CALCULATOR HANDLERS
;-------------------------------------------

Handle_Clear:
    rcall ClearLCD
    rcall ResetCalc
    rcall WaitKeyRelease
    rjmp MainLoop

Handle_Plus:
    ; if result already shown, start new calc
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne HP_NoRes
    rcall ClearLCD
    rcall ResetCalc
HP_NoRes:
    lds Rtmp1, STATE
    cpi Rtmp1, 0
    brne HP_Done              ; ignore if not in OP1 entry

    sts OPER, Rtmp0           ; store '+'
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar         ; show '+'
    ldi Rtmp1, 1
    sts STATE, Rtmp1          ; now entering OP2
HP_Done:
    rcall WaitKeyRelease
    rjmp MainLoop

Handle_Minus:
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne HM_NoRes
    rcall ClearLCD
    rcall ResetCalc
HM_NoRes:
    lds Rtmp1, STATE
    cpi Rtmp1, 0
    brne HM_Done

    sts OPER, Rtmp0           ; store '-'
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar
    ldi Rtmp1, 1
    sts STATE, Rtmp1
HM_Done:
    rcall WaitKeyRelease
    rjmp MainLoop

; Rtmp0 = ASCII digit
Handle_Digit:
    ; if result shown -> new expression
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne HD_NoRes
    rcall ClearLCD
    rcall ResetCalc
HD_NoRes:
    mov Rtmp1, Rtmp0
    subi Rtmp1, '0'        ; Rtmp1 = digit 0..9

    lds Rtmp2, STATE
    cpi Rtmp2, 0
    brne HD_OP2

    ; ---- entering OP1 ----
    lds Rtmp2, OP1         ; Rtmp2 = OP1
    ; OP1 = OP1*10 + digit
    mov Rtmp3, Rtmp2
    lsl Rtmp2              ; *2
    mov Rtmp3, Rtmp2
    lsl Rtmp2              ; *4
    lsl Rtmp2              ; *8
    add Rtmp2, Rtmp3       ; *10
    add Rtmp2, Rtmp1
    sts OP1, Rtmp2
    rjmp HD_Print

HD_OP2:
    ; ---- entering OP2 ----
    lds Rtmp2, OP2
    mov Rtmp3, Rtmp2
    lsl Rtmp2
    mov Rtmp3, Rtmp2
    lsl Rtmp2
    lsl Rtmp2
    add Rtmp2, Rtmp3
    add Rtmp2, Rtmp1
    sts OP2, Rtmp2

HD_Print:
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar
    ret

; '=' pressed, Rtmp0 = '='
Handle_Equal:
    ; echo '=' on first line
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar

    ; load operator
    lds Rtmp1, OPER
    cpi Rtmp1, '+'
    breq Do_Add
    cpi Rtmp1, '-'
    breq Do_Sub

    ; no operator -> ignore
    rcall WaitKeyRelease
    rjmp MainLoop

;------------ ADD -----------
Do_Add:
    lds Rval, OP1
    lds Rtmp1, OP2
    add Rval, Rtmp1            ; 0..198
    clr Rtmp3                  ; sign flag = 0 (positive)
    rjmp Show_Result

;------------ SUB -----------
Do_Sub:
    lds Rtmp1, OP1
    lds Rtmp2, OP2
    cp Rtmp1, Rtmp2
    brsh DS_Positive

    ; negative: VAL = OP2 - OP1, sign=1
    mov Rval, Rtmp2
    sub Rval, Rtmp1
    ldi Rtmp3, 1               ; sign negative
    rjmp Show_Result

DS_Positive:
    mov Rval, Rtmp1
    sub Rval, Rtmp2
    clr Rtmp3                  ; sign positive

Show_Result:
    ; move cursor to beginning of 2nd line
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; if negative, print '-'
    cpi Rtmp3, 1
    brne SR_NoMinus
    ldi Rtmp1, '-'
    rcall LCD_PutChar
SR_NoMinus:
    rcall Print_0_199          ; print Rval

    ldi Rtmp1, 2
    sts STATE, Rtmp1           ; result shown
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; CALCULATOR UTILITIES
;-------------------------------------------

ResetCalc:
    ldi Rtmp0, 0
    sts OP1,   Rtmp0
    sts OP2,   Rtmp0
    sts OPER,  Rtmp0
    sts STATE, Rtmp0
    ret

ClearLCD:
    ldi Rtmp0, 0x01
    rcall LCD_Command
    rcall Delay_ms20
    ret

; Print Rval (0..199) as decimal
Print_0_199:
    ; Rval holds value
    clr Rtmp1                 ; hundreds
P100:
    cpi Rval, 100
    brlo P100Done
    subi Rval, 100
    inc Rtmp1
    rjmp P100
P100Done:

    clr Rtmp2                 ; tens
P10:
    cpi Rval, 10
    brlo P10Done
    subi Rval, 10
    inc Rtmp2
    rjmp P10
P10Done:

    ldi Rtmp0, '0'

    ; if hundreds >0 -> print H T U
    cpi Rtmp1, 0
    breq P_NoHund

    mov Rtmp3, Rtmp1
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

    mov Rtmp3, Rtmp2
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

    mov Rtmp3, Rval
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar
    ret

P_NoHund:
    ; if tens >0 -> print T U
    cpi Rtmp2, 0
    breq P_OnlyOnes

    mov Rtmp3, Rtmp2
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

P_OnlyOnes:
    mov Rtmp3, Rval
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar
    ret

;===========================================
; LCD & KEYPAD LOW-LEVEL
;===========================================

Init_Ports:
    ; LCD data on PORTB
    ldi Rtmp0, 0xFF
    out DDRB, Rtmp0
    clr Rtmp0
    out PORTB, Rtmp0

    ; LCD control: RS=PC1, E=PC0
    sbi DDRC, 0
    sbi DDRC, 1
    cbi PORTC,0
    cbi PORTC,1

    ; Keypad: PD0..PD3 rows out, PD4..PD7 in+pull-up
    ldi Rtmp0, 0x0F
    out DDRD, Rtmp0
    ldi Rtmp0, 0xF0
    ori Rtmp0, 0x0F
    out PORTD, Rtmp0
    ret

Init_LCD:
    ldi Rtmp0, 0x38        ; 8-bit, 2 lines
    rcall LCD_Command
    ldi Rtmp0, 0x0C        ; display on, cursor off
    rcall LCD_Command
    ldi Rtmp0, 0x06        ; entry mode
    rcall LCD_Command
    ldi Rtmp0, 0x01        ; clear
    rcall LCD_Command
    rcall Delay_ms20
    ret

; Rtmp0 = command
LCD_Command:
    out PORTB, Rtmp0
    cbi PORTC,1            ; RS=0
    sbi PORTC,0            ; E=1
    cbi PORTC,0            ; E=0
    rcall Delay_us50
    ret

; Rtmp1 = data
LCD_PutChar:
    out PORTB, Rtmp1
    sbi PORTC,1            ; RS=1
    sbi PORTC,0            ; E=1
    cbi PORTC,0            ; E=0
    rcall Delay_us50
    ret

;-------------------------------------------
; Keypad scanning – return ASCII in Rtmp0
;-------------------------------------------
GetKeyBlocking:
ScanLoop:
    ; Row1 low
    ldi Rtmp0, 0b11111110
    out PORTD, Rtmp0
    rcall Delay_us50
    in  Rtmp1, PIND
    andi Rtmp1, 0xF0
    cpi Rtmp1, 0xF0
    brne Row1

    ; Row2 low
    ldi Rtmp0, 0b11111101
    out PORTD, Rtmp0
    rcall Delay_us50
    in  Rtmp1, PIND
    andi Rtmp1, 0xF0
    cpi Rtmp1, 0xF0
    brne Row2

    ; Row3 low
    ldi Rtmp0, 0b11111011
    out PORTD, Rtmp0
    rcall Delay_us50
    in  Rtmp1, PIND
    andi Rtmp1, 0xF0
    cpi Rtmp1, 0xF0
    brne Row3

    ; Row4 low
    ldi Rtmp0, 0b11110111
    out PORTD, Rtmp0
    rcall Delay_us50
    in  Rtmp1, PIND
    andi Rtmp1, 0xF0
    cpi Rtmp1, 0xF0
    brne Row4

    rjmp ScanLoop

; Row1: 7 8 9 /
Row1:
    sbrs Rtmp1,4
    rjmp K7
    sbrs Rtmp1,5
    rjmp K8
    sbrs Rtmp1,6
    rjmp K9
    sbrs Rtmp1,7
    rjmp KDiv
    rjmp ScanLoop

; Row2: 4 5 6 *
Row2:
    sbrs Rtmp1,4
    rjmp K4
    sbrs Rtmp1,5
    rjmp K5
    sbrs Rtmp1,6
    rjmp K6
    sbrs Rtmp1,7
    rjmp KMul
    rjmp ScanLoop

; Row3: 1 2 3 -
Row3:
    sbrs Rtmp1,4
    rjmp K1
    sbrs Rtmp1,5
    rjmp K2
    sbrs Rtmp1,6
    rjmp K3
    sbrs Rtmp1,7
    rjmp KMinus
    rjmp ScanLoop

; Row4: C 0 = +
Row4:
    sbrs Rtmp1,4
    rjmp KC
    sbrs Rtmp1,5
    rjmp K0
    sbrs Rtmp1,6
    rjmp KEq
    sbrs Rtmp1,7
    rjmp KPlus
    rjmp ScanLoop

; key mapping (ASCII in Rtmp0)
K7:
    ldi Rtmp0, '7'
    ret
K8:
    ldi Rtmp0, '8'
    ret
K9:
    ldi Rtmp0, '9'
    ret
KDiv:
    ldi Rtmp0, '/'
    ret

K4:
    ldi Rtmp0, '4'
    ret
K5:
    ldi Rtmp0, '5'
    ret
K6:
    ldi Rtmp0, '6'
    ret
KMul:
    ldi Rtmp0, '*'
    ret

K1:
    ldi Rtmp0, '1'
    ret
K2:
    ldi Rtmp0, '2'
    ret
K3:
    ldi Rtmp0, '3'
    ret
KMinus:
    ldi Rtmp0, '-'
    ret

KC:
    ldi Rtmp0, 'C'
    ret
K0:
    ldi Rtmp0, '0'
    ret
KEq:
    ldi Rtmp0, '='
    ret
KPlus:
    ldi Rtmp0, '+'
    ret

;-------------------------------------------
; Wait until all keys released
;-------------------------------------------
WaitKeyRelease:
ReleaseLoop:
    ldi Rtmp0, 0b11110000       ; rows low, columns pull-up
    out PORTD, Rtmp0
    rcall Delay_us50
    in  Rtmp1, PIND
    andi Rtmp1, 0xF0
    cpi Rtmp1, 0xF0
    brne ReleaseLoop
    ret

;===========================================
; SOFTWARE DELAYS
;===========================================

; ? 50 µs delay (rough)
Delay_us50:
    ldi Rdel0, 40
Du_loop:
    dec Rdel0
    brne Du_loop
    ret

; ? 20 ms using 50 µs loop
Delay_ms20:
    ldi Rdel1, 200
Dm_loop:
    rcall Delay_us50
    dec Rdel1
    brne Dm_loop
    ret
