# oppo-dv-mkv

**Dolby Vision from MKV on the Oppo UDP-203 (jailbroken):** profile 5, profile 8.x and **profile 7 FEL/MEL** (dual layer,
single track) play as real Dolby Vision, with audio, from MKV files. The original files play as they are, with no
remuxing or conversion.

---

> ## ⚠️ DISCLAIMER: READ THIS FIRST
>
> **USE THIS AT YOUR OWN RISK. I AM NOT RESPONSIBLE FOR ANYTHING THAT HAPPENS TO YOUR PLAYER, YOUR TV, YOUR AV
> RECEIVER, YOUR FILES OR ANYTHING ELSE.**
>
> - This is an **unofficial, unsupported modification** for a player that already runs **unofficial jailbreak
>   firmware**. It is not affiliated with, endorsed by or supported by Oppo, Dolby or MediaTek.
> - It changes how your player boots and patches the running player program and the running Linux kernel in memory.
>   That can crash or hard-lock the player. In the worst case it could leave the player unable to start properly.
> - It was developed and tested on **one** player, with **one** TV and AV receiver. Your setup may behave
>   differently.
> - Using it may void any warranty you have left.
> - There is **no support and no guarantee** of any kind. See [LICENSE](LICENSE): the software is provided "as is".
>
> **If you are not comfortable with any of this, do not install it.**

---

> ## 📺 Important: all testing was done in **TV-led** Dolby Vision mode
>
> Every result in this document was obtained with the player in **TV-led** Dolby Vision mode, the normal mode where
> the TV does the Dolby Vision tone mapping. **Player-led** (low-latency DV, LLDV) mode was **not tested** at all.
> It may work, or it may not.

---

