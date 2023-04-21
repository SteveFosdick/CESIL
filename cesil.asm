;;; A CESIL interpreter for the BBC Micro.
;;;
;;; CESIL is a language invented by ICL in the UK to teach the
;;; concepts of low-level programming of computers.
;;;
;;; This intrepreter was an O-level computer studies project wirtten
;;; in 1984 which implements an extended version of the language on
;;; the BBC Microcomputer.
;;;
;;; This assembler source was reconstructed by disassembly in 2023
;;; from object code found on an old floppy disk.  It is intended to
;;; assembled by either ADE, ADE+, the Lancaster assembler (all native)
;;; or the laxasm cross-assembler.

                ;; Operating System Interface

brkv            EQU     $0202

gsinit          EQU     $FFC2
gsread          EQU     $FFC5
osfind          EQU     $FFCE
osbput          EQU     $FFD4
osbget          EQU     $FFD7
osfile          EQU     $FFDD
osrdch          EQU     $FFE0
osasci          EQU     $FFE3
osnewl          EQU     $FFE7
oswrch          EQU     $FFEE
osword          EQU     $FFF1
osbyte          EQU     $FFF4
oscli           EQU     $FFF7

                ;; Zero page workspace.

                DSECT
page            DS      1
top             DS      2
himem           DS      2
lineno          DS      2
linelen         DS      1
flags           DS      1
flags2          DS      1
cesil_off       DS      1
cesil_pc        DS      2
                ORG     $20
ptr1            DS      2
ptr2            DS      2
                ORG     $2A
iwa             DS      4
cesil_acc       DS      4
cesil_x         DS      4
cesil_y         DS      4
                DEND

                ;; Main language workspace.

varbase         EQU     $0400
stracc          EQU     $0500
strbuf          EQU     $0600
tokbuf          EQU     $0700

                ORG     $1900

                ;; Tokenise the line in strbuf leaving the result
                ;; in tokbuf.  If the line is preceded by a line
                ;; number this is left in lineno and bit 7 of flags set.

tokenise:       LDX     #$FF
                LDY     #$00
                STY     $3A
                STY     flags
tokn_nextch:    INX
tokn_thisch:    LDA     strbuf,X
                CMP     #'0'
                BCC     tokn_symbol     ; symbols.
                CMP     #'9'+1
                BCS     tokn_gtnine     ; not a number
tokn_number:    JSR     dec_to_bin
                BCS     tokn_badnum
                LDA     flags           ; start of line?
                BMI     tokn_store_num
                LDA     $3A
                BNE     tokn_store_num
                LDA     iwa             ; take number as line number.
                STA     lineno
                LDA     iwa+1
                BMI     tokn_invreg
                STA     lineno+1
                LDA     iwa+2           ; check not out of range.
                ORA     iwa+3
                BNE     tokn_badnum
                LDA     flags
                ORA     #$80            ; note line number seen.
                STA     flags
                JMP     tokn_thisch
tokn_badnum:    BIT     $3C
                BMI     tokn_numrange+1
tokn_numrange:  JMP     err_numrange
                JMP     err_eof
tokn_invreg:    JMP     err_invreg
tokn_store_num: LDA     #$80            ; Store a number token...
                JSR     tokn_store_tok
                LDA     iwa             ; followed by the bytes of
                JSR     tokn_store_tok  ; the number (4 bytes).
                LDA     iwa+1
                JSR     tokn_store_tok
                LDA     iwa+2
                JSR     tokn_store_tok
                LDA     iwa+3
                JSR     tokn_store_tok
                JMP     tokn_thisch
tokn_gtnine:    CMP     #'A'            ; Letter?
                BCC     tokn_symbol
                CMP     #'W'
                BCC     tokn_word
                CMP     #'a'
                BCC     tokn_symbol
                CMP     #'w'
                BCC     tokn_word
tokn_symbol:    CMP     #'+'
                BEQ     tokn_number
                CMP     #'-'
                BEQ     tokn_number
                CMP     #'*'
                BEQ     tokn_star
                CMP     #'?'
                BNE     tokn_notq
                LDA     #$DB            ; Subsitute PRINT token for '?'
tokn_notq:      CMP     #' '
                BNE     tokn_notspc
                JMP     tokn_nextch
tokn_notspc:    JSR     tokn_store_tok
                CMP     #'"'
                BEQ     tokn_quote
                CMP     #$0D
                BEQ     tokn_done
                JMP     tokn_nextch
tokn_done:      RTS
tokn_quote:     INX
                LDA     strbuf,X
                CMP     #$0D
                BEQ     tokn_qeol
                JSR     tokn_store_tok
                CMP     #'"'
                BNE     tokn_quote
                JMP     tokn_nextch
tokn_qeol:      LDA     #'"'
                JSR     tokn_store_tok
                LDA     #$0D
                JMP     tokn_store_tok
tokn_star:      LDA     #$DC            ; Substitute OSCLI token for *
tokn_lit_eol:   JSR     tokn_store_tok
                INX
                LDA     strbuf,X
                CMP     #$0D
                BNE     tokn_lit_eol
                JMP     tokn_store_tok
tokn_word:      LDA     #>token_tab     ; Start at the beginning of the
                STA     ptr1            ; token table.
                LDA     #<token_tab
                STA     ptr1+1
                DEX
                STX     $3B             ; Beginning of word in strbuf
                LDY     #$00
                LDA     (ptr1),Y
tokn_next_word: STA     $3C
tokn_ch_match:  INX
                INY
                LDA     strbuf,X        ; Compare strbuf to table
                AND     #$5F            ; case-insensitive.
                CMP     (ptr1),Y
                BEQ     tokn_ch_match
                CMP     #$0E            ; '.' after case folding.
                BEQ     tokn_abbrev
                DEX
                LDA     (ptr1),Y        ; This will be token value if
                BMI     tokn_found      ; whole word matches.
                SEC
                LDA     $3C             ; Add the length of this word
                ADC     ptr1            ; to move onto the next from
                STA     ptr1            ; the table.
                BCC     tokn_noinc
                INC     ptr1+1
tokn_noinc:     LDX     $3B
                LDY     #$00
                LDA     (ptr1),Y
                CMP     #$80            ; End of table?
                BNE     tokn_next_word
                INX
                LDA     strbuf,X        ; Store character literally.
                JMP     tokn_symbol
tokn_abbrev:    LDY     $3C
                LDA     flags
                ORA     #$40
                STA     flags
