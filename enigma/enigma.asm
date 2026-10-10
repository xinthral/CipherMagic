;-------------------------------------------------------------------;
; The Enigma machine is a rotor cipher: every key press steps the
; rotars, so the same letter comes out differently each time it is
; typed. This is a port of enigma.cpp, with the same parts, commands
; and output.
; Author:
;   Xinthral
;
; Signal path for one key press:
;   key -> Plugboard -> Rotar I -> II -> III -> Reflector
;       -> III -> II -> I -> Plugboard -> lamp
; Every stage on the way back undoes its partner on the way in, with
; the Reflector's pairs in the middle, so the same settings both
; encrypt and decrypt.
;
; Assemble and run (Linux x86-64) from the repository root:
;   nasm -felf64 enigma/enigma.asm -o enigma/enigma.obj
;   ld enigma/enigma.obj -o asmEnigma.exe
;   ./asmEnigma.exe            settings from enigma/enigma.ini
;   ./asmEnigma.exe --test     fixed plugboard key, no screen clearing
; or: make asmEnigma
;
; Starting settings (plugboard key, rotar start positions) come from
; enigma/enigma.ini, shared with the other language versions. The
; path is relative to the directory the program is started from.
;
; Conventions:
;   - Contacts are indexes 0-25 (A = 0 ... Z = 25). Every wiring
;     table holds 26 bytes: table[contact] = the contact it leads to.
;   - A routine keeps every register as it found it, apart from RAX
;     and whatever its header lists under Output.
;   - Text is passed as a pointer and a length (RSI, RDX), not as a
;     NUL terminated string.
;   - Lines are read up to LINE_MAX characters; a longer line is
;     handled as several lines.
;-------------------------------------------------------------------;
SYS_READ    equ 0                                                   ; alias for system_read
SYS_WRITE   equ 1                                                   ; alias for system_write
SYS_OPEN    equ 2                                                   ; alias for system_open
SYS_CLOSE   equ 3                                                   ; alias for system_close
SYS_EXIT    equ 60                                                  ; alias for system_exit
SYS_RANDOM  equ 318                                                 ; alias for system_getrandom
STDIN       equ 0                                                   ; alias for stdin file descriptor
STDOUT      equ 1                                                   ; alias for stdout file descriptor
O_RDONLY    equ 0                                                   ; open flag: read only
SYMBOLS     equ 26                                                  ; contacts on every part (letters in the alphabet)
ROTARS      equ 3                                                   ; rotars in the machine
CABLES      equ 10                                                  ; cables in a random plugboard
LINE_MAX    equ 4096                                                ; longest line handled in one piece
READ_MAX    equ 4096                                                ; bytes asked for in one read
CONFIG_MAX  equ 256                                                 ; longest setting value kept from the ini
RANDOM_MAX  equ 64                                                  ; random bytes asked for (2 per shuffle step)
DEFAULT     REL                                                     ; label addresses are relative to RIP

;-------------------------------------------------------------------;
; SECTION [data]: Static Assigned Memory
;-------------------------------------------------------------------;
            SECTION .data
; Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
rotarWire:  DB 'EKMFLGDQVZNTOWYHXUSPAIBRCJ'                         ; rotar I
            DB 'AJDKSIRUXBLHWTMCQGZNPYFVOE'                         ; rotar II
            DB 'BDFHJLCPRTXVZNYEIWGAKMUSQO'                         ; rotar III
reflWire:   DB 'YRUHQSLDPXNGOKMIEBFZCWVJAT'                         ; historical Reflector B
labelI:     DB 'I'                                                  ; name of the first (fast) rotar
labelII:    DB 'II'                                                 ; name of the second rotar
labelIII:   DB 'III'                                                ; name of the third rotar
rotarLabel: DQ labelI, labelII, labelIII                            ; where each rotar's name is
rotarLabLn: DQ 1, 2, 3                                              ; how long each rotar's name is
; 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
testKey:    DB 'AV BS CG DL FU HZ IN KM OW RX'                      ; plugboard key used by --test
lenTestKey: equ $ - testKey                                         ; length of the test key
testPos:    DB 'AAA'                                                ; rotar start positions used by --test and as the default
iniPath:    DB 'enigma/enigma.ini', 0                               ; ini file path (NUL terminated for system_open)
iniPlugs:   DB 'plugs'                                              ; ini setting name: plugboard key
lenIniPlug: equ $ - iniPlugs                                        ; length of the setting name
iniPos:     DB 'positions'                                          ; ini setting name: rotar start positions
lenIniPos:  equ $ - iniPos                                          ; length of the setting name
optTest:    DB '--test'                                             ; the one command line option
lenOptTest: equ $ - optTest                                         ; length of the option
cmdExit:    DB 'exit'                                               ; command: quit
lenCmdExit: equ $ - cmdExit                                         ; length of the command
cmdReset:   DB 'reset'                                              ; command: turn the rotars back to their start positions
lenCmdRset: equ $ - cmdReset                                        ; length of the command
cmdPlugs:   DB 'plugs'                                              ; command: show or set the plugboard key
lenCmdPlug: equ $ - cmdPlugs                                        ; length of the command
cmdShow:    DB 'show'                                               ; command: display every part's wiring
lenCmdShow: equ $ - cmdShow                                         ; length of the command
msgHello:   DB 'Hello World', 0xA                                   ; first line printed
lenHello:   equ $ - msgHello                                        ; length of the message
msgPlugLd:  DB 'Plugboard is Loaded...', 0xA                        ; plugboard built
lenPlugLd:  equ $ - msgPlugLd                                       ; length of the message
msgReflLd:  DB 'Reflector Loaded...', 0xA                           ; reflector built
lenReflLd:  equ $ - msgReflLd                                       ; length of the message
msgEnigLd:  DB 'Enigma is Loaded...', 0xA                           ; machine being built
lenEnigLd:  equ $ - msgEnigLd                                       ; length of the message
msgRotar:   DB 'Rotar '                                             ; rotar built: text before the name
lenRotar:   equ $ - msgRotar                                        ; length of the message
msgLoaded:  DB ' Loaded...', 0xA                                    ; rotar built: text after the name
lenLoaded:  equ $ - msgLoaded                                       ; length of the message
msgKey:     DB 'Plugboard key: '                                    ; header for the plugboard key
lenKey:     equ $ - msgKey                                          ; length of the header
msgPos:     DB 'Rotar positions: '                                  ; header for the rotar start positions
lenPos:     equ $ - msgPos                                          ; length of the header
msgPrompt:  DB '>> '                                                ; command line prompt
lenPrompt:  equ $ - msgPrompt                                       ; length of the prompt
msgReset:   DB 'Rotars reset', 0xA                                  ; rotars turned back to their start positions
lenReset:   equ $ - msgReset                                        ; length of the message
msgOutput:  DB 'Output: '                                           ; header for an encrypted or decrypted line
lenOutput:  equ $ - msgOutput                                       ; length of the header
msgArrow:   DB ' => '                                               ; goes between the letters of a trace line
msgPlugCf:  DB 'Plugboard Configuration ('                          ; display: plugboard title, before the key
lenPlugCf:  equ $ - msgPlugCf                                       ; length of the title
msgParen:   DB ')', 0xA                                             ; display: plugboard title, after the key
lenParen:   equ $ - msgParen                                        ; length of the text
msgRotary:  DB 'Rotary '                                            ; display: rotar title, before the name
lenRotary:  equ $ - msgRotary                                       ; length of the text
msgConfig:  DB ' Configuration', 0xA                                ; display: rotar title, after the name
lenConfig:  equ $ - msgConfig                                       ; length of the text
msgReflCf:  DB 'Reflector Configuration', 0xA                       ; display: reflector title
lenReflCf:  equ $ - msgReflCf                                       ; length of the title
msgReflEr:  DB 'Reflector: invalid wiring at '                      ; reflector check failed, before the letter
lenReflEr:  equ $ - msgReflEr                                       ; length of the message
msgPlug:    DB 'Plugboard: '                                        ; start of most plugboard errors
lenPlug:    equ $ - msgPlug                                         ; length of the text
msgQuote:   DB "Plugboard: '"                                       ; non-letter error, before the character
lenQuote:   equ $ - msgQuote                                        ; length of the text
msgNotLet:  DB "' is not a letter", 0xA                             ; non-letter error, after the character
lenNotLet:  equ $ - msgNotLet                                       ; length of the text
msgNoPart:  DB ' has no partner', 0xA                               ; odd number of letters error, after the letter
lenNoPart:  equ $ - msgNoPart                                       ; length of the text
msgSelf:    DB " can't be plugged into itself", 0xA                 ; letter paired with itself error, after the letter
lenSelf:    equ $ - msgSelf                                         ; length of the text
msgReuse:   DB ' reuses a plugged letter', 0xA                      ; letter used twice error, after the pair
lenReuse:   equ $ - msgReuse                                        ; length of the text
msgPosErA:  DB 'Enigma: positions "'                                ; bad positions error, before the value
lenPosErA:  equ $ - msgPosErA                                       ; length of the text
msgPosErB:  DB '" must be 3 letters, one per rotar', 0xA            ; bad positions error, after the value
lenPosErB:  equ $ - msgPosErB                                       ; length of the text
msgUnknwn:  DB 'Unknown option: '                                   ; bad option error, before the option
lenUnknwn:  equ $ - msgUnknwn                                       ; length of the text
msgUsage:   DB 0xA, 'Usage: '                                       ; bad option error, before the program name
lenUsage:   equ $ - msgUsage                                        ; length of the text
msgUsageB:  DB ' [--test]', 0xA                                     ; bad option error, after the program name
lenUsageB:  equ $ - msgUsageB                                       ; length of the text
msgClear:   DB 0x1B, '[2J', 0x1B, '[3J', 0x1B, '[H'                 ; clear screen, clear scrollback, cursor home
lenClear:   equ $ - msgClear                                        ; length of the escape codes
newline:    DB 0xA                                                  ; newline character for line endings

;-------------------------------------------------------------------;
; SECTION [text]: Instruction Execution Order
;-------------------------------------------------------------------;
            SECTION .text
            global _start                                           ; must be declared for linker (ld)

