# Technical notes

This document is for people who want to understand, verify or extend the patches. All addresses are for the Oppo
UDP-203 on Oppo's v65 firmware (developed and tested on the **RU 65-0131** jailbreak):
- `liblp.so` md5 `e39b358c5b0948933f49fd3099f81114` (identical in all regional v65 firmwares)
- `bdpdrv1` kernel module loaded at `0x7e8d3000`, verified by fingerprint (see below)
- the region-specific player program (`bdpprog.1`, md5 `49b649bdcffe8b611f1b7bbc0d9fa0b1` on RU 65-0131) is not
  patched by the Dolby Vision fix; the subtitle improvements and the factory menu shortcut patch it in RAM

The hardware is a MediaTek MT8581 (4× Cortex-A9) running Linux 3.10.

## Overview

| Part | Target | Patcher | Blob source |
|---|---|---|---|
| MKV Dolby Vision signalling | `liblp.so` inside the running `bdpprog.1` (via `/proc/<pid>/mem`) | `dvhook.sh` | `src/liblp/` |
| Profile 7 decoder fixes | `bdpdrv1` kernel module (via `/dev/mem`) | `p7kel.sh` | `src/kernel/` |
| Better subtitles | running `bdpprog.1` + `liblp.so` (RU 65-0131 program) | `subs.sh` | `src/subtitles/` |
| Factory menu shortcut | running `bdpprog.1` (RU 65-0131 or jb_overlay V3 program) | `fpage.sh` | `src/factory-menu/` |

The patchers are idempotent (`on` when already on does nothing) and reversible (`off`). They verify every patch
site before writing, and they write the code blob before redirecting any call into it.

## Part 1: liblp.so (MKV signalling)

liblp file offset = runtime offset from the library's load base. (In Ghidra, with the default image base, add
0x10000.)

- **Code cave:** the zero padding at the end of the RX segment, `0x6cdc00..0x6ce000`. The blob is 904 bytes of Thumb
  C plus ARM entry shims.
- **State:** 64 bytes of bss slack at `0x757e00`: parser pointer, have/active flags, profile, level, the 24-byte
  `dvcC` record, the 0x1c-byte `MPC_DOVI_INFO_T` and a hit counter.

| Hook (patched `bl`) | Site | Original target | Purpose |
|---|---|---|---|
| H0 | `0x3c57ec`, `0x3c2ff0` | `CLpMkvParser::mrParseTracks` | forget the previous record at the start of Tracks |
| H1 | `0x3c00d4` | `CLpMkvParser::mrSkip` (element id in r5) | for `BlockAdditionMapping` (0x41E4): read 0x41E7 (type `dvcC`/`dvvC`) and 0x41ED (record), then restore the reader position and skip as usual |
| H2 | `0x3d252c` | `CLpMovieMpcWrapper::mrSetMediaInfo` | pass a filled `MPC_DOVI_INFO_T` instead of NULL (dovi, single, BL, EL, RPU) |
| H3 | `0x3c99a4` | `CLpMovieMpcWrapper::mrSetStreamInfo` | set the video info DV bytes `+0x124..0x129` and profile/level at `+0x12c/+0x12d` |

Accepted streams:
- profile 5 or 8 with BL + RPU and no EL;
- profile 7 with BL + EL + RPU (single track).

The HEVC `CodecPrivate` must be longer than 23 bytes, i.e. it must carry parameter-set arrays. Signalling DV for an
hvcC without VPS/SPS/PPS hard-locks the SoC.

Pitfalls:
- In `MPC_DOVI_INFO_T`, bytes 8 and 9 are **not** profile/level (they are an ID / VS10 flag) and must stay 0.
  Profile and level belong only in the video info.
- Profile 5 needs the correct profile/level; profile 8.1 tolerates 0.

## Part 2: bdpdrv1 (profile 7)

### Firmware facts that matter

- In single-stream DV mode (`DOVI_[1]_SINGLE_[1]_BL_[1]_EL_[1]_RPU_[1]`) the MKV splitter (`splitter.ko`, PSR video
  filter) or the TS demux writes the interleaved stream into **one** video FIFO and builds two access-unit tables.
- The VDEC decodes:
  - **ESID 0** = BL + RPU: 3840×2160, dual-core (VLD0+VLD1) plus a look-ahead engine on ESID 7;
  - **ESID 1** = EL: 1920×1080 on VLD1.