tokn_found:     LDA     (ptr1),Y
                CMP     #$DC            ; OSCLI
                BEQ     tokn_lit_eol    ; Store rest of line untokenised.
                JSR     tokn_store_tok
                JMP     tokn_nextch
tokn_store_tok: LDY     $3A
                INC     $3A
                BEQ     tokn_toolong
                STA     tokbuf,Y
                RTS
tokn_toolong:   JMP     err_toolong

                ;; Convert a number stored as ASCII decimal at strbuf,x
                ;; into binary leaving the result in iwa.

dec_to_bin:     TXA
                TAY
                TSX                     ; Enable stack to be restored
                STX     $3B             ; if number overflows.
                LDX     #$03
                LDA     #$00            ; Zero iwa
d2b_clrlp:      STA     iwa,X
                DEX
                BPL     d2b_clrlp
                STA     $3C
                LDA     strbuf,Y
                CMP     #'-'
                BNE     d2b_notminus
                LDA     #$80            ; Note negative as a flag.
                STA     $3C
                BNE     d2b_isneg
d2b_notminus:   CMP     #'+'
                BNE     d2b_notplus
d2b_isneg:      INY
d2b_notplus:    LDA     strbuf,Y
                CMP     #'0'
                BCC     d2b_notdigit
                CMP     #'9'+1
                BCS     d2b_notdigit
                JSR     d2b_lshfit      ; shift iwa left (x2)
                LDX     #$03
d2b_pushlp:     LDA     iwa,X           ; save iwa on stack.
                PHA
                DEX
                BPL     d2b_pushlp
                JSR     d2b_lshfit      ; two more shifts (x4)
                JSR     d2b_lshfit
                LDX     #$00            ; add back in from stack.
                LDA     #$04
                STA     $3D
                CLC
d2b_addlp:      PLA
                ADC     iwa,X
                STA     iwa,X
                INX
                DEC     $3D
                BNE     d2b_addlp       ; final version is x10
                BVS     d2b_over
                LDA     strbuf,Y        ; get the digit.
                SEC
                SBC     #'0'            ; remove offset.
                CLC
                ADC     iwa             ; add to number so far.
                STA     iwa
                BCC     d2b_noinc
                INC     iwa+1
                BNE     d2b_noinc
                INC     iwa+2
                BNE     d2b_noinc
                INC     iwa+3
                BMI     d2b_over        ; overflow.
d2b_noinc:      INY
                BNE     d2b_notplus
d2b_notdigit:   STY     $3D
                LDA     $3C             ; check for negative.
                BPL     d2b_skipneg
                JSR     negate_iwa
d2b_skipneg:    CLC
                BCC     d2b_done
d2b_over:       LDX     $3B
                TXS
                SEC
                STY     $3D
d2b_done:       LDX     $3D
                RTS
d2b_lshfit:     ASL     iwa
                ROL     iwa+1
                ROL     iwa+2
                ROL     iwa+3
                BMI     d2b_over
                RTS

                ;; Print the current line number by copying into the
                ;; IWA and falling into the IWA print routine.

print_lineno:   LDA     lineno
                STA     iwa
                LDA     lineno+1
                STA     iwa+1
                LDA     #$00
                STA     iwa+2
                STA     iwa+3

                ;; Print the number in IWA in decimal.

print_dec:      PHA
                TXA
                PHA
                TYA
                PHA
                LDA     iwa+3           ; Check for negative.
                BPL     pdec_pos
                LDA     #'-'
                JSR     oswrch
                JSR     negate_iwa
pdec_pos:       LDX     #$00
pdec_diglp:     LDY     #$20            ; Max 32-bits of shifting.
                LDA     #$00
pdec_bitlp:     ASL     iwa
                ROL     iwa+1
                ROL     iwa+2
                ROL     iwa+3
                ROL
                CMP     #$0A
                BCC     pdec_nosub
                SBC     #$0A
                INC     iwa
pdec_nosub:     DEY
                BNE     pdec_bitlp
                CLC
                ADC     #'0'
                PHA
                INX
                LDA     iwa
                ORA     iwa+1
                ORA     iwa+2
                ORA     iwa+3
                BNE     pdec_diglp
pdec_prtlp:     PLA
                JSR     oswrch
                DEX
                BNE     pdec_prtlp
                PLA
                TAY
                PLA
                TAX
                PLA
                RTS

                ;; Search the program for the line whose number is
                ;; in lineno.  Returns carry clear is found, set if
                ;; not.

find_line:      LDY     #$00
                STY     ptr1
                LDA     page
                STA     ptr1+1
fl_cmp_msb:     LDY     #$01
                LDA     (ptr1),Y        ; Compare the MSB.
                CMP     lineno+1
                BCS     fl_mismatch
fl_add_len:     LDY     #$03            ; Add the length to get to the
                LDA     (ptr1),Y        ; next line.
                ADC     ptr1
                STA     ptr1
                BCC     fl_cmp_msb
                INC     ptr1+1
                BCS     fl_cmp_msb
fl_mismatch:    BNE     fl_not_found    ; Not found.
                LDY     #$02
                LDA     (ptr1),Y        ; Compare the LSB.
                CMP     lineno
                BCC     fl_add_len
                BNE     fl_not_found
                CLC
fl_not_found:   RTS

                ;; Delete the program line whose line number is stored
                ;; in lineno.

delete_line:    JSR     find_line
                BCS     dl_not_found    ; Not found, nothing to do.
                LDA     ptr1
                STA     ptr2            ; Take two copies of the address
                STA     top             ; of the line.
                LDA     ptr1+1
                STA     ptr2+1
                STA     top+1
                LDY     #$03            ; Get the length.
                LDA     (ptr2),Y
                CLC
                ADC     ptr2            ; Add to one pointer.
                STA     ptr2
                BCC     dl_noinc1
                INC     ptr2+1
dl_noinc1:      LDY     #$00            ; Copy down to close the gap.
dl_char_lp:     LDA     (ptr2),Y
                STA     (top),Y
                CMP     #$0D
                BEQ     dl_eol
dl_next:        INY
                BNE     dl_char_lp
                INC     ptr2+1
                INC     top+1
                BNE     dl_char_lp
dl_eol:         INY
                BNE     dl_noinc2
                INC     ptr2+1
                INC     top+1
dl_noinc2:      LDA     (ptr2),Y
                STA     (top),Y
                BMI     dl_done
                JSR     dl_ptr2_to_top
                JSR     dl_ptr2_to_top
                JMP     dl_next
