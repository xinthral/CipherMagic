;-----------------------------------------------------------------------------------------
;  The Ceasar Cipher is a simple rotational cryptographic algorithm. 
;  However, it is enhanced with the additions of Vigenère modifications.
;  Assemble and run with:
;
;         nasm -felf64 ceasar.asm -o ceasar.obj
;         ld ceasar.obj -o ceasar.exe
;-----------------------------------------------------------------------------------------
SYS_EXIT    equ 60                                                  ; alias for system_exit
SYS_WRITE   equ 1                                                   ; alias for system_write
STDIN       equ 0                                                   ; alias for stdin file descriptor
STDOUT      equ 1                                                   ; alias for stdout file descriptor

            SECTION .data
codeLetter: DB 'H', 0                                               ; byte to hold the offset code
hashWord:   DB 'BABBAGE', 0                                         ; string to hold encryption salt
lenSalt:    equ $ - hashWord                                        ; length of input salt
message:    DB 'HAPPY BIRTHDAY', 0                                  ; string to hold input message
lenMesg:    equ $ - message                                         ; length of input message
alphabet:   DB 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 0                      ; string to hold alphabet
lenAlpha:   equ $ - alphabet                                        ; length of the alphabet
idxHead:    DB 'Input:     ', 0                                     ; first formatted output line
idxHLen:    equ $ - idxHead
encHead:    DB 'Encrypted: ', 0                                     ; second formatted output line
encHLen:    equ $ - encHead
decHead:    DB 'Decrypted: ', 0                                     ; third formatted output line
decHLen:    equ $ - decHead
; tempRow:    TIMES lenAlpha DB 0                                     ; initialize 0 array, len = alphabet

            SECTION .text
            global _start                                           ; must be declared for linker (ld)




_start:                                                             ; tells linker entry point
            ; Copy Offset Code into key buffer
            MOV AL, [codeLetter]                                    ; load key into temp register
            MOV [key], AL                                           ; put code into key buffer

            ; Copy hashvalue into salt buffer
            MOV RSI, hashWord                                       ; load hash index into source index
            MOV RDI, salt                                           ; load buffer index into destination index
            MOV ECX, lenSalt                                        ; set size of salt
.copy_hash:
            MOV AL, [RSI]                                           ; load lowest source bit into temp register
            MOV [RDI], AL                                           ; store bit from temp register into destination
            INC RSI                                                 ; increment source index pointer
            INC RDI                                                 ; increment destination index pointer
            LOOP .copy_hash                                         ; loop through all of the source, decrements ECX

            ; Display Input Header
            MOV RSI, idxHead                                        ; set source index to header message
            MOV RDX, idxHLen                                        ; set size to index length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Display Input Message
            MOV RSI, message                                        ; set source index to message
            MOV RDX, lenMesg                                        ; set size to message length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Concat Newline and Display
            SUB RSP, 16                                             ; create 16 byte space (must be 8-byte aligned)
            MOV byte [RSP], 0xA                                     ; assign newline character to rsp
            MOV RSI, RSP                                            ; assign new stack pointer to source index
            MOV RDX, 1                                              ; set size to size of newline char
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall
            add RSP, 16                                             ; restore stack

            ; Display Encoded Header
            MOV RSI, encHead                                        ; set source index to header message
            MOV RDX, encHLen                                        ; set size to index length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Display Input Message
            MOV RSI, message                                        ; set source index to message
            MOV RDX, lenMesg                                        ; set size to message length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Concat Newline and Display
            SUB RSP, 16                                             ; create 16 byte space (must be 8-byte aligned)
            MOV byte [RSP], 0xA                                     ; assign newline character to rsp
            MOV RSI, RSP                                            ; assign new stack pointer to source index
            MOV RDX, 1                                              ; set size to size of newline char
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall
            add RSP, 16                                             ; restore stack

            ; Display Decoded Header
            MOV RSI, decHead                                        ; set source index to header message
            MOV RDX, decHLen                                        ; set size to index length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Display Input Message
            MOV RSI, message                                        ; set source index to message
            MOV RDX, lenMesg                                        ; set size to message length
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Concat Newline and Display
            SUB RSP, 16                                             ; create 16 byte space (must be 8-byte aligned)
            MOV byte [RSP], 0xA                                     ; assign newline character to rsp
            MOV RSI, RSP                                            ; assign new stack pointer to source index
            MOV RDX, 1                                              ; set size to size of newline char
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall
            add RSP, 16                                             ; restore stack

;-------------------------------------------------------------------;
; _exit:
;   Purpose:
;       Exit Program
;   Input:
;       None
;   Output:
;       None
;-------------------------------------------------------------------;
_exit:
            MOV RAX, SYS_EXIT                                       ; system call number (system_exit)
            XOR RDI, RDI                                            ; exit code 0
            SYSCALL                                                 ; kernel syscall

;-------------------------------------------------------------------;
; get_index_of_letter:
;   Purpose:
;       Loops through alphabet to identify index of input letter
;   Input:
;       AL = character to search for
;   Output:
;       RAX = index of letter in alphabet (0-based)
;       ZF = 1 if not found (RAX undefined)
;-------------------------------------------------------------------;
get_index_of_letter:
            PUSH RSI                                                ; save caller's source index
            MOV RSI, alphabet                                       ; point to alphabet string
            XOR RCX, RCX                                            ; set index counter = 0

.loop_find:
            MOV DL, [RSI + RCX]                                     ; load letter at counter location
            TEST DL, DL                                             ; test for null terminator, ZF=0 means true
            JZ .not_found                                           ; jump if zero (ZF=0) to .not_found subroutine
            CMP DL, AL                                              ; compare input value with index value, ZF=0 means true
            JE .found                                               ; jump if equal (ZF=0) to .found subroutine
            INC RCX                                                 ; increment index counter
            JMP .loop_find                                          ; continue .loop_find subroutine

.found:
            MOV RAX, RCX                                            ; return index in RAX
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

.not_found:
            XOR RAX, RAX                                            ; reset RAX to 0
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; generate_matrix:
;   Purpose:
;       Create "2d array" of rotated letters.
;   Input:
;       None
;   Output:
;       None
;-------------------------------------------------------------------;
; generate_matrix:
;             PUSH RSI                                                ; save caller's source index
;             MOV 



            SECTION .bss
key:        RESB 1                                                  ; buffer to hold the key
salt:       RESB 32                                                 ; buffer to hold the salt
matrix:     RESB lenAlpha * lenAlpha                                ; create len x len size array [26 x 26 = 676]





; Indexing the Matrix
; ; rbx = row, rcx = column
; mov rax, rbx
; imul rax, lenAlpha
; add rax, rcx
; mov al, [matrix + rax]