@ PSR20 gate: the first instruction of Java_org_bluray_system_RegisterAccess_nGetPSR (0x2aefc0, ARM) branches here.
@ r2 = the PSR number. gate_c returns 1/2/4 to answer, anything else to run the player's own code: the replaced
@ instruction "ldr r3, [pc, #0x68]" (its literal at 0x2af030), then on at 0x2aefc4.
    .syntax unified
    .arm
    .section .text.gate,"ax"
    .global bdr_gate
bdr_gate:
    cmp     r2, #20
    bne     1f
    push    {r0-r3, r12, lr}
    ldr     r12, =gate_c
    blx     r12
    cmp     r0, #1
    cmpne   r0, #2
    cmpne   r0, #4
    bne     2f
    add     sp, sp, #4              @ drop the saved r0: the answer is the return value
    pop     {r1-r3, r12, lr}
    bx      lr
2:  pop     {r0-r3, r12, lr}
1:  ldr     r3, =0x2af030
    ldr     r3, [r3]
    ldr     pc, =0x2aefc4
    .ltorg
