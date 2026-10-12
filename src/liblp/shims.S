@ ARM-mode entry shims; each is reached by a patched "bl" and tail-calls the original target.
    .arm
    .section .text.entry,"ax"
    .global _start
_start:
@ base (runtime liblp load address) -> r1, clobbers r2
.macro GETBASE
    adr r1, 9f
    ldr r2, 8f
    sub r1, r1, r2
    b 7f
8:  .word 9f
9:
7:
.endm

h0_tracks:                     @ bl mrParseTracks (r0=this, r2:r3=u64) - two call sites
    push {r0-r3, r12, lr}
    GETBASE
    mov r0, r1
    bl dv_clear
    pop {r0-r3, r12, lr}
    b orig_parse_tracks

h1_skip:                       @ bl mrSkip(this=r0, u64* r1); element ID in r5
    ldr r12, =0x41e4
    cmp r5, r12
    bne orig_mrskip
    push {r0-r3, r12, lr}
    GETBASE
    bl dv_peek                 @ r0=parser, r1=base
    pop {r0-r3, r12, lr}
    b orig_mrskip

h2_mmed:                       @ bl mrSetMediaInfo; r4=CLpMkvMediaManagerProxy; DOVI ptr arg at [sp,#0x5c]
    push {r0-r3, r12, lr}
    GETBASE
    mov r0, r4
    bl dv_decide
    str r0, [sp, #(24 + 0x5c)]
    pop {r0-r3, r12, lr}
    b orig_setmedia

h3_vinfo:                      @ bl mrSetStreamInfo(r0, r1={type, MPCVidElmStrmInf*}, r2)
    push {r0-r3, r12, lr}
    ldr r0, [r1, #4]
    GETBASE
    bl dv_vinfo
    pop {r0-r3, r12, lr}
    b orig_setstream
    .ltorg