dl_done:        JSR     add_y_to_top
                CLC
dl_not_found:   RTS

dl_ptr2_to_top: INY
                BNE     dl_noinc3
                INC     ptr2+1
                INC     top+1
dl_noinc3:      LDA     (ptr2),Y
                STA     (top),Y
                RTS

                ;; Store the tokenised line into the body of the
                ;; program.

store_line:     LDY     #$00
                STY     $24
                JSR     delete_line     ; Delete any existing line.
                LDY     #$07
                STY     $25
                LDY     #$00
                LDA     ($24),Y
                CMP     #$0D
                BEQ     sl_done
                LDY     $3A             ; Get the length of the new line.
                INY                     ; Add two for the line number.
                INY
                STY     $3B
                INC     $3B             ; Add one more for the length.
                SEC
                LDA     top
                STA     $26
                LDA     top+1
                STA     $27
                JSR     add_y_to_top    ; Calculate new TOP with extra line.
                STA     ptr2
                LDA     top+1
                STA     ptr2+1
                DEY
                LDA     himem           ; Check new top doesn't exceed HIMEM.
                CMP     top
                LDA     himem+1
                SBC     top+1
                BCS     sl_loop
                JSR     checkprog
                JMP     err_room
sl_loop:        LDA     ($26),Y         ; Move bytes up in memory...
                STA     (ptr2),Y
                TYA
                BNE     sl_nodec
                DEC     ptr2+1
                DEC     $27
sl_nodec:       DEY
                TYA
                ADC     $26
                LDX     $27
                BCC     sl_noinc
                INX
sl_noinc:       CMP     ptr1            ; Until address to insert extra
                TXA                     ; line is reached.
                SBC     ptr1+1
                BCS     sl_loop
                SEC
                LDY     #$01            ; Store the line number into
                LDA     lineno+1        ; the start of the gap.
                STA     (ptr1),Y
                INY
                LDA     lineno
                STA     (ptr1),Y
                INY
                LDA     $3B             ; Store the length.
                STA     (ptr1),Y
                JSR     add_y_to_ptr1   ; Add Y to line address.
                LDY     #$FF
sl_copy_line:   INY                     ; Copy line into place.
                LDA     ($24),Y
                STA     (ptr1),Y
                CMP     #$0D
                BNE     sl_copy_line
sl_done:        RTS

                ;; Check the program by following the line lengths
                ;; up to the end marker - a kind of linked list.  This
                ;; also calculates TOP, the end of the program.

checkprog:      LDA     page            ; Set TOP=PAGE
                STA     top+1
                LDY     #$00
                STY     top
                INY
checkprog_lp:   DEY
                LDA     (top),Y         ; Check CR.
                CMP     #$0D
                BNE     bad_program     ; Not found - bad program.
                INY
                LDA     (top),Y         ; Check MSB of line number
                BMI     checkprog_end   ; for end marker.
                LDY     #$03
                LDA     (top),Y         ; Get length.
                BEQ     bad_program
                CLC
                JSR     add_a_to_top    ; Add length to TOP.
                BNE     checkprog_lp
checkprog_end:  INY
                CLC
add_y_to_top:   TYA
add_a_to_top:   ADC     top
                STA     top
                BCC     add_top_noinc
                INC     top+1
add_top_noinc:  LDY     #$01
                RTS

add_y_to_ptr1:  TYA
                ADC     ptr1
                STA     ptr1
                BCC     add_ptr1_noinc
                INC     ptr1+1
add_ptr1_noinc: RTS

reset_pc:       LDA     #$00
                STA     cesil_off
                LDA     #$01
                STA     cesil_pc
                LDA     page
                STA     cesil_pc+1
                RTS

nextbyte:       LDY     cesil_off
                INC     cesil_off
                LDA     (cesil_pc),Y
                RTS

bad_program:    LDX     #>msg_badprog
                LDY     #<msg_badprog
                JSR     printmsg
                JMP     exec_new

get_numeric:    JSR     nextbyte
                CMP     #$80
                BNE     get_var_to_iwa
                JSR     nextbyte
                STA     iwa
                JSR     nextbyte
                STA     iwa+1
                JSR     nextbyte
                STA     iwa+2
                JSR     nextbyte
                STA     iwa+3
                RTS

                ;; Fetch the variable whose letter code is in A
                ;; to the IWA.

get_var_to_iwa: SEC
                SBC     #$40            ; Make zero-based.
                BCC     get_var_inv
                ASL                     ; x4 for 32 bit variables.
                ASL
                CMP     #$FD            ; Out of range?
                BCS     get_var_inv
                TAX
                LDA     varbase,X
                STA     iwa
                LDA     varbase+1,X
                STA     iwa+1
                LDA     varbase+2,X
                STA     iwa+2
                LDA     varbase+3,X
                STA     iwa+3
                RTS
get_var_inv:    JMP     err_invnum

acc_to_iwa:     LDA     cesil_acc
                STA     iwa
                LDA     cesil_acc+1
                STA     iwa+1
                LDA     cesil_acc+2
                STA     iwa+2
                LDA     cesil_acc+3
                STA     iwa+3
                RTS

iwa_to_acc:     LDA     iwa
                STA     cesil_acc
                LDA     iwa+1
                STA     cesil_acc+1
                LDA     iwa+2
                STA     cesil_acc+2
                LDA     iwa+3
                STA     cesil_acc+3
                RTS

negate_iwa:     LDX     #$00
                LDY     #$04
                SEC
negate_iwa_lp:  LDA     #$00
                SBC     iwa,X
                STA     iwa,X
                INX
                DEY
                BNE     negate_iwa_lp
                RTS

negate_acc:     LDX     #$00
                LDY     #$04
                SEC
negate_acc_lp:  LDA     #$00
                SBC     cesil_acc,X
                STA     cesil_acc,X
                INX
                DEY
                BNE     negate_acc_lp
                RTS

readline:       JSR     oswrch
                STX     owblock
                STY     owblock+1
                LDA     #$00
                LDX     #>owblock
                LDY     #<owblock
                JSR     osword
                BCS     readline_esc
                RTS
readline_esc:   JMP     err_escape

printmsg:       STX     $3A
                STY     $3B
                LDY     #$00
                BEQ     printmsg_st
printmsg_lp:    JSR     osasci
                INY
printmsg_st:    LDA     ($3A),Y
                BNE     printmsg_lp
                RTS

