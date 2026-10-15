#!/bin/sh
# oppo-dv-mkv USB installer. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# Installs (or, if AutoScript/UNINSTALL exists, removes) the permanent Dolby Vision MKV fix.
# If AutoScript/CHECKONLY exists it only writes a compatibility report to the log and changes nothing.
#   /mnt/ubi_boot/bdpprog               boot wrapper (run by the jailbreak launcher instead of bdpprog.1)
#   /mnt/ubi_boot/bdpprog.prev          the jb_overlay boot script, if that mod was installed (the wrapper chains to it)
#   /mnt/ubi_boot/oppo-dv-mkv/          dvmkv.sh + the parts in this release: dvhook.sh, p7kel.sh (Dolby Vision MKV fix),
#                                       subs.sh, image_bdp83.bin (subtitles). RAM patches applied at every boot.
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
PREV=$U/bdpprog.prev
# parts of this release: decided by which files are on the stick
[ -f $S/oppo-dv-mkv/p7kel.sh ] && DV=1 || DV=; [ -f $S/oppo-dv-mkv/subs.sh ] && SUBS=1 || SUBS=
FILES="dvmkv.sh${DV:+ dvhook.sh p7kel.sh}${SUBS:+ subs.sh}"
SQUARES="09 11 18 19 20 21 22 23"
RU_PLAYER=49b649bdcffe8b611f1b7bbc0d9fa0b1   # RU 65-0131 player program (subtitle patches)
RESORIG=${OPPODV_RESORIG:-/mnt/rootfs_normal/res/image_bdp83.bin}
exec >>$L 2>&1
echo "=== oppo-dv-mkv $VERSION installer, $(date), uptime $(cut -d' ' -f1 /proc/uptime)s"
fail(){ echo "FAILED: $*"; [ -n "$WROTE" ] && echo "The boot wrapper was not (re)activated; the player keeps its previous behaviour." || echo "Nothing was changed."; sync; exit 1; }
m5(){ md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ours(){ grep -q "oppo-dv-mkv boot wrapper" $U/bdpprog 2>/dev/null; }
overlay(){ grep -q "jb_overlay" $U/bdpprog 2>/dev/null; }   # jb_overlay mod (themes, ssh): we chain to it
# the player program that is running now (the overlay runs its own copy, not /usr/local/bin/bdpprog.1)
running(){ [ -n "$OPPODV_RUNMD5" ] && { echo $OPPODV_RUNMD5; return; }; p=$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'); [ -n "$p" ] && m5 /proc/$p/exe; }

# --- supported firmware: Oppo UDP-203, jailbreak built on Oppo's v65 firmware ---
# liblp.so is identical in every regional v65 firmware. The bdpdrv1 video driver is verified in memory by
# p7kel.sh check (module address, original instructions at every hook, entry words, the driver's data offset measured
# from pointers in its code, kernel symbols).
LIBLP_MD5=e39b358c5b0948933f49fd3099f81114   # playback library (MKV hooks)
KCHECK=${OPPODV_KCHECK:-sh $S/oppo-dv-mkv/p7kel.sh check}
KDIAG=${OPPODV_KDIAG:-sh $S/oppo-dv-mkv/p7kel.sh diag}
if [ -e $S/CHECKONLY ]; then
  echo "--- compatibility report (nothing is installed or changed) ---"
  echo "uname:     $(uname -a)"
  echo "cmdline:   $(tr ' ' '\n' < /proc/cmdline | grep -E '^(BL_Ver|mem)=' | tr '\n' ' ')"
  echo "liblp.so:  $(m5 $LIBLP)  (needed $LIBLP_MD5)"
  echo "bdpdrv1:   $($KCHECK 2>&1 | tr '\n' ' ')"
  echo "bdpprog.1: $(m5 $PLAYER)  (region player program, informative)"
  echo "running:   $(running)  (player program in use; subtitles need $RU_PLAYER)"
  echo "launcher:  $(m5 $LAUNCHER), starts /mnt/ubi_boot/bdpprog: $(grep -q /mnt/ubi_boot/bdpprog $LAUNCHER 2>/dev/null && echo yes || echo NO)"
  echo "module:    $(grep '^bdpdrv1 ' $MODULES)"
  if [ -e $U/bdpprog ]; then
    if ours; then echo "boot hook: oppo-dv-mkv installed"; elif overlay; then echo "boot hook: jb_overlay mod (oppo-dv-mkv would start first, then hand over to it)"
    else echo "boot hook: /mnt/ubi_boot/bdpprog belongs to ANOTHER mod"; fi
  else echo "boot hook: free"; fi
  ok=yes; dv=yes; su=yes
  [ "$(m5 $LIBLP)" = $LIBLP_MD5 ] || ok=no
  grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || ok=no
  [ -e $U/bdpprog ] && ! ours && ! overlay && ok=no
  { grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES && $KCHECK >/dev/null 2>&1; } || dv=no
  [ $dv = no ] && [ -f $S/oppo-dv-mkv/p7kel.sh ] && grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES && $KDIAG 2>&1 | sed 's/^/driver:    /'   # details for porting
  [ "$(running)" = $RU_PLAYER ] || su=no
  if [ $ok = no ] || [ $dv$su = nono ]; then echo "VERDICT: NOT COMPATIBLE - the installer would refuse (see the lines above)."
  else echo "VERDICT: COMPATIBLE - Dolby Vision MKV fix: $dv, subtitle improvements: $su"; fi
  sync; exit 0
fi
[ -n "$DV$SUBS" ] || fail "no oppo-dv-mkv parts on the stick (unzip the whole release)"
[ "$(m5 $LIBLP)" = $LIBLP_MD5 ] || fail "liblp.so md5 $(m5 $LIBLP) - unsupported firmware (needs Oppo v65 base)"
grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || fail "launcher does not start /mnt/ubi_boot/bdpprog - this jailbreak is not supported"
if [ -n "$DV" ] && [ ! -e $S/UNINSTALL ]; then   # (uninstalling needs no driver check)
  grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES || fail "bdpdrv1 kernel module not at 0x7e8d3000 - unsupported firmware"
  k=$($KCHECK 2>&1) || fail "bdpdrv1 video driver check: $k - unsupported firmware${SUBS:+ (the subtitles-only zip may still work)}"
  echo "video driver: $k"
fi
[ -d $U ] && touch $U/.oppodv && rm -f $U/.oppodv || fail "$U is not writable"
echo "firmware OK (bdpprog.1 md5 $(m5 $PLAYER), running player program $(running))"

# --- uninstall ---
if [ -e $S/UNINSTALL ]; then
  if [ -e $U/bdpprog ] && ! ours; then fail "$U/bdpprog belongs to another mod; not touching it"; fi
  if [ -f $PREV ]; then   # give the boot hook back to the jb_overlay mod
    cp $PREV $U/bdpprog.tmp && chmod 755 $U/bdpprog.tmp && sync && mv $U/bdpprog.tmp $U/bdpprog && sync && rm -f $PREV \
      || fail "restoring the jb_overlay boot script"
    echo "  jb_overlay boot script restored"
  else rm -f $U/bdpprog; fi
  sync; rm -rf $D; sync
  echo "UNINSTALLED. Remove the USB stick and power-cycle the player: it is back to its previous behaviour."
  exit 0
fi

# --- install / update ---
CHAIN=
if [ -e $U/bdpprog ] && ! ours; then
  overlay || fail "$U/bdpprog already exists and belongs to another mod (custom firmware mods?). Not overwriting it."
  CHAIN=1; echo "jb_overlay mod found: it keeps working, oppo-dv-mkv starts first and then hands over to it"
fi
[ -z "$CHAIN" ] && ours && [ -f $PREV ] && CHAIN=1   # update of an install that already chains
if [ -n "$SUBS" ] && { [ -n "$CHAIN" ] || [ "$(running)" != $RU_PLAYER ]; }; then
  [ -n "$CHAIN" ] && why="the jb_overlay mod uses its own player program and theme" || why="this is not the RU 65-0131 player program"
  [ -z "$DV" ] && fail "subtitle improvements cannot be installed: $why"
  SUBS=; FILES="dvmkv.sh dvhook.sh p7kel.sh"; echo "  subtitle improvements skipped: $why (Dolby Vision fix unaffected)"
fi
for f in $FILES bdpprog ${SUBS:+$(for q in $SQUARES; do echo sq$q.png; done)}; do
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
[ -z "$DV" ] && rm -f $D/dvhook.sh $D/p7kel.sh && echo "  Dolby Vision MKV fix not part of this release: removed if it was installed"
if [ -n "$SUBS" ]; then
  # subtitle menu squares: rebuild image_bdp83.bin from the player's own file + our 8 colour squares
  if [ "$(m5 $RESORIG)" != 463cec5560b62e5c60fe584b6d14e20b ]; then echo "  subtitle menu image: unexpected original file (skipped)"
  elif [ "$(m5 $D/image_bdp83.bin)" = 44bedb87bacfc5217ec22cffd2b18295 ]; then echo "  $D/image_bdp83.bin up to date"
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
fi
rm -f $D/disable $D/bootcount
if [ -n "$CHAIN" ] && ! ours; then   # keep the jb_overlay boot script; our wrapper runs it instead of the player
  put $U/bdpprog $PREV || fail "saving the jb_overlay boot script"
fi
put $S/oppo-dv-mkv/bdpprog $U/bdpprog || fail "writing $U/bdpprog"   # wrapper last: only active once all files are in
sync
echo "INSTALLED $VERSION ($([ -n "$DV" ] && echo "Dolby Vision MKV fix")$([ -n "$DV$SUBS" ] && [ -n "$DV" ] && [ -n "$SUBS" ] && echo " + ")$([ -n "$SUBS" ] && echo "subtitle improvements")$([ -n "$CHAIN" ] && echo ", chained to jb_overlay")). Remove the USB stick and power-cycle the player."
echo "After the restart it is active at every boot; its log is $D/dvmkv.log on the player."
