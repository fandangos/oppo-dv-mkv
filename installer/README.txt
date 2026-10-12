oppo-dv-mkv - Dolby Vision (profile 5, 7 FEL/MEL, 8) from MKV for the Oppo UDP-203 (RU 65-0131 jailbreak firmware)
https://github.com/fandangos/oppo-dv-mkv

!!! USE AT YOUR OWN RISK. This modifies how your player boots. The author(s) accept NO responsibility for
!!! any damage, bricked players, lost warranty or anything else. Read the full README on GitHub first.

REQUIREMENTS
  - Oppo UDP-203 running the free "RU 65-0131" jailbreak firmware (the installer checks this and refuses otherwise).
  - A FAT32 USB stick. No other USB storage plugged in while installing.
  - Display set to TV-led Dolby Vision (all testing was done in TV-led mode, NOT player-led / low latency).

INSTALL
  1. Copy the contents of this zip (the AutoScript folder and this file) to the ROOT of the USB stick.
  2. Power the player OFF, plug the stick into the REAR USB port, power the player ON.
     At boot the player runs AutoScript/install.sh from the stick (takes a second or two).
  3. Wait until the home menu has been up for about 30 seconds, power the player OFF and remove the stick.
  4. Optional: check oppo-dv-mkv.log in the root of the stick on a PC - it must contain a line starting with "INSTALLED".
  5. Power the player ON. The fix is now active at every boot.

UNINSTALL
  Use the oppo-dv-mkv-*-uninstall.zip release the same way (log ends with "UNINSTALLED").
  Emergency off switch: the boot wrapper disables itself after two unhealthy boots or a crash of the player
  shortly after start.
