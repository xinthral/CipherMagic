;-------------------------------------------------------------------;
; The Ceasar Cipher is a simple rotational cryptographic algorithm. 
; However, it is enhanced with the additions of Vigenère modifications.
; Author:
;   Xinthral
;
; Assemble and run with:
;   nasm -felf64 ceasar.asm -o ceasar.obj
;   ld ceasar.obj -o ceasar.exe
;
;-------------------------------------------------------------------;
SYS_EXIT    equ 60                                                  ; alias for system_exit
SYS_WRITE   equ 1                                                   ; alias for system_write
STDIN       equ 0                                                   ; alias for stdin file descriptor
STDOUT      equ 1                                                   ; alias for stdout file descriptor
DEFAULT     REL                                                     ; label addresses are relative to RIP

;-------------------------------------------------------------------;
; SECTION [data]: Static Assigned Memory
;-------------------------------------------------------------------;
            SECTION .data
codeLetter: DB 'H', 0                                               ; byte to hold the offset code
hashWord:   DB 'BABBAGE'                                            ; string to hold encryption salt
lenSalt:    equ $ - hashWord                                        ; length of input salt
            DB 0                                                    ; NUL terminator
message:    DB 'HAPPY BIRTHDAY'                                     ; string to hold input message
lenMesg:    equ $ - message                                         ; length of input message
            DB 0                                                    ; NUL terminator
alphabet:   DB 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'                         ; string to hold alphabet
lenAlpha:   equ $ - alphabet                                        ; length of the alphabet
            DB 0                                                    ; NUL terminator
idxHead:    DB 'Input:     '                                        ; first formatted output line
idxHLen:    equ $ - idxHead                                         ; length of the index header
            DB 0                                                    ; NUL terminator
encHead:    DB 'Encrypted: '                                        ; second formatted output line
encHLen:    equ $ - encHead                                         ; length of the encrypted header
            DB 0                                                    ; NUL terminator
decHead:    DB 'Decrypted: '                                        ; third formatted output line
decHLen:    equ $ - decHead                                         ; length of the decrypted header
            DB 0                                                    ; NUL terminator
newline:    DB 0xA                                                  ; newline character for line endings
maxSize:    equ lenAlpha * lenAlpha                                 ; maximum size for the matrix buffer
; tempRow:    TIMES lenAlpha DB 0                                     ; initialize 0 array, len = alphabet

;-------------------------------------------------------------------;
; SECTION [text]: Instruction Execution Order
;-------------------------------------------------------------------;
            SECTION .text
            global _start                                           ; must be declared for linker (ld)

_start:
    mov rbp, rsp; for correct debugging
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

.perform_logic:
            CALL generate_matrix                                    ; generate matrix for encryption
            CALL encrypt_message                                    ; encrypt the message
            CALL decrypt_message                                    ; decrypt the encrypted message

.console_display:
            ; Display Input Line
            MOV RSI, idxHead                                        ; set header to input header
            MOV RDX, idxHLen                                        ; set header size
            MOV R8, message                                         ; set body to input message
            MOV R9, lenMesg                                         ; set body size
            CALL print_line                                         ; print header + body + newline

            ; Display Encrypted Line
            MOV RSI, encHead                                        ; set header to encrypted header
            MOV RDX, encHLen                                        ; set header size
            MOV R8, output                                          ; set body to encrypted output
            MOV R9, lenMesg                                         ; set body size
            CALL print_line                                         ; print header + body + newline

            ; Display Decrypted Line
            MOV RSI, decHead                                        ; set header to decrypted header
            MOV RDX, decHLen                                        ; set header size
            MOV R8, decrypted                                       ; set body to decrypted output
            MOV R9, lenMesg                                         ; set body size
            CALL print_line                                         ; print header + body + newline

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
; print_line:
;   Purpose:
;       Writes a header, a body, and a newline to stdout
;   Input:
;       RSI = header buffer, RDX = header size
;       R8  = body buffer,   R9  = body size
;   Output:
;       None
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
print_line:
            PUSH RSI                                                ; save caller's source index
            PUSH RDX                                                ; save caller's D register value
            CALL print                                              ; print header, args: {RSI, RDX}
            MOV RSI, R8                                             ; set source index to body
            MOV RDX, R9                                             ; set size to body size
            CALL print                                              ; print body
            MOV RSI, newline                                        ; set source index to newline
            MOV RDX, 1                                              ; set size to size of newline char
            CALL print                                              ; print newline
            POP RDX                                                 ; restore caller's D register value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; clear_buffer:
;   Purpose:
;       Clears a buffer by setting all bytes to 0
;   Input:
;       RDI = buffer to clear
;       ECX = size of buffer in bytes
;   Output:
;       None
;   Clobbers:
;       None
;-------------------------------------------------------------------;
clear_buffer:
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value

.clear_loop:
            MOV byte [RDI], 0                                       ; set byte at destination index to 0
            INC RDI                                                 ; increment destination index
            LOOP .clear_loop                                        ; loop until ECX is zero

            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            RET

;-------------------------------------------------------------------;
; encrypt_message:
;   Purpose:
;       Loops through the input message and encrypts it using the Vigenère Cipher
;       which utilizes a salt and shifted matrix to generate the cipher text.
;   Input:
;       None
;   Output:
;       output buffer = encrypted message (NUL terminated)
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
encrypt_message:
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            PUSH R8                                                 ; save caller's 8th register value
            PUSH R9                                                 ; save caller's 9th register value
            PUSH RDX                                                ; save caller's D register value
            PUSH R10                                                ; save caller's 10th register value
            MOV RSI, message                                        ; set source index to message
            MOV ECX, lenMesg + 1                                    ; set size to message length (+1 for NUL)
            MOV RDI, output                                         ; set destination index to encrypted buffer
            CALL clear_buffer                                       ; clear encrypted buffer, args: {RDI, ECX}
            XOR RCX, RCX                                            ; set message index counter = 0
            XOR R8, R8                                              ; set salt index counter = 0

.loop_encrypt:
            MOV DL, [RSI + RCX]                                     ; load message[i]
            TEST DL, DL                                             ; test for null terminator, ZF=1 means DL is 0
            JZ .return_complete_encrypt                             ; jump if zero (ZF=1) to .return_complete_encrypt
            CMP DL, 'A'                                             ; compare letter with 'A'
            JB .store_encrypt                                       ; below 'A' is not a letter, copy as-is
            CMP DL, 'Z'                                             ; compare letter with 'Z'
            JA .store_encrypt                                       ; above 'Z' is not a letter, copy as-is

            ; Row = index of salt[k]
            LEA R10, [salt]                                         ; load salt address
            MOV AL, [R10 + R8]                                      ; load salt[k]
            CALL get_index_of_letter                                ; RAX = row index
            IMUL R9, RAX, lenAlpha                                  ; row offset = row * length of alphabet

            ; Column = index of message[i]
            MOV AL, DL                                              ; load message[i]
            CALL get_index_of_letter                                ; RAX = column index
            ADD R9, RAX                                             ; matrix offset = row offset + column

            LEA R10, [matrix]                                       ; load matrix address
            MOV DL, [R10 + R9]                                      ; DL = matrix[row][column]

.store_encrypt:
            MOV [RDI + RCX], DL                                     ; store DL into output[i]

            ; Salt advances on every character, including spaces
            INC R8                                                  ; increment salt index
            CMP R8, lenSalt                                         ; compare salt index < length of salt
            JB .next_encrypt                                        ; if in range, skip the wrap
            XOR R8, R8                                              ; wrap salt index back to 0

.next_encrypt:
            INC RCX                                                 ; increment index counter
            JMP .loop_encrypt                                       ; loop through input message

.return_complete_encrypt:
            XOR RAX, RAX                                            ; clear RAX
            POP R10                                                 ; restore caller's 10th register value
            POP RDX                                                 ; restore caller's D register value
            POP R9                                                  ; restore caller's 9th register value
            POP R8                                                  ; restore caller's 8th register value
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            RET

;-------------------------------------------------------------------;
; decrypt_message:
;   Purpose:
;       Loops through the encrypted output and reverses the Vigenère Cipher
;       by searching the salt's matrix row for each encrypted letter.
;   Input:
;       None (reads the output buffer)
;   Output:
;       decrypted buffer = decrypted message (NUL terminated)
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
decrypt_message:
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            PUSH R8                                                 ; save caller's 8th register value
            PUSH R9                                                 ; save caller's 9th register value
            PUSH RDX                                                ; save caller's D register value
            PUSH R10                                                ; save caller's 10th register value
            PUSH R11                                                ; save caller's 11th register value
            MOV RSI, output                                         ; set source index to encrypted buffer
            MOV ECX, lenMesg + 1                                    ; set size to message length (+1 for NUL)
            MOV RDI, decrypted                                      ; set destination index to decrypted buffer
            CALL clear_buffer                                       ; clear decrypted buffer, args: {RDI, ECX}
            XOR RCX, RCX                                            ; set message index counter = 0
            XOR R8, R8                                              ; set salt index counter = 0

.loop_decrypt:
            MOV DL, [RSI + RCX]                                     ; load output[i]
            TEST DL, DL                                             ; test for null terminator, ZF=1 means DL is 0
            JZ .return_complete_decrypt                             ; jump if zero (ZF=1) to .return_complete_decrypt
            CMP DL, 'A'                                             ; compare letter with 'A'
            JB .store_decrypt                                       ; below 'A' is not a letter, copy as-is
            CMP DL, 'Z'                                             ; compare letter with 'Z'
            JA .store_decrypt                                       ; above 'Z' is not a letter, copy as-is

            ; Row = index of salt[k]
            LEA R10, [salt]                                         ; load salt address
            MOV AL, [R10 + R8]                                      ; load salt[k]
            CALL get_index_of_letter                                ; RAX = row index
            IMUL R9, RAX, lenAlpha                                  ; row offset = row * length of alphabet
            LEA R10, [matrix]                                       ; load matrix address
            ADD R10, R9                                             ; R10 = start of this row
            XOR R11, R11                                            ; set column counter = 0

.loop_decrypt_search:
            CMP R11, lenAlpha                                       ; compare column counter < length of alphabet
            JAE .store_decrypt                                      ; not in row (should not happen), copy as-is
            CMP [R10 + R11], DL                                     ; compare row[column] with encrypted letter
            JE .found_decrypt                                       ; jump if equal (ZF=1) to .found_decrypt
            INC R11                                                 ; increment column counter
            JMP .loop_decrypt_search                                ; continue searching the row

.found_decrypt:
            LEA R10, [alphabet]                                     ; load alphabet address
            MOV DL, [R10 + R11]                                     ; DL = alphabet[column]

.store_decrypt:
            MOV [RDI + RCX], DL                                     ; store DL into decrypted[i]

            ; Salt advances on every character, including spaces
            INC R8                                                  ; increment salt index
            CMP R8, lenSalt                                         ; compare salt index < length of salt
            JB .next_decrypt                                        ; if in range, skip the wrap
            XOR R8, R8                                              ; wrap salt index back to 0

.next_decrypt:
            INC RCX                                                 ; increment index counter
            JMP .loop_decrypt                                       ; loop through encrypted message

.return_complete_decrypt:
            XOR RAX, RAX                                            ; clear RAX
            POP R11                                                 ; restore caller's 11th register value
            POP R10                                                 ; restore caller's 10th register value
            POP RDX                                                 ; restore caller's D register value
            POP R9                                                  ; restore caller's 9th register value
            POP R8                                                  ; restore caller's 8th register value
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            RET

;-------------------------------------------------------------------;
; get_index_of_letter:
;   Purpose:
;       Loops through alphabet to identify index of input letter
;   Input:
;       AL = character to search for
;   Output:
;       RAX = index of letter in alphabet (0-based)
;       RAX = 0 if not found (same as 'A', so only pass letters A-Z)
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
get_index_of_letter:
            PUSH RSI                                                ; save caller's source index
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            MOV RSI, alphabet                                       ; point to alphabet string
            XOR RCX, RCX                                            ; set index counter = 0

.loop_alphabet:
            MOV DL, [RSI + RCX]                                     ; load letter at counter location
            TEST DL, DL                                             ; test for null terminator, ZF=1 means DL is 0
            JZ .loop_alphabet_no_letter_found                       ; jump if zero (ZF=1) to .no_letter_found
            CMP DL, AL                                              ; compare input value with index value, ZF=1 means equal
            JE .loop_alphabet_letter_found                          ; jump if equal (ZF=1) to .letter_found
            INC RCX                                                 ; increment index counter
            JMP .loop_alphabet                                      ; continue .loop_alphabet subroutine

.loop_alphabet_letter_found:
            MOV RAX, RCX                                            ; return index to RAX (before RCX is restored)
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

.loop_alphabet_no_letter_found:
            XOR RAX, RAX                                            ; clear RAX
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; generate_matrix:
;   Purpose:
;       Create "2d array" of rotated letters, stored as an array in
;       the matrix buffer.
;   Input:
;       None (reads the offset letter from key)
;   Output:
;       matrix buffer = rotated alphabet rows
;   Clobbers:
;       RAX
;-------------------------------------------------------------------;
generate_matrix:
            PUSH RSI                                                ; save caller's source index
            PUSH RDI                                                ; save caller's destination index
            PUSH RCX                                                ; save caller's counter value
            PUSH RDX                                                ; save caller's D register value
            PUSH R8                                                 ; save caller's 8th register value
            PUSH R9                                                 ; save caller's 9th register value
            PUSH R10                                                ; save caller's 10th register value
            MOV RSI, alphabet                                       ; load alphabet into source index
            MOV RDI, matrix                                         ; load matrix into destination index
            MOV AL, [key]                                           ; load offset key into temp register
            CALL get_index_of_letter                                ; initiate instruction ( [in]AL , [out]RAX )
            MOV R9, RAX                                             ; set row start = key index
            XOR R8, R8                                              ; set destination counter = 0

.loop_matrix_row:
            CMP R8, maxSize                                         ; compare if counter < maxSize
            JAE .loop_matrix_exit                                   ; jump if above or equal, matrix buffer full
            MOV RCX, R9                                             ; set alphabet index to this row's first letter
            XOR R10, R10                                            ; set column counter = 0

.loop_matrix_col:
            MOV DL, [RSI + RCX]                                     ; load letter at alphabet index
            MOV [RDI + R8], DL                                      ; set matrix[i] to temp char
            INC R8                                                  ; increment destination counter
            INC RCX                                                 ; increment alphabet index
            CMP RCX, lenAlpha                                       ; compare alphabet index < length of alphabet
            JB .loop_matrix_col_next                                ; if in range, skip the wrap
            XOR RCX, RCX                                            ; wrap alphabet index back to 0

.loop_matrix_col_next:
            INC R10                                                 ; increment column counter
            CMP R10, lenAlpha                                       ; compare column counter < length of alphabet
            JB .loop_matrix_col                                     ; if row not full, continue row

            ; Next row starts one letter later: (start + 1) % lenAlpha
            INC R9                                                  ; increment row start
            CMP R9, lenAlpha                                        ; compare row start < length of alphabet
            JB .loop_matrix_row                                     ; if in range, start next row
            XOR R9, R9                                              ; wrap row start back to 0
            JMP .loop_matrix_row                                    ; start next row

.loop_matrix_exit:
            XOR RAX, RAX                                            ; reset the RAX counter to 0
            POP R10                                                 ; restore caller's 10th register value
            POP R9                                                  ; restore caller's 9th register value
            POP R8                                                  ; restore caller's 8th register value
            POP RDX                                                 ; restore caller's D register value
            POP RCX                                                 ; restore caller's counter value
            POP RDI                                                 ; restore caller's destination index
            POP RSI                                                 ; restore caller's source index
            RET                                                     ; return to caller

;-------------------------------------------------------------------;
; SECTION [bss]: Unitialized Data Reserves
;-------------------------------------------------------------------;

            SECTION .bss
key:        RESB 1                                                  ; buffer to hold the key
salt:       RESB 32                                                 ; buffer to hold the salt
matrix:     RESB lenAlpha * lenAlpha                                ; create len x len size array [26 x 26 = 676]
output:     RESB lenMesg + 1                                        ; buffer to hold translated output (+1 for NUL)
decrypted:  RESB lenMesg + 1                                        ; buffer to hold decrypted output (+1 for NUL)
