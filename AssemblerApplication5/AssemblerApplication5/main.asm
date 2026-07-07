;===========================================
; ATmega328P – 2-digit + / - * / calculator
; LCD 8-bit on PORTB, keypad on PORTD
; Software delays only
;===========================================

.include "m328pdef.inc"

;-------------------------------------------
; Data section: variables in SRAM
;-------------------------------------------
.dseg
OP1:    .byte 1      ; first operand (0..99)
OP2:    .byte 1      ; second operand (0..99)
STATE:  .byte 1      ; 0=enter OP1, 1=enter OP2, 2=result shown
OPER:   .byte 1      ; '+', '-', '*', '/'

;-------------------------------------------
; Code section
;-------------------------------------------
.cseg
.org 0x0000
    jmp RESET        ; absolute jump, no range issue

; general purpose registers
.def Rtmp0 = r16
.def Rtmp1 = r17
.def Rtmp2 = r18
.def Rtmp3 = r19
.def Rval  = r20     ; result / generic value
.def Rdel0 = r21
.def Rdel1 = r22
.def RremLo = r23    ; 16-bit remainder/working value, low byte
.def RremHi = r24    ; 16-bit remainder/working value, high byte
.def Rdec1  = r25    ; first decimal digit (D1)
.def Rdec2  = r26    ; second decimal digit (D2)
.def Rzero = r27

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
	clr Rzero

;===========================================
; MAIN LOOP
;===========================================
MainLoop:
    rcall GetKeyBlocking          ; ASCII key in Rtmp0

    ; ----- CLEAR (C) -----
    cpi Rtmp0, 'C'
    breq KeyIsClear

    ; ----- operators + - * / -----
    cpi Rtmp0, '+'
    breq KeyIsPlus
    cpi Rtmp0, '-'
    breq KeyIsMinus
    cpi Rtmp0, '*'
    breq KeyIsMul
    cpi Rtmp0, '/'
    breq KeyIsDiv

    ; ----- EQUAL (=) -----
    cpi Rtmp0, '='
    breq KeyIsEqual

    ; ----- DIGIT 0..9 ? -----
    cpi Rtmp0, '0'
    brlo NotDigit

    cpi Rtmp0, '9'+1
    brsh NotDigit

    ; It IS a digit
    rcall Handle_Digit
    rcall WaitKeyRelease
    rjmp MainLoop

; local labels fed by branches (short distance)
KeyIsClear:
    rjmp Handle_Clear

KeyIsPlus:
KeyIsMinus:
KeyIsMul:
KeyIsDiv:
    rjmp Handle_Operator        ; Rtmp0 already has '+','-','*','/'

KeyIsEqual:
    rjmp Handle_Equal

NotDigit:
    rcall WaitKeyRelease
    rjmp MainLoop

;===========================================
; CALCULATOR HANDLERS
;===========================================

;-------------------------------------------
; Clear key: reset and clear screen
;-------------------------------------------
Handle_Clear:
    rcall ClearLCD
    rcall ResetCalc
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; Generic operator handler for + - * /
; Rtmp0 contains the operator char
;-------------------------------------------
Handle_Operator:
    ; if result shown, start a new calculation
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne Op_NoRes
    rcall ClearLCD
    rcall ResetCalc

Op_NoRes:
    ; accept operator only right after OP1
    lds Rtmp1, STATE
    cpi Rtmp1, 0
    brne Op_Done         ; ignore if not in state 0

    sts OPER, Rtmp0      ; store '+','-','*','/'
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar    ; show operator

    ldi Rtmp1, 1         ; now entering second operand
    sts STATE, Rtmp1

Op_Done:
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; Digit key handler (multi-digit support)
; Rtmp0 = ASCII digit
;-------------------------------------------
Handle_Digit:
    ; if a result is currently shown, start fresh
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne HD_NoRes
    rcall ClearLCD
    rcall ResetCalc
HD_NoRes:
    mov Rtmp1, Rtmp0
    subi Rtmp1, '0'      ; Rtmp1 = digit 0..9

    ; check which operand is being edited
    lds Rtmp2, STATE
    cpi Rtmp2, 0
    brne HD_Op2

    ; ---- entering OP1 ----
    lds Rtmp2, OP1       ; Rtmp2 = OP1
    ; OP1 = OP1*10 + digit  (x10 = x*8 + x*2)
    mov Rtmp3, Rtmp2
    lsl Rtmp2            ; *2
    mov Rtmp3, Rtmp2
    lsl Rtmp2            ; *4
    lsl Rtmp2            ; *8
    add Rtmp2, Rtmp3     ; *10
    add Rtmp2, Rtmp1
    sts OP1, Rtmp2
    rjmp HD_Print

