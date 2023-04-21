# CESIL
An interpreter for an extended CESIL on the BBC Microcomputer.
## Introduction
This was my O-level computer studies project from 1985, to implement an
interpreter for the computer language CESIL on the BBC Microcomputer.  CESIL
is a lanugage instroduced by ICL in 1974 to teach low-level computer
programming.  In its original form it was not an interactive language but
this version makes it interactive in a similar way to the BASIC interepeter
on the BBC Micro, and many other computers of the time, with lines being added
by preceding each with a line number.  The INPUT instruction also takes input
from the keyboard.  This version also adds new instructions specific to the
BBC Micro.

The code in this respository, at least as of the initial commit, is a 2023
disassembly of an executable file found on an floppy from 1985.

## Assembling the Source Code
The source code is in the single file cesil.asm.  It is in Lancaster/ADE
syntax and can be assembled on a BBC Micro using a native assembler.  Either
ADE, ADE+ or the free Lancaster 65C02 aseembler can be used for this.

The provided Makefile will attempt to cross-assemble the code using a
cross assembler called LaXasm which is designed to assemble a common subset
of the ADE/Lancaster syntax.  This can be found at
https://github.com/SteveFosdick/laxasm

Once the code is assembled the file will need to be transferred to either
a BBC Micro or used in an emulator.  For the latter you may be able to use
the file directly (for example with VDFS under B-Em) or you may need to
build it into a disc image.  Various tool are available for this including
Steve Harris's tools: https://sweh.spuddy.org/Beeb/mmb_utils.html,
Some tools I have written: https://github.com/SteveFosdick/AcornFsUtils
and some graphical disc image managers.

## Running the Examples
The examples directory contains two example programs.  These are in text
form so once transferred or made available in the emulator you will need
to start the CESIL interpreter with *CESIL and then *EXEC the example
program.

## Editing programs
Programs can be entered interactively in much the same way as BBC BASIC.
Once the interpreter is started it will prompt in a similar way to BASIC
but with the ampersand as the prompt, for example:
```
EXTENDED CESIL

&
```
Just as with BASIC, if you enter a line of text with a number at the beginning
it will be entered into the program in memory, replacing any line with the same
number.  To enable lines to be interted between existing lines it is wise to
start with a gap between line numbers, for example by numbering in tens as there
is no renumber command.

If you enter a line with no line number it is taken as an instruction and
executed immediately.  Useful immediate instructions are `LIST`, to list the
program to the screen, `PUTFILE` to save the program to a file, `GETFILE` to load
a program from a file, `EXECUTE` to run the program, `NEW` to start a new program,
and `OLD` to restore an old program after hitting the Break key.  All of these
can be entered in abbreviated form, in a similar way to BBC BASIC keywords,
by typing a few characters and then a full stop, for example:
```
EXEC.
```
The `GETFILE` and `PUTFILE` instructions take the filename as a quoted string
just like the BASIC `LOAD` and `SAVE` commands.

## CESIL BASICS
CESIL is based around an accumulator.  This can be loaded from a memory location
with, for example:
```
LOAD c
```
where c is a symbolic name for a memory location (variable) and can be stored into
a memory location with, for example:
```
STORE h
```
Arithmetic operations use the accumulator for one operand and the other one is
either a memory location, for example:
```
ADD d
```
or an immediate value, for example:
```
DIV. 2
```
The arithmetic and logic instructions available are: `AND`, `ADD`, `COMPARE`,
`DIVIDE`, `MULTIPLY` and `SUBTRACT`.

The `INPUT` instruction accepts a value from the keyboard into the accumulator
while the `OUTPUT` instruction will print the contents of the accumulator.  Text
strings may be printed with the PRINT instrction, for example:
```
PRINT "The quick brown fox"
```
and the `LINE` instruction starts a new line.
## Flow Control
Flow control is achieved with the unconditional jump instruction `JUMP` and the
conditional jumps `JIZ` (jump if zero) and `JIN` (jump if negative) which work
on the current value of the accumulator.  To set flags for JIZ and JIN without
changing the accumulator, use the `COMPARE` instruction.

The destination of a jump instruction is a label.  These are entered on a line
after the line number and before the instruction and therefore cannot be the
same word as an instruction.  For example:
```
470 PRINT "Your choice ? "
480filoop GETCHR
490 COMPARE 49
500 JIZ fchoice
...
580fchoice VDU
590 LINE
```
so the `JIZ` on line 500 goes forward to the label on line 580.  There are no
subroutines and no high level loops - these need to be done with compares and
conditional jumps.
## Extensions
This version includes some extensions.  There are two additional registers
as well as the accumulator and, as on the 6502 in the BBC Micro, these are
called `X` and `Y`.  Values can be transferred into or out of these with the
`TRANSFER` instruction, for example:
```
TRANSFER ax
```
Extra keywords for the BBC micro include: `ADVAL`, `BGET`, `BPUT`, `CALL`,
`COLOUR`, `CLOSE`, `CLS`, `CLG`, `CHAIN`, `GETCHR`, `GETLINE`, `MODE`,
`OPENIN`, `OPENOUT`, `OPENUP`, `OSCLI`, `VDU`.

The majroity of these act on the value in the accumulator in the usual way.
The file opening instructions take the filename as a string and return
the file handle in Y.  The instructions for reading and writing to a file
expect the file handle in Y, as does the `CLOSE` instruction.
