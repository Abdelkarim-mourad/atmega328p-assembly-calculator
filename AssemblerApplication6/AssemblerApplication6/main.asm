;===========================================
; ATmega328P – 2-digit calculator
; +  -  *  /  (division with 2 decimals)
; LCD 8-bit on PORTB, keypad on PORTD
; LM016L 16x2
;===========================================

.include "m328pdef.inc"

;-------------------------------------------
; Data section (SRAM variables)
;-------------------------------------------
.dseg
OP1:    .byte 1      ; first operand  (0..99)
OP2:    .byte 1      ; second operand (0..99)
STATE:  .byte 1      ; 0=enter OP1, 1=enter OP2, 2=result shown
OPER:   .byte 1      ; '+', '-', '*', '/'

;-------------------------------------------
; Code section
;-------------------------------------------
.cseg
.org 0x0000
    jmp RESET        ; absolute jump, safe range

;-------------------------------------------
; Register aliases
;-------------------------------------------
.def Rzero  = r15    ; constant 0 (we keep it cleared)
.def Rtmp0  = r16
.def Rtmp1  = r17
.def Rtmp2  = r18
.def Rtmp3  = r19
.def Rval   = r20    ; result / generic
.def Rdel0  = r21    ; delay counter
.def Rdel1  = r22    ; delay counter
.def RremLo = r23    ; 16-bit remainder/working (low)
.def RremHi = r24    ; 16-bit remainder/working (high)
.def Rdec1 = r30     ; SAFE
.def Rdec2 = r31     ; SAFE

;-------------------------------------------
; RESET
;-------------------------------------------
RESET:
    ; init stack
    ldi Rtmp0, HIGH(RAMEND)
    out SPH, Rtmp0
    ldi Rtmp0, LOW(RAMEND)
    out SPL, Rtmp0

    clr Rzero          ; make sure Rzero really is 0
	clr r30
    clr r31

    rcall Init_Ports
    rcall Delay_ms20
    rcall Init_LCD

    rcall ClearLCD
    rcall ResetCalc

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

KeyIsClear:
    rjmp Handle_Clear

KeyIsPlus:
KeyIsMinus:
KeyIsMul:
KeyIsDiv:
    rjmp Handle_Operator        ; Rtmp0 has '+','-','*','/'

KeyIsEqual:
    rjmp Handle_Equal

NotDigit:
    rcall WaitKeyRelease
    rjmp MainLoop

;===========================================
; CALCULATOR HANDLERS
;===========================================

;-------------------------------------------
; Clear key handler
;-------------------------------------------
Handle_Clear:
    rcall ClearLCD
    rcall ResetCalc
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; Generic operator handler (+ - * /)
; Rtmp0 contains operator character
;-------------------------------------------
Handle_Operator:
    ; if result already shown, start new calc
    lds Rtmp1, STATE
    cpi Rtmp1, 2
    brne Op_NoRes
    rcall ClearLCD
    rcall ResetCalc
Op_NoRes:
    ; only accept operator when entering OP1
    lds Rtmp1, STATE
    cpi Rtmp1, 0
    brne Op_Done           ; ignore if not state 0

    sts OPER, Rtmp0        ; store '+','-','*','/'
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar      ; show operator

    ldi Rtmp1, 1           ; now entering OP2
    sts STATE, Rtmp1

Op_Done:
    rcall WaitKeyRelease
    rjmp MainLoop

;-------------------------------------------
; Digit handler (multi-digit)
; Rtmp0 = ASCII digit
;-------------------------------------------
Handle_Digit:
    ; if result shown, clear and restart
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
    brne HD_Op2

    ; ---- entering OP1 ----
    lds Rtmp2, OP1         ; Rtmp2 = OP1
    mov Rtmp3, Rtmp2
    lsl Rtmp2              ; *2
    mov Rtmp3, Rtmp2
    lsl Rtmp2              ; *4
    lsl Rtmp2              ; *8
    add Rtmp2, Rtmp3       ; *10
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
; '=' pressed
;-------------------------------------------
Handle_Equal:
    ; echo '=' on line 1
    mov Rtmp1, Rtmp0
    rcall LCD_PutChar

    ; choose operator
    lds Rtmp1, OPER
    cpi Rtmp1, '+'
    breq Do_Add
    cpi Rtmp1, '-'
    breq Do_Sub
    cpi Rtmp1, '*'
    breq Do_Mul
    cpi Rtmp1, '/'
    breq Do_Div

    ; no valid operator
    rcall WaitKeyRelease
    rjmp MainLoop