## Contents
- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Uninstall and emergency off switch](#uninstall-and-emergency-off-switch)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [What was broken, and how it was fixed](#what-was-broken-and-how-it-was-fixed)
- [Tests](#tests)
- [How it is installed on the player](#how-it-is-installed-on-the-player)
- [Building from source](#building-from-source)
- [Credits](#credits)

## What it does

On stock firmware (jailbroken or not), the UDP-203 plays MKV files that contain Dolby Vision as HDR10 at best.
Profile 5 even shows the familiar purple and green picture, and profile 7 is reduced to its HDR10 base layer. Dolby
Vision only works from discs, BDMV folders and some specially crafted TS files.

With this fix installed:

| MKV content | Stock firmware | With oppo-dv-mkv |
|---|---|---|
| DV profile 8.1 (single layer, HDR10 compatible) | HDR10 | **Dolby Vision** |
| DV profile 5 (single layer, IPT) | purple/green picture | **Dolby Vision** |
| DV profile 7 FEL (base + full enhancement layer, single track) | HDR10 (base layer only) | **Dolby Vision, full FEL** |
| DV profile 7 MEL (base + minimal enhancement layer, single track) | HDR10 (base layer only) | Dolby Vision (same code path as FEL, see [limitations](#known-limitations)) |
| HDR10 / SDR | normal | normal (unchanged) |

Audio (tested with AC-3 bitstreamed to an AV receiver), pause and resume, seeking, stopping and playing the next
file all work. Discs and TS files keep working as before.

## Requirements

- An **Oppo UDP-203**.
- Running the free **"RU 65-0131" jailbreak firmware**. The installer checks this exactly: the md5 of `liblp.so`
  must be `e39b358c5b0948933f49fd3099f81114` and that of `bdpprog.1` must be `49b649bdcffe8b611f1b7bbc0d9fa0b1`,
  the launcher must support `/mnt/ubi_boot/bdpprog`, and the `bdpdrv1` kernel module must be at its expected
  address. **On any other firmware it refuses to install and changes nothing.**
  - The UDP-205 and other firmware versions are **not supported**, because the patches are tied to exact binary
    addresses.
- A USB stick formatted **FAT32**.
- A Dolby Vision display, set up for **TV-led** Dolby Vision (see above).

## Install

1. Download `oppo-dv-mkv-vX.Y.Z.zip` from the [Releases](../../releases) page.
2. Unzip it to the **root** of a FAT32 USB stick. You should see `AutoScript/` and `README.txt` at the top level of
   the stick.
3. Power the player **off**. Plug the stick into the **rear** USB port, and make sure no other USB storage is
   connected. Power the player **on**.
   - At boot the player runs `AutoScript/install.sh` from the stick. It takes a second or two.
4. When the home menu has been up for about 30 seconds, power the player **off** and remove the stick.
5. (Optional) On a PC, open `oppo-dv-mkv.log` in the root of the stick. It should contain a line starting with
   **`INSTALLED`**. If it says **`FAILED`**, the reason is on that line, and nothing was activated.
6. Power the player **on**. From now on the fix is applied automatically at every boot.

The installer also works as an updater: running a newer release the same way replaces the files.

## Uninstall and emergency off switch

- **Uninstall:** download `oppo-dv-mkv-vX.Y.Z-uninstall.zip` and use it exactly like the installer. The log should
  say **`UNINSTALLED`**. After the next power cycle the player behaves as before the install.
- **Built-in fail-safes:** the boot wrapper switches the patches off by itself and boots a stock player:
  - if two boots in a row never reach a healthy state, which the patcher marks 90 seconds after start; or
  - if the player program crashes within 120 seconds of a patched start. In this case it reboots once with the
    patches disabled.
- Logs on the player: `/mnt/ubi_boot/oppo-dv-mkv/dvmkv.log` and `wrapper.log`.

## Known limitations

- **Single-track profile 7 only.** Almost all P7 MKVs (MakeMKV, mkvmerge) store the base layer, the enhancement
  layer and the RPU in **one** video track, and that is what this supports. **Dual-track** P7 MKVs (BL and EL in
  two separate video tracks) are **untested** and probably play as HDR10.
- **MEL** files use exactly the same code path as FEL, but the published tests used FEL material.
- **Profile 5/8 MKVs whose HEVC `CodecPrivate` (hvcC) has no VPS/SPS/PPS** play the stock way, without DV. This is
  typical of MKVs remuxed from an `hev1` MP4. Signalling DV for such files hard-locks the player, so they are
  deliberately left alone. Remuxing them so the parameter sets are in the hvcC (for example mkvmerge from a TS) makes
  them work.
- **MP4 files with Dolby Vision** are not covered; they freeze the player even on stock firmware.
- **Player-led (LLDV) mode** was not tested.
- At the exact point of a **seek**, one or two enhancement-layer pictures may fail to decode. This is invisible in
  practice, and the base layer and audio are unaffected.

## Troubleshooting

- **Everything plays in SDR/HDR10 and the receiver shows no Dolby audio, even for discs.** The player read no Dolby
  Vision capability from your TV/receiver chain at boot (the HDMI EDID handshake). This happens sometimes after a
  power cycle when the TV or receiver was not ready. Turn the TV (or the receiver) off and on again. In this state
  playback can also stall at start-up; the fix is the same.
- **MKV DV stopped working after a firmware update.** The patches only apply to the exact firmware above, so the
  patcher logs a mismatch and does nothing.
- **Check that it is active:** `dvmkv.log` on the player should contain `dvhook: dvhook ON`, `p7kel: p7kel ON` and
  `boot marked healthy`.

## What was broken, and how it was fixed

The fix has two parts:

- **A patch to the player program's playback library** (`liblp.so`), so that MKV files with Dolby Vision are
  *announced* as Dolby Vision.
- **A patch to the video driver** (`bdpdrv1`, a Linux kernel module), so that profile 7 actually *decodes and
  displays* correctly.

Both parts are applied **in RAM** at every boot. **No firmware file is modified.**

### 1. MKV files never tell the decoder about Dolby Vision (P5, P7, P8)

**Symptom:** P8.1 MKVs play as HDR10, P5 shows purple and green, and P7 plays its HDR10 base layer.

**Cause:** the MKV demuxer never passes any Dolby Vision information to the media engine. The "DOVI info" pointer
it hands over is literally `NULL`, and the per-stream Dolby Vision flags stay zero. The TS path fills both, which is
why TS files can work.

**Fix:** hooks in the MKV parser read the Matroska `BlockAdditionMapping` element (`dvcC`/`dvvC` record) of the
video track. When the record is valid, the hooks hand the media engine the Dolby Vision flags, profile and level.
For profile 7 the flags announce a "single-stream dual-layer" stream (BL + EL + RPU interleaved in one stream).
The firmware already contains code for that mode, but nothing ever enabled it for MKV. Files without proper HEVC
parameter sets are excluded, because signalling DV for them hard-locks the player.

### 2. The enhancement layer cannot be decoded from a single stream (P7)

**Symptom:** with DV signalled, profile 7 showed a black picture. The EL decoder failed on every enhancement-layer
picture.

**Cause:** in a single-track P7 stream every EL NAL unit is wrapped in a NAL unit of type 63 (`00 00 01 7E 01 ...`).
The decoder's *software* start-code reader strips this wrapper, but the *hardware* slice finder does not. It
locates the 2nd, 3rd ... Nth slice of a picture on its own and cannot skip the wrapper. Typical material has 8
slices per picture, so every EL picture failed.

This was pinned down with crafted dual-PID TS files: with only the parameter sets and the first slice wrapped, the
result was perfect Dolby Vision; with every slice wrapped, or only the following slices, the picture was pink
garbage.

**Fix:** a kernel hook runs just before the EL decoder starts a picture. It rewrites every wrapped *continuation*
slice in place, from `00 00 01 7E 01 <slice>` to `00 00 00 00 01 <slice>`. The length stays the same and the
result is still a legal Annex-B stream. Everything else stays wrapped, because the base-layer decoder walks the same
bytes and must keep ignoring them. The change is pushed to RAM (D-cache clean) before the hardware reads it.

### 3. The demuxer overwrites base-layer data before it is decoded (garbage, then hang)

**Symptom:** after fix 2, profile 7 MKV played in Dolby Vision for less than a second. From picture 17 onwards it
showed garbage, then decode time-outs, then a hang, at exactly the same picture every time.

**Cause:** the base layer (4K) and the enhancement layer (1080p) share one 8 MB video FIFO, but each decoder
releases the space it has consumed through its own handle. The MKV splitter refills the buffer based on the
**enhancement layer's** release. The EL decodes much faster than the 4K base layer and runs up to several MB ahead,
so the splitter overwrote base-layer pictures that had not been decoded yet.

**Fix:** a kernel hook on the FIFO release clamps the enhancement layer's release to the base layer's read position.
Only the EL is clamped. An earlier version that also held the base layer back to a lagging EL deadlocked TS playback
with audio: the FIFO filled up, the demuxer could not deliver audio, and AV sync never started.

### 4. Pictures across the end of the ring buffer were not fixed

**Symptom:** a handful of EL decode errors per film, always on pictures that straddle the end of the video ring
buffer.

**Cause:** the hardware is given a 12 MB window, but the FIFO ring is 8 MB. The rewrite in fix 2 wrapped around at
the wrong place for those pictures.

**Fix:** the hook uses the real ring bounds from the FIFO manager. It also never reads beyond the demuxer's current
write position, and skips pictures it has already handled.

### 5. Hard lock as soon as Dolby Vision starts, but only with audio

**Symptom:** P7 MKVs without audio played perfectly. The same files with audio hard-locked the whole player (no
HDMI signal) the moment the Dolby Vision output started.

**Cause:** in the MKV path the player gives the **enhancement-layer video plane** an AV-sync controller, which is
slaved to the audio clock, but never gives one to the **base-layer** plane. TS and Blu-ray assign it to both
planes, and MKV without audio assigns it to neither. The mismatch hard-locks the chip when the EL plane shows its
first picture. Setting the TV output to a fixed 24 Hz did not help; the lock is not caused by the HDMI mode switch.

**Fix:** the EL plane is refused an AV-sync controller unless the base-layer plane was given one in the previous
5 seconds. TS and Blu-ray therefore keep their normal behaviour, and the MKV case falls back to the same scheme as
MKV without audio, which works.

### 6. Stopping a film leaves garbage on screen until reboot

**Symptom:** after **STOP** in the middle of a P7 MKV, every following screen, even the "resume playback?" prompt,
showed garbage until the player was rebooted. Letting a file play to its end was fine.

**Cause:** at the natural end of a file the firmware switches off the EL video plane and the composer's enhancement
layer. On **STOP** the MKV middleware never does this, so the plane kept scanning out frame buffers that had already
been freed and reused.

**Fix:** when the EL decoder is stopped and its plane is still on, the hook turns the plane off with the firmware's
own function, exactly as the natural-end path does. A seek does not stop the decoder, so seeking is unaffected.

## Tests

All tests were run on one Oppo UDP-203 with the RU 65-0131 jailbreak, connected through an AV receiver to a Dolby
Vision TV in **TV-led** mode. Audio was AC-3 5.1 bitstreamed to the receiver.

The main test material was a **90-second Dolby Vision profile 7 FEL excerpt cut from a commercial UHD release**:
3840×2160, 23.976 fps, CM v2.9, 8 slices per picture, AC-3 5.1. Every other test file was derived from it with
`dovi_tool`, `mkvmerge`, `ffmpeg` and `tsMuxeR`: remuxes, layer splits, P8.1 conversions, and bitstream variants
built with small Python scripts. Separate short P5 and P8.1 samples were used for the single-layer work. The source
titles are deliberately not named.

### Stock firmware: how far each container gets

| Test file | Result on stock firmware |
|---|---|
| P7 FEL, single-track MKV | HDR10 (base layer only) |
| P7 FEL, BDMV folder (BL and EL as separate streams) | **Dolby Vision**, clean |
| P7 FEL, dual-stream m2ts without DV descriptor | HDR10 |
| P7 FEL, dual-stream m2ts with DV descriptor | Dolby Vision, but every later file shows garbage until reboot |
| Same, descriptor on both streams | garbage picture |
| P7 FEL, single-stream TS (BL+EL+RPU interleaved) with DV descriptor | black screen, stuck at 00:00 |
| P7 base layer + P7 RPU, EL removed | Dolby Vision with vertical-line garbage |
| P7 converted to P8.1 (EL dropped), TS and MKV | Dolby Vision |
| P7 converted to P8.1, MP4 | **player freezes** |
| P8.1 MKV / P5 MKV | HDR10 / purple and green |
| P5 TS with DV descriptor | Dolby Vision |

### Finding the enhancement-layer problem

| Test file | Result |
|---|---|
| Single-stream TS variants: EL SEI removed / duplicate BL parameter sets removed / EL VPS removed | no change, still black |
| Dual-stream TS, EL stream with every NAL wrapped in type 63 | pink garbage |
| Dual-stream TS, EL with only parameter sets + **first** slice wrapped | **perfect Dolby Vision, 0 decode errors** |
| Dual-stream TS, EL with only the **continuation** slices wrapped | pink garbage |
| Single-stream TS with continuation slices unwrapped offline | **perfect Dolby Vision on stock firmware** |
| Same bitstream as MKV + DV signalling | base-layer errors then hard lock: the MKV splitter puts unwrapped EL slices into the base layer |

This is why the fix rewrites the original stream inside the player instead of asking anyone to convert files.

### Profile 7 with the fix, step by step

| Stage | MKV, no audio | MKV with audio | Single-stream TS (original wrapped stream) |
|---|---|---|---|
| Fix 2 only (slice rewrite) | DV logo, garbage from picture 17, hang | hard lock at start | **perfect DV, 0 errors**, with and without audio |
| + fix 3 (FIFO clamp) | **DV, correct picture**, a few EL errors at the ring wrap | hard lock at start | first (two-sided) clamp: stalled at start with audio; one-sided clamp: **perfect** |
| + fix 4 (ring bounds) | **DV, 0 decode errors over the full 90 s** | hard lock at start | — |
| + fix 5 (AV sync) | (not re-run) | **DV + Dolby Digital, 0 decode errors over the full 90 s** | perfect (AV sync untouched: both planes get a controller in TS) |
| + fix 6 (stop) | (not re-run) | STOP mid-film → replay clean | perfect |

Counters from a full 90-second run: 2,180 enhancement-layer pictures fixed, 15,260 slices rewritten, about 2,170
FIFO releases clamped, 0 decode errors, 0 time-outs.

### Final regression run (persistent install, fresh boot)

| Test | Result |
|---|---|
| P7 FEL MKV, original file, with audio | ✅ Dolby Vision + Dolby Digital, 0 decode errors |
| ... pause / resume | ✅ |
| ... seek by time | ✅ clean (1–2 EL pictures at the jump point, invisible) |
| ... STOP mid-film, then play again | ✅ clean |
| ... 5 remote stop → resume cycles, including playing to the end | ✅ no lock, 0 errors |
| P7 FEL single-stream TS with audio | ✅ Dolby Vision + Dolby Digital |
| P5 MKV | ✅ Dolby Vision, correct colours |
| P8.1 MKV | ✅ Dolby Vision |
| P5 MKV with empty hvcC | plays the stock way, by design |
| Commercial UHD Blu-ray disc with FEL Dolby Vision | ✅ unchanged, perfect |
| Reboot | ✅ patches applied automatically |

SDR and HDR10 MKVs (no Dolby Vision record) were checked when the liblp part was first made persistent: they play
exactly as on stock firmware, because the hooks only act when a valid `dvcC`/`dvvC` record is present.

## How it is installed on the player

The jailbreak firmware's launcher (`/usr/local/bin/bdpprog`) starts `/mnt/ubi_boot/bdpprog` instead of the player
program if that file exists. The installer puts there:

```
/mnt/ubi_boot/bdpprog                 boot wrapper with the fail-safes; starts the patcher, then the real player
/mnt/ubi_boot/oppo-dv-mkv/dvmkv.sh    waits for the player, applies both patches, marks the boot healthy
/mnt/ubi_boot/oppo-dv-mkv/dvhook.sh   liblp.so patch   (on|off|status)
/mnt/ubi_boot/oppo-dv-mkv/p7kel.sh    kernel patch     (on|off|status)
```

Before writing a single byte, both patchers verify every patch site: the exact original instructions must be in
place, and for the kernel patch the unused code area it occupies must match the original by md5. On any mismatch
they do nothing. The installer refuses to overwrite an existing `/mnt/ubi_boot/bdpprog` that belongs to another
mod.

Details (addresses, hook points, data structures, debug switches): [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Building from source

```sh
nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm nixpkgs#zip -c ./mkrelease.sh   # or install zig, lld, llvm, zip yourself
```

`mkrelease.sh` compiles both patch blobs (`src/liblp`, `src/kernel`), generates the on-device patchers
(`mkinstall.py`, `mkkinst.py`) and builds both release zips into `dist/`. The builds are reproducible: the md5 of
each blob is printed. No firmware files are needed or included.

## Credits

- The authors of the free **RU 65-0131** UDP-203 jailbreak firmware, without which none of this would be possible.
- [dovi_tool](https://github.com/quietvoid/dovi_tool), [MKVToolNix](https://mkvtoolnix.download/),
  [FFmpeg](https://ffmpeg.org/), [tsMuxeR](https://github.com/justdan96/tsMuxer) and
  [Ghidra](https://ghidra-sre.org/), used to make the test files and to analyse the firmware.
- Reverse engineering, patches and testing: fandangos, together with Claude (Anthropic) as co-author.

## License

[MIT](LICENSE). Provided **as is**, without warranty of any kind. See the disclaimer at the top.
