#!/bin/sh
# oppo-dv-mkv USB installer. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# Installs (or, if AutoScript/UNINSTALL exists, removes) the permanent Dolby Vision MKV fix.
# If AutoScript/CHECKONLY exists it only writes a compatibility report to the log and changes nothing.
#   /mnt/ubi_boot/bdpprog               boot wrapper (run by the jailbreak launcher instead of bdpprog.1)
#   /mnt/ubi_boot/oppo-dv-mkv/          dvmkv.sh, dvhook.sh, p7kel.sh (RAM patches applied at every boot)
# Nothing in the firmware itself is modified. Log: oppo-dv-mkv.log in the root of the USB stick.
VERSION=@VERSION@
S=${OPPODV_SRC:-/mnt/sda1/AutoScript}                 # this folder on the stick
L=${OPPODV_LOG:-/mnt/sda1/oppo-dv-mkv.log}
U=${OPPODV_UBI:-/mnt/ubi_boot}                        # persistent partition used by the jailbreak launcher
LIBLP=${OPPODV_LIBLP:-/usr/local/lib/liblp.so}
PLAYER=${OPPODV_PLAYER:-/usr/local/bin/bdpprog.1}
LAUNCHER=${OPPODV_LAUNCHER:-/usr/local/bin/bdpprog}
MODULES=${OPPODV_MODULES:-/proc/modules}
D=$U/oppo-dv-mkv
FILES="dvmkv.sh dvhook.sh p7kel.sh subs.sh"
SQUARES="09 11 18 19 20 21 22 23"
RESORIG=${OPPODV_RESORIG:-/mnt/rootfs_normal/res/image_bdp83.bin}
exec >>$L 2>&1
echo "=== oppo-dv-mkv $VERSION installer, $(date), uptime $(cut -d' ' -f1 /proc/uptime)s"
fail(){ echo "FAILED: $*"; [ -n "$WROTE" ] && echo "The boot wrapper was not (re)activated; the player keeps its previous behaviour." || echo "Nothing was changed."; sync; exit 1; }
m5(){ md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ours(){ grep -q "oppo-dv-mkv boot wrapper" $U/bdpprog 2>/dev/null; }

# --- supported firmware: Oppo UDP-203, jailbreak built on Oppo's v65 firmware ---
# liblp.so is identical in every regional v65 firmware. The bdpdrv1 video driver is verified in memory by
# p7kel.sh check (module address, original instructions at every hook, entry words, table pointers, kernel symbols).
LIBLP_MD5=e39b358c5b0948933f49fd3099f81114   # playback library (MKV hooks)
KCHECK=${OPPODV_KCHECK:-sh $S/oppo-dv-mkv/p7kel.sh check}
if [ -e $S/CHECKONLY ]; then
  echo "--- compatibility report (nothing is installed or changed) ---"
  echo "uname:     $(uname -a)"
  echo "cmdline:   $(tr ' ' '\n' < /proc/cmdline | grep -E '^(BL_Ver|mem)=' | tr '\n' ' ')"
  echo "liblp.so:  $(m5 $LIBLP)  (needed $LIBLP_MD5)"
  echo "bdpdrv1:   $($KCHECK 2>&1 | tr '\n' ' ')"
  echo "bdpprog.1: $(m5 $PLAYER)  (region player program, informative)"
  echo "launcher:  $(m5 $LAUNCHER), starts /mnt/ubi_boot/bdpprog: $(grep -q /mnt/ubi_boot/bdpprog $LAUNCHER 2>/dev/null && echo yes || echo NO)"
  echo "module:    $(grep '^bdpdrv1 ' $MODULES)"
  if [ -e $U/bdpprog ]; then ours && echo "boot hook: oppo-dv-mkv installed" || echo "boot hook: /mnt/ubi_boot/bdpprog belongs to ANOTHER mod"; else echo "boot hook: free"; fi
  ok=yes
  [ "$(m5 $LIBLP)" = $LIBLP_MD5 ] || ok=no; $KCHECK >/dev/null 2>&1 || ok=no
  grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || ok=no; grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES || ok=no
  [ -e $U/bdpprog ] && ! ours && ok=no
  [ $ok = yes ] && echo "VERDICT: COMPATIBLE - the installer would install." || echo "VERDICT: NOT COMPATIBLE - the installer would refuse (see the lines above)."
  sync; exit 0
fi
[ "$(m5 $LIBLP)" = $LIBLP_MD5 ] || fail "liblp.so md5 $(m5 $LIBLP) - unsupported firmware (needs Oppo v65 base)"
grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || fail "launcher does not start /mnt/ubi_boot/bdpprog - this jailbreak is not supported"
grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES || fail "bdpdrv1 kernel module not at 0x7e8d3000 - unsupported firmware"
k=$($KCHECK 2>&1) || fail "bdpdrv1 video driver check: $k - unsupported firmware"
[ -d $U ] && touch $U/.oppodv && rm -f $U/.oppodv || fail "$U is not writable"
echo "firmware OK (bdpprog.1 md5 $(m5 $PLAYER))"

# --- uninstall ---
if [ -e $S/UNINSTALL ]; then
  if [ -e $U/bdpprog ] && ! ours; then fail "$U/bdpprog belongs to another mod; not touching it"; fi
  rm -f $U/bdpprog; sync
  rm -rf $D; sync
  echo "UNINSTALLED. Remove the USB stick and power-cycle the player: it is back to the stock jailbreak behaviour."
  exit 0
fi

# --- install / update ---
[ -e $U/bdpprog ] && ! ours && fail "$U/bdpprog already exists and belongs to another mod (custom firmware mods?). Not overwriting it."
for f in $FILES bdpprog $(for q in $SQUARES; do echo sq$q.png; done); do
  [ -f $S/oppo-dv-mkv/$f ] || fail "missing $f on the stick (unzip the whole release)"
  grep -q " $f\$" $S/oppo-dv-mkv/MD5SUMS && [ "$(m5 $S/oppo-dv-mkv/$f)" = "$(grep " $f\$" $S/oppo-dv-mkv/MD5SUMS | cut -d' ' -f1)" ] \
    || fail "$f on the stick is corrupt (md5 mismatch) - re-copy the release"
done
WROTE=1; mkdir -p $D || fail "cannot create $D"
put(){  # atomic copy: $1 source, $2 destination
  [ "$(m5 $1)" = "$(m5 $2)" ] && { echo "  $2 up to date"; return 0; }
  cp $1 $2.tmp && chmod 755 $2.tmp && sync && [ "$(m5 $2.tmp)" = "$(m5 $1)" ] && mv $2.tmp $2 && sync || return 1
  echo "  $2 installed"
}
for f in $FILES; do put $S/oppo-dv-mkv/$f $D/$f || fail "writing $D/$f"; done
# subtitle menu squares: rebuild image_bdp83.bin from the player's own file + our 8 colour squares (RU player only)
if [ "$(m5 $PLAYER)" = 49b649bdcffe8b611f1b7bbc0d9fa0b1 ] && [ "$(m5 $RESORIG)" = 463cec5560b62e5c60fe584b6d14e20b ]; then
  if [ "$(m5 $D/image_bdp83.bin)" = 44bedb87bacfc5217ec22cffd2b18295 ]; then echo "  $D/image_bdp83.bin up to date"
  else
    I=$D/image_bdp83.bin.tmp; cp $RESORIG $I || fail "copying image_bdp83.bin"
    for e in 09:4516:865358:2837:113 11:4556:871032:2837:113 18:4696:890888:2838:113 19:4716:893726:2838:113 \
             20:4736:896564:2838:113 21:4756:899402:2837:112 22:4776:902239:2838:113 23:4796:905077:2838:113; do
      IFS=: read q tab off old new <<EOT
$e
EOT
      dd if=$S/oppo-dv-mkv/sq$q.png of=$I bs=1 seek=$off conv=notrunc 2>/dev/null
      dd if=/dev/zero of=$I bs=1 seek=$((off + new)) count=$((old - new)) conv=notrunc 2>/dev/null
      printf "\\$(printf %o $new)\\000\\000\\000" | dd of=$I bs=1 seek=$tab conv=notrunc 2>/dev/null
    done
    sync; [ "$(m5 $I)" = 44bedb87bacfc5217ec22cffd2b18295 ] && mv $I $D/image_bdp83.bin && sync \
      && echo "  $D/image_bdp83.bin built" || { rm -f $I; echo "  subtitle menu image could not be built (skipped)"; }
  fi
else
  rm -f $D/subs.sh $D/image_bdp83.bin
  echo "  not the RU 65-0131 player program: subtitle improvements skipped (Dolby Vision fix unaffected)"
fi
rm -f $D/disable $D/bootcount
put $S/oppo-dv-mkv/bdpprog $U/bdpprog || fail "writing $U/bdpprog"   # wrapper last: only active once all files are in
sync
echo "INSTALLED $VERSION. Remove the USB stick and power-cycle the player."
echo "After the restart the fix is active at every boot; its log is $D/dvmkv.log on the player."