;------------ ADD : OP1 + OP2 -------------------
Do_Add:
    lds Rval, OP1
    lds Rtmp1, OP2
    add Rval, Rtmp1        ; 0..198
    clr Rtmp3              ; sign = positive
    rjmp Show_Result

;------------ SUB : OP1 - OP2 -------------------
Do_Sub:
    lds Rtmp1, OP1
    lds Rtmp2, OP2
    cp  Rtmp1, Rtmp2
    brsh DS_Positive

    ; negative result
    mov Rval, Rtmp2
    sub Rval, Rtmp1
    ldi Rtmp3, 1           ; sign = negative
    rjmp Show_Result

DS_Positive:
    mov Rval, Rtmp1
    sub Rval, Rtmp2
    clr Rtmp3              ; sign = positive
    rjmp Show_Result

;------------ MUL : OP1 * OP2 -------------------
; simple repeated addition (OK for 1-digit operands)
Do_Mul:
    lds Rtmp1, OP1         ; multiplicand
    lds Rtmp2, OP2         ; multiplier
    clr Rval               ; result = 0
Mul_Loop:
    cpi Rtmp2, 0
    breq Mul_Done
    add Rval, Rtmp1
    dec Rtmp2
    rjmp Mul_Loop
Mul_Done:
    clr Rtmp3              ; positive
    rjmp Show_Result

;------------ DIV : OP1 / OP2 (2 decimal digits) -------------------
; Result: Q.D1D2   (e.g. 7/6=1.16, 7/3=2.33)
;------------ DIV : OP1 / OP2  (2 decimal digits) -------------
; Result format:  Q.D1D2
; Uses: Rtmp0..Rtmp3, Rval, RremLo/Hi, Rdec1, Rdec2, Rzero

;------------------------------------------------------
; Do_Div : OP1 / OP2  ->  Q.D1D2  (two decimal digits)
; Uses: Rtmp0..Rtmp3, Rval, RremLo/Hi, Rdec1, Rdec2, Rzero
;------------------------------------------------------
;------------------------------------------------------
; Do_Div : OP1 / OP2  ->  Q.D1D2  (two decimal digits)
; FIXED VERSION - preserves divisor properly
;------------------------------------------------------
Do_Div:
    ; Load operands
    lds Rtmp1, OP1          ; A = dividend
    lds Rtmp2, OP2          ; B = divisor

    ; Divide by zero ?
    cpi Rtmp2, 0
    breq Div_By_Zero

    ; ***** SAVE DIVISOR BEFORE IT GETS DESTROYED *****
    mov r25, Rtmp2          ; Save divisor in r25 (unused register)

    ;--------------------------------------
    ; 1) Integer part Q and remainder R
    ;--------------------------------------
    clr Rval                ; Q = 0
    mov RremLo, Rtmp1       ; R = A
    clr RremHi

Div_IntLoop:
    cp  RremLo, Rtmp2
    brlo Div_IntDone
    sub RremLo, Rtmp2
    inc Rval
    rjmp Div_IntLoop
Div_IntDone:
    ; Now: Q in Rval, remainder R in RremLo (RremHi = 0)

    ;--------------------------------------
    ; Move cursor to 2nd line and print Q
    ;--------------------------------------
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; Print integer part Q (Rval) - this destroys Rtmp0-Rtmp3
    rcall Print_0_199

    ; Print decimal point '.'
    ldi Rtmp1, '.'
    rcall LCD_PutChar

    ; ***** RESTORE DIVISOR *****
    mov Rtmp2, r25          ; Restore divisor from r25

    ;--------------------------------------
    ; 2) First decimal digit D1
    ;    D1 = floor( (R * 10) / B )
    ;--------------------------------------
    mov Rtmp3, RremLo       ; save R (8-bit)
    clr RremLo
    clr RremHi
    ldi Rtmp0, 10           ; loop counter for *10
