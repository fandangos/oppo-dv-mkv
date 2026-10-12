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
sync_stub:                                  @ u4VDP_AssignSyncCtrl 0x7e9c0c48 (replaces a debug-print bl); r4 = VDP, r5 = query
    ldrb r1, [r4]                           @ result, r7 = the plane's previous SyncCtrl. VDP objects: VDP0 = VDP1 - 0x880
    ldr r2, =elstat+80                      @ [r2] = VDP0 seen flag (field blrd), [r2+8] = its jiffies (field blcalls)
    ldr r3, =jiffies
    ldr r3, [r3]
    cmp r1, #0
    streq r3, [r2, #8]
    moveq r0, #1
    streq r0, [r2]
    bxeq lr
    cmp r1, #1
    bxne lr
    cmp r5, #0
    bxne lr
    ldr r0, [r2]                            @ TS / Blu-ray: VDP0 got a SyncCtrl in the last 5 s -> stock behaviour
    cmp r0, #0                              @ (a flag, not a 0 timestamp: jiffies wraps to 0 at 300 s uptime)
    beq 1f
    ldr r0, [r2, #8]
    sub r0, r3, r0
    cmp r0, #500
    bxlo lr
1:  sub r4, r4, #0x880                      @ MKV path offers the AV-sync controller to the EL plane only, which hard-locks
    ldr r7, [r4, #0x6c8]                    @ the SoC with audio; give it to the base-layer plane VDP0 instead (the rest of
    bx lr                                   @ the function assigns it to [r4]) -> AV sync like single-layer MKV
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
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0
