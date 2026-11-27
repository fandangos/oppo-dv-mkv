@ Subtitle menu rows: trampoline that stays in the player program (the jailbreak's free .text1 at RS_ADDR in
@ mkinstall.py, RWX). The row site jumps here instead of straight into liblp, because the player unloads liblp.so while a
@ disc plays (the range is then reused by /dev/bdkmem) and loads it again at another address afterwards: a jump into
@ liblp from the player program then runs whatever is there and kills the thread that handles the remote keys.
@ Here: read the first 8 bytes at the target with process_vm_readv on our own process (it fails with EFAULT instead of
@ faulting when the range is unmapped or device memory) and jump to r_row only when they are ours; otherwise do what the
@ stock code does at the site, a final " " on the row, and go back.
@ Entered from the Thumb site through "ldr.w pc, [pc]" (ARM address), with the site's registers and stack: the row text
@ (UTF-16) is at sp+0x98, r_row and the stock code after the site need the rest unchanged.
@ No relocations: everything is pc-relative, the blob runs where it is written.
    .syntax unified
    .arm
    .text
    .global rs_hdr, rs_entry
rs_hdr:
.Lhdr:
    .ascii "RROW"              @ +0  magic
rs_target: .word 0             @ +4  r_row in liblp (ARM); 0 = off (stock behaviour only)
rs_probe:  .word 0, 0          @ +8  the 8 bytes at rs_target when liblp is the one dvhook.sh patched
rs_back:   .word 0             @ +16 where the stock code copies the text out (Thumb address | 1)
rs_count:  .word 0             @ +20 times the stock way was taken (diagnostics)
rs_entry:                      @ +24
    push {r0-r5, r7, r12, lr}  @ 9 words
    sub sp, sp, #24            @ [sp] local iovec, [sp+8] remote iovec, [sp+16] the 8 bytes read
    adr r12, .Lhdr
    ldr r0, [r12, #4]
    cmp r0, #0
    beq 1f
    str r0, [sp, #8]
    mov r1, #8
    str r1, [sp, #12]
    str r1, [sp, #4]
    add r1, sp, #16
    str r1, [sp]
    mov r7, #20                @ getpid
    svc #0
    mov r1, sp
    mov r2, #1
    add r3, sp, #8
    mov r4, #1
    mov r5, #0
    movw r7, #376              @ process_vm_readv(pid, local, 1, remote, 1, 0)
    svc #0
    adr r12, .Lhdr
    cmp r0, #8
    bne 1f
    ldr r0, [sp, #16]
    ldr r1, [r12, #8]
    cmp r0, r1
    bne 1f
    ldr r0, [sp, #20]
    ldr r1, [r12, #12]
    cmp r0, r1
    bne 1f
    add sp, sp, #24
    pop {r0-r5, r7, r12, lr}
    ldr pc, rs_target          @ liblp is there: r_row, with the site's registers and stack
1:  ldr r1, [r12, #20]         @ not there: the stock " "
    add r1, r1, #1
    str r1, [r12, #20]
    add r0, sp, #(24 + 36 + 0x98)
    mov r2, #0
2:  ldrh r1, [r0]
    cmp r1, #0
    beq 3f
    add r0, r0, #2
    add r2, r2, #1
    cmp r2, #120
    blt 2b
3:  mov r1, #' '
    strh r1, [r0]
    mov r1, #0
    strh r1, [r0, #2]
    add sp, sp, #24
    pop {r0-r5, r7, r12, lr}
    ldr pc, rs_back
