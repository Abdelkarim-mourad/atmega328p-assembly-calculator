;====================================================================
; Simple Calculator for ATmega328P
; Add and Subtract numbers 0-99 with negative result support
; Based on your LCD configuration
;====================================================================

.ORG 0X00

MSG_Ready:
    .db 'C','a','l','c',' ','R','e','a','d','y',0

;====================================================================
; Register Definitions
;====================================================================
.def temp = r16
.def num1 = r17          ; First number
.def num2 = r18          ; Second number
.def result = r19        ; Result
.def operation = r20     ; '+' or '-'
.def digit_count = r21   ; Digit counter
.def keypress = r22      ; Current key
.def neg_flag = r23      ; Negative flag

;====================================================================
; Main Program
;====================================================================
Main:
    LDI R16, HIGH(RAMEND)
    OUT SPH, R16    
    LDI R16, LOW(RAMEND)
    OUT SPL, R16
    
    CALL Delay_18ms         ; Wait for LCD to Power On
    CALL Init_ports         ; Initialize Ports
    CALL Init_LCD           ; Initialize LCD

Main_Loop:
    ; Initialize variables
    CLR num1
    CLR num2
    CLR result
    CLR operation
    CLR digit_count
    CLR neg_flag
    
    ; Get first number
    CALL Get_Number
    MOV num1, result
    
    ; operation is already in keypress from Get_Number
    MOV operation, keypress
    
    ; Display operation
    MOV R16, operation
    CALL SEND_char
    
    ; Wait for key release
    CALL Wait_Key_Release
    
    ; Get second number
    CALL Get_Number
    MOV num2, result
    
    ; Display '='
    LDI R16, '='
    CALL SEND_char
    
    ; Calculate
    CALL Calculate
    
    ; Display result
    CALL Display_Result
    
    ; Wait before next calculation
    CALL Delay_3s
    CALL Init_LCD
    
    RJMP Main_Loop

;====================================================================
; Initialize Ports
;====================================================================
Init_ports:
    LDI R16, 0XFF
    OUT DDRD, R16           ; LCD data (D0-D7)
    
    ; LCD control pins
    SBI DDRC, 0             ; E
    SBI DDRC, 1             ; RS
    CBI DDRC, 2             ; RW = 0 (write mode)
    
    ; Keypad setup - Based on schematic
    ; Rows r1-r4 connected to PD0-PD3 (shared with LCD D0-D3)
    ; Columns c1-c4 connected to PB0-PB3 as inputs with pull-ups
    LDI R16, 0x00
    OUT DDRB, R16           ; PB0-PB3 as inputs (columns)
    LDI R16, 0x0F
    OUT PORTB, R16          ; Enable pull-ups on PB0-PB3
    
    RET

;====================================================================
; LCD Functions (from your code)
;====================================================================
Init_LCD:
    LDI R16, 0X01           ; Clear display screen
    CALL SEND_cmd
    LDI R16, 0X38           ; 2 lines and 5×7 matrix
    CALL SEND_cmd 
    LDI R16, 0X0C           ; Display on, cursor off
    CALL SEND_cmd
    RET

SEND_cmd:
    OUT PORTD, R16
    CBI PORTC, 1            ; RS=0
    SBI PORTC, 0            ; E=1
    CBI PORTC, 0            ; E=0
    CALL Delay_50us
    CALL Delay_50us
    RET

SEND_char:
    OUT PORTD, R16
    SBI PORTC, 1            ; RS=1
    SBI PORTC, 0            ; E=1
    CBI PORTC, 0            ; E=0
    CALL Delay_50us
    CALL Delay_50us
    RET

Print_String:
PS_Loop:
    LPM R16, Z+
    CPI R16, 0
    BREQ PS_Done
    CALL SEND_char
    RJMP PS_Loop
PS_Done:
    RET

;====================================================================
; Get Number from Keypad (0-99)
;====================================================================
Get_Number:
    CLR result
    CLR digit_count

