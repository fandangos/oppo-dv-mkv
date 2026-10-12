oppo-dv-mkv - driver dump (READ-ONLY) for porting to other firmware builds
https://github.com/fandangos/oppo-dv-mkv

Use this only if you were asked to: the oppo-dv-mkv check reported "module fingerprint mismatch" and you want to
help make the fix work on your firmware (for example a USA-region player).

It copies the player's bdpdrv1 video driver from memory to the USB stick, plus a short info file (kernel and
firmware versions, md5s of the player program and liblp.so, the loaded modules). It writes NOTHING to the player
and installs nothing. No personal data is collected.

!!! USE AT YOUR OWN RISK. The author(s) accept NO responsibility for any damage. Read the README on GitHub.

STEPS
  1. Copy the contents of this zip (the AutoScript folder and this file) to the ROOT of a FAT32 USB stick with at
     least 20 MB free. No other USB storage plugged in.
  2. Power the player OFF, plug the stick into the REAR USB port, power the player ON.
  3. Wait 5 minutes after the home menu appears (the copy takes about 30 seconds in the background), then power the player OFF and
     remove the stick.
  4. On a PC, open oppo-dv-mkv-dump.log in the root of the stick: the last line must start with "DONE".
     If it is missing or says FAILED, run it once more (it overwrites the previous dump).
  5. Zip the folder oppo-dv-mkv-dump together with oppo-dv-mkv-dump.log and share it (about 7 MB; it is Oppo's
     own driver code, so share it privately with the developer, not on a public forum).
  6. Delete the AutoScript folder from the stick, otherwise the dump runs again at every boot with the stick in.