get_string_xy:  JSR     get_string
                LDX     #$00
                LDY     #$06
                RTS

get_string:     JSR     nextbyte
                CMP     #'$'
                BNE     get_string_lit
                LDY     #$00
get_string_lp:  LDA     stracc,Y
                STA     strbuf,Y
                INY
                BNE     get_string_lp
                RTS
get_string_lit: LDA     cesil_pc
                STA     $F2
                LDA     cesil_pc+1
                STA     $F3
                LDY     cesil_off
                DEY
                SEC
                JSR     gsinit
                LDX     #$00
get_string_gsr: JSR     gsread
                BCS     get_string_end
                STA     strbuf,X
                INX
                BNE     get_string_gsr
get_string_end: LDA     #$0D
                STA     strbuf,X
                RTS
                JMP     err_notfnd

                ;; Load a program into memory.

load_prog:      JSR     get_string
                LDA     #$00
                STA     $3A             ; Filename is on a page boundary.
                STA     $3C             ; Load address is on a page boundary.
                STA     $40             ; Flat to load at the specified address.
                LDA     page            ; MSB of load address = page
                STA     $3D
                LDA     #$06            ; MSG of filename = strbuf.
                STA     $3B
                LDA     #$82            ; Get high order address.
                JSR     osbyte
                STX     $3E             ; High bytes of load address.
                STY     $3F
                LDA     #$FF            ; Load file with OSFILE.
                LDX     #$3A
                LDY     #$00
                JSR     osfile
                JMP     checkprog
owblock:        DFB     $00,$06, $FF, $20, $FF

tokent          MACRO
                DFB     T@0-*
                ASC     @1
T@0:            DFB     @2
                ENDM

token_tab:      tokent  "AND",      $FF
                tokent  "ADD",      $FE
                tokent  "ADVAL",    $FD
                tokent  "AUTO",     $FC
                tokent  "BGET",     $FB
                tokent  "BPUT",     $FA
                tokent  "CALL",     $F9
                tokent  "COMPARE",  $F8
                tokent  "COLOUR",   $F7
                tokent  "COLOR",    $F7
                tokent  "CLOSE",    $F6
                tokent  "CLS",      $F5
                tokent  "CLG",      $F4
                tokent  "CHAIN",    $D0
                tokent  "DATA",     $F3
                tokent  "DELETE",   $F2
                tokent  "DIVIDE",   $F1
                tokent  "EXECUTE",  $F0
                tokent  "GETCHR",   $EF
                tokent  "GETLINE",  $EE
                tokent  "GETFILE",  $ED
                tokent  "HALT",     $CF
                tokent  "INPUT",    $EC
                tokent  "INSERT",   $EB
                tokent  "JUMP",     $EA
                tokent  "JIZ",      $E9
                tokent  "JIN",      $E8
                tokent  "LIST",     $E7
                tokent  "LINE",     $E6
                tokent  "LOAD",     $E5
                tokent  "MODE",     $E4
                tokent  "MULTIPLY", $E3
                tokent  "NEW",      $E2
                tokent  "OLD",      $E1
                tokent  "OUTPUT",   $E0
                tokent  "OPENIN",   $DF
                tokent  "OPENOUT",  $DE
                tokent  "OPENUP",   $DD
                tokent  "OSCLI",    $DC
                tokent  "PRINT",    $DB
                tokent  "PLOT",     $DA
                tokent  "PUTFILE",  $D9
                tokent  "QUIT",     $D8
                tokent  "REMOVE",   $D7
                tokent  "RESTORE",  $D6
                tokent  "READ",     $D5
                tokent  "STORE",    $D4
                tokent  "SUBTRACT", $D3
                tokent  "TRANSFER", $D2
                tokent  "VDU",      $D1
                DFB     $80

msg_badprog:    STR     "Bad program"
err_numrange:   BRK
                DFB     $01
                ASC     "Number out of range."
err_eof:        BRK
                DFB     $02
                ASC     "Attempt to read past end of file."
err_invreg:     BRK
                DFB     $03
                ASC     "Invalid register designation."
err_room:       BRK
                DFB     $04
                ASC     "No room for that line."
err_toolong:    BRK
                DFB     $05
                ASC     "Line too long."
err_invnum:     BRK
                DFB     $06
                ASC     "Inavlid number / storage location."
err_notfnd:     BRK
                DFB     $07
                ASC     "Line identification not found."
err_nohalt:     BRK
                DFB     $08
                ASC     "What about a halt statement!"
err_escape:     BRK
                DFB     $11
                ASC     "Escape.|@"
basic:          STR     "BASIC"
msg_banner:     ASC     "EXTENDED CESIL|M|M|@"
msg_error:      DFB     $0D
                ASC     "Error |@"
msg_detect:     ASC     " detected |@"
msg_atline:     ASC     "at line |@"

jmptab_l:       DFB     >exec_halt      ; $CF
                DFB     >exec_chain     ; $D0
                DFB     >exec_vdu       ; $D1
                DFB     >exec_transfer  ; $D2
                DFB     >exec_subtract  ; $D3
                DFB     >exec_store     ; $D4
                DFB     >exec_read      ; $D5
                DFB     >exec_restore   ; $D6
                DFB     >exec_remove    ; $D7
                DFB     >exec_quit      ; $D8
                DFB     >exec_putfile   ; $D9
                DFB     >exec_plot      ; $DA
                DFB     >exec_print     ; $DB
                DFB     >exec_oscli     ; $DC
                DFB     >exec_openup    ; $DD
                DFB     >exec_openout   ; $DE
                DFB     >exec_openin    ; $DF
                DFB     >exec_output    ; $E0
                DFB     >exec_old       ; $E1
                DFB     >exec_new       ; $E2
                DFB     >exec_multiply  ; $E3
                DFB     >exec_mode      ; $E4
                DFB     >exec_load      ; $E5
                DFB     >exec_line      ; $E6
                DFB     >exec_list      ; $E7
                DFB     >exec_jin       ; $E8
                DFB     >exec_jiz       ; $E9
                DFB     >exec_jump      ; $EA
                DFB     >exec_insert    ; $EB
                DFB     >exec_input     ; $EC
                DFB     >exec_getfile   ; $ED
                DFB     >exec_getline   ; $EE
                DFB     >exec_getchr    ; $EF
                DFB     >exec_execute   ; $F0
                DFB     >exec_divide    ; $F1
                DFB     >exec_delete    ; $F2
                DFB     >exec_next_line ; $F3
                DFB     >exec_clg       ; $F4
                DFB     >exec_cls       ; $F5
                DFB     >exec_close     ; $F6
                DFB     >exec_colour    ; $F7
                DFB     >exec_compare   ; $F8
                DFB     >exec_call      ; $F9
                DFB     >exec_bput      ; $FA
                DFB     >exec_bget      ; $FB
                DFB     >exec_auto      ; $FC
                DFB     >exec_adval     ; $FD
                DFB     >exec_add       ; $FE
                DFB     >exec_and       ; $FF