GN_Loop:
    CALL Keypad_Scan
    CPI keypress, 0xFF
    BREQ GN_Loop

    ; Check if it's a digit (0-9)
    CPI keypress, '0'
    BRLO GN_Check_Op
    CPI keypress, ':'       ; '9' + 1
    BRSH GN_Check_Op

    ; It's a digit - display it
    MOV R16, keypress
    CALL SEND_char
    
    ; Convert ASCII to number
    MOV temp, keypress
    SUBI temp, '0'

    ; result = result * 10 + digit
    MOV R24, result
    LDI R25, 10
    MUL R24, R25
    MOV result, R0
    ADD result, temp

    INC digit_count
    CPI digit_count, 2
    BRSH GN_Wait_Op

    ; Wait for key release
    CALL Wait_Key_Release
    RJMP GN_Loop

GN_Wait_Op:
    ; Already have 2 digits, wait for operation key
    CALL Wait_Key_Release
    RJMP GN_Op_Loop

GN_Check_Op:
    ; Check if operation key pressed
    CPI keypress, '+'
    BREQ GN_Done
    CPI keypress, '-'
    BREQ GN_Done
    CPI keypress, '='
    BREQ GN_Done
    RJMP GN_Loop

GN_Op_Loop:
    ; Wait for operation key after 2 digits entered
    CALL Keypad_Scan
    CPI keypress, 0xFF
    BREQ GN_Op_Loop
    
    CPI keypress, '+'
    BREQ GN_Done
    CPI keypress, '-'
    BREQ GN_Done
    CPI keypress, '='
    BREQ GN_Done
    RJMP GN_Op_Loop

GN_Done:
    RET

;====================================================================
; Calculate Result
;====================================================================
Calculate:
    CLR neg_flag
    CPI operation, '+'
    BREQ Do_Add
    CPI operation, '-'
    BREQ Do_Sub
    RET

Do_Add:
    MOV result, num1
    ADD result, num2
    RET

Do_Sub:
    MOV result, num1
    CP result, num2
    BRSH Sub_Positive
    
    ; Result will be negative
    LDI neg_flag, 1
    MOV result, num2
    SUB result, num1
    RET

Sub_Positive:
    SUB result, num2
    RET

;====================================================================
; Display Result
;====================================================================
Display_Result:
    ; Check if negative
    CPI neg_flag, 1
    BRNE DR_Positive
    LDI R16, '-'
    CALL SEND_char

DR_Positive:
    ; Convert to ASCII (reuse your conversion code)
    MOV R16, result
    
    ; HEX to BCD
    CLR R17
HEX_BCD_Loop:
    SUBI R16, 10
    BRCS HEX_BCD_Done
    INC R17
    RJMP HEX_BCD_Loop
HEX_BCD_Done:
    SUBI R16, -10
    SWAP R17
    OR R16, R17

    ; BCD to ASCII
    LDI R17, 0X30
    MOV R1, R16
    
    ; Tens digit
    ANDI R16, 0XF0
    LSR R16
    LSR R16
    LSR R16
    LSR R16
    ADD R16, R17
    MOV R26, R16
    
    ; Ones digit
    MOV R16, R1
    ANDI R16, 0X0F
    ADD R16, R17
    MOV R27, R16
    
    ; Display
    MOV R16, R26
    CALL SEND_char
    MOV R16, R27
    CALL SEND_char
    
    RET

;====================================================================
; Keypad Functions
;====================================================================
Keypad_Scan:
    PUSH R24
    PUSH R25
    LDI R24, 0              ; Row counter
    LDI keypress, 0xFF      ; No key

KS_Row_Loop:
    CPI R24, 4
    BREQ KS_Done

    ; Save current PORTD state
    IN R16, PORTD
    PUSH R16
    
    ; Set all row bits high first
    ORI R16, 0x0F
    OUT PORTD, R16
    
    ; Set current row low
    LDI R16, 0xFE
    MOV R25, R24
KS_Rotate:
    CPI R25, 0
    BREQ KS_Apply
    ROL R16
    DEC R25
    RJMP KS_Rotate

