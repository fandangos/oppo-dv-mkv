# oppo-dv-mkv

**Dolby Vision from MKV on the Oppo UDP-203 (jailbroken):** profile 5, profile 8.x and **profile 7 FEL/MEL** (dual layer,
single track) play as real Dolby Vision, with audio, from MKV files. The original files play as they are, with no
remuxing or conversion.

**Plus better subtitles:** anti-aliased text instead of jagged 1-bit glyphs, a thicker outline with a real black
option, and grey text colours for comfortable, dimmer subtitles on HDR and Dolby Vision.

**Plus a factory menu shortcut:** opens Oppo's hidden service page (versions, region codes) with the normal remote.

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
- [Better subtitles](#better-subtitles)
- [Factory menu](#factory-menu)
- [Requirements](#requirements)
- [Compatibility](#compatibility)
- [Install](#install)
- [Uninstall and emergency off switch](#uninstall-and-emergency-off-switch)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [What was broken, and how it was fixed](#what-was-broken-and-how-it-was-fixed)
- [Tests](#tests)
- [How it is installed on the player](#how-it-is-installed-on-the-player)
- [Building from source](#building-from-source)
- [Credits](#credits)
- [Changelog](#changelog)

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

Audio (tested with AC-3 and Dolby TrueHD Atmos bitstreamed to an AV receiver, with correct lip sync), pause and
resume, seeking, fast-forward, stopping and playing the next file all work. Discs and TS files keep working as before.

## Better subtitles

The stock subtitle renderer draws 1-bit monochrome glyphs, which gives jagged edges and colour fringing around the
letters. Its colour choices are all full-brightness, which is glaring on HDR and Dolby Vision. The installer also
improves this, at every boot and in RAM only:

| | Stock | With oppo-dv-mkv |
|---|---|---|
| Glyph rendering | 1-bit monochrome, hinted (jagged, fringing) | **anti-aliased**, unhinted (smooth edges) |
| Outline (edge) width | 1 | **2** |
| Outline colours | no black | last option is **black** |
| Text colours | bright colours only | in the 6×4 colour grid, the 4th and 6th squares of row 2 and the **whole 4th row** become **greys** (row 4: C8, B4, A0, 88, 68, 48) for dimmer text on HDR/DV |
| Subtitle colour menu | — | the colour squares show the new colours |

Pick the colours in the player's subtitle settings as usual. These changes were tested on the development player
(the same RU 65-0131 jailbreak) together with the Dolby Vision fix. The subtitle part needs the RU 65-0131 player program,
the region-specific part of the firmware. On any other jailbreak the installer skips it automatically, and the Dolby
Vision fix is unaffected. The menu colour squares are rebuilt **on the player** from its own image file plus 8 small
colour squares that ship with this project; no firmware file is distributed.

**Other regions and jb_overlay.** Removing or disabling jb_overlay does not bring the subtitle improvements to a
player from another region: its stock player program (`/usr/local/bin/bdpprog.1`) is different too, so the installer
still skips them. The patch changes a few fixed places in the player program (colour table, glyph rendering flags,
outline width), and the library part (`liblp.so`) is already identical in every region, so it can probably be ported
to other player programs. If you want the better subtitles on your player, make a
[full dump](#helping-to-support-another-firmware-full-dump) and share it privately: it has the player program your
player really runs, with or without jb_overlay. With jb_overlay the colour squares
in the subtitle menu would probably stay unchanged, because the overlay's theme has its own images.

## Factory menu

The player has a hidden service page, the **Factory Page**. Its stock trigger needs keys that only Oppo's factory
remote has. With the factory menu shortcut installed, the normal remote opens it:

1. Press **Setup** and open **Playback Setup**.
2. Move the cursor to the **second item, Gapless Playback**. Do not press Enter.
3. Press **0 0 0 0**.

The page shows the firmware version, sub version and loader version, the DVD and Blu-ray region codes, and some
service buttons. Close it with Return.

> ⚠️ **Look, but do not press anything on this page unless you know exactly what it does.**
> - **Fmt buda** and **Fmt apda** **format** storage areas of the player.
> - The **region** fields change the player's stored DVD / Blu-ray region. This was not tested. The code that saves
>   a new region also resets other data, which was not analysed.
> - **Reset Password** was not tested either.

Opening the page runs Oppo's own code, unchanged, and that code also does two things until the next power cycle:
- **The firmware update stops checking the region/model tag** of update files. Do not run update files meant for
  another region or model while it is off (power-cycle first).
- **It starts `inetd`, a telnet server.** It can only listen when the player's network (IP) control is switched off,
  because both use port 23, and logging in needs the player's root password, which is not known. (Switching IP control
  off froze the Setup menu once during testing; a power cycle fixed it.)

How it works: the page's trigger in the player program waits, with Gapless Playback highlighted, for the factory
keys F3, F5 and F11. The shortcut replaces these three keys by the digit 0, in place (5 small edits, in RAM, at every
boot): the first 0 arms the trigger, three more open the page, any other key cancels. Nothing else changes.
It needs the exact player program it was made for: the RU 65-0131 free jailbreak (`49b649bd…`), or the copy of it
that **jb_overlay V3** runs (`82e04bcf…`, the same program with 40 bytes changed for the theme, none of them near
the trigger). On any other player program the installer skips it and writes why in `oppo-dv-mkv-result.txt`.

## Requirements

- An **Oppo UDP-203**.
- A **jailbreak firmware built on Oppo's v65 firmware** that starts `/mnt/ubi_boot/bdpprog` at boot. The free
  **"RU 65-0131" jailbreak is the only one that was actually tested.** See [Compatibility](#compatibility) for
  other jailbreaks and regions, and how to check yours without installing anything.
- A USB stick formatted **FAT32**.
- A Dolby Vision display, set up for **TV-led** Dolby Vision (see above).

## Compatibility

The patches modify two pieces of Oppo's firmware:
- the playback library `liblp.so`;
- the `bdpdrv1` video driver (a kernel module).

The Dolby Vision fix does not touch the region-specific player program, the part that differs between regions and
between jailbreaks. The subtitle improvements and the factory menu shortcut do patch the player program, so they are
installed only on the exact programs they were made for (checked by the md5 of the program that is running). Each
part is checked on its own: the installer installs the parts that pass, skips the others and writes why.

- **`liblp.so` is byte-identical in all seven regional v65 firmwares** (default/US, EU, AU, CN, JP, RU, TW). The
  installer requires its md5 to be `e39b358c5b0948933f49fd3099f81114`.
- **The `bdpdrv1` video driver is verified in memory** before anything is written. The installer and the patcher
  check:
  - its load address;
  - the original instruction at every hook point and at the instruction after it;
  - the entry of every driver function the patch calls;
  - where the driver's global data sits: six pointers in the driver code to the data the patch uses must all show the
    same offset;
  - the kernel symbols it uses.

  Unlike `liblp.so`, the driver comes from a region-specific, encrypted part of the firmware. Since v1.3.1, **driver
  builds that differ only in where their global data sits are supported**: the patcher measures that offset on the
  player and moves the patch's few data addresses by it. Three builds were checked against driver dumps: RU 65-0131
  (offset 0), USA (+0x90) and a third build of unknown region (+0x50). In each, the hook sites, the code caves and
  every instruction the patch relies on are identical; their real code changes (HDMI handling) are in parts the patch
  does not touch. A driver whose patched code differs fails the checks, and nothing is written.
- **The jailbreak must start `/mnt/ubi_boot/bdpprog` at boot.** The installer never overwrites a
  `/mnt/ubi_boot/bdpprog` that belongs to another mod, and if another mod already patched the same places, the
  patcher sees unexpected bytes and does nothing.
- **jb_overlay** (the overlay mod with themes such as *Dark Space*, ssh and telnet) is recognised. Its boot script is
  kept as `/mnt/ubi_boot/bdpprog.prev`: at boot, oppo-dv-mkv starts first and then hands over to the overlay, which
  keeps working as before. Uninstalling puts the overlay's script back. The subtitle improvements are not installed
  with the overlay, because it runs its own copy of the player program and its own theme images. Reinstalling the
  overlay simply switches the Dolby Vision fix off until you install oppo-dv-mkv again.

| Firmware | Status |
|---|---|
| RU 65-0131 free jailbreak | **tested** (Dolby Vision fix + subtitles + factory menu) |
| USA-region player (v65) | Dolby Vision fix supported since v1.3.1 (USA driver build). **Confirmed by a user with v1.3.1 and jb_overlay**: P7 MEL and FEL MKVs with fast-forward, rewind, chapter skips both ways and playing to the end, P8.1, and the uninstaller. Subtitle improvements and factory menu: not available without jb_overlay yet (different player program, see [Better subtitles](#better-subtitles)) |
| Third driver build (data +0x50, `check` reports `driver data+0x50`) | Dolby Vision fix supported since v1.3.1, checked against a driver dump; **untested on a player** |
| Any of the above with **jb_overlay** (themes) | Dolby Vision fix: chains to the overlay. Subtitle improvements: not installed. Factory menu: installed with jb_overlay V3 (checked against its player program, **untested on a player**) |
| Other jailbreaks on v65 firmware (other regions or variants) | Dolby Vision fix should work if the check passes (it then reports the driver's data offset); **untested**, at your own risk. Subtitle improvements and factory menu are skipped |
| Any other firmware version (for example v60), stock firmware, UDP-205 | not supported: the installer refuses |

### Checking a player without installing anything

Use `oppo-dv-mkv-vX.Y.Z-check.zip` exactly like the installer (see [Install](#install)). It **changes nothing**:
it only writes a report to `oppo-dv-mkv.log` on the stick, ending with `VERDICT: COMPATIBLE` or
`VERDICT: NOT COMPATIBLE` and the reason, and `oppo-dv-mkv-result.txt` with one line per part (yes, or no and why). If the video driver check fails, the report adds `driver:` lines (the
instructions that differ and where the driver keeps its data), which often show whether the fix can be ported without
a driver dump. If you try a jailbreak other than RU 65-0131, please share the report (it contains md5s and kernel
information, no personal data) by opening an issue.

### Helping to support another firmware (full dump)

If the check or the installer says a part is not supported on your player (`module fingerprint mismatch`,
`unknown driver build`, a player program other than RU 65-0131, jb_overlay with its own player program, another
firmware version), that part has to be ported to your firmware. `oppo-dv-mkv-full-dump.zip` (on the release page) collects
everything needed for all parts in one go, with or without jb_overlay, and with or without oppo-dv-mkv installed.
It is **read-only**: it writes nothing to the player and installs nothing. It copies to the stick:

- the player program that is actually running (found by what it loads, so the jb_overlay copy is found too) and the
  libraries it uses, but only the ones the project does not have yet (checked by md5);
- the `bdpdrv1`, `bdpdrv` and `splitter` video drivers, copied from memory with their symbols;
- the boot setup (jailbreak launcher, `/mnt/ubi_boot` boot hook, jb_overlay scripts), kernel and firmware versions;
- the subtitle menu image the player really uses (also a jb_overlay theme's) and the subtitle font;
- a list of every system file with its md5.

No personal data: no network settings, passwords or keys, no jb_overlay `config.ini` / `autostart.sh` / rclone / ssh
files, no Blu-ray storage (BUDA/APDA), no network share mounts.

1. Copy the contents of the zip to the root of a FAT32 stick with at least 200 MB free.
2. Power the player off, plug the stick into the rear USB port, power it on.
3. Leave it on the home menu for 5 minutes (the dump takes about a minute in the background), then power off and
   remove the stick.
4. `oppo-dv-mkv-dump.log` on the stick must end with a line starting with `DONE`.
5. Send `oppo-dv-mkv-dump.tar.gz` from the stick (usually 5 to 30 MB).
6. Delete the `AutoScript` folder from the stick, so the dump does not run again at every boot.

The dump contains Oppo's own program code: **do not post it publicly**. Open an issue saying you have one, and share
it privately.

## Install

1. Download **one** of these from the [Releases](../../releases) page:

   | File | Installs |
   |---|---|
   | `oppo-dv-mkv-vX.Y.Z-full.zip` | Dolby Vision MKV fix + better subtitles + factory menu shortcut |
   | `oppo-dv-mkv-vX.Y.Z-mkv-subtitles.zip` | Dolby Vision MKV fix + better subtitles |
   | `oppo-dv-mkv-vX.Y.Z-mkv-only.zip` | Dolby Vision MKV fix only |
   | `oppo-dv-mkv-vX.Y.Z-subtitles-only.zip` | better subtitles only |
   | `oppo-dv-mkv-vX.Y.Z-factory-menu-only.zip` | factory menu shortcut only |

   Every part is checked on its own (see [Compatibility](#compatibility)). A part that cannot be installed safely on
   your player is skipped, and the others are still installed.
2. Unzip it to the **root** of a FAT32 USB stick. You should see `AutoScript/` and `README.txt` at the top level of
   the stick.
3. Power the player **off**. Plug the stick into the **rear** USB port, and make sure no other USB storage is
   connected. Power the player **on**.
   - At boot the player runs `AutoScript/install.sh` from the stick. It takes a second or two.
4. When the home menu has been up for about 30 seconds, power the player **off** and remove the stick.
5. (Optional) On a PC, open **`oppo-dv-mkv-result.txt`** in the root of the stick. Its first line says
   **`INSTALLED`** or **`FAILED`**, then one line per part: `installed`, `NOT installed` with the reason, or
   `not in this zip`. `FAILED` means nothing could be installed, and nothing was changed. The full log is
   `oppo-dv-mkv.log`.
6. Power the player **on**. From now on the fix is applied automatically at every boot.

The installer also works as an updater: running a newer release the same way replaces the files. You can switch
between the options at any time by running another one: it installs what is in that zip and removes the parts that
are not.

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
- **MEL** files use exactly the same code path as FEL. Both were tested with full-length films (see Tests).
- **Profile 5/8 MKVs whose HEVC `CodecPrivate` (hvcC) has no VPS/SPS/PPS** play the stock way, without DV. This is
  typical of MKVs remuxed from an `hev1` MP4. Signalling DV for such files hard-locks the player, so they are
  deliberately left alone. Remuxing them so the parameter sets are in the hvcC (for example mkvmerge from a TS) makes
  them work.
- **MP4 files with Dolby Vision** are not covered; they freeze the player even on stock firmware.
- **Player-led (LLDV) mode** was not tested.
- At the exact point of a **seek** or a fast-forward step, one or two enhancement-layer pictures may fail to decode.
  This is invisible in practice, and the base layer and audio are unaffected.
- **Resuming within the last minute or so of a P7 film** froze the picture once during development, right after a
  test patch was loaded into the running player (the audio clock kept running). It did not happen again in more
  than 25 later jumps and resumes in the last five minutes with v1.3.1. If it does: Stop, then play again.

## Troubleshooting

- **Everything plays in SDR/HDR10 and the receiver shows no Dolby audio, even for discs.** The player read no Dolby
  Vision capability from your TV/receiver chain at boot (the HDMI EDID handshake). This happens sometimes after a
  power cycle when the TV or receiver was not ready. Turn the TV (or the receiver) off and on again. In this state
  playback can also stall at start-up; the fix is the same.
- **MKV DV stopped working after a firmware update.** The patches only apply to the firmware they were made for, so
  the patcher logs a mismatch and does nothing.
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

### 5. Hard lock as soon as Dolby Vision starts with audio, and lip sync

**Symptom:** P7 MKVs without audio played perfectly. The same files with audio hard-locked the whole player (no
HDMI signal) the moment the Dolby Vision output started.

**Cause:** for audio/video sync, each video plane can be attached to an AV-sync controller that follows the audio
clock. With P7 MKV the player attaches the controller to the **enhancement-layer** plane, and never to the
**base-layer** plane. TS and Blu-ray attach it to both planes, single-layer MKV to the base-layer plane, and MKV
without audio to neither. The EL plane following the audio clock on its own hard-locks the chip when it shows its
first picture. Setting the TV output to a fixed 24 Hz did not help; the lock is not caused by the HDMI mode switch.

**Fix:** when the player offers the controller to the EL plane in the MKV case, the hook redirects it to the
**base-layer plane**, which is what single-layer MKV does. If the base-layer plane was given one in the previous
5 seconds (TS, Blu-ray), the firmware's own behaviour is kept.

v1.0.0 and v1.1.0 refused the controller instead of redirecting it. That prevented the lock, but left the video
unsynchronised: audio was about half a second off for every P7 MKV with audio. Those versions also had a rare
timing bug. The kernel's tick counter wraps to zero 300 seconds after power-on, and an MKV started with audio in
the 5 seconds after that could still hard-lock. Both are fixed in v1.2.0.

### 6. Stopping a film leaves garbage on screen until reboot

**Symptom:** after **STOP** in the middle of a P7 MKV, every following screen, even the "resume playback?" prompt,
showed garbage until the player was rebooted. Letting a file play to its end was fine.

**Cause:** at the natural end of a file the firmware switches off the EL video plane and the composer's enhancement
layer. On **STOP** the MKV middleware never does this, so the plane kept scanning out frame buffers that had already
been freed and reused.

**Fix:** when the EL decoder is stopped and its plane is still on, the hook turns the plane off with the firmware's
own function, exactly as the natural-end path does. A seek does not stop the decoder, so seeking is unaffected.

### 7. Green strips after fast-forward or seeking

**Symptom:** after fast-forwarding (or several quick seeks) in a P7 MKV, playback froze and stopped. From then on
every P7 file showed green strips in parts of the picture until the player was rebooted. Single-layer files were
not affected.

**Cause:** after a seek or trick-play restart, the EL decoder can start reading at a base-layer access unit, where
it finds the **base layer's** 3840×2160 SPS (same SPS id as its own 1920×1080 one). It then decoded EL pictures
with 4K dimensions into 1080p frame buffers, writing past their end into neighbouring memory. On stock firmware
the EL never displays, so this was invisible.

**Fix:** two kernel hooks, in the SPS parser call and in the pre-parse that sizes the frame buffers. In
single-stream DV mode they reject any SPS wider than 1920 on the EL decoder, and its own SPS follows a moment
later.

### 8. Freezes after chapter skips, seeking, or changing the audio or subtitle track (v1.3.1)

**Symptom:** in P7 MKVs (MEL files much more than FEL), skipping to the next or previous chapter, seeking, or
changing the audio or subtitle track sometimes froze the picture: the clock and often the audio ran on, nothing else
happened until Stop. Skipping **back** a chapter froze a MEL film almost every time.

**Cause:** in single-stream Dolby Vision the player shows a base-layer frame only together with its
enhancement-layer frame. A chapter skip, a seek or a track change restarts both decoders in place. If the
enhancement-layer plane gets no frame after the restart, the base-layer frames stay queued, the base-layer decoder
runs out of buffers, the shared input buffer fills up, and the enhancement-layer decoder starves: a deadlock. Six
things could leave the enhancement layer without frames:
- After a skip that interrupted a base-layer picture (the base layer decodes on two cores), the shared multi-core
  hardware block was not reset, and the enhancement layer's first picture never finished decoding. Its next usable
  picture came about a second later. A full stop resets that block; an in-place restart did not.
- After a skip **back**, the enhancement-layer plane compared its new frames with the base-layer frame still frozen
  on screen from before the skip. That frame is newer, so every new enhancement-layer frame looked late and was
  thrown away.
- A "re-parse" flag left set by the restart made the first enhancement-layer picture skip its buffer set-up.
- The enhancement-layer decoder's input queue was not cleared by a seek, so it decoded stale data.
- After a seek, the enhancement-layer decoder could keep a 4K frame size from the base layer's parameters (the v1.2.0
  guard rejected them but left the wrong size behind).
- A picture across the end of the input ring buffer was not fixed when the ring end was taken from the **audio**
  buffer instead of the video buffer (seen as a stall at fixed points of a film, or right after an audio change).

**Fix:** six kernel hooks, three of them in a second unused test function of the driver. The multi-core block is
reset before the enhancement layer's first picture, the enhancement-layer plane waits instead of throwing frames
away while the frozen pre-seek frame is on screen, the flag is cleared and the input queue emptied as a full stop
does, the frame size is restored, and the ring end comes from the video buffer.

### 9. Crash at the end of every P7 film (v1.3.1)

**Symptom:** when a P7 MKV played to its very end, the picture froze on the last frame and the player stayed in
play mode. Stop brought back the file list, but no film played again until the player was restarted.

**Cause:** at the end of the file the demuxer sends both decoders a last, empty message. The base-layer decoder
gets an end-of-stream command before it and ignores it. The enhancement-layer decoder never gets that command, so
it decoded the empty message as a picture with no data address, and the kernel thread of that decoder crashed.

**Fix:** one more kernel hook (in the second test function). An empty message with no data address marks the end
of the stream, as the missing command would have. The enhancement layer then finishes like the base layer, and at
the end of the film the player returns to the file list.

### 10. Freezes and green strips on UHD Blu-ray discs (v1.4.0)

**Symptom:** with v1.3.1 installed, Dolby Vision UHD Blu-ray discs and ISOs could freeze after a chapter skip,
fast-forward or rewind (the player had to be switched off with the power button). The looping Dolby Vision video
of some disc menus showed green strips. Without oppo-dv-mkv the same discs played fine.

**Cause:** the firmware plays Dolby Vision in one of two modes. MKV and TS files carry both layers in **one** video
track (single-stream mode, the one this project fixes). Blu-ray discs carry them in **two** separate streams
(dual-stream mode, which already worked). The hooks added in v1.3.1 for fixes 8 and 9, and the stop hook of fix 6,
did not check which mode was active, so they also ran during disc playback. One of them resets the decoder's shared
multi-core block before the enhancement layer's first picture. On a disc the base layer can be decoding at that
moment; the reset cut its picture short (green strips), and when the picture never finished, playback froze.

**Fix:** each of these hooks now reads the mode the firmware stores for the decoder (`fgIsSingle`) and does nothing
unless it is single-stream Dolby Vision. Discs, BDMV folders and dual-stream content play exactly as on stock
firmware again.

## Tests

All tests were run on one Oppo UDP-203 with the RU 65-0131 jailbreak, connected through an AV receiver to a Dolby
Vision TV in **TV-led** mode. Audio was AC-3 5.1 or Dolby TrueHD Atmos, bitstreamed to the receiver.

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

### Audio formats, trick play and lip sync (v1.2.0)

| Test | Result |
|---|---|
| Same P7 FEL clip with **Dolby TrueHD Atmos** as the only audio | ✅ Dolby Vision + Atmos on the receiver (raw HBR passthrough) |
| Fast-forward until the end, then play again | ✅ no freeze, no strips (before fix 7: freeze, then green strips until reboot) |
| Several quick seeks, including past the end | ✅ |
| Lip sync, P7 MKV with audio, from the start and after resume | ✅ correct (v1.0/v1.1: audio about 0.5 s off) |
| MKV started with audio exactly 297–312 s after power-on (tick counter wrap) | ✅ no lock (v1.0/v1.1: could hard-lock) |
| P7 single-stream TS with audio, P5 MKV, P8.1 MKV | ✅ unchanged |

### Seeking and chapter skips (v1.3.1)

Two full-length films: a P7 **MEL** UHD remux (36 chapters, Dolby Digital, FLAC and DTS-HD MA tracks) and a P7
**FEL** UHD remux (19 chapters). Skips were sent over the player's IP control and checked automatically: a skip
passes when the decoders keep running.

| Test | Before (v1.2.0 / v1.3.0) | v1.3.1 |
|---|---|---|
| MEL film, skip back a chapter | froze 4 of 4 times | 26 skips back (6 of them about 25 s), all fine |
| MEL film, skip forward | froze about 1 in 3 to 1 in 8 | all fine |
| Skips that landed while a base-layer picture was being decoded | first enhancement-layer picture lost in 19 of 20 | lost in 0 of 15 |
| FEL film, 30 skips (17 forward, 13 back) | occasional freezes | all fine, picture checked on screen |
| MEL film, 12 audio and subtitle track changes (DD, FLAC, DTS-HD MA) | — | all fine |
| Base- and enhancement-layer first picture after each skip | different whenever a picture was lost | identical in every skip |
| Persistent install, fresh boot: MEL film, 30 skips, 6 skips back after about 25 s, 6 audio changes, every subtitle track and "off" | — | all fine |
| Persistent install, fresh boot: FEL film, 30 skips, 4 skips back after about 25 s, 4 audio and 4 subtitle changes | — | all fine |
| MEL film, 7 jumps and 6 stop/resume cycles in the last five minutes | froze once (development build) | all fine |
| MEL and FEL film, played to the end | decoder crash on the last frame, every time (v1.2.0 too) | playback ends, back to the file list |
| Starting a film right after another one played to the end | nothing played until a restart | plays normally |

### UHD Blu-ray discs (v1.4.0)

Dolby Vision UHD Blu-ray ISOs played from a network share, with chapter skips both ways, fast-forward and rewind.
Kernel counters showed whether any hook ran.

| Test | v1.3.1 | v1.4.0 |
|---|---|---|
| Disc A (FEL), menu with looping Dolby Vision video | green strips in the menu | clean |
| Disc A, 11 chapter skips + 5 fast-forward/rewind rounds | no freeze this time, hooks ran at every skip | — |
| Disc B (the title of the original freeze report), chapter skips | froze (tester's report) | fine |
| Discs A, B, C, D: menus and chapter skips | multi-core reset ran about 11 times per decoder restart | no hook ran at all |
| P7 MEL MKV after the change: chapter skips and stop | — | seek fixes and stop hook still active, all fine |

### Installer and factory menu (v1.4.0)

| Test | Result |
|---|---|
| Installer, offline (busybox, fake `/mnt/ubi_boot`): RU program full zip, then switching to mkv-subtitles and factory-menu-only, then uninstall | each zip installs its parts and removes the others; uninstall removes everything |
| ... jb_overlay V3 player: full zip, then uninstall | Dolby Vision fix + factory menu installed and chained, subtitles skipped with the reason; uninstall restores the overlay's boot script |
| ... USA program without overlay: full zip / factory-menu-only zip | Dolby Vision fix only, the two others skipped with the reason / `FAILED`, nothing changed |
| ... unknown driver build, unsupported firmware, boot hook of another mod, launcher without the hook | Dolby Vision fix skipped / `FAILED` with the reason, nothing changed |
| ... check zip on a supported and an unsupported player | report and per-part result, nothing changed |
| Installer and check zip on the RU development player (into a scratch folder instead of `/mnt/ubi_boot`) | all three parts pass their checks and install |
| Factory menu shortcut on the RU development player: Gapless Playback + 0 0 0 0 | the Factory Page opens; on/off/on cycles of the patch |

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
/mnt/ubi_boot/oppo-dv-mkv/dvmkv.sh    waits for the player, applies the installed patches, marks the boot healthy
/mnt/ubi_boot/oppo-dv-mkv/dvhook.sh   liblp.so patch   (on|off|status)
/mnt/ubi_boot/oppo-dv-mkv/p7kel.sh    kernel patch     (on|off|status|check)
/mnt/ubi_boot/oppo-dv-mkv/subs.sh     subtitle patch (RU 65-0131 player program only)
/mnt/ubi_boot/oppo-dv-mkv/image_bdp83.bin  subtitle colour menu image, built at install time, swapped into /res at boot
/mnt/ubi_boot/oppo-dv-mkv/fpage.sh    factory menu shortcut (RU 65-0131 or jb_overlay V3 player program; on|off|status)
```

Before writing a single byte, every patcher verifies every patch site: the exact original instructions must be in
place, and for the kernel patch the driver fingerprint must match and the unused code area it occupies must match
the original by md5. On any mismatch
they do nothing. The installer refuses to overwrite an existing `/mnt/ubi_boot/bdpprog` that belongs to another
mod.

Details (addresses, hook points, data structures, debug switches): [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Building from source

```sh
nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm nixpkgs#zip -c ./mkrelease.sh   # or install zig, lld, llvm, zip yourself
```

`mkrelease.sh` compiles both patch blobs (`src/liblp`, `src/kernel`), generates the on-device patchers
(`mkinstall.py`, `mkkinst.py`) and builds the release zips into `dist/`. The builds are reproducible: the md5 of
each blob is printed. No firmware files are needed or included.

## Credits

- The authors of the free **RU 65-0131** UDP-203 jailbreak firmware, without which none of this would be possible.
- [dovi_tool](https://github.com/quietvoid/dovi_tool), [MKVToolNix](https://mkvtoolnix.download/),
  [FFmpeg](https://ffmpeg.org/), [tsMuxeR](https://github.com/justdan96/tsMuxer) and
  [Ghidra](https://ghidra-sre.org/), used to make the test files and to analyse the firmware.
- Reverse engineering, patches and testing: fandangos, together with Claude (Anthropic) as co-author.

## Changelog

- **v1.4.0: recommended update for everyone on v1.3.1.**
  - **Fixed freezes and green strips on Dolby Vision UHD Blu-ray discs and ISOs** (fix 10). The seek, end-of-file
    and stop hooks of v1.3.1 also ran during disc playback; they now act only on single-stream Dolby Vision (MKV and
    TS). Discs play exactly as on stock firmware again. MKV playback is unchanged from v1.3.1.
  - **New: factory menu shortcut.** Setup > Playback Setup, Gapless Playback highlighted, 0 0 0 0 opens Oppo's hidden
    Factory Page (see [Factory menu](#factory-menu) and its warnings). RU 65-0131 and jb_overlay V3 player programs.
  - **The installer checks each part on its own**, installs the parts that can be installed safely and skips the
    others. `oppo-dv-mkv-result.txt` on the stick says per part what was installed, or why not.
  - **Five download options:** full (Dolby Vision + subtitles + factory menu), mkv-subtitles (the old "full"),
    mkv-only, subtitles-only, factory-menu-only.
  - Added later: read-only **full dump** zip (`oppo-dv-mkv-full-dump.zip`), which replaces the driver dump. One dump
    has everything needed to port every part to another firmware, region or jb_overlay setup.

- **v1.3.1: recommended update for everyone.** (v1.3.0 was a test build for one USA-region tester and was not
  published.)
  - **No more freezes after chapter skips, seeking, or audio/subtitle track changes in P7 MKVs** (fix 8), especially
    with MEL files and when skipping back.
  - **P7 films now end normally.** At the very end of the file the enhancement-layer decoder crashed: the picture
    froze on the last frame and nothing played again until a restart (fix 9). Now the player returns to the file
    list.
  - **More driver builds:** the patcher measures where the `bdpdrv1` driver keeps its global data and moves the
    patch's data addresses to match. This covers the USA build (+0x90) and another build (+0x50), and any other build
    whose patched code is unchanged.
  - **jb_overlay** (themes, ssh) is supported: oppo-dv-mkv chains to it instead of refusing.
  - **Three download options:** full (Dolby Vision + subtitles), MKV fix only, subtitles only.
  - Updating over an older version works while its patch is active (the driver check recognises it).
  - Read-only **driver dump** zip, to help port the fix to other firmware builds.

- **v1.2.0: recommended update for everyone on v1.0/v1.1.**
  - Lip sync: the AV-sync controller now goes to the base-layer plane, so P7 MKV audio is in sync. It was about
    0.5 s off.
  - Fixed a rare hard lock when an MKV with audio was started 300–305 s after power-on (tick counter wrap).
  - Fixed freezes and lasting green strips after fast-forward or seeking in P7 MKVs (EL decoder reading the base
    layer's SPS).
  - Tested with Dolby TrueHD Atmos.

- **v1.1.0:** **better subtitles** (anti-aliased, outline width 2 with black, grey colours for HDR/DV, menu squares
  to match), on the RU 65-0131 player program. Wider compatibility for the Dolby Vision fix: The installer no longer requires the region-specific player program to be the
  RU 65-0131 one; it checks the files that are actually patched instead (`liblp.so` md5, plus an in-memory
  fingerprint of the `bdpdrv1` driver). Added a **check-only** zip that writes a compatibility report and changes
  nothing. The Dolby Vision patches themselves are unchanged from v1.0.0.
- **v1.0.0:** first release.

## License

[MIT](LICENSE). Provided **as is**, without warranty of any kind. See the disclaimer at the top.
