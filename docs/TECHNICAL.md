# Technical notes

This document is for people who want to understand, verify or extend the patches. All addresses are for the Oppo
UDP-203 on Oppo's v65 firmware (developed and tested on the **RU 65-0131** jailbreak):
- `liblp.so` md5 `e39b358c5b0948933f49fd3099f81114` (identical in all regional v65 firmwares)
- `bdpdrv1` kernel module loaded at `0x7e8d3000`, verified by fingerprint (see below)
- the region-specific player program (`bdpprog.1`, md5 `49b649bdcffe8b611f1b7bbc0d9fa0b1` on RU 65-0131) is not
  patched

The hardware is a MediaTek MT8581 (4× Cortex-A9) running Linux 3.10.

## Overview

| Part | Target | Patcher | Blob source |
|---|---|---|---|
| MKV Dolby Vision signalling | `liblp.so` inside the running `bdpprog.1` (via `/proc/<pid>/mem`) | `dvhook.sh` | `src/liblp/` |
| Profile 7 decoder fixes | `bdpdrv1` kernel module (via `/dev/mem`) | `p7kel.sh` | `src/kernel/` |

Both patchers are idempotent (`on` when already on does nothing) and reversible (`off`). They verify every patch
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
| `0x7e9fa3ac` | `0x7ee41cac` | literal: ESM handle table |
| `0x7eabd2cc` | `0x7ee6e690` | literal: VDEC instance table |
| `0x7e9a41ec` | `0x7ee3cb60` | literal: VDP global state |

It also checks:
- `/proc/kallsyms`: `printk` at `0x803f7df0` and `jiffies` at `0x805760c0`;
- the original or patched instruction at each of the 6 hook sites.

### Code cave and hooks

The cave is the dead CLI test function `_FbmCli_Test_4K`, `0x7e98be80..0x7e98c7c0`. Code runs up to `0x7e98c748`;
the counters and state (`elstat`) follow, up to `0x7e98c7c0`. `p7kel.sh` checks the original contents by md5 (three
chunks: page split and code/data split), so no firmware bytes are shipped.

| Hook | Site | Original instruction | Entry |
|---|---|---|---|
| EL slice rewrite | `i4VDEC_HAL_H265_InitBarrelShifter` `0x7ea9c7b4` | `push {r0,r1,r4-r8,lr}` | `entry` → `elfix(bs, vld, lr)` |
| FIFO clamp | `i4ESM_FifoRdPtrSet` `0x7e9fa2dc` | `ldr r2,[pc,#0xc8]` (literal `0x7ee41cac`) | `rd_entry` → `rdfix(handle, rd)` returns the rd to use |
| AV-sync guard | `u4VDP_AssignSyncCtrl` `0x7e9c0c48` | `bl` to a debug print (replaced) | `sync_stub` |
| Stop | `VDec_Stop` `0x7eaac99c` | `cmp r0,#7` | `vdp_entry` → `vdp_off(esid)` |
| EL SPS guard | `i4H265_Parse_Syntax_Proc` `0x7eb26d9c` | `bl i4VDecH265SPSPsr` | `spsfix(ctx, sps_base, pic)` |
| EL pre-parse guard | `i4H265_Pre_Parse_SPS_Proc` `0x7eb215cc` | `bl vH265PreParseSPS` | `ppfix(esid, .., .., .., out)` |

#### elfix (EL slice rewrite)

It is called for every barrel-shifter init: BL cores, the look-ahead engine and the EL. `bs = {rdptr, fifo_end,
fifo_start, ...}`, all kernel linear-map addresses.

1. Bound the scan:
   - ring end = the ESM fifo end recorded by `rdfix` (not the 12 MB window);
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

#### vdp_off (stop)

On `VDec_Stop(1)`, if VDP1's state is still 2, it calls `VDP_SetEnable(1, 0)`. That disables the composer EL and
lets the EL frame buffers be released, which is what the natural end-of-file path does.

### Enable flags and counters

`elstat+0x18` holds the enable mask; the release uses `3219`.

| Bit | Meaning |
|---|---|
| 1 | scan (elfix active) |
| 2 | rewrite slices |
| 16 | legacy (always set) |
| 64 | unused (was debug printk during development) |
| 128 | FIFO clamp |
| 1024 | stop fix |
| 2048 | EL SPS guard |

`p7kel.sh status` prints the sites state and the first 32 bytes of `elstat`:

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