- The software start-code reader (`u4VDEC_HAL_H265_GetStartCode_PicStart`) strips the NAL-62/63 wrapper
  (`(v & 0xfdff) == 0x7c01`). It also skips VCL NALs with `first_slice_segment_in_pic_flag = 0`. The hardware slice
  finder sees the raw bytes.
- The ESM (elementary stream manager) handle table is at `0x7ee41cac`. A handle points to a fifo struct
  `{sa, ea, rd, wr}`. The VDEC's per-ESID handle is at `0x7ee6e690 + 8 + esid*0x14 + 0xc` (from `VDec_Update_Esm`).
  BL and EL use **different handles and fifo structs over the same memory**.
- The video FIFO ring is 8 MB, but the barrel-shifter struct passed to the hardware describes a 12 MB window.
- VDP0 is the main (BL) video plane and VDP1 the second plane, used for the DV EL. The plane state is at
  `*(0x7ee3cb60 + 0x34) + id*0x880 + 0x118`; 2 means shown.
- `u4VDP_AssignSyncCtrl` assigns the AV-sync controller per plane. MKV with audio assigns it to VDP1 only.

### Driver fingerprint

`p7kel.sh check` (also run by the installer) reads these words through `/dev/mem` and refuses on any mismatch:

| Address | Expected | What |
|---|---|---|
| `0x7ea9c7b8`, `0x7e9fa2e0`, `0x7eaac9a0`, `0x7e9c0c4c` | original code | instruction after each hook point |
| `0x7e9a3f40` | `020050e3` | `VDP_SetEnable` entry |
| `0x7eb5bc94` | `70402de9` | `DOVI_CleanDCacheRange` entry |
| `0x7eb22120`, `0x7eb207c8` | `f04f2de9` | `i4VDecH265SPSPsr`, `vH265PreParseSPS` entries |
| `0x7eb26da0`, `0x7eb215d0` | original code | instruction after the two SPS hooks |
| `0x7eac868c`, `0x7eac8950`, `0x7eac8958` | original code | `fgVDecInitProc`: r4 = stream info, `movw r3,#0x4c94`, return point |
| `0x7eb26934`, `0x7eb26938`, `0x7eb2693c`, `0x7eb26974` | original code | `i4H265_Parse_Syntax_Proc`: r4/r6/r5 set-up, return point |
| `0x7ea9300c` | `08402de9` | `vVDecResetMultiCore` entry |
| `0x7e9b60d0` | original code | `VDPCheckFirstPicPts` after the hooked print |
| `0x7e9be544`, `0x7e9be570`, `0x7e9be5a8` | original code | `_VdpGetNextDisp`: r4 = VDP0, difference at `sp+0x110`, return point |
| `0x7eabb860`, `0x7eabb874`, `0x7eabb884` | original code | `fgVDecRetrieveEsIsPic`: r6 = stream info, r1 = ES message, return point |
| `0x7e9fa3ac` | `0x7ee41cac` + D | anchor: `_parESITable` (ESM handle table) |
| `0x7eabd2cc` | `0x7ee6e690` + D | anchor: VDEC instance table |
| `0x7e9a41ec` | `0x7ee3cb60` + D | anchor: VDP global state |
| `0x7eab77c8` | `0x7ee6e698` + D | anchor: `_arVDecEsmInfo` |
| `0x7eab87d4` | `0x7ee6e738` + D | anchor: `_arVDecEsInfo` |
| `0x7e98eca8` | `0x7ee3cb94` + D | anchor: `VdpData` |

The anchors give the **driver build's data offset** D: each is a literal pool word of the driver that points at one of
the global data objects the patch uses (the values above are the RU 65-0131 ones), and all six must show the same D
(a multiple of 4, at most ±0x1000). Driver builds seen so far share the code but place the module's data and bss
elsewhere:

| Build | D | Code differences |
|---|---|---|
| RU 65-0131 | 0 | — |
| USA | +0x90 | `vCheckEDID` (HDMI EDID handling) moves code from `0x7ebbbe30` on by 0x30 |
| third build (region unknown) | +0x50 | HDMI audio input handling (`u1UpdateHdmiIecInput`) and later functions move code from `0x7eb83cb0` on |