D1_Mul10:
    add RremLo, Rtmp3
    adc RremHi, Rzero
    dec Rtmp0
    brne D1_Mul10

    ; Divide 16-bit Rrem by B ? D1 in Rdec1
    clr Rdec1               ; D1 = 0
D1_DivLoop:
    tst RremHi
    brne D1_DoSub
    cp  RremLo, Rtmp2
    brlo D1_Done
D1_DoSub:
    sub RremLo, Rtmp2
    sbc RremHi, Rzero
    inc Rdec1
    rjmp D1_DivLoop
D1_Done:
    ; Rdec1 = D1, remainder1 in RremHi:RremLo

    ;--------------------------------------
    ; 3) Second decimal digit D2
    ;    D2 = floor( (R1 * 10) / B )
    ;--------------------------------------
    mov Rtmp3, RremLo       ; R1 low
    mov Rtmp1, RremHi       ; R1 high
    clr RremLo
    clr RremHi
    ldi Rtmp0, 10           ; loop counter for *10
D2_Mul10:
    add RremLo, Rtmp3
    adc RremHi, Rtmp1
    dec Rtmp0
    brne D2_Mul10

    clr Rdec2               ; D2 = 0
D2_DivLoop:
    tst RremHi
    brne D2_DoSub
    cp  RremLo, Rtmp2
    brlo D2_Done
D2_DoSub:
    sub RremLo, Rtmp2
    sbc RremHi, Rzero
    inc Rdec2
    rjmp D2_DivLoop
D2_Done:
    ; Rdec1 = first decimal digit, Rdec2 = second

    ;--------------------------------------
    ; 4) Print D1 and D2
    ;--------------------------------------
    mov Rtmp1, Rdec1
    ldi Rtmp0, '0'
    add Rtmp1, Rtmp0
    rcall LCD_PutChar       ; print first decimal digit

    mov Rtmp1, Rdec2
    ldi Rtmp0, '0'
    add Rtmp1, Rtmp0
    rcall LCD_PutChar       ; print second decimal digit

    ; Mark result as shown
    ldi Rtmp1, 2
    sts STATE, Rtmp1

    rcall WaitKeyRelease
    rjmp MainLoop


;------------ DIVIDE BY ZERO : show "ERROR" ----
Div_By_Zero:
    ldi Rtmp0, 0xC0
    rcall LCD_Command

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

    ldi Rtmp1, 2
    sts STATE, Rtmp1

    rcall WaitKeyRelease
    rjmp MainLoop

;------------ Common integer result print -------
; Used by +, -, * only
Show_Result:
    ; move cursor to second line
    ldi Rtmp0, 0xC0
    rcall LCD_Command

    ; print sign if negative
    cpi Rtmp3, 1
    brne SR_NoMinus
    ldi Rtmp1, '-'
    rcall LCD_PutChar
SR_NoMinus:
    rcall Print_0_199      ; print Rval (0..199)

    ldi Rtmp1, 2
    sts STATE, Rtmp1

    rcall WaitKeyRelease
    rjmp MainLoop

;===========================================
; CALC UTILS
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
    ; use Rtmp0..Rtmp3
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

    ; hundreds
    cpi Rtmp1, 0
    breq P_NoHund
    mov Rtmp3, Rtmp1
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

    ; tens
    mov Rtmp3, Rtmp2
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar

    ; ones
    mov Rtmp3, Rval
    ldi Rtmp0, '0'
    add Rtmp3, Rtmp0
    mov Rtmp1, Rtmp3
    rcall LCD_PutChar
    ret

P_NoHund:
    ; tens?
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

    ; Keypad rows PD0..PD3 out, cols PD4..PD7 in w/ pull-ups
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

; Key mapping: ASCII in Rtmp0
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
    ldi Rtmp0, 0b11110000       ; rows low, cols pull-up
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

; ~50 µs (approx)
Delay_us50:
    ldi Rdel0, 40
Du_Loop:
    dec Rdel0
    brne Du_Loop
    ret

; ~20 ms (approx)
Delay_ms20:
    ldi Rdel1, 200
Dm_Loop:
    rcall Delay_us50
    dec Rdel1
    brne Dm_Loop
    ret

