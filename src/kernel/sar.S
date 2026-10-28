@ oppo-dv-mkv: bdpdrv1 stubs for pictures with non-square pixels (sarfix.sh). Linked at 0x7e94d600 (bdpdrv1 at
@ 0x7e8d3000), in the unused tail of _Cmd_ImgResz_TestPerformance (driver CLI only; p7kel.sh's code ends at 0x7e94d3e0).
@
@ When a picture has no aspect-ratio code (MKV: code 0), the video plane (VDP) describes the source shape as
@ (SAR_w * width, SAR_h * height) and never reduces it. VDP_GetFixedRegion then multiplies that pair by the picture
@ size in 32 bits. With a SAR such as 1199:1200 at 3840x1744 the pair is (4604160, 2092800) and the product wraps: the
@ letterbox comes out 17 lines instead of 207 and the 2.20:1 picture is drawn 2125 lines tall (stretched to ~16:9).
@ A 1:1 picture gives (3840, 1744) and is fine.
@ Each stub redoes the stock multiplies, then shifts both values right (rounded) until they fit in 12 bits, the range
@ of a 1:1 picture size; the ratio stays within 0.05%. A pair that already fits (every square-pixel picture up to
@ 4095 wide) is left exactly as the stock code computes it. r0-r3 and ip are free: on the other path into each join
@ the stock code calls VDP_GetSrcAspectRatio.
        .syntax unified
        .arm
        .text
@ _VdpUpdateFrameInfo 0x7e9b8538 (aspect code 0): video plane regions. r8 = frame info, sb = width, [sp+0x50] = height.
        .global sar_frame
sar_frame:
        ldr     r3, [r8, #0xfc]         @ SAR w
        ldr     r1, [sp, #0x50]         @ height
        mul     r3, r3, sb              @ a = SAR w * width
        ldr     r2, [r8, #0x100]        @ SAR h
        mul     r1, r2, r1              @ b = SAR h * height
        bl      fit
        str     r3, [sp, #0x5c]
        str     r1, [sp, #0x60]
        b       join_frame              @ 0x7e9b8574
@ u4VDP_DesiredResolution 0x7e9c187c (aspect code 0): decoder pre-downscale size. r6 = picture info (u16 fields).
        .global sar_desired
sar_desired:
        ldrh    r2, [r6, #8]            @ width
        ldrh    r3, [r6, #0x14]         @ SAR w
        mul     r3, r2, r3
        ldrh    r2, [r6, #0xa]          @ height
        ldrh    r1, [r6, #0x16]         @ SAR h
        mul     r1, r2, r1
        bl      fit
        str     r3, [sp, #0x68]
        str     r1, [sp, #0x6c]
        b       join_desired            @ 0x7e9c18c4
@ (r3, r1) >>= s, rounded, with s = the number of bits of (r3 | r1) above 12. lr is free too (the other path's bl).
fit:
        orr     r2, r3, r1
        clz     r2, r2
        rsbs    r2, r2, #20             @ s = 20 - clz
        bxle    lr
        sub     ip, r2, #1
        mov     r0, #1
        add     r3, r3, r0, lsl ip      @ round
        add     r1, r1, r0, lsl ip
        lsr     r3, r3, r2
        lsr     r1, r1, r2
        bx      lr