Everything the patch hooks or calls lies below `0x7eb83cb0`. Each port was checked against a full driver dump
(`oppo-dv-mkv-driver-dump.zip`) by classifying every differing word in the shared code range: all are pointer,
branch or `movw` relocations, and the code caves hold the same original bytes.

`p7kel.sh` ships one blob, built for the RU layout, and moves its data addresses by D when it writes it: 9 words, 3
literal pool words holding an address and 6 `movw` holding an address's low half (refused if that half would wrap,
since the `movt` would then change too). `build.sh` also compiles the blob with `-DDSHIFT=0x90`, `0x50` and `0x1000`.
`mkkinst.py` finds the relocated words from the `0x1000` build, asserts that each is a data address inside an
anchored object, and that relocating the RU blob by 0x90 / 0x50 / 0x1000 gives exactly the compiled blobs. `check`
reports the build as `ru`, `us` or `data+0x..`.

It also checks:
- `/proc/kallsyms`: `printk` at `0x803f7df0` and `jiffies` at `0x805760c0`;
- the original or patched instruction at each of the 12 hook sites. The hook bytes written by released older
  versions (v1.0.0–v1.2.0 differ at three sites) are recognised too: `check` then reports `sites old` instead of
  refusing, because the installer runs while the old patch is active and the new one only takes over at the next
  boot. `on` refuses in that state, and `off` also switches an older version's hooks off.

### Code cave and hooks

The main cave is the dead CLI test function `_FbmCli_Test_4K`, `0x7e98be80..0x7e98c7c0`. Code runs up to
`0x7e98c748`; the counters and state (`elstat`) follow, up to `0x7e98c7c0`. Since v1.3.1 the seek and end-of-file
fixes live in a second cave, the dead CLI test function `_Cmd_ImgResz_TestPerformance` (`0x7e94d210`, 1376 bytes;
v1.4.0: 448 bytes of code, then 16 bytes of counters, `c2stat` at `0x7e94d3d0`; the original bytes are identical in
every known driver build up to `0x7e94d728`). Like the first, it is reachable only from a CLI command table. `p7kel.sh` checks
the original contents of both caves by md5 (five chunks: page split and code/data split), so no firmware bytes are
shipped.

| Hook | Site | Original instruction | Entry |
|---|---|---|---|
| EL slice rewrite | `i4VDEC_HAL_H265_InitBarrelShifter` `0x7ea9c7b4` | `push {r0,r1,r4-r8,lr}` | `entry` → `elfix(bs, vld, lr)` |
| FIFO clamp | `i4ESM_FifoRdPtrSet` `0x7e9fa2dc` | `ldr r2,[pc,#0xc8]` (literal `0x7ee41cac`) | `rd_entry` → `rdfix(handle, rd)` returns the rd to use |
| AV-sync guard | `u4VDP_AssignSyncCtrl` `0x7e9c0c48` | `bl` to a debug print (replaced) | `sync_stub` |
| Stop | `VDec_Stop` `0x7eaac99c` | `cmp r0,#7` | `vdp_gate` (cave 2, single-stream DV only) → `vdp_entry` → `vdp_off(esid)` |
| EL SPS guard | `i4H265_Parse_Syntax_Proc` `0x7eb26d9c` | `bl i4VDecH265SPSPsr` | `spsfix(ctx, sps_base, pic)` |
| EL pre-parse guard | `i4H265_Pre_Parse_SPS_Proc` `0x7eb215cc` | `bl vH265PreParseSPS` | `ppfix(esid, .., .., .., out)` |
| EL FIFO clear | `vESM_FifoClear` tail `0x7e9fd48c` | `mov r3,#0` | `clr_entry` → `clrfix(handle)` |
| Reparse flag | `fgVDecInitProc` `0x7eac8954` ("ReInit From SSStop") | `strb r2,[r4,r3]` | `nofb_stub` (cave 2) |
| EL multi-core reset | `i4H265_Parse_Syntax_Proc` `0x7eb26968` | `bne` (skip the reset on single-core ES) | `mc_stub` (cave 2) |
| Frozen BL frame: record | `VDPCheckFirstPicPts` `0x7e9b60cc` | `bl` to a debug print (kept, after the stub) | `rec_stub` (cave 2) |
| Frozen BL frame: EL timing | `_VdpGetNextDisp` `0x7e9be5a0` | `b` after the VDP1-vs-VDP0 `PTS_DIFFERENCE` | `cmp_stub` (cave 2) |
| EL end of stream | `fgVDecRetrieveEsIsPic` `0x7eabb880` | `str r3,[r6,#0x5f4]` (picture start) | `eos_stub` (cave 2) |

