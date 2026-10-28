@ oppo-dv-mkv: splitter.ko stub for MKVs whose HEVC CodecPrivate (hvcC) has no parameter-set arrays (hvccfix.sh).
@ Offsets are from the module's .text (= the module base in /proc/modules); the code is position independent.
@
@ vCfaMkvTxDoneStCtrl (.text+0x5de84), header state 0xb, codec 0x15 (HEVC), reads the hvcC one parameter set per call.
@ When no array is left (arrays-left byte == 0 and pos >= size-1) the stock code still queues one header packet whose
@ length is a field this file never wrote (u16 at inst+0x804c0). A 0-byte packet makes i4CfaMkvPbb2FifoAUCtrl call
@ vMkvSkipBlock, which restarts parsing at file offset 0 (no block yet) -> demux error -> stream restart.
@ Site .text+0x5f340 `bcs .text+0x5f3b8` (1c00002a) -> `bcs hvcc_stub` (6f05002a). The stub ends the header like the
@ normal last-parameter-set path (state 0xd after its packet), without queueing anything:
@   inst+8 (read position) = inst+0x80530 (CodecPrivate offset) + inst+0x80538 (CodecPrivate length)
@   inst+0x80538 = 0, then vToNextState(param_1, inst, 5, 0, 2) via .text+0x5e234 (shared tail of the state switch).
@ r8 = inst, r9 = param_1 throughout vCfaMkvTxDoneStCtrl. Cave: cli_cfamkv_debug_off (.text+0x60904, driver CLI only).
        .syntax unified
        .arm
        .text
        .global hvcc_stub
hvcc_stub:
        adr     r0, runs                @ runs++ (shown by hvccfix.sh status)
        ldr     r1, [r0]
        add     r1, r1, #1
        str     r1, [r0]
        movw    ip, #0x0538
        movt    ip, #0x0008             @ ip = 0x80538: CodecPrivate length (u64)
        sub     r3, ip, #8              @ r3 = 0x80530: CodecPrivate file offset (u64)
        ldrd    r0, r1, [r8, r3]
        ldrd    r2, r3, [r8, ip]
        adds    r2, r2, r0
        adc     r3, r3, r1
        strd    r2, r3, [r8, #8]        @ read position = end of the CodecPrivate
        mov     r2, #0
        mov     r3, #0
        strd    r2, r3, [r8, ip]        @ header length = 0: header done
        b       cont                    @ .text+0x5e234: vToNextState(param_1, inst, 5, 0, 2)
runs:   .word   0