jmptab_h:       DFB     <exec_halt      ; $CF
                DFB     <exec_chain     ; $D0
                DFB     <exec_vdu       ; $D1
                DFB     <exec_transfer  ; $D2
                DFB     <exec_subtract  ; $D3
                DFB     <exec_store     ; $D4
                DFB     <exec_read      ; $D5
                DFB     <exec_restore   ; $D6
                DFB     <exec_remove    ; $D7
                DFB     <exec_quit      ; $D8
                DFB     <exec_putfile   ; $D9
                DFB     <exec_plot      ; $DA
                DFB     <exec_print     ; $DB
                DFB     <exec_oscli     ; $DC
                DFB     <exec_openup    ; $DD
                DFB     <exec_openout   ; $DE
                DFB     <exec_openin    ; $DF
                DFB     <exec_output    ; $E0
                DFB     <exec_old       ; $E1
                DFB     <exec_new       ; $E2
                DFB     <exec_multiply  ; $E3
                DFB     <exec_mode      ; $E4
                DFB     <exec_load      ; $E5
                DFB     <exec_line      ; $E6
                DFB     <exec_list      ; $E7
                DFB     <exec_jin       ; $E8
                DFB     <exec_jiz       ; $E9
                DFB     <exec_jump      ; $EA
                DFB     <exec_insert    ; $EB
                DFB     <exec_input     ; $EC
                DFB     <exec_getfile   ; $ED
                DFB     <exec_getline   ; $EE
                DFB     <exec_getchr    ; $EF
                DFB     <exec_execute   ; $F0
                DFB     <exec_divide    ; $F1
                DFB     <exec_delete    ; $F2
                DFB     <exec_next_line ; $F3
                DFB     <exec_clg       ; $F4
                DFB     <exec_cls       ; $F5
                DFB     <exec_close     ; $F6
                DFB     <exec_colour    ; $F7
                DFB     <exec_compare   ; $F8
                DFB     <exec_call      ; $F9
                DFB     <exec_bput      ; $FA
                DFB     <exec_bget      ; $FB
                DFB     <exec_auto      ; $FC
                DFB     <exec_adval     ; $FD
                DFB     <exec_add       ; $FE
                DFB     <exec_and       ; $FF


exec_and:       JSR     get_numeric
                LDA     cesil_acc
                AND     iwa
                STA     cesil_acc
                LDA     cesil_acc+1
                AND     iwa+1
                STA     cesil_acc+1
                LDA     cesil_acc+2
                AND     iwa+2
                STA     cesil_acc+2
                LDA     cesil_acc+3
                AND     iwa+3
                STA     cesil_acc+3
                JMP     exec_next_line

exec_add:       JSR     get_numeric
                CLC
                LDA     cesil_acc       ; Perform the addition.
                ADC     iwa
                STA     cesil_acc
                LDA     cesil_acc+1
                ADC     iwa+1
                STA     cesil_acc+1
                LDA     cesil_acc+2
                ADC     iwa+2
                STA     cesil_acc+2
                LDA     cesil_acc+3
                ADC     iwa+3
                STA     cesil_acc+3
                AND     #$80
                STA     $09
                LDA     cesil_acc       ; Check for zero.
                ORA     cesil_acc+1
                ORA     cesil_acc+2
                ORA     cesil_acc+3
                BEQ     exec_add_zero
                LDA     $09
                ORA     #$40            ; Set the zero flag.
                STA     $09
exec_add_zero:  JMP     exec_next_line

exec_adval:     LDA     #$80            ; Specify ADVAL OSBYTE.
                LDX     cesil_acc       ; Channel from CESIL accumulator.
                LDY     #$FF
                JSR     osbyte
                STX     cesil_acc       ; Store 16-bit result from X,Y
                STY     cesil_acc+1
                LDX     #$00            ; extend to 32-bit.
                STX     cesil_acc+2
                STX     cesil_acc+3
                JMP     exec_next_line

exec_auto:      BRK
                DFB     $00
                ASC     "AUTO NOT IMPLEMENTED|@"

exec_bget:      LDY     cesil_y
                JSR     osbget
                BCS     exec_bget_eof
a_to_cesil_acc: STA     cesil_acc
                LDA     #$00
a_to_acc_ms3:   STA     cesil_acc+1
                STA     cesil_acc+2
                STA     cesil_acc+3
                JMP     exec_next_line
exec_bget_eof:  JMP     err_eof

exec_bput:      LDY     cesil_y
                LDA     cesil_acc
                JSR     osbput
                JMP     exec_next_line

exec_call:      JSR     get_numeric
                LDA     cesil_acc
                LDX     cesil_x
                LDY     cesil_y
                JSR     jmpi_2a
                STA     cesil_acc
                STX     cesil_x
                STY     cesil_y
                LDA     #$00
                STA     cesil_x+1
                STA     cesil_x+2
                STA     cesil_x+3
                STA     cesil_y+1
                STA     cesil_y+2
                STA     cesil_y+3
                JMP     a_to_acc_ms3
jmpi_2a:        JMP     ($002A)

exec_compare:   JSR     get_numeric
                SEC
                LDA     cesil_acc
                SBC     iwa
                STA     iwa
                LDA     cesil_acc+1
                SBC     iwa+1
                STA     iwa+1
                LDA     cesil_acc+2
                SBC     iwa+2
                STA     iwa+2
                LDA     cesil_acc+3
                SBC     iwa+3
                STA     iwa+3
                AND     #$80
                STA     $09
                LDA     iwa
                ORA     iwa+1
                ORA     iwa+2
                ORA     iwa+3
                BNE     exec_cmp_nz
                LDA     $09
                ORA     #$40
                STA     $09
exec_cmp_nz:    JMP     exec_next_line

exec_colour:    LDA     #$11            ; VDU code for COLOUR
                JSR     oswrch
cesil_acc_wrch: LDA     cesil_acc
wrch_next:      JSR     oswrch
                JMP     exec_next_line

