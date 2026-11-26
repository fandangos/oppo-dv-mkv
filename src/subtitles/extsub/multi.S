@ oppo-dv-mkv: stubs for the player's subtitle lists (RU 65-0131 player program), see multi.c. Each is reached by an
@ 8-byte "ldr.w pc, [pc, #k] ; .word stub" that extsub.sh writes over the instructions named below, does their work
@ (with N files instead of one) and jumps back. Register use follows the player's code at each place.
    .syntax unified
    .thumb
    .text
    .macro back addr
    ldr pc, =\addr + 1
    .endm

@ popup build FUN_00a93bbc, 0xa93c58: adds r3,#1 / str r3,[sp,#0x10] / cbz r2 / str r3,[sp,#0x14]
@ r3 = disc streams, r2 = file subtitle active; [sp+0x10] count, [sp+0x14] current
    .global t1
    .thumb_func
t1: mov r0, r3
    mov r1, r2
    mov r2, sp
    bl es_t1
    back 0xa93c60

@ popup refresh FUN_00a946b4, 0xa94772: ldr r6,[sp,#0x18] / movs r3,#1 / strb r3,[r5,#2] / ldrb r3,[r5,#3]
@ then (not overwritten) adds r6,#1 / str / cbnz r3 / mov r6,r7. r5 = 0x1970134, r7 = wanted current
    .global t2
    .thumb_func
t2: ldr r0, [sp, #0x18]
    movs r3, #1
    strb r3, [r5, #2]
    ldrb r1, [r5, #3]
    mov r2, sp
    mov r3, r7
    bl es_t2
    mov r6, r0
    back 0xa94782

@ name FUN_00a936ac, 0xa93748: ldrb r3,[r4,#2] / cbz r3 / adds r7,#1 / uxth r7,r7.  r7 = disc streams -> total;
@ r3 (has a file) is used again below
    .global t3
    .thumb_func
t3: ldrb r3, [r4, #2]
    cbz r3, 1f
    push {r3, lr}
    mov r0, r7
    bl es_t3
    uxth r7, r0
    pop {r3, lr}
1:  back 0xa93750

@ name FUN_00a936ac, 0xa93768: cmp r7,r6 / bne / cbz r3 / ldr r3,=..  r6 = index, r7 = total, sb = out (UTF-16)
@ a file entry: c_uc_w2s_strcpy(sb, label) at 0xa93b7a (then return 0); else the disc stream path 0xa93782
    .global t4
    .thumb_func
t4: cbz r3, 2f
    push {r3, lr}
    mov r0, r6
    mov r1, r7
    bl es_t4
    pop {r3, lr}
    cbz r0, 2f
    mov r1, r0
    mov r0, sb
    back 0xa93b7a
2:  back 0xa93782

@ select FUN_00a9417c, 0xa942ac: ldrh.w r3,[sp,#0x26] / subs r3,#1 / str r3,[sp,#0x28]  (current while a file is on)
    .global t5
    .thumb_func
t5: ldrh.w r0, [sp, #0x26]
    mov r1, sp
    bl es_t5
    back 0xa942b4

@ select FUN_00a9417c, 0xa94344: subs r2,#1 / cmp r8,r2 / strb.w sl,[r3,#4] / (bne 0xa94420 kept, not reached)
@ r2 = list entries, r8 = chosen, r3 = 0x1970134, sl = 1. A file: parse thread start 0xa9436a with r7 = 0
    .global t6
    .thumb_func
t6: strb.w sl, [r3, #4]
    ldrb r0, [r3, #2]
    cbz r0, 3f
    mov r0, r8
    mov r1, r2
    bl es_t6
    cbz r0, 3f
    movs r7, #0
    back 0xa9436a
3:  back 0xa94420

@ info banner FUN_008f47b8, 0x8f4806: ldr r3,=0x134ca00 / ldrb r2,[r3] / add.w r2,#0x3080  (a file is on: its name)
    .global t7
    .thumb_func
t7: bl es_t7
    mov r2, r0
    movs r0, #1
    add r1, sp, #0x2c
    back 0x8f4bec

@ info banner FUN_008f47b8, 0x8f4b90: ldrh r3,[r6] / adds r3,#1 / strh r3,[r6] / b 0x8f4ba0  (total)
    .global t8
    .thumb_func
t8: bl es_n
    ldrh r3, [r6]
    add r3, r0
    strh r3, [r6]
    back 0x8f4ba0
    .ltorg
