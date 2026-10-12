    .arm
    .section .text.entry,"ax"
    .global entry
entry:                                      @ i4VDEC_HAL_H265_InitBarrelShifter entry
    push {r0-r3, ip, lr}
    mov r0, r2
    mov r2, lr
    bl elfix
    pop {r0-r3, ip, lr}
    push {r0, r1, r4, r5, r6, r7, r8, lr}   @ displaced original instruction
    b orig_cont
    .global rd_entry
rd_entry:                                   @ i4ESM_FifoRdPtrSet entry (r0 handle, r1 rd)
    push {r0, r2, r3, r4, ip, lr}
    bl rdfix
    mov r1, r0
    pop {r0, r2, r3, r4, ip, lr}
    ldr r2, =0x7ee41cac                     @ displaced: ldr r2, [pc, #0xc8]
    b rd_cont
    .ltorg
    .global sync_stub
sync_stub:                                  @ u4VDP_AssignSyncCtrl 0x7e9c0c48 (replaces a debug-print bl); r4 = VDP, r5 = query result
    ldrb r1, [r4]                           @ VDP id
    ldr r2, =elstat+216                     @ jiffies of the last VDP0 SyncCtrl assignment
    ldr r3, =jiffies
    ldr r3, [r3]
    cmp r1, #0
    streq r3, [r2]
    bxeq lr
    cmp r1, #1
    bxne lr
    cmp r5, #0
    bxne lr
    ldr r0, [r2]
    sub r0, r3, r0
    cmp r0, #500                            @ VDP0 not assigned in the last 5 s (MKV path): keep VDP1 off SyncCtrl
    orrhs r5, r5, #1                        @ (EL plane slaved to audio sync without the BL plane hard-locks the SoC)
    bx lr
    .ltorg
    .global vdp_entry
vdp_entry:                                  @ VDec_Stop entry (r0 esid)
    push {r0-r3, ip, lr}
    bl vdp_off
    pop {r0-r3, ip, lr}
    cmp r0, #7                              @ displaced
    b vdp_cont
    .section .data.st,"aw"
    .global elstat
elstat:
    .word 0x454c4658, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .word 0, 0, 0, 0, 0, 0, 0, 100
    .space 128
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .space 128
    .word 0, 0