KS_Apply:
    ; Apply row pattern to lower 4 bits of PORTD
    POP R25                 ; Get saved PORTD
    ANDI R25, 0xF0          ; Keep upper bits
    ANDI R16, 0x0F          ; Keep lower bits
    OR R16, R25             ; Combine
    OUT PORTD, R16
    
    CALL Delay_50us

    ; Read columns from PINB (PB0-PB3)
    IN R16, PINB
    ANDI R16, 0x0F          ; Mask PB0-PB3
    CPI R16, 0x0F           ; All high?
    BREQ KS_Next_Row

    ; Key found - check which column
    LDI R25, 0
KS_Col_Loop:
    CPI R25, 4
    BREQ KS_Next_Row
    
    ; Check column bit
    LDI R16, 1              ; Start with PB0
    MOV R26, R25
KS_Col_Shift:
    CPI R26, 0
    BREQ KS_Col_Check
    LSL R16
    DEC R26
    RJMP KS_Col_Shift

KS_Col_Check:
    IN R26, PINB
    AND R26, R16
    BRNE KS_Next_Col
    
    ; Key found at row R24, col R25
    CALL Get_Key_Char
    RJMP KS_Done

KS_Next_Col:
    INC R25
    RJMP KS_Col_Loop

KS_Next_Row:
    INC R24
    RJMP KS_Row_Loop

KS_Done:
    POP R25
    POP R24
    RET

Get_Key_Char:
    ; Map row/col to character
    ; Keypad layout:
    ; 7 8 9 /
    ; 4 5 6 *
    ; 1 2 3 -
    ; % 0 = +
    
    LDI ZH, HIGH(2*KEYMAP)
    LDI ZL, LOW(2*KEYMAP)
    
    ; Offset = row * 4 + col
    MOV R16, R24
    LSL R16
    LSL R16
    ADD R16, R25
    
    ADD ZL, R16
    LDI R16, 0
    ADC ZH, R16
    
    LPM keypress, Z
    RET

KEYMAP:
    .db '7', '8', '9', '/'
    .db '4', '5', '6', '*'
    .db '1', '2', '3', '-'
    .db '%', '0', '=', '+'

Wait_Key_Release:
WKR_Loop:
    ; Save and restore PORTD for LCD
    IN R16, PORTD
    PUSH R16
    ORI R16, 0x0F           ; Set all rows high
    OUT PORTD, R16
    CALL Delay_50us
    IN R16, PINB
    ANDI R16, 0x0F
    POP R25
    OUT PORTD, R25          ; Restore PORTD
    CPI R16, 0x0F
    BRNE WKR_Loop
    RET

;====================================================================
; Delay Functions (from your code)
;====================================================================
Delay_18ms:
    LDI R24, 0XEE
    STS TCNT1H, R24
    LDI R24, 0X6C
    STS TCNT1L, R24
    LDI R24, 0
    STS TCCR1A, R24
    LDI R24, 3
    STS TCCR1B, R24
again18ms:
    SBIS TIFR1, TOV1
    RJMP again18ms
    LDI R24, 0
    STS TCCR1B, R24
    LDI R24, 1
    OUT TIFR1, R24
    RET

Delay_50us:
    LDI R24, 0XFF
    STS TCNT1H, R24
    LDI R24, 0XF3
    STS TCNT1L, R24
    LDI R24, 0
    STS TCCR1A, R24
    LDI R24, 3
    STS TCCR1B, R24
again50us:
    SBIS TIFR1, TOV1
    RJMP again50us
    LDI R24, 0
    STS TCCR1B, R24
    LDI R24, 3
    OUT TIFR1, R24
    RET

Delay_3s:
    LDI R24, 0X38
    STS TCNT1H, R24
    LDI R24, 0XAF
    STS TCNT1L, R24
    LDI R24, 0
    STS TCCR1A, R24
    LDI R24, 5
    STS TCCR1B, R24
again3s:
    SBIS TIFR1, TOV1
    RJMP again3s
    LDI R24, 0
    STS TCCR1B, R24
    LDI R24, 3
    OUT TIFR1, R24
    RET