exec_close:     LDA     #$00
                LDY     cesil_y
                JSR     osfind
                JMP     exec_next_line

exec_cls:       LDA     #$0C            ; VDU code for CLS
                JMP     wrch_next

exec_clg:       LDA     #$10            ; VDU code for CLG
                JMP     wrch_next

exec_delete:    BRK
                DFB     $00
                ASC     "DELETE NOT IMPLEMENTED|@"

exec_divide:    LDA     #$00
                LDX     #$04
exec_div_clr:   STA     $3A,X
                DEX
                BPL     exec_div_clr
                LDA     cesil_acc+3
                BPL     exec_div_nn1
                INC     $3A
                JSR     negate_acc
exec_div_nn1:   JSR     get_numeric
                LDA     iwa+3
                BPL     exec_div_lp
                JSR     negate_iwa
                DEC     $3A
exec_div_lp:    SEC
                LDA     cesil_acc
                SBC     iwa
                STA     cesil_acc
                LDA     cesil_acc+1
                SBC     iwa+1
                STA     cesil_acc+1
                LDA     cesil_acc+2
                SBC     iwa+2
                STA     cesil_acc+2
                LDA     cesil_acc+3
                SBC     iwa+3
                STA     cesil_acc+3
                BCC     exec_div_done
                INC     $3B
                BNE     exec_div_lp
                INC     $3C
                BNE     exec_div_lp
                INC     $3D
                BNE     exec_div_lp
                INC     $3E
                BPL     exec_div_lp
                JMP     err_numrange
exec_div_done:  LDA     $3B
                STA     cesil_acc
                LDA     $3C
                STA     cesil_acc+1
                LDA     $3D
                STA     cesil_acc+2
                LDA     $3E
                STA     cesil_acc+3
                LDA     $3A
                BEQ     exec_div_nnr
                JSR     negate_acc
exec_div_nnr:   JMP     exec_next_line

exec_getchr:    JSR     osrdch
                JMP     a_to_cesil_acc

exec_getline:   LDX     #$00
                LDY     #$05
                LDA     #'?'
                JSR     readline
                STY     cesil_y
                JSR     clear_acc_ms24
                JMP     exec_next_line

exec_getfile:   JSR     load_prog
                JMP     exec_halt

exec_chain:     JSR     load_prog
                JMP     exec_execute

exec_input:     LDA     #'%'
                LDX     #$00
                LDY     #$06
                JSR     readline
                JSR     dec_to_bin
                JSR     iwa_to_acc
                JMP     exec_next_line

exec_insert:    LDY     cesil_y
                LDA     cesil_acc
                STA     stracc,Y
                JMP     exec_next_line

exec_jin:       BIT     $09
                BMI     exec_jump
                JMP     exec_next_line

exec_jiz:       BIT     $09
                BVS     exec_jump
                JMP     exec_next_line

exec_jump:      JSR     get_string
                LDA     #$01            ; Start at PAGE.
                STA     ptr1
                LDA     page
                STA     ptr1+1
exec_jump_line: LDX     #$FF
                LDY     #$00
                LDA     (ptr1),Y        ; End marker?
                BMI     exec_jump_nfnd
                LDY     #$02
                LDA     (ptr1),Y
                STA     $3A
exec_jump_loop: INX
                INY
                LDA     (ptr1),Y
                BMI     exec_jump_tokn  ; Got a token, label is over.
                CMP     #$0D
                BEQ     exec_jump_next  ; Newline, not found.
                CMP     strbuf,X        ; Compare label with string.
                BEQ     exec_jump_loop
exec_jump_tokn: LDA     strbuf,X        ; End of the string being sought?
                CMP     #$0D
                BEQ     exec_jump_fnd
exec_jump_next: CLC
                LDA     $3A
                ADC     ptr1
                STA     ptr1
                BCC     exec_jump_line
                INC     ptr1+1
                BCS     exec_jump_line
exec_jump_fnd:  LDA     ptr1
                STA     cesil_pc
                LDA     ptr1+1
                STA     cesil_pc+1
                JMP     exec_this_line
exec_jump_nfnd: JMP     err_notfnd

exec_load:      JSR     get_numeric
                JSR     iwa_to_acc
                JMP     exec_next_line

exec_line:      JSR     osnewl
                JMP     exec_next_line

exec_list_esc:  JMP     err_escape
exec_list:      LDA     #$01            ; Start at PAGE.
                STA     ptr1
                LDA     page
                STA     ptr1+1
exec_list_lilp: BIT     $FF             ; Check for Escape
                BMI     exec_list_esc
                LDY     #$00
                LDA     (ptr1),Y
                BMI     exec_list_done  ; Hit end marker.
                STA     lineno+1
                INY
                LDA     (ptr1),Y
                STA     lineno
                JSR     print_lineno    ; Print the line number.
                INY
                BNE     exec_list_next  ; Always taken.
exec_list_loop: CMP     #$80
                BCC     exec_list_lit
                BEQ     exec_list_num
                STA     $3A
                STY     $3B
                LDA     #' '
                JSR     oswrch
                LDA     #>token_tab     ; Search the token table for
                STA     ptr2            ; the token from the program.
                LDA     #<token_tab
                STA     ptr2+1
exec_list_tlp:  LDY     #$00
                LDA     (ptr2),Y        ; Get length from token table.
                CMP     #$80            ; End of Table?
                BEQ     exec_list_bdtk
                TAY
                LDA     (ptr2),Y        ; Get token value for this entry.
                CMP     $3A
                BEQ     exec_list_tokn  ; Output the expanded token.
                SEC
                TYA                     ; Add length from table to pointer
                ADC     ptr2            ; to point to next entry.
                STA     ptr2
                BCC     exec_list_tlp
                INC     ptr2+1
                BCS     exec_list_tlp
exec_list_tokn: LDY     #$01
exec_list_chlp: LDA     (ptr2),Y
                BMI     exec_list_bdtk
                JSR     oswrch
                INY
                BNE     exec_list_chlp
exec_list_bdtk: LDY     $3B
                LDA     #' '
exec_list_lit:  JSR     oswrch
exec_list_next: INY
                LDA     (ptr1),Y
                CMP     #$0D
                BNE     exec_list_loop
                JSR     osnewl          ; Print newline for end of line.
                SEC
                TYA
                ADC     ptr1            ; Add length to get next program line.
                STA     ptr1
                BCC     exec_list_lilp
                INC     ptr1+1
                BCS     exec_list_lilp