HD_Op2:
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

;-------------------------------------------
; '=' key pressed
;-------------------------------------------
Handle_Equal:
    ; echo '=' on first line
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar

    ; select operation based on OPER
    lds Rtmp1, OPER
    cpi Rtmp1, '+'
    breq Do_Add
    cpi Rtmp1, '-'
    breq Do_Sub
    cpi Rtmp1, '*'
    breq Do_Mul
    cpi Rtmp1, '/'
    breq Do_Div

    ; no valid operator -> ignore
    rcall WaitKeyRelease
    rjmp MainLoop

;------------ ADD : OP1 + OP2 -------------------
Do_Add:
    lds Rval, OP1
    lds Rtmp1, OP2
    add Rval, Rtmp1            ; 0..198
    clr Rtmp3                  ; sign flag = 0 (positive)
    rjmp Show_Result

;------------ SUB : OP1 - OP2 -------------------
Do_Sub:
    lds Rtmp1, OP1
    lds Rtmp2, OP2
    cp Rtmp1, Rtmp2
    brsh DS_Positive

    ; negative: VAL = OP2 - OP1, sign=1
    mov Rval, Rtmp2
    sub Rval, Rtmp1
    ldi Rtmp3, 1               ; negative
    rjmp Show_Result

DS_Positive:
    mov Rval, Rtmp1
    sub Rval, Rtmp2
    clr Rtmp3                  ; positive
    rjmp Show_Result

;------------ MUL : OP1 * OP2 -------------------
; Simple repeated addition, enough for 1-digit or small numbers
Do_Mul:
    lds Rtmp1, OP1             ; multiplicand
    lds Rtmp2, OP2             ; multiplier
    clr Rval                   ; result = 0

Mul_Loop:
    cpi Rtmp2, 0
    breq Mul_Done
    add Rval, Rtmp1
    dec Rtmp2
    rjmp Mul_Loop

Mul_Done:
    clr Rtmp3                  ; always positive
    rjmp Show_Result

;------------ DIV : OP1 / OP2 -------------------
; integer division (truncating); e.g. 7/3 = 2, 2/5 = 0
Do_Div:
    ; A = OP1 (dividend), B = OP2 (divisor)
    lds Rtmp1, OP1           ; A
    lds Rtmp2, OP2           ; B

    ; check divide by zero
    cpi Rtmp2, 0
    breq Div_By_Zero

    ;--------------------------------------
    ; 1) Integer part Q = A / B
    ;--------------------------------------
    clr Rval                 ; Q = 0
Div_IntLoop:
    cp  Rtmp1, Rtmp2
    brlo Div_IntDone
    sub Rtmp1, Rtmp2
    inc Rval
    rjmp Div_IntLoop
Div_IntDone:
    ; now:
    ;   Rval  = Q (integer part)
    ;   Rtmp1 = R (remainder)

    ;--------------------------------------
    ; Move cursor to second line
    ;--------------------------------------
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; print integer part Q (0..99 but in practice small)
    mov Rtmp3, Rval
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

    ; print decimal point '.'
    ldi Rtmp1, '.'
    rcall LCD_PutChar

    ;--------------------------------------
    ; 2) First decimal digit D1
    ;    D1 = floor( (R * 10) / B )
    ;    R1 = (R * 10) % B   (kept in RremHi:RremLo)
    ;--------------------------------------

    ; Rrem = R * 10 (16-bit) using repeated addition
    clr RremLo
    clr RremHi
    ldi Rdec1, 10           ; use Rdec1 as loop counter here
Mul10_D1_Loop:
    add RremLo, Rtmp1
    adc RremHi, Rzero ; __zero_reg__ = r1 is always 0 in AVR-GCC,
                              ; if not using GCC, replace with a real zero reg
    dec Rdec1
    brne Mul10_D1_Loop

    ; Now divide Rrem (16-bit) by B to get D1 and remainder
    clr Rdec1               ; Rdec1 will hold D1 (0..9)