;-------------------------------------------------------------------;
; _start:
;   Purpose:
;       Starts the machine and its command line.
;       Usage: asmEnigma.exe [--test]
;       No option:  plugboard key and rotar start positions from
;                   enigma.ini (random key if the ini leaves plugs
;                   empty), console cleared once.
;       --test:     ignores enigma.ini; fixed plugboard key,
;                   positions AAA and no clearing, so every run
;                   starts in the same state and its output can be
;                   compared with an earlier run.
;   Input:
;       [RSP]     = number of command line words (argc)
;       [RSP + 8] = pointers to the words, program name first (argv)
;   Output:
;       Exit code 0 normally, 1 on an unknown option
;-------------------------------------------------------------------;
_start:
            MOV RBP, RSP                                            ; keep the starting stack pointer, where the arguments are
            MOV R12, [RBP]                                          ; load the number of command line words
            MOV R13, 1                                              ; set word counter = 1 (word 0 is the program name)

.next_option:
            CMP R13, R12                                            ; compare word counter < number of words
            JAE .options_done                                       ; if every word is checked, carry on
            MOV RSI, [RBP + 8 + R13 * 8]                            ; load pointer to this word
            CALL str_len                                            ; measure it ( [in]RSI , [out]RAX )
            MOV RDX, RAX                                            ; set size of this word
            MOV RDI, optTest                                        ; set the text to compare against
            MOV RCX, lenOptTest                                     ; set the size of that text
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JZ .unknown_option                                      ; anything but --test is an error
            MOV byte [testMode], 1                                  ; remember that --test was given
            INC R13                                                 ; increment word counter
            JMP .next_option                                        ; check the next word

.unknown_option:
            MOV R14, RSI                                            ; keep pointer to the bad option
            MOV R15, RDX                                            ; keep size of the bad option
            MOV RSI, msgUnknwn                                      ; set source index to the error text
            MOV RDX, lenUnknwn                                      ; set size of the error text
            CALL print                                              ; print 'Unknown option: '
            MOV RSI, R14                                            ; set source index to the bad option
            MOV RDX, R15                                            ; set size of the bad option
            CALL print                                              ; print the option
            MOV RSI, msgUsage                                       ; set source index to the usage text
            MOV RDX, lenUsage                                       ; set size of the usage text
            CALL print                                              ; print newline + 'Usage: '
            MOV RSI, [RBP + 8]                                      ; load pointer to the program name
            CALL str_len                                            ; measure it ( [in]RSI , [out]RAX )
            MOV RDX, RAX                                            ; set size of the program name
            CALL print                                              ; print the program name
            MOV RSI, msgUsageB                                      ; set source index to the rest of the usage text
            MOV RDX, lenUsageB                                      ; set size of the rest
            CALL print                                              ; print ' [--test]' + newline
            MOV RDI, 1                                              ; exit code 1
            JMP _exit                                               ; leave the program

.options_done:
            MOV RSI, msgHello                                       ; set source index to the greeting
            MOV RDX, lenHello                                       ; set size of the greeting
            CALL print                                              ; print 'Hello World'

            ; --test: fixed starting state instead of enigma.ini
            MOV RSI, testKey                                        ; set key to the test key
            MOV RDX, lenTestKey                                     ; set key size
            MOV R8, testPos                                         ; set positions to AAA
            MOV R9, ROTARS                                          ; set positions size
            CMP byte [testMode], 0                                  ; compare test mode flag with 0
            JNE .build_machine                                      ; in test mode, keep the fixed state
            CALL load_config                                        ; read enigma.ini into the config buffers
            MOV RSI, cfgPlugs                                       ; set key to the ini plugs value
            MOV RDX, [cfgPlugLen]                                   ; set key size
            MOV R8, cfgPos                                          ; set positions to the ini positions value
            MOV R9, [cfgPosLen]                                     ; set positions size

.build_machine:
            CALL enigma_setup                                       ; build the machine ( [in]RSI,RDX,R8,R9 )
            CALL run_cli                                            ; read commands until exit or end of input
            XOR RDI, RDI                                            ; exit code 0

;-------------------------------------------------------------------;
; _exit:
;   Purpose:
;       Exit Program
;   Input:
;       RDI = exit code
;   Output:
;       None
;-------------------------------------------------------------------;
_exit:
            MOV RAX, SYS_EXIT                                       ; system call number (system_exit)
            SYSCALL                                                 ; kernel syscall

;-------------------------------------------------------------------;
; print:
;   Purpose:
;       Writes a buffer to stdout
;   Input:
;       RSI = buffer to write
;       RDX = size of buffer in bytes
;   Output:
;       None
;   Clobbers:
;       RAX
;   Note:
;       SYSCALL itself overwrites RCX and R11, so they are saved here
;-------------------------------------------------------------------;
print:
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value (SYSCALL overwrites it)
            PUSH R11                                                ; save caller's 11th register value (SYSCALL overwrites it)
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall
            POP R11                                                 ; restore caller's 11th register value
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; print_char:
;   Purpose:
;       Writes one character to stdout
;   Input:
;       AL = character to write
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_char:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            MOV [charBuf], AL                                       ; put the character in memory, where print can reach it
            MOV RSI, charBuf                                        ; set source index to the character
            MOV RDX, 1                                              ; set size to one character
            CALL print                                              ; print the character
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; str_len:
;   Purpose:
;       Measures a NUL terminated string (the command line words are
;       the only text the program gets in that form)
;   Input:
;       RSI = string to measure
;   Output:
;       RAX = length in bytes, not counting the NUL
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
str_len:
            XOR RAX, RAX                                            ; set length = 0

.loop_len:
            CMP byte [RSI + RAX], 0                                 ; compare this byte with the NUL terminator
            JE .return_len                                          ; at the NUL, the length is known
            INC RAX                                                 ; increment length
            JMP .loop_len                                           ; check the next byte

.return_len:
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; str_equal:
;   Purpose:
;       Checks whether two pieces of text are the same
;   Input:
;       RSI = first text,  RDX = size of first text
;       RDI = second text, RCX = size of second text
;   Output:
;       RAX = 1 if they match byte for byte, 0 otherwise
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
str_equal:
            PUSH RBX                                                ; save caller's B register value
            PUSH R8                                                 ; save caller's 8th register value
            XOR RAX, RAX                                            ; set result = 0 (different) until proven the same
            CMP RDX, RCX                                            ; compare the two sizes
            JNE .return_equal                                       ; different sizes can never match
            XOR R8, R8                                              ; set byte counter = 0

.loop_equal:
            CMP R8, RDX                                             ; compare byte counter < size
            JAE .texts_match                                        ; every byte was the same
            MOV BL, [RSI + R8]                                      ; load byte of the first text
            CMP BL, [RDI + R8]                                      ; compare with the same byte of the second text
            JNE .return_equal                                       ; a different byte, result stays 0
            INC R8                                                  ; increment byte counter
            JMP .loop_equal                                         ; check the next byte

.texts_match:
            MOV RAX, 1                                              ; set result = 1 (same)

.return_equal:
            POP R8                                                  ; restore caller's 8th register value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; to_index:
;   Purpose:
;       Converts a letter to its contact index, and so also answers
;       whether a character is a letter the machine has a key for
;   Input:
;       AL = character
;   Output:
;       RAX = index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25
;       RAX = -1 if the character is not a letter A-Z or a-z
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
to_index:
            MOVZX RAX, AL                                           ; clear the rest of RAX around the character
            CMP AL, 'a'                                             ; compare with the first lowercase letter
            JB .check_upper                                         ; below 'a' can only be uppercase or not a letter
            CMP AL, 'z'                                             ; compare with the last lowercase letter
            JA .not_letter                                          ; above 'z' is not a letter
            SUB AL, 'a' - 'A'                                       ; lowercase -> uppercase

.check_upper:
            CMP AL, 'A'                                             ; compare with the first uppercase letter
            JB .not_letter                                          ; below 'A' is not a letter
            CMP AL, 'Z'                                             ; compare with the last uppercase letter
            JA .not_letter                                          ; above 'Z' is not a letter
            SUB AL, 'A'                                             ; letter -> index: 'A' (65) -> 0 ... 'Z' (90) -> 25
            RET                                                     ; return to caller

.not_letter:
            MOV RAX, -1                                             ; set result = -1 (not a letter)
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; is_space:
;   Purpose:
;       Checks whether a character is whitespace: space, tab, newline,
;       vertical tab, form feed or carriage return
;   Input:
;       AL = character
;   Output:
;       RAX = 1 if whitespace, 0 otherwise
;   Clobbers:
;       RAX (the character is gone afterwards, keep a copy)
;-------------------------------------------------------------------;
is_space:
            CMP AL, ' '                                             ; compare with a space
            JE .space_found                                         ; a space is whitespace
            CMP AL, 0x9                                             ; compare with tab, the first of the control group
            JB .space_missing                                       ; below tab is not whitespace
            CMP AL, 0xD                                             ; compare with carriage return, the last of the group
            JA .space_missing                                       ; above carriage return is not whitespace

.space_found:
            MOV RAX, 1                                              ; set result = 1 (whitespace)
            RET                                                     ; return to caller