exec_list_done: JMP     exec_next_line
exec_list_num:  INY
                LDA     (ptr1),Y
                STA     iwa
                INY
                LDA     (ptr1),Y
                STA     iwa+1
                INY
                LDA     (ptr1),Y
                STA     iwa+2
                INY
                LDA     (ptr1),Y
                STA     iwa+3
                JSR     print_dec
                JMP     exec_list_next

exec_multiply:  LDA     #$00
                LDX     #$08
exec_mul_clr:   STA     $3A,X
                DEX
                BPL     exec_mul_clr
                LDA     cesil_acc+3
                BPL     exec_mul_nn1
                INC     $3A
                JSR     negate_acc
exec_mul_nn1:   JSR     get_numeric
                LDA     iwa+3
                BPL     exec_mul_nn2
                DEC     $3A
                JSR     negate_iwa
exec_mul_nn2:   LDX     #$20            ; 32-bits.
exec_mul_loop:  LSR     iwa+3
                ROR     iwa+2
                ROR     iwa+1
                ROR     iwa
                BCC     exec_mul_nadd
                CLC
                LDA     $3F
                ADC     cesil_acc
                STA     $3F
                LDA     $40
                ADC     cesil_acc+1
                STA     $40
                LDA     $41
                ADC     cesil_acc+2
                STA     $41
                LDA     $42
                ADC     cesil_acc+3
                STA     $42
exec_mul_nadd:  LSR     $42
                ROR     $41
                ROR     $40
                ROR     $3F
                ROR     $3E
                ROR     $3D
                ROR     $3C
                ROR     $3B
                DEX
                BNE     exec_mul_loop
                LDA     $3B
                STA     cesil_acc
                LDA     $3C
                STA     cesil_acc+1
                LDA     $3D
                STA     cesil_acc+2
                LDA     $3E
                BMI     exec_mul_over
                STA     cesil_acc+3
                LDA     $3A
                BEQ     exec_mul_nn3
                JSR     negate_acc
exec_mul_nn3:   JMP     exec_next_line
exec_mul_over:  JMP     err_numrange

exec_mode:      LDA     #$16            ; VDU code for MODE.
                JSR     oswrch
                JMP     cesil_acc_wrch

exec_old:       LDA     page
                STA     ptr1+1
                LDA     #$00
                STA     ptr1
                LDY     #$01
                STA     (ptr1),Y
                JSR     checkprog
                JMP     exec_halt

exec_output:    JSR     acc_to_iwa
                JSR     print_dec
                JMP     exec_next_line

exec_openin:    JSR     get_string_xy
                LDA     #$40            ; Open for reading.
exec_opn_comm:  JSR     osfind
                STA     cesil_y
clear_acc_ms24: LDA     #$00
                STA     cesil_y+1
                STA     cesil_y+2
                STA     $3A
                JMP     exec_next_line
exec_openout:   JSR     get_string_xy
                LDA     #$80            ; Open for writing.
                JMP     exec_opn_comm
exec_openup:    LDA     #$C0            ; Open for update.
                JMP     exec_opn_comm
exec_print:     JSR     get_string
                LDY     #$00
exec_print_lp:  LDA     strbuf,Y
                CMP     #$0D
                BEQ     exec_print_end
                JSR     oswrch
                INY
                BNE     exec_print_lp
exec_print_end: JMP     exec_next_line

exec_plot:      LDA     cesil_acc
                JSR     oswrch
                LDA     cesil_x
                JSR     oswrch
                LDA     cesil_x+1
                JSR     oswrch
                LDA     cesil_y
                JSR     oswrch
                LDA     cesil_y+1
                JSR     oswrch
                JMP     exec_next_line

exec_putfile:   JSR     get_string_xy
                STX     $3A             ; Filemame.
                STY     $3B
                LDY     #$00
                STY     $3C
                STY     $44
                LDY     page
                STY     $3D
                STY     $45
                LDY     #$00
                STY     $40
                LDA     #$80
                STY     $41
                LDA     top
                STA     $48
                LDA     top+1
                STA     $49
                LDA     #$82
                JSR     osbyte
                STX     $3E
                STY     $3F
                STX     $42
                STY     $43
                STX     $46
                STY     $47
                STX     $4A
                STY     $4B
                LDX     #$3A
                LDY     #$00
                TYA
                JSR     osfile
                JMP     exec_next_line

exec_quit:      LDA     #$00
                LDY     #$00
                JSR     osfind
                LDX     #>basic
                LDY     #<basic
                JSR     oscli

exec_remove:    LDX     cesil_x
                LDA     stracc,X
                JMP     a_to_cesil_acc

exec_restore:   BRK
                DFB     $00
                ASC     "RESTORE NOT IMPLEMENTED|@"
exec_read:      BRK
                DFB     $00
                ASC     "READ NOT IMPLEMENTED|@"

exec_store:     JSR     nextbyte
                SEC
                SBC     #'@'            ; Convert to zero-based.
                BCC     exec_store_nf
                ASL                     ; x4 for 32 bit variables.
                ASL
                CMP     #$FD            ; Out of range?
                BCS     exec_store_nf
                TAX
                LDA     cesil_acc
                STA     varbase,X
                LDA     cesil_acc+1
                STA     varbase+1,X
                LDA     cesil_acc+2
                STA     varbase+2,X
                LDA     cesil_acc+3
                STA     varbase+3,X
                JMP     exec_next_line
exec_store_nf:  JMP     err_notfnd

exec_subtract:  JSR     get_numeric
                SEC
                LDA     cesil_acc
                SBC     iwa
                STA     cesil_acc
                LDA     cesil_acc+1
                SBC     iwa+1
                STA     cesil_acc+1
                LDA     cesil_acc+2
                SBC     iwa+2
                STA     cesil_acc+2
                LDA     cesil_acc+3
                SBC     iwa+3
                STA     cesil_acc+3
                AND     #$80
                STA     $09
                LDA     cesil_acc
                ORA     cesil_acc+1
                ORA     cesil_acc+2
                ORA     cesil_acc+3
                BNE     exec_subtr_nz
                LDA     $09
                ORA     #$40
                STA     $09
exec_subtr_nz:  JMP     exec_next_line

exec_transfer:  JSR     nextbyte        ; Get byte indicating from register.
                AND     #$5F
                CMP     #'A'
                BNE     exec_xfr_nfa
                JSR     acc_to_iwa
                JMP     exec_xfr_to