DivDec1_Check:
    cpi RremHi, 0
    brne DivDec1_DoSub
    cp  RremLo, Rtmp2
    brlo DivDec1_Done

DivDec1_DoSub:
    sub RremLo, Rtmp2
    sbc RremHi, Rzero
    inc Rdec1
    rjmp DivDec1_Check

DivDec1_Done:
    ; Rdec1 = D1, RremHi:RremLo = R1

    ;--------------------------------------
    ; 3) Second decimal digit D2
    ;    D2 = floor( (R1 * 10) / B )
    ;--------------------------------------

    ; multiply R1 (16-bit) by 10: Rrem = R1 * 10
    mov Rtmp1, RremLo        ; copy R1 low
    mov Rtmp3, RremHi        ; copy R1 high
    clr RremLo
    clr RremHi
    ldi Rdec2, 10            ; loop counter for *10
Mul10_D2_Loop:
    add RremLo, Rtmp1
    adc RremHi, Rtmp3
    dec Rdec2
    brne Mul10_D2_Loop

    ; divide Rrem (16-bit) by B to get D2
    clr Rdec2               ; will hold D2
DivDec2_Check:
    cpi RremHi, 0
    brne DivDec2_DoSub
    cp  RremLo, Rtmp2
    brlo DivDec2_Done

DivDec2_DoSub:
    sub RremLo, Rtmp2
    sbc RremHi, Rzero
    inc Rdec2
    rjmp DivDec2_Check

DivDec2_Done:
    ; Rdec1 = first decimal digit
    ; Rdec2 = second decimal digit

    ;--------------------------------------
    ; 4) Print D1 and D2
    ;--------------------------------------
    mov Rtmp1, Rdec1
    ldi Rtmp0, '0'
    add Rtmp1, Rtmp0
    rcall LCD_PutChar        ; print first decimal

    mov Rtmp1, Rdec2
    ldi Rtmp0, '0'
    add Rtmp1, Rtmp0
    rcall LCD_PutChar        ; print second decimal

    ; mark result as shown
    ldi Rtmp1, 2
    sts STATE, Rtmp1

    rcall WaitKeyRelease
    rjmp MainLoop

;------------ DIVIDE BY ZERO : show "ERROR" -----
Div_By_Zero:
    ; go to second line
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; print "ERROR"
    ldi Rtmp1, 'E'
    rcall LCD_PutChar
    ldi Rtmp1, 'R'
    rcall LCD_PutChar
    ldi Rtmp1, 'R'
    rcall LCD_PutChar
    ldi Rtmp1, 'O'
    rcall LCD_PutChar
    ldi Rtmp1, 'R'
    rcall LCD_PutChar

    ; mark state as result shown
    ldi Rtmp1, 2
    sts STATE, Rtmp1

    rcall WaitKeyRelease
    rjmp MainLoop

;------------ Common result display -------------
; Rval contains magnitude (0..199)
; Rtmp3 = 0 positive, 1 negative (only used for subtraction)
Show_Result:
    ; move cursor to second line
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; print '-' if negative
    cpi Rtmp3, 1
    brne SR_NoMinus
    ldi Rtmp1, '-'
    rcall LCD_PutChar
SR_NoMinus:
    rcall Print_0_199          ; prints Rval

    ldi Rtmp1, 2
    sts STATE, Rtmp1           ; result shown

    rcall WaitKeyRelease
    rjmp MainLoop

;===========================================
; CALCULATOR UTILITIES
;===========================================

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

; Print Rval (0..199) as decimal (no leading zeros)
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

    ; if hundreds>0 -> print H T U
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
    ; if tens>0 -> print T U
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

    ; LCD control RS=PC1, E=PC0
    sbi DDRC, 0
    sbi DDRC, 1
    cbi PORTC,0
    cbi PORTC,1

    ; Keypad: PD0..PD3 rows out, PD4..PD7 in with pull-ups
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

; key mapping: ASCII in Rtmp0
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

; ? 50 µs simple loop (rough, depends on F_CPU)
Delay_us50:
    ldi Rdel0, 40
Du_Loop:
    dec Rdel0
    brne Du_Loop
    ret

; ? 20 ms by calling Delay_us50 many times
Delay_ms20:
    ldi Rdel1, 200
Dm_Loop:
    rcall Delay_us50
    dec Rdel1
    brne Dm_Loop
    ret


