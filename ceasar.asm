;-----------------------------------------------------------------------------------------
;  The Ceasar Cipher is a simple rotational cryptographic algorithm. 
;  However, it is enhanced with the additions of Vigenère modifications.
;  Assemble and run with:
;
;         nasm -felf32 ceasar.asm -o ceasar.o
;         ld ceasar.o -o ceasar.exe
;-----------------------------------------------------------------------------------------

            global _start                                           ; must be declared for linker (ld)
            SECTION .data

message:    db 'Hello, world!', 0hA                                 ; string to be printed
len:        equ $ - message                                         ; length of the string
alaphabet:  db 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 0                      ; string to hold alphabet

            SECTION .text
_start:                                                             ; tells linker entry point
            mov rax, 1                                              ; system call number (system_write)
            mov rdi, 1                                              ; file descriptor (stdout)
            mov rsi, message                                        ; message to write
            mov rdx, len                                            ; message length
            syscall                                                 ; kernel syscall

            mov rax, 60                                             ; system call number (system_exit)
            xor rdi, rdi                                            ; exit code 0
            syscall                                                 ; kernel syscall

            SECTION .bss
salt:       resb 100                                                ; buffer to hold encrypted text
key:        resb 100                                                ; buffer to hold the key