#### elfix (EL slice rewrite)

It is called for every barrel-shifter init: BL cores, the look-ahead engine and the EL. `bs = {rdptr, fifo_end,
fifo_start, ...}`, all kernel linear-map addresses.

1. Bound the scan:
   - ring end = the ESM fifo end recorded by `rdfix` (not the 12 MB window). Since v1.3.1 it is recorded only for
     the BL and EL handles: `rdfix` also sees the audio and subtitle FIFOs, and with their end an EL access unit
     across the end of the 8 MB video ring was not rewritten (EL decode error, then a stall);
   - length = the distance to the furthest ESM write pointer for this FIFO, so it never reads unwritten data.
2. Skip the call if `rdptr` lies inside the EL access unit handled last. Every NAL header parse calls this hook.
3. Scan from `rdptr`. If it is an EL AU (wrapped NALs), count the wrapped VCL NALs with first_slice = 0. Stop at
   the second first slice, the RPU or the first plain non-slice NAL.
4. If there are any, rewrite each `01 7E` to `00 00` (giving `00 00 00 00 01`), then
   `DOVI_CleanDCacheRange(addr, 1)` for both bytes.

#### rdfix (FIFO clamp)

- It records the ESM ring bounds for elfix.
- If the caller is the EL handle (ESID 1), BL and EL share the FIFO (same `sa`), and the BL's `rd` is behind the
  EL's (more unread data from `wr`), it returns the BL's `rd`.
- It never changes the BL's own releases. Holding the BL back to a lagging EL deadlocks TS playback with audio: the
  FIFO fills, the demux cannot deliver audio, and AV sync never starts.

#### sync_stub (AV-sync redirect)

At the replaced debug-print `bl`:
- r4 holds the VDP object (byte 0 = id). The VDP objects are the per-plane state structs, and VDP0 = VDP1 − 0x880.
- r5 holds the query result.
- r7 holds the plane's previous controller.

Behaviour:
- **VDP0:** the stub sets a "seen" flag (elstat+80) and stores `jiffies` (elstat+88). It uses a flag rather than a
  zero timestamp because `jiffies` starts at −300 s and wraps to 0 at 300 s uptime.
- **VDP1 with a successful query:**
  - if VDP0 was assigned within the last 500 jiffies (HZ = 100), as in TS or Blu-ray, the stub returns unchanged;
  - otherwise (the P7 MKV path) it sets `r4 -= 0x880` and reloads `r7 = [r4+0x6c8]`. The rest of the firmware
    function then attaches the controller to VDP0, exactly like single-layer MKV.

#### spsfix / ppfix (EL SPS guard)

After a seek or a trick-play restart, the EL decoder can parse the base layer's 3840×2160 SPS, which has the same
SPS id. For the EL decoder (ESID 1, stream info at `*(0x7ee6e690 + 0xa8 + 4)`, single-stream flag at `+0x650ac`,
EL flag at `+0x650af`), an SPS wider than 1920 is handled as follows:
- **`spsfix`** marks the SPS invalid (`sps+0x2b4 = 0`, with `sps = base + sps_id*0x28a8`; width at `+0x450`) and
  returns `0xff03`.
- **`ppfix`** restores the previous pre-parse result. The output is `{w, h, x, valid}`, and the previous values
  are at `out[4..7]`.

The rejected SPS has already overwritten the EL's SPS slot (same id), and the EL frame-buffer group is sized from
that slot. Since v1.3.1 `spsfix` puts the EL's last width and height back (`elw`/`elh`); before, the EL could get a
4K buffer group and never decode again.

#### clrfix (EL FIFO clear)

On a seek, trick play or stop the firmware's `vESM_FifoClear` clears the BL's ESM handle and the audio one, but not
the EL's (handle 3, same FIFO memory). The EL decoder kept its old picture queue and decoded stale entries after a
seek. At the end of every `vESM_FifoClear(h)`, `clrfix` clears every other handle on the same FIFO memory (with a
recursion guard).

#### Single-stream DV only (v1.4.0)