exec_xfr_nfa:   CMP     #'X'
                BNE     exec_xfr_nfx
                LDA     cesil_x         ; Transfer CESIL X to IWA
                STA     iwa
                LDA     cesil_x+1
                STA     iwa+1
                LDA     cesil_x+2
                STA     iwa+2
                LDA     cesil_x+3
                STA     iwa+3
                JMP     exec_xfr_to
exec_xfr_nfx:   CMP     #'Y'
                BNE     exec_xfr_inv
                LDA     cesil_y         ; Transfer CESIL Y to IWA
                STA     iwa
                LDA     cesil_y+1
                STA     iwa+1
                LDA     cesil_y+2
                STA     iwa+2
                LDA     cesil_y+3
                STA     iwa+3
exec_xfr_to:    JSR     nextbyte        ; Get byte inicating to register.
                AND     #$5F
                CMP     #'A'
                BNE     exec_xfr_nta
                JSR     iwa_to_acc
                JMP     exec_next_line
exec_xfr_nta:   CMP     #$05            ; BUG!
                BNE     exec_xfr_ntx
                LDA     iwa             ; Transger IWA to CESIL X.
                STA     cesil_x
                LDA     iwa+1
                STA     cesil_x+1
                LDA     iwa+2
                STA     cesil_x+2
                LDA     iwa+3
                STA     cesil_x+3
                JMP     exec_next_line
exec_xfr_ntx:   CMP     #'Y'
                BNE     exec_xfr_inv
                LDA     iwa             ; Transfer IWA to CESIL Y
                STA     cesil_y
                LDA     iwa+1
                STA     cesil_y+1
                LDA     iwa+2
                STA     cesil_y+2
                LDA     iwa+3
                STA     cesil_y+3
                JMP     exec_next_line
exec_xfr_inv:   JMP     err_invreg

exec_vdu:       LDA     cesil_acc
                JSR     oswrch
                JMP     exec_next_line
exec_execute:   JSR     reset_pc
exec_this_line: LDA     #$00            ; Reset to start for new line.
                STA     cesil_off
                JSR     nextbyte        ; Get first byte.
                BMI     exec_end_mark   ; End marker found with no HALT.
                STA     lineno+1        ; Keep the line number in ZP
                JSR     nextbyte
                STA     lineno
                JSR     nextbyte        ; The same with the length.
                STA     linelen
exec_next_byte: JSR     nextbyte
                CMP     #$CF            ; HALT token (lowest numbered).
                BCC     exec_not_token
                TAX
                LDA     jmptab_l-$CF,X
                STA     $3A
                LDA     jmptab_h-$CF,X
                STA     $3B
                JMP     ($003A)
exec_not_token: CMP     #$0D
                BNE     exec_next_byte
                JMP     exec_next_line
exec_end_mark:  JMP     err_nohalt
exec_escape:    JMP     err_escape
exec_oscli:     CLC                     ; Add the offset to the CESIL PC
                LDA     cesil_off
                ADC     cesil_pc
                TAX                     ; Put in X,Y for OSCLI call.
                LDA     #$00
                ADC     cesil_pc+1
                TAY
                JSR     oscli
exec_next_line: BIT     $FF             ; Check for Escape
                BMI     exec_escape
                LDA     cesil_pc+1      ; Immediate command?
                CMP     #<tokbuf
                BEQ     exec_halt
                CLC                     ; Add the lenhth of this line to
                LDA     linelen         ; The CESIL PC.
                ADC     cesil_pc
                STA     cesil_pc
                BCC     exec_this_line
                INC     cesil_pc+1
                BCS     exec_this_line
exec_halt:      LDX     #$FF            ; Reset stack.
                TXS
                LDX     #>tokbuf        ; Execution from token buffer.
                STX     cesil_off
                STX     cesil_pc
                LDY     #<tokbuf
                STY     cesil_pc+1
                DEY
                LDA     #'&'            ; Our prompt.
                JSR     readline        ; Print prompt and read line.
                LDY     #$00
                JSR     tokenise        ; Tokenise the line
                BIT     flags
                BPL     exec_next_byte  ; Branch to execute immediately.
                JSR     store_line      ; Store the line in the program.
                JMP     exec_halt
start:          LDX     #>brkhand       ; Install our BRK handler.
                LDY     #<brkhand
                STX     brkv
                STY     brkv+1
                LDX     #>msg_banner    ; Print the banner message.
                LDY     #<msg_banner
                JSR     printmsg
                LDA     #$84            ; Get HIMEM from the OS
                JSR     osbyte
                STX     himem
                STY     himem+1
                LDX     #<(end+$FF)     ; Next page after the end of interpreter.
                STX     page            ; Store as the local value of PAGE.
                LDA     #$B4            ; Set as OSHWM.
                LDY     #$00
                JSR     osbyte
exec_new:       LDA     page            ; Start at PAGE.
                STA     ptr1+1
                LDY     #$00
                STY     ptr1
                LDA     #$0D            ; Store a newline.
                STA     (ptr1),Y
                INY
                LDA     #$FF            ; And end marker.
                STA     (ptr1),Y
                JSR     checkprog
                JMP     exec_halt       ; Interactive mode.

                ;; BRK Handler

brkhand:        LDX     #>msg_error     ; Print "Error "
                LDY     #<msg_error
                JSR     printmsg
                LDY     #$00            ; Get the error number.
                LDA     ($FD),Y
                STA     iwa
                CMP     #$11            ; Is it Escape?
                BNE     brk_notesc
                LDA     #$7E            ; Acknowledge escape.
                JSR     osbyte
brk_notesc      LDA     #$00
                STA     iwa+1
                STA     iwa+2
                STA     iwa+3
                JSR     print_dec       ; Print the error number.
                LDX     #>msg_detect    ; Print " detected "
                LDY     #<msg_detect
                JSR     printmsg
                LDA     cesil_pc+1      ; Is this an immediate command?
                CMP     #<tokbuf
                BEQ     brk_no_line
                LDX     #>msg_atline    ; Print " at line "
                LDY     #<msg_atline
                JSR     printmsg
                JSR     print_lineno    ; Print the line number.
brk_no_line:    JSR     osnewl
                LDY     #$01
                BNE     brk_err_msg
brk_print_ch:   JSR     osasci
                INY
brk_err_msg:    LDA     ($FD),Y
                BNE     brk_print_ch
                JSR     osnewl
                JMP     exec_halt       ; Interactive mode.
                DFB     $D0
end:
