;Start of Crack.ASM 

Code    Segment Byte Public 
Assume  Cs:Code, Ds:Code 
Org     100h 

; Patch for Fascination, Hebrew version.
; The game freezes in a certain scene. From the debugger, we can 
; see that the game is stuck in an infinite loop. We need to change
; two jumps in order to exit the loop.
; This patch allows the user to click F6 in order to un-freeze the game.

; The strategy:
; Hook INT15 (keyboard), and raise move to state #1 when F6 is clicked.
; Hook INT1C (timer), and check if we are in state #1. If so, patch a jump
; and move to state #2. Wait for next timer to pop. Then, in state #2, patch
; another jump and move to state #3. Wait for next timer to pop. Then, in 
; state #3, revert both patches to allow the game to proceed in the original
; manner.

; =======================================================================================================

Start: 
   mov  dx,Offset Welcome               ; Greets =) 
   call Print 

   mov  ax,3521h                        ; Get INT21 vector 
   int  21h 
   mov  word ptr Jmp21Nfo+1,bx          ; place IP of it in JMP 
   mov  word ptr Jmp21Nfo+3,es          ; place CS of it in JMP 
   mov  ax,2521h                        ; set new INT 21 
   mov  dx,offset myint21               ; pointer to new INT 21 
   int  21h 
   
   mov  ax,3515h                        ; Get INT15 vector 
   int  21h 
   mov  word ptr Jmp15Nfo+1,bx          ; place IP of it in JMP 
   mov  word ptr Jmp15Nfo+3,es          ; place CS of it in JMP 
   mov  ax,2515h                        ; set new INT 15 
   mov  dx,offset myint15               ; pointer to new INT 15
   int  21h 
   
   mov  ax,351Ch                        ; Get INT1C vector 
   int  21h 
   mov  word ptr Jmp1CNfo+1,bx          ; place IP of it in JMP 
   mov  word ptr Jmp1CNfo+3,es          ; place CS of it in JMP 
   mov  ax,251Ch                        ; set new INT 1C 
   mov  dx,offset myint1C               ; pointer to new INT 1C
   int  21h 
   
   mov  dx,offset IntHooked             ; print success msg 
   call Print 
   mov  ah,31h                          ; TSR Function 
   mov  dx,40h                          ; reserve 40 paragraphs of mem 
   int  21h 

; =======================================================================================================
   
Print Proc 
   mov  ah,9 
   int  21h 
   ret 
Print EndP 

; =======================================================================================================

myint1C:
   ; Save the registers we will be using
   push ax
   push bx
   push cx
   push di
   push si
   push es
   push ds
   
   ; Read current state of state machine
   
   push cs                            ; The TSR's variables are saved in cs:XXX
   pop  es                            ; Move cs into es to be able to use it as a data segment
   mov  di, offset state              ; Offset of the state machine variable
   mov  bx, es:[di]                   ; bs will contain the current state
   cmp  bl, 1                         ; State == 1?
   jz   phase1
   cmp  bl, 2                         ; State == 2?
   jz   phase2
   cmp  bl, 3                         ; State == 3?
   jz   phase3
   jmp  restore1C                     ; Any other state - nothing to do
   
; State #1: Patch the first jump
phase1:
   
   ; Search for the segment of the first jump
   add sp,01Ch                        ; Move the stack backwards, looking for the segment
   pop cx                             ; Pop whatever's on the stack to cx
   push cx                            ; Restore the stack from the pop
   sub sp,01Ch                        ; Fully restore the stack
   
   ; Set ds:[si] to real code
   push cx                            ; cx has the segment we suspect
   pop ds                             ; Move it to ds to use as a data segment
   mov si, 0A7h                       ; set the offset of the jump (actually 1 byte after the jump)
     
   ; Compare saved signature to real code
   cld                                ; Search forward
   mov cx, 15                         ; Compare 15 bytes
   mov di, offset patchjmp1           ; Offset of the saved signature
   repe cmpsb                         ; Compares es:di (saved signature) to ds:si (real code)
   jnz restore1C                      ; Not what we are looking for
   
   ; We found the signature!
   
   ; Save real-code segment in patchseg1
   ; This will be used later to revert the patch
   mov di, offset patchseg1           ; Offset of the variable
   mov word ptr es:[di], ds           ; Save the DS segment value
   
   ; Patch code
   mov si, 0A6h                       ; Move SI back to the location of the jump
   mov byte ptr ds:[si], 073h         ; JC->JNC
   
   ; Update state
   mov  di, offset state              ; Offset of the state variable
   inc bl                             ; State++
   mov  byte ptr es:[di], bl          ; Save state
   jmp restore1C                      ; Done
   
; State #2: Patch the second jump
phase2:

   add sp,01Ch
   pop cx
   push cx
   sub sp,01Ch
   
   ; Set ds:[si] to real code
   push cx
   pop ds
   mov si, 02457h
   
   ; Compare saved signature to real code
   cld
   mov cx, 15
   mov di, offset patchjmp2 
   repe cmpsb
   jnz restore1C
   
   ; Save real-code segment in patchseg2
   mov di, offset patchseg2
   mov word ptr es:[di], ds
   
   ; Patch code
   mov si, 02456h
   mov byte ptr ds:[si], 075h
   
   ; Update state
   mov  di, offset state
   inc bl
   mov  byte ptr es:[di], bl
   jmp restore1C

; State #3: Revert patch
phase3: ;Revert jump #1

   mov di, offset patchseg1         ; Read the segment we patched before
   mov ds, word ptr es:[di]
   
   ; Patch code
   mov si, 0A6h                     ; Offset of jump #1
   mov ax, ds:[si]                  ; Read the current value in code
   cmp al, 072h                     ; If it's 0x72 (JC) - this part is already done
   jz  phase3b                      ; Continue by reverting next patch
   cmp al, 073h                     ; If it's 0x73 (JNC), need to turn to 0x72 (JC)
   jnz restore1C                    ; Any other value - not what we expected, ignore
   mov byte ptr ds:[si], 072h       ; Revert the patch
   
phase3b: ; Revert jump #2
   mov di, offset patchseg2         ; Read the segment we patched before
   mov ds, word ptr es:[di]
   
   ; Patch code
   mov si, 02456h                   ; Offset of jump #2
   mov ax, ds:[si]
   cmp al, 075h
   jnz restore1C
   mov byte ptr ds:[si], 074h       ; 0x75 (JNE) -> 0x74 (JE)
   
   ; Update state
   mov  di, offset state
   mov  byte ptr es:[di], 0         ; State goes back to 0, so we can press F6 again and 
                                    ; repeat this
   jmp restore1C
   
restore1C:
   ; Restore the registers we used
   pop ds
   pop es
   pop si
   pop di
   pop cx
   pop bx
   pop ax
   jmp bye1C ; Perform original INT 1C

; =======================================================================================================
   
; New INT15 Procedure

myint15:
   cmp al, 40h                      ; Is this F6?
   jz raiseflag
   cmp al, 42h                      ; Is this F8?
   jz raiseflag
   jnz bye15                        ; Anything else - perform original task

raiseflag:
   push es
   push di
   
   push cs                          ; cs->es, to be used as data segment, in order to save state
   pop  es
   mov  di, offset state            ; Offset of state variable
   sub  al, 3Fh                     ; F6 (0x40) brings us to state 1 (0x40-0x3F), F8 (0x42) brings us to state 3
   mov  byte ptr es:[di], al        ; Update state
   add  al, 3Fh                     ; Restore al
   
   pop di
   pop es
   jmp bye15                        ; Perform original INT15
   
; =======================================================================================================

myint21: 
   cmp  ah,4Ch                          ; is it a terminate? 
   jnz  bye21                           ; if not, continue with original INT21

removehooks:
   push es                              ; save ES 
   push ax                              ; save AX 
   xor  di,di 
   mov  es,di                           ; set ES to 0 
   mov  di,84h                          ; 4 * 21h == 84h 
   mov  ax,word ptr cs:[Jmp21Nfo+1]       ; place IP of original INT21 in bx 
   stosw                                ; store AX at ES:DI and add 2 to DI 
   mov  ax,word ptr cs:[Jmp21Nfo+3]       ; place CS of original INT21 in bx 
   stosw                                ; store AX at ES:DI 
   
   mov  di,054h                          ; 4 * 15h == 54h 
   mov  ax,word ptr cs:[Jmp15Nfo+1]       ; place IP of original INT15 in bx 
   stosw                                ; store AX at ES:DI and add 2 to DI 
   mov  ax,word ptr cs:[Jmp15Nfo+3]       ; place CS of original INT15 in bx 
   stosw                                ; store AX at ES:DI 
   
   mov  di,070h                          ; 4 * 1Ch == 70h 
   mov  ax,word ptr cs:[Jmp1CNfo+1]       ; place IP of original INT1C in bx 
   stosw                                ; store AX at ES:DI and add 2 to DI 
   mov  ax,word ptr cs:[Jmp1CNfo+3]       ; place CS of original INT1C in bx 
   stosw                                ; store AX at ES:DI 
   
   pop  ax                              ; restore ax 
   pop  es                              ; restore es 
   jmp  bye21                           ; jump to INT21 

; =======================================================================================================

bye21: 
Jmp21Nfo        DB  0EAh,0,0,0,0 ; EA - jump far
bye15:
Jmp15Nfo        DB  0EAh,0,0,0,0 ; EA - jump far
bye1C:
Jmp1CNfo        DB  0EAh,0,0,0,0 ; EA - jump far
Welcome         DB  13,10,'Fascination TSR Patch by Gordi!',13,10,24h 
IntHooked       DB  'Patch successfully installed.',13,10,'During the game, try F6 or F8 if the game freezes.',13,10,24h 
state           DB  0
patchjmp1       DB  0D5h, 0EBh, 021h, 0A1h, 0A2h, 02Ch, 099h, 02Bh, 046h, 0FCh, 01Bh, 056h, 0FEh, 0Bh, 0D2h, 0
patchseg1       DB  0,0
patchjmp2       DB  0A7h, 0C4h, 01Eh, 048h, 014h, 026h, 0FFh, 0Fh, 0C4h, 01Eh, 090h, 017h, 026h, 083h, 03Fh, 0
patchseg2       DB  0,0

Code Ends 
End Start 

; End of Crack.ASM