The firmware plays Dolby Vision in two modes, stored per stream by `vVDec_Set_Dolby_Info` (`0x7eaaba08`; printed as
`[ESID_x] Hdr_Type: 2,fgIsDual: …,fgIsSingle: …`): stream info `+0x650a8` Hdr_Type, `+0x650ac` **fgIsSingle**,
`+0x650ad` fgIsDual, `+0x650ae..+0x650b0` BL / EL / RPU present. MKV and TS (BL, EL and RPU in one video track) are
single-stream (`fgIsSingle` 1 on both ESIDs). UHD Blu-ray (separate BL and EL streams) is dual-stream (`fgIsSingle`
0), the firmware's own working path. In v1.3.1 the cave-2 stubs and the stop hook did not check the mode and also
ran on discs: `mc_stub` reset the multi-core block about 11 times per decoder (re)start while the dual-core BL could
be mid-picture, which showed as green strips in a disc menu with looping DV video and could hang playback after
chapter skips. Since v1.4.0 every cave-2 stub returns to the original path unless `fgIsSingle` is 1 (`nofb_stub`,
`mc_stub` and `eos_stub` read their own stream info, `rec_stub` the EL's (ESID 1, `0x7ee6e73c`), `cmp_stub` does
nothing without a record), and `VDec_Stop` goes through `vdp_gate`, which calls `vdp_entry` only when the EL stream is
single-stream. `fgIsSingle` is cleared at a full stop. Fingerprint words for the field: the `vVDec_Set_Dolby_Info`
stores at `0x7eaaba34..0x7eaaba50` and the literal `0x6503c` at `0x7eaabaa8`.

#### Seek fixes (cave 2, v1.3.1)

In single-stream DV, `_VdpGetNextDisp` holds the BL plane (VDP0) while the EL plane (VDP1) has no frame queued
(`0x7e9bab50..0x7e9bab6c`; with the VDP debug mask `0x7ee3cb68` bit 0x40 it logs `check main and sub Q buffer
count`). If the EL plane runs dry after a seek, the BL frames stay queued, the BL decoder runs out of frame buffers
(state 9), the shared FIFO fills, the EL decoder starves (state 1) and the picture freezes while the clock runs.
Chapter skips, seeks, and audio or subtitle changes all do a *same-stream stop* and restart. Three ways that
emptied the EL plane are fixed:

- **`nofb_stub` (stale reparse flag).** `fgNoFbReParse` (stream info `+0x4c9c`) is set between "free frame buffer
  found" (state 9) and the decode. A full stop clears it (`vVDecReleaseProc`); a same-stream stop did not, so the
  first EL picture after the restart skipped its frame-buffer setup (`No empty OutFbInfo`) and was lost. The stub
  does the displaced store and clears the flag on the "ReInit From SSStop" path.