.space_missing:
            XOR RAX, RAX                                            ; set result = 0 (not whitespace)
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; trim:
;   Purpose:
;       Drops the whitespace from both ends of a piece of text. The
;       text is not copied or changed; only the pointer and size move.
;   Input:
;       RSI = text, RDX = size of text
;   Output:
;       RSI = first non-whitespace character, RDX = size without the ends
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
trim:
.trim_front:
            TEST RDX, RDX                                           ; test the size, ZF=1 means nothing is left
            JZ .return_trim                                         ; nothing left to trim
            MOV AL, [RSI]                                           ; load the first character
            CALL is_space                                           ; check it ( [in]AL , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means not whitespace
            JZ .trim_back                                           ; the front is clean, move on to the back
            INC RSI                                                 ; move the start past the whitespace
            DEC RDX                                                 ; one character fewer
            JMP .trim_front                                         ; check the new first character

.trim_back:
            TEST RDX, RDX                                           ; test the size, ZF=1 means nothing is left
            JZ .return_trim                                         ; nothing left to trim
            MOV AL, [RSI + RDX - 1]                                 ; load the last character
            CALL is_space                                           ; check it ( [in]AL , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means not whitespace
            JZ .return_trim                                         ; the back is clean too
            DEC RDX                                                 ; one character fewer
            JMP .trim_back                                          ; check the new last character

.return_trim:
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; get_byte:
;   Purpose:
;       Hands out the input one byte at a time. The kernel is only
;       asked for more (up to READ_MAX bytes) when the read buffer
;       has been used up.
;   Input:
;       None (reads from the file descriptor in readFd)
;   Output:
;       RAX = the next byte, or -1 at the end of the input
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
get_byte:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value (SYSCALL overwrites it)
            PUSH R11                                                ; save caller's 11th register value (SYSCALL overwrites it)
            MOV RAX, [readPos]                                      ; load how far into the read buffer we are
            CMP RAX, [readLen]                                      ; compare with how much the read buffer holds
            JB .byte_ready                                          ; there are unread bytes, no need to ask for more

            MOV RAX, SYS_READ                                       ; system call number (system_read)
            MOV RDI, [readFd]                                       ; file descriptor to read from
            MOV RSI, readBuf                                        ; buffer to fill
            MOV RDX, READ_MAX                                       ; most bytes to accept
            SYSCALL                                                 ; kernel syscall, RAX = bytes read
            CMP RAX, 0                                              ; compare bytes read with 0
            JLE .input_ended                                        ; 0 is the end of the input, negative is an error
            MOV [readLen], RAX                                      ; remember how much the read buffer holds
            MOV qword [readPos], 0                                  ; start again from the front of the read buffer

.byte_ready:
            MOV RSI, readBuf                                        ; point to the read buffer
            MOV RDX, [readPos]                                      ; load the position of the next byte
            MOVZX RAX, byte [RSI + RDX]                             ; load the next byte
            INC RDX                                                 ; move past it
            MOV [readPos], RDX                                      ; remember the new position
            JMP .return_byte                                        ; hand the byte back

.input_ended:
            MOV qword [readLen], 0                                  ; the read buffer holds nothing
            MOV qword [readPos], 0                                  ; so there is nothing to be part way through
            MOV RAX, -1                                             ; set result = -1 (end of input)

.return_byte:
            POP R11                                                 ; restore caller's 11th register value
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; read_line:
;   Purpose:
;       Reads one line of input into lineBuf, without its newline or
;       any carriage returns before it
;   Input:
;       None (reads from the file descriptor in readFd)
;   Output:
;       lineBuf = the line
;       RAX = length of the line, or -1 when the input has ended and
;             there was nothing left to read
;   Clobbers:
;       RAX
;   Note:
;       A line longer than LINE_MAX is handed back in pieces
;-------------------------------------------------------------------;
read_line:
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            MOV RDI, lineBuf                                        ; point to the line buffer
            XOR RCX, RCX                                            ; set line length = 0

.loop_line:
            CALL get_byte                                           ; fetch the next byte ( [out]RAX )
            CMP RAX, -1                                             ; compare with the end-of-input marker
            JE .line_input_ended                                    ; no more input
            CMP AL, 0xA                                             ; compare with a newline
            JE .strip_line                                          ; the line is complete
            MOV [RDI + RCX], AL                                     ; store the byte in the line buffer
            INC RCX                                                 ; increment line length
            CMP RCX, LINE_MAX                                       ; compare line length < size of the line buffer
            JB .loop_line                                           ; if there is room, fetch the next byte
            JMP .strip_line                                         ; buffer full: hand back this piece

.line_input_ended:
            TEST RCX, RCX                                           ; test the line length, ZF=1 means nothing was read
            JNZ .strip_line                                         ; a last line with no newline still counts
            MOV RAX, -1                                             ; set result = -1 (end of input)
            JMP .return_line                                        ; nothing to hand back

.strip_line:
            TEST RCX, RCX                                           ; test the line length, ZF=1 means empty
            JZ .line_length                                         ; nothing to strip from an empty line
            CMP byte [RDI + RCX - 1], 0xD                           ; compare the last byte with a carriage return
            JNE .line_length                                        ; the end is clean
            DEC RCX                                                 ; drop the carriage return
            JMP .strip_line                                         ; check the new last byte

.line_length:
            MOV RAX, RCX                                            ; set result = line length

.return_line:
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; load_config:
;   Purpose:
;       Loads the plugs and positions settings from the shared
;       enigma.ini file. Reads simple key = value lines, skipping
;       blank lines, comments (; or #), and [section] headers.
;   Input:
;       None
;   Output:
;       cfgPlugs, cfgPlugLen = the plugs value and its size
;       cfgPos,   cfgPosLen  = the positions value and its size
;       Any setting missing from the file (or a missing file) keeps
;       its default: plugs is empty (random cables), positions is AAA
;   Clobbers:
;       RAX
;   Note:
;       Borrows get_byte and read_line by pointing readFd at the file,
;       then points it back at stdin
;-------------------------------------------------------------------;
load_config:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R8                                                 ; save caller's 8th register value
            PUSH R9                                                 ; save caller's 9th register value
            PUSH R11                                                ; save caller's 11th register value (SYSCALL overwrites it)

            ; Defaults: no plugs, positions AAA
            MOV qword [cfgPlugLen], 0                               ; set plugs size = 0 (empty)
            MOV RDI, cfgPos                                         ; point to the positions value
            MOV byte [RDI], 'A'                                     ; rotar I starts at A
            MOV byte [RDI + 1], 'A'                                 ; rotar II starts at A
            MOV byte [RDI + 2], 'A'                                 ; rotar III starts at A
            MOV qword [cfgPosLen], ROTARS                           ; set positions size = one letter per rotar

            MOV RAX, SYS_OPEN                                       ; system call number (system_open)
            MOV RDI, iniPath                                        ; path of the file to open
            MOV RSI, O_RDONLY                                       ; open it for reading only
            XOR RDX, RDX                                            ; no permission bits (only used when creating a file)
            SYSCALL                                                 ; kernel syscall, RAX = file descriptor
            CMP RAX, 0                                              ; compare file descriptor with 0
            JL .config_done                                         ; negative means no readable ini: defaults stay
            MOV [readFd], RAX                                       ; read from the ini instead of stdin
            MOV qword [readPos], 0                                  ; nothing read yet
            MOV qword [readLen], 0                                  ; nothing in the read buffer yet

.config_line:
            CALL read_line                                          ; read one line of the ini ( [out]RAX )
            CMP RAX, -1                                             ; compare with the end-of-input marker
            JE .config_close                                        ; the whole file has been read
            MOV RSI, lineBuf                                        ; point to the line
            MOV RDX, RAX                                            ; set size of the line
            CALL trim                                               ; drop whitespace at both ends ( [in/out]RSI,RDX )
            TEST RDX, RDX                                           ; test the size, ZF=1 means a blank line
            JZ .config_line                                         ; skip blank lines
            MOV AL, [RSI]                                           ; load the first character
            CMP AL, ';'                                             ; compare with a comment marker
            JE .config_line                                         ; skip comments
            CMP AL, '#'                                             ; compare with the other comment marker
            JE .config_line                                         ; skip comments
            CMP AL, '['                                             ; compare with the start of a section header
            JE .config_line                                         ; skip [section] headers
            XOR RCX, RCX                                            ; set search counter = 0

.config_find_equals:
            CMP RCX, RDX                                            ; compare search counter < size of the line
            JAE .config_line                                        ; no '=' in the line, skip it
            CMP byte [RSI + RCX], '='                               ; compare this character with '='
            JE .config_split                                        ; found where the name ends and the value starts
            INC RCX                                                 ; increment search counter
            JMP .config_find_equals                                 ; check the next character

.config_split:
            LEA R8, [RSI + RCX + 1]                                 ; the value starts after the '='
            MOV R9, RDX                                             ; value size = line size ...
            SUB R9, RCX                                             ; ... minus the name ...
            DEC R9                                                  ; ... minus the '=' itself
            MOV RDX, RCX                                            ; the name is everything before the '='
            CALL trim                                               ; drop whitespace around the name ( [in/out]RSI,RDX )

            MOV RDI, iniPlugs                                       ; set the setting name to compare against
            MOV RCX, lenIniPlug                                     ; set the size of that name
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JNZ .config_is_plugs                                    ; this line sets plugs
            MOV RDI, iniPos                                         ; set the other setting name to compare against
            MOV RCX, lenIniPos                                      ; set the size of that name
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JZ .config_line                                         ; not a setting we know, skip the line
            MOV RDI, cfgPos                                         ; the value goes in the positions buffer
            MOV RBX, cfgPosLen                                      ; and its size beside it
            JMP .config_store                                       ; go and store it

.config_is_plugs:
            MOV RDI, cfgPlugs                                       ; the value goes in the plugs buffer
            MOV RBX, cfgPlugLen                                     ; and its size beside it

.config_store:
            MOV RSI, R8                                             ; point to the value
            MOV RDX, R9                                             ; set size of the value
            CALL trim                                               ; drop whitespace around the value ( [in/out]RSI,RDX )
            CMP RDX, CONFIG_MAX                                     ; compare value size with the room there is
            JBE .config_value_fits                                  ; if it fits, keep all of it
            MOV RDX, CONFIG_MAX                                     ; otherwise keep what fits

.config_value_fits:
            MOV [RBX], RDX                                          ; store the size of the value
            XOR RCX, RCX                                            ; set copy counter = 0

.config_copy:
            CMP RCX, RDX                                            ; compare copy counter < size of the value
            JAE .config_line                                        ; value copied, on to the next line
            MOV AL, [RSI + RCX]                                     ; load character of the value
            MOV [RDI + RCX], AL                                     ; store it in the config buffer
            INC RCX                                                 ; increment copy counter
            JMP .config_copy                                        ; copy the next character

.config_close:
            MOV RAX, SYS_CLOSE                                      ; system call number (system_close)
            MOV RDI, [readFd]                                       ; file descriptor of the ini
            SYSCALL                                                 ; kernel syscall

.config_done:
            MOV qword [readFd], STDIN                               ; read from stdin again
            MOV qword [readPos], 0                                  ; nothing read yet
            MOV qword [readLen], 0                                  ; nothing in the read buffer
            POP R11                                                 ; restore caller's 11th register value
            POP R9                                                  ; restore caller's 9th register value
            POP R8                                                  ; restore caller's 8th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; print_label:
;   Purpose:
;       Writes a rotar's name (I, II or III) to stdout
;   Input:
;       RBX = which rotar: 0 = the first (fast) rotar
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_label:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            MOV RSI, rotarLabel                                     ; point to the table of name addresses
            MOV RSI, [RSI + RBX * 8]                                ; load the address of this rotar's name
            MOV RDX, rotarLabLn                                     ; point to the table of name sizes
            MOV RDX, [RDX + RBX * 8]                                ; load the size of this rotar's name
            CALL print                                              ; print the name
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; print_wiring:
;   Purpose:
;       Writes a wiring table to stdout the way every display prints
;       it: the 26 letters, each followed by a space, then a newline
;   Input:
;       RSI = wiring table (26 contact indexes)
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_wiring:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            MOV RDI, wireBuf                                        ; point to the buffer the line is built in
            XOR RCX, RCX                                            ; set contact counter = 0

.loop_wiring:
            MOV AL, [RSI + RCX]                                     ; load where this contact leads
            ADD AL, 'A'                                             ; index -> letter
            MOV [RDI + RCX * 2], AL                                 ; store the letter
            MOV byte [RDI + RCX * 2 + 1], ' '                       ; and a space after it
            INC RCX                                                 ; increment contact counter
            CMP RCX, SYMBOLS                                        ; compare contact counter < number of contacts
            JB .loop_wiring                                         ; if not done, format the next contact

            MOV byte [RDI + SYMBOLS * 2], 0xA                       ; end the line with a newline
            MOV RSI, wireBuf                                        ; set source index to the finished line
            MOV RDX, SYMBOLS * 2 + 1                                ; set size: letter + space per contact, + newline
            CALL print                                              ; print the line
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; rotar_setup:
;   Purpose:
;       Builds rotars I, II and III from the historical wirings, all
;       starting at position 0. A rotar is a two-way translation
;       table: the signal goes forward through it on the way to the
;       reflector and backward on the way out. The wiring never
;       changes; turning the rotar only moves its position, which
;       rotar_pass applies as an offset.
;   Input:
;       None
;   Output:
;       ingress    = forward wiring per rotar: entry contact -> exit contact
;       engress    = inverse wiring per rotar: exit contact -> entry contact
;       rotarStart = 0 per rotar (position it begins at and resets to)
;       rotarPos   = 0 per rotar (current position)
;   Clobbers:
;       RAX
;   Note:
;       The inverse is calculated from the forward wiring, so the two
;       can never disagree
;-------------------------------------------------------------------;
rotar_setup:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R8                                                 ; save caller's 8th register value
            XOR RBX, RBX                                            ; set rotar counter = 0

.loop_rotar:
            MOV RSI, msgRotar                                       ; set source index to the first part of the message
            MOV RDX, lenRotar                                       ; set size of the first part
            CALL print                                              ; print 'Rotar '
            CALL print_label                                        ; print the rotar's name ( [in]RBX )
            MOV RSI, msgLoaded                                      ; set source index to the last part of the message
            MOV RDX, lenLoaded                                      ; set size of the last part
            CALL print                                              ; print ' Loaded...' + newline

            ; Each rotar's tables are SYMBOLS bytes on from the rotar before
            MOV RAX, RBX                                            ; load rotar counter
            IMUL RAX, RAX, SYMBOLS                                  ; rotar counter * 26 = offset of this rotar's row
            MOV RSI, rotarWire                                      ; point to the wiring letters
            ADD RSI, RAX                                            ; move to this rotar's letters
            MOV RDI, ingress                                        ; point to the forward tables
            ADD RDI, RAX                                            ; move to this rotar's forward table
            MOV R8, engress                                         ; point to the inverse tables
            ADD R8, RAX                                             ; move to this rotar's inverse table
            XOR RCX, RCX                                            ; set entry contact = 0

.loop_contact:
            MOVZX RAX, byte [RSI + RCX]                             ; load the letter this entry contact is wired to
            SUB RAX, 'A'                                            ; letter -> exit contact
            MOV [RDI + RCX], AL                                     ; forward: entry contact -> exit contact
            MOV [R8 + RAX], CL                                      ; inverse: exit contact -> entry contact
            INC RCX                                                 ; increment entry contact
            CMP RCX, SYMBOLS                                        ; compare entry contact < number of contacts
            JB .loop_contact                                        ; if not done, wire the next contact

            MOV RSI, rotarStart                                     ; point to the start positions
            MOV byte [RSI + RBX], 0                                 ; this rotar starts at position 0
            MOV RSI, rotarPos                                       ; point to the current positions
            MOV byte [RSI + RBX], 0                                 ; and is at position 0 now
            INC RBX                                                 ; increment rotar counter
            CMP RBX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_rotar                                          ; if not done, build the next rotar

            POP R8                                                  ; restore caller's 8th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; rotar_pass:
;   Purpose:
;       Passes an index through a rotar at its current position, in
;       whichever direction the given tables describe.
;       The disc turns but the wires don't: the signal enters wire
;       (idx + p), and the wire's other end has turned p places too,
;       so p is subtracted on the way out.
;   Input:
;       RSI = wiring tables to use: ingress (forward) or engress (backward)
;       RBX = which rotar: 0 = the first (fast) rotar
;       AL  = contact the signal comes in on, 0-25
;   Output:
;       RAX = contact the signal leaves on, 0-25
;   Clobbers:
;       RAX
;   Note:
;       Both sums stay below 52, so one subtraction of 26 does the
;       job of a remainder
;-------------------------------------------------------------------;
rotar_pass:
            PUSH RSI                                                ; save caller's source index
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            MOVZX RAX, AL                                           ; clear the rest of RAX around the contact
            MOV RDX, rotarPos                                       ; point to the current positions
            MOVZX RCX, byte [RDX + RBX]                             ; load this rotar's position p
            ADD RAX, RCX                                            ; contact + p = the wire the signal meets
            CMP RAX, SYMBOLS                                        ; compare with the number of contacts
            JB .wire_in_range                                       ; if in range, skip the wrap
            SUB RAX, SYMBOLS                                        ; wrap around the disc

.wire_in_range:
            MOV RDX, RBX                                            ; load rotar number
            IMUL RDX, RDX, SYMBOLS                                  ; rotar number * 26 = offset of this rotar's table
            ADD RSI, RDX                                            ; move to this rotar's table
            MOVZX RAX, byte [RSI + RAX]                             ; follow the wire to its other end
            ADD RAX, SYMBOLS                                        ; add 26 first, so the next line can't go negative
            SUB RAX, RCX                                            ; subtract p, the other end has turned too
            CMP RAX, SYMBOLS                                        ; compare with the number of contacts
            JB .return_pass                                         ; if in range, skip the wrap
            SUB RAX, SYMBOLS                                        ; wrap around the disc

.return_pass:
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; rotar_forward:
;   Purpose:
;       Passes an index forward through a rotar at its current position
;   Input:
;       RBX = which rotar: 0 = the first (fast) rotar
;       AL  = entry contact, 0-25
;   Output:
;       RAX = exit contact, 0-25
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
rotar_forward:
            PUSH RSI                                                ; save caller's source index
            MOV RSI, ingress                                        ; use the forward wiring
            CALL rotar_pass                                         ; pass the index through ( [in]RSI,RBX,AL , [out]RAX )
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; rotar_reverse:
;   Purpose:
;       Passes an index backward through a rotar at its current
;       position: the return trip after the reflector. Same position
;       offset as rotar_forward, but looked up in the inverse wiring,
;       so at any position reversing a forwarded index gives the
;       index back.
;   Input:
;       RBX = which rotar: 0 = the first (fast) rotar
;       AL  = contact the signal comes back in on, 0-25
;   Output:
;       RAX = contact it leaves on, 0-25
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
rotar_reverse:
            PUSH RSI                                                ; save caller's source index
            MOV RSI, engress                                        ; use the inverse wiring
            CALL rotar_pass                                         ; pass the index through ( [in]RSI,RBX,AL , [out]RAX )
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; reflector_setup:
;   Purpose:
;       Loads the historical Reflector B wiring and checks it. The
;       reflector sits after the last rotar and sends the signal back
;       through the rotars in reverse. Its wiring is 13 swapped pairs,
;       so it is its own inverse and no letter maps to itself. It
;       never steps and is applied once per key press.
;   Input:
;       None
;   Output:
;       reflection = contact -> paired contact, the same table both ways
;   Clobbers:
;       RAX
;   Note:
;       Prints a message for any letter that breaks the two reflector
;       rules: pairs only, and no letter to itself
;-------------------------------------------------------------------;
reflector_setup:
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            MOV RSI, msgReflLd                                      ; set source index to the message
            MOV RDX, lenReflLd                                      ; set size of the message
            CALL print                                              ; print 'Reflector Loaded...'
            MOV RSI, reflWire                                       ; point to the wiring letters
            MOV RDI, reflection                                     ; point to the reflector table
            XOR RCX, RCX                                            ; set contact counter = 0

.loop_reflect:
            MOV AL, [RSI + RCX]                                     ; load the letter this contact is paired with
            SUB AL, 'A'                                             ; letter -> contact
            MOV [RDI + RCX], AL                                     ; store the paired contact
            INC RCX                                                 ; increment contact counter
            CMP RCX, SYMBOLS                                        ; compare contact counter < number of contacts
            JB .loop_reflect                                        ; if not done, convert the next letter

            ; A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
            XOR RCX, RCX                                            ; set contact counter = 0

.loop_check:
            MOVZX RAX, byte [RDI + RCX]                             ; load this contact's partner
            CMP RAX, RCX                                            ; compare the partner with the contact itself
            JE .invalid_wiring                                      ; a contact can't be its own partner
            MOVZX RDX, byte [RDI + RAX]                             ; load the partner's partner
            CMP RDX, RCX                                            ; compare it with the contact we started from
            JE .next_check                                          ; back where we started: a proper pair

.invalid_wiring:
            MOV RSI, msgReflEr                                      ; set source index to the error text
            MOV RDX, lenReflEr                                      ; set size of the error text
            CALL print                                              ; print 'Reflector: invalid wiring at '
            MOV AL, CL                                              ; load the contact
            ADD AL, 'A'                                             ; contact -> letter
            CALL print_char                                         ; print the letter
            MOV AL, 0xA                                             ; load a newline
            CALL print_char                                         ; end the line

.next_check:
            INC RCX                                                 ; increment contact counter
            CMP RCX, SYMBOLS                                        ; compare contact counter < number of contacts
            JB .loop_check                                          ; if not done, check the next contact

            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; plugboard_setup:
;   Purpose:
;       Builds a plugboard with random cables. Each cable swaps two
;       letters (A <-> V); letters without a cable pass through
;       unchanged. Up to 13 cables, 10 was standard. Because it is
;       built from pairs it is its own inverse, so the same table
;       serves the pass in and the pass out. Use set_pairs afterwards
;       to plug in a known key instead.
;   Input:
;       None
;   Output:
;       plugTable = letter -> swapped letter (itself when no cable is plugged)
;       plugPairs, plugPairLn = the cables as "AV BS CG ..." and its size
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
plugboard_setup:
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            MOV RSI, msgPlugLd                                      ; set source index to the message
            MOV RDX, lenPlugLd                                      ; set size of the message
            CALL print                                              ; print 'Plugboard is Loaded...'
            MOV RDI, plugTable                                      ; point to the plugboard table
            XOR RCX, RCX                                            ; set letter counter = 0

.loop_unplugged:
            MOV [RDI + RCX], CL                                     ; no cables: every letter maps to itself
            INC RCX                                                 ; increment letter counter
            CMP RCX, SYMBOLS                                        ; compare letter counter < number of letters
            JB .loop_unplugged                                      ; if not done, set the next letter

            MOV qword [plugPairLn], 0                               ; no cables, so the key is empty
            CALL random_config                                      ; plug in random cables
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; random_config:
;   Purpose:
;       Plugs in CABLES random cables. Shuffles the 26 letters and
;       takes neighbours as pairs, (0,1), (2,3), ..., so no letter can
;       land in two cables. Print the key to keep it for decrypting.
;   Input:
;       None
;   Output:
;       plugTable, plugPairs, plugPairLn (see plugboard_setup)
;   Clobbers:
;       RAX
;   Note:
;       The random numbers come from the kernel (system_getrandom),
;       two bytes for each step of the shuffle
;-------------------------------------------------------------------;
random_config:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value (SYSCALL overwrites it)
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R11                                                ; save caller's 11th register value (SYSCALL overwrites it)
            MOV RAX, SYS_RANDOM                                     ; system call number (system_getrandom)
            MOV RDI, randBuf                                        ; buffer to fill with random bytes
            MOV RSI, RANDOM_MAX                                     ; number of random bytes wanted
            XOR RDX, RDX                                            ; no flags
            SYSCALL                                                 ; kernel syscall

            MOV RDI, shuffleBuf                                     ; point to the letters to shuffle
            XOR RCX, RCX                                            ; set letter counter = 0

.loop_letters:
            MOV AL, CL                                              ; load letter counter
            ADD AL, 'A'                                             ; index -> letter
            MOV [RDI + RCX], AL                                     ; store the letter: A, B, C, ... in order
            INC RCX                                                 ; increment letter counter
            CMP RCX, SYMBOLS                                        ; compare letter counter < number of letters
            JB .loop_letters                                        ; if not done, store the next letter

            ; Fisher-Yates shuffle: swap each slot, last to second, with a random slot at or below it
            MOV RSI, randBuf                                        ; point to the random bytes
            MOV RCX, SYMBOLS - 1                                    ; set slot counter i = last slot

.loop_shuffle:
            MOVZX RAX, word [RSI + RCX * 2]                         ; load 16 random bits for this step
            XOR RDX, RDX                                            ; clear the high half of the dividend
            LEA RBX, [RCX + 1]                                      ; set divisor = i + 1 (slots 0 to i)
            DIV RBX                                                 ; RDX = random % (i + 1) = slot j
            MOV AL, [RDI + RCX]                                     ; load the letter in slot i
            MOV BL, [RDI + RDX]                                     ; load the letter in slot j
            MOV [RDI + RCX], BL                                     ; slot i gets the letter from slot j
            MOV [RDI + RDX], AL                                     ; slot j gets the letter from slot i
            DEC RCX                                                 ; decrement slot counter, ZF=1 when it reaches 0
            JNZ .loop_shuffle                                       ; slot 0 has nothing below it to swap with

            MOV RSI, shuffleBuf                                     ; set key to the shuffled letters
            MOV RDX, CABLES * 2                                     ; set key size: two letters per cable
            CALL set_pairs                                          ; plug them in ( [in]RSI,RDX , [out]RAX )
            POP R11                                                 ; restore caller's 11th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; set_pairs:
;   Purpose:
;       Plugs in cables from a key-sheet style string. Builds the
;       table into a scratch copy and only keeps it if every pair is
;       valid, so a typo leaves the previous cables in place.
;   Input:
;       RSI = letter pairs, spaces optional, any case: "AV BS CG" or "avbscg"
;       RDX = size of the text
;   Output:
;       RAX = 1 when the key was plugged in
;       RAX = 0 (with a message) on a non-letter, a letter paired with
;             itself, a letter used twice, or a leftover letter with
;             no partner
;       plugTable, plugPairs, plugPairLn updated when RAX = 1
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
set_pairs:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R8                                                 ; save caller's 8th register value
            PUSH R9                                                 ; save caller's 9th register value
            PUSH R10                                                ; save caller's 10th register value
            MOV RDI, tmpTable                                       ; point to the scratch table
            XOR RCX, RCX                                            ; set letter counter = 0

.loop_scratch:
            MOV [RDI + RCX], CL                                     ; no cables: every letter maps to itself
            INC RCX                                                 ; increment letter counter
            CMP RCX, SYMBOLS                                        ; compare letter counter < number of letters
            JB .loop_scratch                                        ; if not done, set the next letter

            ; Pass 1: keep the letters, uppercased; skip whitespace; refuse anything else
            MOV RDI, letters                                        ; point to the buffer the letters are kept in
            XOR R8, R8                                              ; set letters kept = 0
            XOR RCX, RCX                                            ; set text counter = 0

.loop_collect:
            CMP RCX, RDX                                            ; compare text counter < size of the text
            JAE .letters_collected                                  ; the whole text has been read
            MOV BL, [RSI + RCX]                                     ; load this character (BL keeps it across the calls)
            INC RCX                                                 ; increment text counter
            MOV AL, BL                                              ; copy the character for the check
            CALL is_space                                           ; check for whitespace ( [in]AL , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means not whitespace
            JNZ .loop_collect                                       ; skip whitespace
            MOV AL, BL                                              ; copy the character for the conversion
            CALL to_index                                           ; letter -> index ( [in]AL , [out]RAX )
            CMP RAX, -1                                             ; compare with the not-a-letter marker
            JE .error_not_letter                                    ; only letters can be plugged
            ADD AL, 'A'                                             ; index -> uppercase letter
            MOV [RDI + R8], AL                                      ; keep the letter
            INC R8                                                  ; increment letters kept
            JMP .loop_collect                                       ; read the next character

.error_not_letter:
            MOV RSI, msgQuote                                       ; set source index to the error text
            MOV RDX, lenQuote                                       ; set size of the error text
            CALL print                                              ; print "Plugboard: '"
            MOV AL, BL                                              ; load the character that isn't a letter
            CALL print_char                                         ; print it
            MOV RSI, msgNotLet                                      ; set source index to the rest of the error
            MOV RDX, lenNotLet                                      ; set size of the rest
            CALL print                                              ; print "' is not a letter"
            JMP .pairs_rejected                                     ; the key is refused

.letters_collected:
            TEST R8, 1                                              ; test the lowest bit of letters kept, ZF=1 means even
            JZ .pairs_start                                         ; an even count can be split into pairs
            MOV RSI, msgPlug                                        ; set source index to the error text
            MOV RDX, lenPlug                                        ; set size of the error text
            CALL print                                              ; print 'Plugboard: '
            MOV AL, [RDI + R8 - 1]                                  ; load the last letter, the one left over
            CALL print_char                                         ; print it
            MOV RSI, msgNoPart                                      ; set source index to the rest of the error
            MOV RDX, lenNoPart                                      ; set size of the rest
            CALL print                                              ; print ' has no partner'
            JMP .pairs_rejected                                     ; the key is refused

            ; Pass 2: plug each pair into the scratch table
.pairs_start:
            MOV RSI, tmpTable                                       ; point to the scratch table
            MOV R10, tmpPairs                                       ; point to the buffer the tidy key is built in
            XOR R9, R9                                              ; set tidy key size = 0
            XOR RCX, RCX                                            ; set letter counter = 0

.loop_pair:
            CMP RCX, R8                                             ; compare letter counter < letters kept
            JAE .pairs_accepted                                     ; every pair is plugged
            MOVZX RAX, byte [RDI + RCX]                             ; load the first letter of the pair
            MOVZX RBX, byte [RDI + RCX + 1]                         ; load the second letter of the pair
            CMP AL, BL                                              ; compare the two letters
            JE .error_self                                          ; a cable needs two different letters
            SUB AL, 'A'                                             ; first letter -> index a
            SUB BL, 'A'                                             ; second letter -> index b
            CMP [RSI + RAX], AL                                     ; compare table[a] with a
            JNE .error_reused                                       ; already swapped by an earlier cable
            CMP [RSI + RBX], BL                                     ; compare table[b] with b
            JNE .error_reused                                       ; already swapped by an earlier cable
            MOV [RSI + RAX], BL                                     ; table[a] = b
            MOV [RSI + RBX], AL                                     ; table[b] = a
            ADD AL, 'A'                                             ; index a -> letter
            ADD BL, 'A'                                             ; index b -> letter
            MOV [R10 + R9], AL                                      ; add the first letter to the tidy key
            MOV [R10 + R9 + 1], BL                                  ; add the second letter
            MOV byte [R10 + R9 + 2], ' '                            ; and a space after the pair
            ADD R9, 3                                               ; tidy key grew by three characters
            ADD RCX, 2                                              ; move on two letters
            JMP .loop_pair                                          ; plug the next pair

.error_self:
            MOV RSI, msgPlug                                        ; set source index to the error text
            MOV RDX, lenPlug                                        ; set size of the error text
            CALL print                                              ; print 'Plugboard: '
            MOV AL, BL                                              ; load the letter (both of the pair are the same)
            CALL print_char                                         ; print it
            MOV RSI, msgSelf                                        ; set source index to the rest of the error
            MOV RDX, lenSelf                                        ; set size of the rest
            CALL print                                              ; print " can't be plugged into itself"
            JMP .pairs_rejected                                     ; the key is refused

.error_reused:
            MOV RSI, msgPlug                                        ; set source index to the error text
            MOV RDX, lenPlug                                        ; set size of the error text
            CALL print                                              ; print 'Plugboard: '
            MOV AL, [RDI + RCX]                                     ; load the first letter of the pair again
            CALL print_char                                         ; print it
            MOV AL, [RDI + RCX + 1]                                 ; load the second letter of the pair again
            CALL print_char                                         ; print it
            MOV RSI, msgReuse                                       ; set source index to the rest of the error
            MOV RDX, lenReuse                                       ; set size of the rest
            CALL print                                              ; print ' reuses a plugged letter'
            JMP .pairs_rejected                                     ; the key is refused

            ; Every pair was valid: the scratch copies become the real ones
.pairs_accepted:
            MOV RSI, tmpTable                                       ; point to the scratch table
            MOV RDI, plugTable                                      ; point to the plugboard table
            XOR RCX, RCX                                            ; set copy counter = 0

.loop_keep_table:
            MOV AL, [RSI + RCX]                                     ; load entry of the scratch table
            MOV [RDI + RCX], AL                                     ; store it in the plugboard table
            INC RCX                                                 ; increment copy counter
            CMP RCX, SYMBOLS                                        ; compare copy counter < number of letters
            JB .loop_keep_table                                     ; if not done, copy the next entry

            TEST R9, R9                                             ; test the tidy key size, ZF=1 means no cables
            JZ .keep_key                                            ; nothing to trim from an empty key
            DEC R9                                                  ; drop the space after the last pair

.keep_key:
            MOV [plugPairLn], R9                                    ; store the size of the key
            MOV RDI, plugPairs                                      ; point to the key
            XOR RCX, RCX                                            ; set copy counter = 0

.loop_keep_key:
            CMP RCX, R9                                             ; compare copy counter < size of the key
            JAE .key_kept                                           ; the whole key is copied
            MOV AL, [R10 + RCX]                                     ; load character of the tidy key
            MOV [RDI + RCX], AL                                     ; store it in the key
            INC RCX                                                 ; increment copy counter
            JMP .loop_keep_key                                      ; copy the next character

.key_kept:
            MOV RAX, 1                                              ; set result = 1 (plugged in)
            JMP .return_pairs                                       ; done

.pairs_rejected:
            XOR RAX, RAX                                            ; set result = 0 (refused, nothing changed)

.return_pairs:
            POP R10                                                 ; restore caller's 10th register value
            POP R9                                                  ; restore caller's 9th register value
            POP R8                                                  ; restore caller's 8th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; print_key:
;   Purpose:
;       Writes the plugboard key line to stdout
;   Input:
;       None
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_key:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            MOV RSI, msgKey                                         ; set source index to the header
            MOV RDX, lenKey                                         ; set size of the header
            CALL print                                              ; print 'Plugboard key: '
            MOV RSI, plugPairs                                      ; set source index to the key
            MOV RDX, [plugPairLn]                                   ; set size of the key
            CALL print                                              ; print the key
            MOV AL, 0xA                                             ; load a newline
            CALL print_char                                         ; end the line
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; print_positions:
;   Purpose:
;       Writes the rotar start positions line to stdout: one uppercase
;       letter per rotar, rotar I first
;   Input:
;       None
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_positions:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            PUSH RCX                                                ; save caller's counter value
            MOV RSI, msgPos                                         ; set source index to the header
            MOV RDX, lenPos                                         ; set size of the header
            CALL print                                              ; print 'Rotar positions: '
            MOV RSI, rotarStart                                     ; point to the start positions
            XOR RCX, RCX                                            ; set rotar counter = 0

.loop_positions:
            MOV AL, [RSI + RCX]                                     ; load this rotar's start position
            ADD AL, 'A'                                             ; position -> letter
            CALL print_char                                         ; print the letter
            INC RCX                                                 ; increment rotar counter
            CMP RCX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_positions                                      ; if not done, print the next rotar's letter

            MOV AL, 0xA                                             ; load a newline
            CALL print_char                                         ; end the line
            POP RCX                                                 ; restore caller's counter value
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; enigma_setup:
;   Purpose:
;       Builds the machine: a plugboard, Reflector B and rotars I, II,
;       III. Encrypting and decrypting are the same operation: put the
;       machine back in the state it started in (same plugboard key,
;       same start positions, rotars reset) and type the ciphertext.
;       Prints the plugboard key and the rotar start positions once,
;       after they are settled, so they can be written down and used
;       later to decrypt.
;   Input:
;       RSI = plugboard pairs, e.g. "AV BS CG"; RDX = size of the text.
;             Size 0 keeps the random cables the plugboard starts
;             with; so does a key that set_pairs refuses.
;       R8  = one start letter per rotar, rotar I first, e.g. "AAA";
;       R9  = size of the text. Size 0, or a value set_positions
;             refuses, leaves every rotar at A.
;   Output:
;       None
;   Clobbers:
;       RAX
;   Note:
;       Stepping is a plain odometer carry, and there are no ring
;       settings or rotar order to choose, so output will not match a
;       historical Enigma
;-------------------------------------------------------------------;
enigma_setup:
            PUSH RSI                                                ; save caller's source index (the key)
            PUSH RDX                                                ; save caller's D register value (the key size)
            CALL plugboard_setup                                    ; build the plugboard with random cables
            CALL reflector_setup                                    ; build the reflector
            MOV RSI, msgEnigLd                                      ; set source index to the message
            MOV RDX, lenEnigLd                                      ; set size of the message
            CALL print                                              ; print 'Enigma is Loaded...'
            CALL rotar_setup                                        ; build rotars I, II, III
            POP RDX                                                 ; restore the key size
            POP RSI                                                 ; restore the key

            TEST RDX, RDX                                           ; test the key size, ZF=1 means no key given
            JZ .setup_positions                                     ; keep the random cables
            CALL set_plugs                                          ; plug in the key ( [in]RSI,RDX , [out]RAX )

.setup_positions:
            TEST R9, R9                                             ; test the positions size, ZF=1 means none given
            JZ .setup_report                                        ; leave every rotar at A
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            MOV RSI, R8                                             ; set source index to the positions
            MOV RDX, R9                                             ; set size of the positions
            CALL set_positions                                      ; set the start positions ( [in]RSI,RDX , [out]RAX )
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index

.setup_report:
            CALL print_key                                          ; print the plugboard key line
            CALL print_positions                                    ; print the rotar positions line
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; display:
;   Purpose:
;       Prints the wiring of every part: plugboard, each rotar, then
;       the reflector. In each table the letter in slot 1 is where A
;       leads, slot 2 where B leads, and so on. Rotar wiring is shown
;       as built; the current position is not applied.
;   Input:
;       None
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
display:
            PUSH RBX                                                ; save caller's B register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            MOV RSI, msgPlugCf                                      ; set source index to the plugboard title
            MOV RDX, lenPlugCf                                      ; set size of the title
            CALL print                                              ; print 'Plugboard Configuration ('
            MOV RSI, plugPairs                                      ; set source index to the key
            MOV RDX, [plugPairLn]                                   ; set size of the key
            CALL print                                              ; print the key
            MOV RSI, msgParen                                       ; set source index to the end of the title
            MOV RDX, lenParen                                       ; set size of the end
            CALL print                                              ; print ')' + newline
            MOV RSI, plugTable                                      ; point to the plugboard table
            CALL print_wiring                                       ; print it ( [in]RSI )
            XOR RBX, RBX                                            ; set rotar counter = 0

.loop_display:
            MOV RSI, msgRotary                                      ; set source index to the rotar title
            MOV RDX, lenRotary                                      ; set size of the title
            CALL print                                              ; print 'Rotary '
            CALL print_label                                        ; print the rotar's name ( [in]RBX )
            MOV RSI, msgConfig                                      ; set source index to the end of the title
            MOV RDX, lenConfig                                      ; set size of the end
            CALL print                                              ; print ' Configuration' + newline
            MOV RAX, RBX                                            ; load rotar counter
            IMUL RAX, RAX, SYMBOLS                                  ; rotar counter * 26 = offset of this rotar's table
            MOV RSI, ingress                                        ; point to the forward tables
            ADD RSI, RAX                                            ; move to this rotar's forward table
            CALL print_wiring                                       ; print it ( [in]RSI )
            INC RBX                                                 ; increment rotar counter
            CMP RBX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_display                                        ; if not done, display the next rotar

            MOV RSI, msgReflCf                                      ; set source index to the reflector title
            MOV RDX, lenReflCf                                      ; set size of the title
            CALL print                                              ; print 'Reflector Configuration'
            MOV RSI, reflection                                     ; point to the reflector table
            CALL print_wiring                                       ; print it ( [in]RSI )
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; process_input:
;   Purpose:
;       Runs a line of text through the machine and prints the result.
;       Each letter is one key press, so the rotars keep moving from
;       wherever the last line left them. Non-letters are skipped and
;       do not step the rotars. Prints one trace line per letter (see
;       translate_character), then "Output:" with the result.
;   Input:
;       RSI = text to encrypt or decrypt, any case
;       RDX = size of the text
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
process_input:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R8                                                 ; save caller's 8th register value
            MOV RDI, outBuf                                         ; point to the buffer the result is built in
            XOR R8, R8                                              ; set result size = 0
            XOR RCX, RCX                                            ; set text counter = 0

.loop_input:
            CMP RCX, RDX                                            ; compare text counter < size of the text
            JAE .input_done                                         ; the whole text has been through
            MOV BL, [RSI + RCX]                                     ; load this character (BL keeps it across the call)
            INC RCX                                                 ; increment text counter
            MOV AL, BL                                              ; copy the character for the check
            CALL to_index                                           ; is it a letter? ( [in]AL , [out]RAX )
            CMP RAX, -1                                             ; compare with the not-a-letter marker
            JE .loop_input                                          ; skip non-letters
            MOV AL, BL                                              ; copy the letter for the key press
            CALL translate_character                                ; press the key ( [in]AL , [out]AL )
            MOV [RDI + R8], AL                                      ; add the lit lamp to the result
            INC R8                                                  ; increment result size
            JMP .loop_input                                         ; read the next character

.input_done:
            MOV RSI, msgOutput                                      ; set source index to the header
            MOV RDX, lenOutput                                      ; set size of the header
            CALL print                                              ; print 'Output: '
            MOV RSI, outBuf                                         ; set source index to the result
            MOV RDX, R8                                             ; set size of the result
            CALL print                                              ; print the result
            MOV AL, 0xA                                             ; load a newline
            CALL print_char                                         ; end the line
            POP R8                                                  ; restore caller's 8th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; run_cli:
;   Purpose:
;       Reads lines until "exit" (or the end of input).
;       Commands:   exit            quit
;                   reset           turn the rotars back to their start positions
;                   plugs           show the plugboard key
;                   plugs AV BS ..  set the plugboard (also resets the rotars)
;                   show            display every part's wiring
;       Any other line is run through the machine; non-letters are
;       skipped. To decrypt: reset (and set the same plugs), then type
;       the ciphertext. In a new run the start positions must match
;       too; those come from enigma.ini.
;       A line that starts with a command word is always taken as the
;       command, so those four words can't begin a message.
;   Input:
;       testMode = 0 wipes the console once before the first prompt
;                  and prints the plugboard key and rotar positions
;                  again; results stay on screen after that.
;                  1 leaves the console alone.
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
run_cli:
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH R12                                                ; save caller's 12th register value
            PUSH R13                                                ; save caller's 13th register value
            PUSH R14                                                ; save caller's 14th register value
            PUSH R15                                                ; save caller's 15th register value
            CMP byte [testMode], 0                                  ; compare test mode flag with 0
            JNE .cli_prompt                                         ; in test mode, leave the console alone
            MOV RSI, msgClear                                       ; set source index to the escape codes
            MOV RDX, lenClear                                       ; set size of the escape codes
            CALL print                                              ; clear the screen once, so results stay on screen between prompts
            CALL print_key                                          ; the startup copy was just cleared, print the key again
            CALL print_positions                                    ; and the positions

.cli_prompt:
            MOV RSI, msgPrompt                                      ; set source index to the prompt
            MOV RDX, lenPrompt                                      ; set size of the prompt
            CALL print                                              ; print '>> '
            CALL read_line                                          ; read a line into lineBuf ( [out]RAX )
            CMP RAX, -1                                             ; compare with the end-of-input marker
            JE .cli_done                                            ; no more input
            MOV R12, RAX                                            ; keep the size of the line

            ; The command is everything before the first space, the arguments everything after it
            MOV RSI, lineBuf                                        ; point to the line
            XOR RCX, RCX                                            ; set search counter = 0

.cli_find_space:
            CMP RCX, R12                                            ; compare search counter < size of the line
            JAE .cli_no_arguments                                   ; no space: the whole line is the command
            CMP byte [RSI + RCX], ' '                               ; compare this character with a space
            JE .cli_arguments                                       ; found where the command ends
            INC RCX                                                 ; increment search counter
            JMP .cli_find_space                                     ; check the next character

.cli_no_arguments:
            MOV R13, R12                                            ; command size = the whole line
            XOR R15, R15                                            ; arguments size = 0
            JMP .cli_dispatch                                       ; go and find the command

.cli_arguments:
            MOV R13, RCX                                            ; command size = characters before the space
            LEA R14, [RSI + RCX + 1]                                ; the arguments start after the space
            MOV R15, R12                                            ; arguments size = line size ...
            SUB R15, RCX                                            ; ... minus the command ...
            DEC R15                                                 ; ... minus the space itself

.cli_dispatch:
            MOV RDX, R13                                            ; set size of the command (RSI still points to the line)
            MOV RDI, cmdExit                                        ; set the command to compare against
            MOV RCX, lenCmdExit                                     ; set the size of that command
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JNZ .cli_done                                           ; exit: stop reading

            MOV RDI, cmdReset                                       ; set the command to compare against
            MOV RCX, lenCmdRset                                     ; set the size of that command
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JNZ .cli_reset                                          ; reset: turn the rotars back

            MOV RDI, cmdPlugs                                       ; set the command to compare against
            MOV RCX, lenCmdPlug                                     ; set the size of that command
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JNZ .cli_plugs                                          ; plugs: show or set the key

            MOV RDI, cmdShow                                        ; set the command to compare against
            MOV RCX, lenCmdShow                                     ; set the size of that command
            CALL str_equal                                          ; compare ( [in]RSI,RDX,RDI,RCX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means different
            JNZ .cli_show                                           ; show: display the wiring

            MOV RDX, R12                                            ; not a command: set size of the whole line
            CALL process_input                                      ; run it through the machine ( [in]RSI,RDX )
            JMP .cli_prompt                                         ; ask for the next line

.cli_reset:
            CALL reset_rotars                                       ; turn every rotar back to its start position
            MOV RSI, msgReset                                       ; set source index to the message
            MOV RDX, lenReset                                       ; set size of the message
            CALL print                                              ; print 'Rotars reset'
            JMP .cli_prompt                                         ; ask for the next line

.cli_plugs:
            TEST R15, R15                                           ; test the arguments size, ZF=1 means none
            JZ .cli_show_key                                        ; no key given: only show the current one
            MOV RSI, R14                                            ; set source index to the arguments
            MOV RDX, R15                                            ; set size of the arguments
            CALL set_plugs                                          ; plug in the key ( [in]RSI,RDX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means the key was refused
            JZ .cli_show_key                                        ; refused: nothing was reset
            MOV RSI, msgReset                                       ; set source index to the message
            MOV RDX, lenReset                                       ; set size of the message
            CALL print                                              ; print 'Rotars reset'

.cli_show_key:
            CALL print_key                                          ; print the plugboard key line
            JMP .cli_prompt                                         ; ask for the next line

.cli_show:
            CALL display                                            ; print the wiring of every part
            JMP .cli_prompt                                         ; ask for the next line

.cli_done:
            POP R15                                                 ; restore caller's 15th register value
            POP R14                                                 ; restore caller's 14th register value
            POP R13                                                 ; restore caller's 13th register value
            POP R12                                                 ; restore caller's 12th register value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; step_rotars:
;   Purpose:
;       Steps the rotars like an odometer. The first rotar steps on
;       every key press; each rotar that wraps from position 25 back
;       to 0 carries one step into the next.
;   Input:
;       None
;   Output:
;       rotarPos = the new positions
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
step_rotars:
            PUSH RSI                                                ; save caller's source index
            PUSH RCX                                                ; save caller's counter value
            MOV RSI, rotarPos                                       ; point to the current positions
            XOR RCX, RCX                                            ; set rotar counter = 0

.loop_step:
            MOV AL, [RSI + RCX]                                     ; load this rotar's position
            INC AL                                                  ; advance it one position
            CMP AL, SYMBOLS                                         ; compare with the number of positions
            JB .step_stops                                          ; no full turn, so nothing carries further
            MOV byte [RSI + RCX], 0                                 ; full turn: back to position 0
            INC RCX                                                 ; carry into the next rotar
            CMP RCX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_step                                           ; if there is a next rotar, step it
            JMP .return_step                                        ; the last rotar's carry goes nowhere

.step_stops:
            MOV [RSI + RCX], AL                                     ; store the new position

.return_step:
            POP RCX                                                 ; restore caller's counter value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; reset_rotars:
;   Purpose:
;       Turns every rotar back to its start position. The plugboard is
;       left alone. Do this before typing ciphertext to decrypt it.
;   Input:
;       None
;   Output:
;       rotarPos = rotarStart
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
reset_rotars:
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            MOV RSI, rotarStart                                     ; point to the start positions
            MOV RDI, rotarPos                                       ; point to the current positions
            XOR RCX, RCX                                            ; set rotar counter = 0

.loop_reset:
            MOV AL, [RSI + RCX]                                     ; load this rotar's start position
            MOV [RDI + RCX], AL                                     ; make it the current position
            INC RCX                                                 ; increment rotar counter
            CMP RCX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_reset                                          ; if not done, reset the next rotar

            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; set_plugs:
;   Purpose:
;       Plugs in a new key and resets the rotars, so the machine
;       starts from a known state
;   Input:
;       RSI = letter pairs, e.g. "AV BS CG"
;       RDX = size of the text
;   Output:
;       RAX = 1 when the key was plugged in
;       RAX = 0 if the key was refused; the previous cables and rotar
;             positions stay as they were
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
set_plugs:
            CALL set_pairs                                          ; plug in the key ( [in]RSI,RDX , [out]RAX )
            TEST RAX, RAX                                           ; test the result, ZF=1 means the key was refused
            JZ .return_plugs                                        ; refused: leave the rotars where they are
            CALL reset_rotars                                       ; turn the rotars back (clobbers RAX)
            MOV RAX, 1                                              ; set result = 1 (plugged in)

.return_plugs:
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; set_positions:
;   Purpose:
;       Sets where each rotar starts, and turns the rotars there
;   Input:
;       RSI = one letter per rotar, rotar I (the fast rotar) first,
;             either case: "AAA" is all at 0, "BAA" starts rotar I
;             one step on
;       RDX = size of the text
;   Output:
;       RAX = 1 when the positions were set
;       RAX = 0 (with a message) unless it is exactly one letter per
;             rotar; the rotars then stay as they were
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
set_positions:
            PUSH RCX                                                ; save caller's counter value
            PUSH RDI                                                ; save caller's destination index
            CMP RDX, ROTARS                                         ; compare size of the text with the number of rotars
            JNE .positions_invalid                                  ; it has to be one letter per rotar
            XOR RCX, RCX                                            ; set rotar counter = 0

            ; Check every letter before changing anything
.loop_check_positions:
            MOV AL, [RSI + RCX]                                     ; load this rotar's character
            CALL to_index                                           ; letter -> index ( [in]AL , [out]RAX )
            CMP RAX, -1                                             ; compare with the not-a-letter marker
            JE .positions_invalid                                   ; only letters name a position
            INC RCX                                                 ; increment rotar counter
            CMP RCX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_check_positions                                ; if not done, check the next character

            XOR RCX, RCX                                            ; set rotar counter = 0

.loop_set_positions:
            MOV AL, [RSI + RCX]                                     ; load this rotar's letter
            CALL to_index                                           ; letter -> position ( [in]AL , [out]RAX )
            MOV RDI, rotarStart                                     ; point to the start positions
            MOV [RDI + RCX], AL                                     ; the rotar begins at and resets to this position
            MOV RDI, rotarPos                                       ; point to the current positions
            MOV [RDI + RCX], AL                                     ; and is turned there now
            INC RCX                                                 ; increment rotar counter
            CMP RCX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_set_positions                                  ; if not done, set the next rotar

            MOV RAX, 1                                              ; set result = 1 (positions set)
            JMP .return_positions                                   ; done

.positions_invalid:
            PUSH RSI                                                ; save the text pointer (print needs RSI)
            PUSH RDX                                                ; save the text size (print needs RDX)
            MOV RSI, msgPosErA                                      ; set source index to the error text
            MOV RDX, lenPosErA                                      ; set size of the error text
            CALL print                                              ; print 'Enigma: positions "'
            POP RDX                                                 ; restore the text size
            POP RSI                                                 ; restore the text pointer
            CALL print                                              ; print the value that was refused
            PUSH RSI                                                ; save the text pointer again
            PUSH RDX                                                ; save the text size again
            MOV RSI, msgPosErB                                      ; set source index to the rest of the error
            MOV RDX, lenPosErB                                      ; set size of the rest
            CALL print                                              ; print '" must be 3 letters, one per rotar'
            POP RDX                                                 ; restore the text size
            POP RSI                                                 ; restore the text pointer
            XOR RAX, RAX                                            ; set result = 0 (refused, nothing changed)

.return_positions:
            POP RDI                                                 ; restore caller's destination index
            POP RCX                                                 ; restore caller's counter value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; trace_add:
;   Purpose:
;       Adds the next stage to the trace line: ' => ' and the letter
;       for a contact
;   Input:
;       RAX = contact, 0-25
;       RDI = where in traceBuf to write
;   Output:
;       RDI = moved past what was written
;       RAX = unchanged
;   Clobbers:
;       None
;-------------------------------------------------------------------;
trace_add:
            PUSH RDX                                                ; save caller's D register value
            MOV EDX, [msgArrow]                                     ; load the four characters ' => '
            MOV [RDI], EDX                                          ; write them to the trace line
            MOV DL, AL                                              ; copy the contact
            ADD DL, 'A'                                             ; contact -> letter
            MOV [RDI + 4], DL                                       ; write the letter after the arrow
            ADD RDI, 5                                              ; move past the arrow and the letter
            POP RDX                                                 ; restore caller's D register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; translate_character:
;   Purpose:
;       One key press: steps the rotars, then runs the full signal path.
;       key -> plugboard -> I -> II -> III -> reflector
;           -> III -> II -> I -> plugboard -> lamp
;       Prints each stage, so the line reads left to right along that
;       path: ten letters, the first being the key typed and the last
;       the lamp.
;   Input:
;       AL = the key pressed; must be a letter, either case
;   Output:
;       AL = the lit lamp (uppercase letter)
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
translate_character:
            PUSH RBX                                                ; save caller's B register value
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            CALL to_index                                           ; letter -> index: 'A'/'a' -> 0 ... 'Z'/'z' -> 25
            MOV RCX, RAX                                            ; keep the index (step_rotars clobbers RAX)
            CALL step_rotars                                        ; rotors move before the signal passes through
            MOV RAX, RCX                                            ; bring the index back

            MOV RDI, traceBuf                                       ; point to the start of the trace line
            MOV DL, AL                                              ; copy the index
            ADD DL, 'A'                                             ; index -> letter
            MOV [RDI], DL                                           ; the trace starts with the key typed
            INC RDI                                                 ; move past it

            MOV RSI, plugTable                                      ; point to the plugboard table
            MOVZX RAX, byte [RSI + RAX]                             ; through the plugboard, on the way in
            CALL trace_add                                          ; add the stage to the trace ( [in]RAX,RDI )
            XOR RBX, RBX                                            ; set rotar counter = 0 (the fast rotar first)

.loop_forward:
            CALL rotar_forward                                      ; forward through this rotar ( [in]RBX,AL , [out]RAX )
            CALL trace_add                                          ; add the stage to the trace ( [in]RAX,RDI )
            INC RBX                                                 ; increment rotar counter
            CMP RBX, ROTARS                                         ; compare rotar counter < number of rotars
            JB .loop_forward                                        ; if not done, go through the next rotar

            MOV RSI, reflection                                     ; point to the reflector table
            MOVZX RAX, byte [RSI + RAX]                             ; bounce off the reflector
            CALL trace_add                                          ; add the stage to the trace ( [in]RAX,RDI )
            MOV RBX, ROTARS                                         ; set rotar counter = number of rotars (one past the last)

.loop_reverse:
            DEC RBX                                                 ; decrement rotar counter: the last rotar first
            CALL rotar_reverse                                      ; backward through this rotar ( [in]RBX,AL , [out]RAX )
            CALL trace_add                                          ; add the stage to the trace ( [in]RAX,RDI )
            TEST RBX, RBX                                           ; test the rotar counter, ZF=1 means rotar 0 is done
            JNZ .loop_reverse                                       ; if not done, go back through the next rotar

            MOV RSI, plugTable                                      ; point to the plugboard table
            MOVZX RAX, byte [RSI + RAX]                             ; same cables on the way out
            CALL trace_add                                          ; add the stage to the trace ( [in]RAX,RDI )
            MOV byte [RDI], 0xA                                     ; end the trace line with a newline
            INC RDI                                                 ; move past it

            MOV RCX, RAX                                            ; keep the index (print clobbers RAX)
            MOV RSI, traceBuf                                       ; set source index to the trace line
            MOV RDX, RDI                                            ; size of the trace = where writing stopped ...
            SUB RDX, RSI                                            ; ... minus where it started
            CALL print                                              ; print the trace line
            MOV RAX, RCX                                            ; bring the index back
            ADD AL, 'A'                                             ; index -> letter: the lit lamp
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RBX                                                 ; restore caller's B register value
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; SECTION [bss]: Unitialized Data Reserves
;-------------------------------------------------------------------;

            SECTION .bss
ingress:    RESB ROTARS * SYMBOLS                                   ; forward wiring per rotar: entry contact -> exit contact
engress:    RESB ROTARS * SYMBOLS                                   ; inverse wiring per rotar: exit contact -> entry contact
rotarStart: RESB ROTARS                                             ; position each rotar begins at and resets to (0-25)
rotarPos:   RESB ROTARS                                             ; current position of each rotar (0-25); a carry happens when it wraps to 0
reflection: RESB SYMBOLS                                            ; reflector: contact -> paired contact, same table both ways
plugTable:  RESB SYMBOLS                                            ; plugboard: letter -> swapped letter (itself when no cable is plugged)
plugPairs:  RESB SYMBOLS / 2 * 3                                    ; current cables as "AV BS CG ...", reusable as a key
plugPairLn: RESQ 1                                                  ; size of the current key
tmpTable:   RESB SYMBOLS                                            ; scratch plugboard table, kept only if the whole key is valid
tmpPairs:   RESB SYMBOLS / 2 * 3                                    ; scratch key (13 cables at most, 3 characters each)
letters:    RESB LINE_MAX                                           ; letters of a key being checked, uppercased
shuffleBuf: RESB SYMBOLS                                            ; the alphabet, shuffled, for a random key
randBuf:    RESB RANDOM_MAX                                         ; random bytes from the kernel
cfgPlugs:   RESB CONFIG_MAX                                         ; plugs value from the ini
cfgPlugLen: RESQ 1                                                  ; size of the plugs value
cfgPos:     RESB CONFIG_MAX                                         ; positions value from the ini
cfgPosLen:  RESQ 1                                                  ; size of the positions value
readFd:     RESQ 1                                                  ; file descriptor get_byte reads from (0 = stdin)
readPos:    RESQ 1                                                  ; how far into readBuf get_byte is
readLen:    RESQ 1                                                  ; how many bytes readBuf holds
readBuf:    RESB READ_MAX                                           ; input waiting to be handed out by get_byte
lineBuf:    RESB LINE_MAX                                           ; the line read_line last read
outBuf:     RESB LINE_MAX                                           ; result of the line being encrypted or decrypted
traceBuf:   RESB 64                                                 ; one trace line (10 letters, 9 arrows and a newline use 47)
wireBuf:    RESB 64                                                 ; one wiring line (26 letters, 26 spaces and a newline use 53)
charBuf:    RESB 1                                                  ; the character print_char is writing
testMode:   RESB 1                                                  ; 1 when --test was given
