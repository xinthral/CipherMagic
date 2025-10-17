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

            ; Display Input Message
            MOV RSI, idxHead
            MOV RDX, idxHLen
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            MOV RSI, message                                        ; set source index to message
            MOV RDX, lenMesg                                        ; set size to message
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall

            ; Display Newline
            SUB RSP, 8                                              ; create 8 byte space (must be 16byte aligned)
            MOV byte [RSP], 0xA                                     ; assign newline character to rsp
            MOV RSI, RSP                                            ; assign new stack pointer to source index
            MOV RDX, 1                                              ; set size of bytes in newline
            MOV RAX, SYS_WRITE                                      ; system call number (system_write)
            MOV RDI, STDOUT                                         ; file descriptor (stdout)
            SYSCALL                                                 ; kernel syscall
            add RSP, 8                                              ; restore stack

_exit:
            MOV RAX, SYS_EXIT                                       ; system call number (system_exit)
            XOR RDI, RDI                                            ; exit code 0
            SYSCALL                                                 ; kernel syscall

            SECTION .bss
key:        RESB 1                                                  ; buffer to hold the key
salt:       RESB 32                                                 ; buffer to hold the salt