- **`mc_stub` (EL multi-core reset).** The BL decodes on two cores. `i4H265_Parse_Syntax_Proc` resets the HEVC
  multi-core block (`vVDecResetMultiCore`) before every BL picture (stream info `+0x65012 == 1`), and a full stop
  does too (`vH265ReleaseProc`). A same-stream stop that interrupts a BL picture (log: `Wait VDEC_DECODING(vld:0)`)
  leaves the block stale; the EL's first picture after the restart (single core) then never finishes (`Decode
  Timeout`, `cur FBId:255`) and the EL resumes about a second later, at its next I picture. Seen in 19 of 20 such
  skips, against 1 of 81 otherwise. The stub makes the EL decoder (ES 1) do the same reset while its picture count
  (`+0x10`) is at most 1, unless the BL is decoding at that moment (state 5).
- **`rec_stub` / `cmp_stub` (frozen BL frame).** VDP1 times each EL frame against the frame VDP0 shows now
  (`EL − BL` PTS: < 0 late = dropped, 0 shown, > 0 wait; dovi threshold at `0x7ed2d3d8+0x30`). After a same-stream
  stop VDP0 keeps showing its last pre-seek frame until the first new BL frame is due. After a backward jump that
  frame is newer than every new EL frame, so VDP1 dropped them all. `rec_stub` records the frame-info pointer of
  the frame VDP0 shows when the first picture after the restart arrives (`VDPCheckFirstPicPts`, then the original
  debug print). While VDP0 still shows that frame, `cmp_stub` sets the difference to `+0x7fffffff`, so VDP1 waits,
  as it does after a forward jump. The record is cleared as soon as VDP0 shows another frame.

The stubs read the VDP0 object pointer (`0x7ee3cb94`) and the ESID 0 stream-info pointer (`0x7ee6e738`); both are
global data, +0x90 in the USA driver build.

#### End of file (cave 2, v1.3.1)

At the end of the file the EL decoder (MPV1) gets one last ES message from the shared FIFO: a data message with no
read pointer (`+0x14` = 0) and no picture flags (`+0x10` = 0), covering only the bytes after its last picture. The
BL decoder first gets the end-of-stream in-band command, which sets the EOS flag (stream info `+0x184` bit 0x80);
`i4H265VParseProc` then treats such a message as the end (flush the DPB, no picture). The EL never got that
command, so it parsed the empty message as a picture starting at address 0 (`Forbiden Zero bit error`,
`SLICE_REF_PIC_LOST`) and, in `fgH265ResultChk`, summed its bitstream bytes from address 0
(`ui4DecDebugChecksum`, NULL pointer in `v7_dma_inv_range`). The oops killed MPV1: the picture froze on the last
frame, the player stayed in PLAY, and nothing played again until a reboot. It happened every time, with MEL and
FEL films; v1.2.0 does the same (tested with the MEL film), and the older releases have the same EL path.

`eos_stub` does the displaced store (`+0x5f4` = picture start) and, for a message with neither a read pointer nor
picture flags, sets the EOS flag. The EL then takes the firmware's own end-of-stream path, the BL finishes its last
pictures, playback ends and the player returns to the file list. A read pointer of 0 never occurs in a real
message (the FIFO is in the kernel linear map), so no other message is affected.

#### vdp_off (stop)

On `VDec_Stop(1)`, if VDP1's state is still 2, it calls `VDP_SetEnable(1, 0)`. That disables the composer EL and
lets the EL frame buffers be released, which is what the natural end-of-file path does.

### Enable flags and counters

`elstat+0x18` holds the enable mask; the release uses `7315`. The cave-2 fixes have no enable bit; they are
switched with the other hooks by `p7kel.sh on|off`.

| Bit | Meaning |
|---|---|
| 1 | scan (elfix active) |
| 2 | rewrite slices |
| 16 | legacy (always set) |
| 64 | unused (was debug printk during development) |
| 128 | FIFO clamp |
| 1024 | stop fix |
| 2048 | EL SPS guard |
| 4096 | EL FIFO clear |

`p7kel.sh status` prints the sites state (`ok`, `off`, or `old` when an older release's patch is active), the
first 32 bytes of `elstat`, and `seek=` with the four cave-2 counters (`c2stat`, `0x7e94d3d0`), all zero on discs: EL multi-core resets, the VDP0 frame recorded
at the last restart (0 once VDP0 moved on), EL frames held back from the frozen frame, and end-of-stream messages
flagged (one per file played to the end).

| Word | Field |
|---|---|
| 0 | magic `XFLE` |
| 1 | calls |
| 2 | EL pictures fixed |
| 3 | slices rewritten |
| 4 | longest scan |
| 5 | last rd |
| 6 | enable |

The VDP0 sync timestamp, the clamp counters and the stop counter live further in the struct (see `elfix.c`).

## Part 3: subtitles (`subs.sh`, RU 65-0131 player program only)

It is gated on the md5s of `bdpprog.1` (`49b649bd…`) and `liblp.so`. It writes into the running player through
`/proc/<pid>/mem`.

| What | Where | Change |
|---|---|---|
| Rendered text colour table (ARGB, 24 entries = the menu grid) | bdpprog `.data` `0x01238c20` | slots 9, 11 → `A0A0A0`, `686868`; slots 18–23 → `C8`, `B4`, `A0`, `88`, `68`, `48` grey |
| Palette mirror (RGBA, entries 10..33) | liblp `0x6aa790` + runtime base | same values |
| Glyph render flags | bdpprog `0x4cbfdc` (ARM) | `movw r2,#0x1004` (RENDER\|MONOCHROME) → `mov r2,#6` (RENDER\|NO_HINTING) |
| Outline colour row | bdpprog `0x8da2a4` (Thumb) | `adds r3,#0x1c` → `#0x1d` (options = palette 29..34, last = black) |
| Outline preview colours | bdpprog `0x1238c80` | `B4`, `A0`, `88`, `68`, `48`, `000000` |
| Outline (edge) width | liblp `0x584998` (5 instructions) + `0x584ad8` | 1 → 2 |

