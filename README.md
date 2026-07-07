# ATmega328P Assembly Calculator

## Overview

This project is a microcontroller-based calculator developed using **AVR Assembly** for the **ATmega328P** microcontroller.

The calculator supports basic arithmetic operations and uses a keypad for user input and a 16x2 LCD display for output. The project also includes Proteus simulation files, allowing the circuit and program behavior to be tested virtually.

## Features

* Built using AVR Assembly language
* Designed for the ATmega328P microcontroller
* Supports two-digit operands
* Supports addition, subtraction, multiplication, and division
* Displays input and results on a 16x2 LCD
* Uses keypad input for numbers and operators
* Handles negative subtraction results
* Supports multiplication results up to 99 × 99
* Displays division results with two decimal digits
* Includes Proteus simulation files
* Includes compiled HEX output for simulation or flashing

## Supported Operations

The calculator supports the following arithmetic operations:

| Operation      | Symbol |
| -------------- | ------ |
| Addition       | `+`    |
| Subtraction    | `-`    |
| Multiplication | `*`    |
| Division       | `/`    |
| Clear          | `C`    |
| Equal          | `=`    |

## Hardware Components

The project is designed around the following components:

* ATmega328P microcontroller
* 16x2 LCD display
* Matrix keypad
* LED indicator
* Supporting resistors and wiring
* Proteus simulation circuit

## Software and Tools

The project uses:

* AVR Assembly
* Atmel Studio / Microchip Studio
* Proteus Design Suite
* ATmega328P device definition file
* HEX file generated from the assembly code

## Project Structure

```text
micro-project/
├── AssemblerApplication7/
│   └── AssemblerApplication7/
│       ├── main.asm
│       ├── AssemblerApplication7.asmproj
│       └── Debug/
│           ├── AssemblerApplication7.hex
│           ├── AssemblerApplication7.lss
│           ├── AssemblerApplication7.map
│           └── AssemblerApplication7.obj
├── calcul.pdsprj
├── Backup Of calcul.pdsbak
├── Last Loaded calcul.pdsbak
└── screenshots
```

## How It Works

The calculator works by reading keypad input, storing the first operand, detecting the selected operator, storing the second operand, and then calculating the result when the equal key is pressed.

The program uses SRAM variables to store:

* First operand
* Second operand
* Current calculator state
* Selected operator

The result is displayed on the LCD.

## LCD and Keypad

The LCD is used in 8-bit mode and displays both the entered expression and the final result.

The keypad is used to enter digits, select arithmetic operations, clear the calculator, and calculate the result.

## Arithmetic Logic

### Addition

The program loads both operands and adds them directly.

### Subtraction

The program compares both operands and supports negative results when the second operand is greater than the first.

### Multiplication

The program uses the AVR hardware `MUL` instruction to multiply two 8-bit operands. It supports results up to:

```text
99 × 99 = 9801
```

### Division

The division routine supports displaying the result with two decimal digits.

## Simulation

The project includes Proteus files that can be used to simulate the calculator circuit.

To run the simulation:

1. Open `calcul.pdsprj` in Proteus.
2. Load the compiled HEX file if needed.
3. Run the simulation.
4. Use the keypad to enter calculations.
5. View the result on the LCD.

## How to Build

To build the assembly project:

1. Open the project in Atmel Studio or Microchip Studio.
2. Select the ATmega328P device.
3. Open `main.asm`.
4. Build the project.
5. Use the generated `.hex` file for Proteus simulation or microcontroller programming.

## Educational Value

This project demonstrates important embedded systems concepts, including:

* AVR Assembly programming
* Register-level programming
* SRAM variable handling
* LCD interfacing
* Keypad scanning
* Arithmetic operations in assembly
* Program state management
* Microcontroller simulation using Proteus
* HEX file generation and testing

## Conclusion

This project provides a practical example of building a calculator using low-level AVR Assembly programming. It combines microcontroller architecture, digital input handling, LCD output, arithmetic logic, and circuit simulation.

The project is useful for students learning embedded systems, microcontroller programming, and assembly language fundamentals.
