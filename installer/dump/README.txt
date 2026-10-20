oppo-dv-mkv - full dump (READ-ONLY) for porting oppo-dv-mkv to your firmware
https://github.com/fandangos/oppo-dv-mkv

Use this if the oppo-dv-mkv check or installer says a part is not supported on your player (other region, other
firmware version, other jailbreak, jb_overlay with its own player program, ...) and you want to help add support.
One dump has everything needed for all parts (Dolby Vision MKV fix, subtitles, factory menu), with or without
jb_overlay. It is fine if oppo-dv-mkv or jb_overlay is installed; leave everything as it is.

What it copies to the USB stick:
  - the player program that is actually running and the libraries it uses (only those the developer does not have yet)
  - the bdpdrv1, bdpdrv and splitter video drivers, copied from memory
  - the boot setup (jailbreak launcher, /mnt/ubi_boot boot hook, jb_overlay scripts), kernel and firmware versions
  - the subtitle menu image and font, and a list of all system files with their checksums
It writes NOTHING to the player and installs nothing.
It does NOT collect personal data: no network settings, passwords or keys, no jb_overlay config.ini / autostart.sh /
rclone / ssh files, no Blu-ray storage (BUDA/APDA), no network share mounts.

!!! USE AT YOUR OWN RISK. The author(s) accept NO responsibility for any damage. Read the README on GitHub.

STEPS
  1. Copy the contents of this zip (the AutoScript folder and this file) to the ROOT of a FAT32 USB stick with at
     least 200 MB free. No other USB storage plugged in.
  2. Power the player OFF, plug the stick into the REAR USB port, power the player ON.
  3. Leave the player on the home menu for 5 minutes (the dump takes about 1 minute in the background; do not
     play anything meanwhile), then power the player OFF and remove the stick.
  4. On a PC, open oppo-dv-mkv-dump.log in the root of the stick: the last line must start with "DONE".
     If it is missing or says FAILED, run it once more (it overwrites the previous dump).
  5. Send the file oppo-dv-mkv-dump.tar.gz from the stick (usually 5 to 30 MB). If the DONE line says packing
     failed, zip the folder oppo-dv-mkv-dump together with oppo-dv-mkv-dump.log and send that instead.
     It contains Oppo's own program code: share it privately with the developer, not on a public forum.
  6. Delete the AutoScript folder from the stick, otherwise the dump runs again at every boot with the stick in.