Every instruction patch checks the expected original bytes first.

**Menu squares:** `image_bdp83.bin` is a container with a 282-entry index (`u16 w, u16 h, u32, u32, u32 size,
u32 offset`, 20 bytes each, after a `u32` count). Entries 216..239 are the 56×30 subtitle-colour squares. The
installer:
1. copies the player's own `/mnt/rootfs_normal/res/image_bdp83.bin` (md5 `463cec55…`, identical in every regional
   v65 firmware);
2. writes the 8 shipped squares over entries 225, 227 and 234–239, zero-fills the rest of each old square and
   updates the size fields;
3. accepts the result only if its md5 is `44bedb87…`.

At boot the wrapper replaces the `/res` symlink by a directory of symlinks and points `image_bdp83.bin` at the rebuilt
file. This happens in RAM, so the root filesystem is never written.

## Part 4: factory menu shortcut (`fpage.sh`)

The Factory Page is built by the Playback Setup key handler `FUN_008482f8` (called from `FUN_00848980`). Its
trigger: the list's highlighted index (widget command `0x1000301d`) must be 1 (Gapless Playback); key `0xbf00e`
(F3 in the CLI key table, which lists code, name pairs) arms it (state `0x13464c4`: `+0x129` armed, `+0x12a` count,
`+0x12b..` buffer, cleared); keys `0xbf010` (F5) and `0xbf016` (F11) are stored as `key - 0xc` and compared with
`{4, 10}` (`0x123887a`, 2 bytes); any other key disarms. On a match it clears the firmware-update tag check flag
`0x12515d9`, builds the page in the Setup widget block `0x134512c` and runs `ipcd_exec("inetd")`. Digit keys are
`0x10030..0x10039`.

| Site | Original | Patched |
|---|---|---|
| `0x8483bc` literal | `0x000bf010` (F5) | `0x00010030` (`0`) |
| `0x84838a` | `adds r1,#6` (F11 = F5 + 6) | `adds r1,#0` (`0`) |
| `0x8483cc` | `beq.w 0x848966` (not armed: return) | `beq.w 0x848394` (arm: `r2` = state address, non-zero; `r3` = 0) |
| `0x8483e2` | `movs r2,#2` (compare length) | `movs r2,#3` |
| `0x8486a4` literal | `0x0123887a` (`{4,10}`) | `0x00fe77e5`: three `0x24` bytes (`'0' - 0xc`) in a read-only table |

So the first 0 arms, the next three fill the buffer and match. F3 (`0x10028` after the change) can no longer arm it.
The sites are the same in the RU 65-0131 program (`49b649bd`) and the jb_overlay V3 copy (`82e04bcf`: 40 bytes differ,
`res` → `tmp` in five resource paths and a few `.text1` patches). `fpage.sh` finds the player by name, checks the md5
of `/proc/<pid>/exe` and writes through `/proc/<pid>/mem`, after checking every site holds the original or the
patched bytes.

## Debugging tips (for developers)

- The kernel log goes to `/proc/kmsg`.
  - `busybox dmesg` only holds a few hundred lines, and the player floods it.
  - To capture everything up to a hard lock, stream it to a PC:
    on the player `cat /proc/kmsg | busybox nc -l -p 5556`, and on the PC `nc <player-ip> 5556 > log`.
- The stock `dd` segfaults on large reads from `/dev/mem`. Single words and small ranges are fine.
- Useful log lines:
  - `[VDEC]: [H265-1]: Dec Err` (EL decode error);
  - `Decode Timeout` (BL);
  - `[DOVI]HDMI EDID inf:e d` (the display supports DV) versus `inf:0 0` (failed EDID read: no DV output);
  - `SDR -> DOVI` (DV output started);
  - `[VDP1] Dovi VDP2 Disable and disable Composer EL` (EL plane off).

## Offline alternative

`docs/unwraprest.py` makes the equivalent change offline on a raw HEVC elementary stream (it drops the 2-byte wrapper from every continuation slice instead of zeroing it in place):

```
python3 unwraprest.py in.hevc out.hevc
```

A single-stream P7 TS with a DOVI descriptor, built from the output, plays as FEL Dolby Vision on **stock** firmware.
It does not help with MKV, because the MKV splitter then puts the unwrapped EL slices into the base layer. It is
kept for reference only.
