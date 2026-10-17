#!/bin/sh
# oppo-dv-mkv USB installer. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# Installs (or, if AutoScript/UNINSTALL exists, removes) the parts of this release that are on the stick:
#   Dolby Vision MKV fix, subtitle improvements, factory menu shortcut.
# Each part is checked on its own; a part that cannot be installed safely on this player is skipped (and removed if an
# older copy was installed). Why, per part: oppo-dv-mkv-result.txt in the root of the USB stick.
# If AutoScript/CHECKONLY exists it only writes a compatibility report to the log and the result file, changing nothing.
#   /mnt/ubi_boot/bdpprog               boot wrapper (run by the jailbreak launcher instead of bdpprog.1)
#   /mnt/ubi_boot/bdpprog.prev          the jb_overlay boot script, if that mod was installed (the wrapper chains to it)
#   /mnt/ubi_boot/oppo-dv-mkv/          dvmkv.sh + the installed parts: dvhook.sh, p7kel.sh (Dolby Vision MKV fix),
#                                       subs.sh, image_bdp83.bin (subtitles), fpage.sh (factory menu). RAM patches
#                                       applied at every boot.
# Nothing in the firmware itself is modified. Log: oppo-dv-mkv.log in the root of the USB stick.
VERSION=@VERSION@
S=${OPPODV_SRC:-/mnt/sda1/AutoScript}                 # this folder on the stick
L=${OPPODV_LOG:-/mnt/sda1/oppo-dv-mkv.log}
R=${OPPODV_RESULT:-/mnt/sda1/oppo-dv-mkv-result.txt}  # short per-part result, rewritten at every run
U=${OPPODV_UBI:-/mnt/ubi_boot}                        # persistent partition used by the jailbreak launcher
LIBLP=${OPPODV_LIBLP:-/usr/local/lib/liblp.so}
PLAYER=${OPPODV_PLAYER:-/usr/local/bin/bdpprog.1}
LAUNCHER=${OPPODV_LAUNCHER:-/usr/local/bin/bdpprog}
MODULES=${OPPODV_MODULES:-/proc/modules}
D=$U/oppo-dv-mkv
PREV=$U/bdpprog.prev
# parts of this release: decided by which files are on the stick
[ -f $S/oppo-dv-mkv/p7kel.sh ] && DV=1 || DV=; [ -f $S/oppo-dv-mkv/subs.sh ] && SUBS=1 || SUBS=
[ -f $S/oppo-dv-mkv/fpage.sh ] && MENU=1 || MENU=
IN_DV=$DV; IN_SUBS=$SUBS; IN_MENU=$MENU   # what this zip contains (DV/SUBS/MENU become what gets installed)
SQUARES="09 11 18 19 20 21 22 23"
RU_PLAYER=49b649bdcffe8b611f1b7bbc0d9fa0b1   # RU 65-0131 player program (subtitle patches, factory menu)
MENU_PLAYERS="$RU_PLAYER 82e04bcfc60a53892668ea325311b3a6"   # factory menu: RU 65-0131, and the jb_overlay V3 copy of it
RESORIG=${OPPODV_RESORIG:-/mnt/rootfs_normal/res/image_bdp83.bin}
exec >>$L 2>&1
echo "=== oppo-dv-mkv $VERSION installer, $(date), uptime $(cut -d' ' -f1 /proc/uptime)s"
# result file: one line per part, written at the end of every run (also on failure). *_R: the part's result
DV_R=; SUBS_R=; MENU_R=; HEAD=
line(){ [ -n "$1" ] && echo "${2:-not installed}" || echo "not in this zip"; }
result(){
  { echo "oppo-dv-mkv $VERSION - $HEAD"
    echo "Dolby Vision MKV fix:   $(line "$IN_DV" "$DV_R")"
    echo "Subtitle improvements:  $(line "$IN_SUBS" "$SUBS_R")"
    echo "Factory menu shortcut:  $(line "$IN_MENU" "$MENU_R")"
    echo "Details: oppo-dv-mkv.log (same folder)."; } > $R; sync; }
fail(){ echo "FAILED: $*"; [ -n "$WROTE" ] && echo "The boot wrapper was not (re)activated; the player keeps its previous behaviour." || echo "Nothing was changed."
  HEAD="FAILED: $*"; [ -n "$WROTE" ] || HEAD="${HEAD%.}. Nothing was changed."
  [ "$DV_R" = installed ] && DV_R=; [ "$SUBS_R" = installed ] && SUBS_R=; [ "$MENU_R" = installed ] && MENU_R=
  result; exit 1; }
m5(){ md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ours(){ grep -q "oppo-dv-mkv boot wrapper" $U/bdpprog 2>/dev/null; }
overlay(){ grep -q "jb_overlay" $U/bdpprog 2>/dev/null; }   # jb_overlay mod (themes, ssh): we chain to it
# the player program that is running now (the overlay runs its own copy, not /usr/local/bin/bdpprog.1)
running(){ [ -n "$OPPODV_RUNMD5" ] && { echo $OPPODV_RUNMD5; return; }; p=$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'); [ -n "$p" ] && m5 /proc/$p/exe; }

# --- supported firmware: Oppo UDP-203, jailbreak built on Oppo's v65 firmware ---
# liblp.so is identical in every regional v65 firmware. The bdpdrv1 video driver is verified in memory by
# p7kel.sh check (module address, original instructions at every hook, entry words, the driver's data offset measured
# from pointers in its code, kernel symbols). Subtitles and the factory menu patch the player program, so they need
# the exact program they were made for (md5 of the running one).
LIBLP_MD5=e39b358c5b0948933f49fd3099f81114   # playback library (MKV hooks)
KCHECK=${OPPODV_KCHECK:-sh $S/oppo-dv-mkv/p7kel.sh check}
KDIAG=${OPPODV_KDIAG:-sh $S/oppo-dv-mkv/p7kel.sh diag}
RUN=$(running)
# boot hook: free, ours, or the jb_overlay mod (chained); anything else blocks every part
CHAIN=; HOOK=
if [ -e $U/bdpprog ] && ! ours; then
  if overlay; then CHAIN=1; else HOOK="$U/bdpprog already exists and belongs to another mod (custom firmware mods?). Not overwriting it."; fi
fi
ours && [ -f $PREV ] && CHAIN=1   # an install that already chains
# per-part checks: an empty *_WHY means the part can be installed safely
DV_WHY=; SUBS_WHY=; MENU_WHY=; DVK=
if [ "$(m5 $LIBLP)" != $LIBLP_MD5 ]; then
  DV_WHY="liblp.so md5 $(m5 $LIBLP) is not the Oppo v65 one ($LIBLP_MD5) - unsupported firmware"; SUBS_WHY=$DV_WHY
elif ! grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES; then
  DV_WHY="bdpdrv1 kernel module not at 0x7e8d3000 - unsupported firmware"
elif ! DVK=$($KCHECK 2>&1); then
  DV_WHY="video driver check: $(echo $DVK) (a driver dump helps to add support for it, see the README)"
fi
if [ -z "$SUBS_WHY" ]; then
  if [ -n "$CHAIN" ]; then SUBS_WHY="the jb_overlay mod uses its own player program and theme"
  elif [ "$RUN" != $RU_PLAYER ]; then SUBS_WHY="the running player program (md5 ${RUN:-unknown}) is not the RU 65-0131 one"; fi
fi
case " $MENU_PLAYERS " in *" $RUN "*) [ -n "$RUN" ] || MENU_WHY="player program not found";;
  *) MENU_WHY="the running player program (md5 ${RUN:-unknown}) is not a supported one (RU 65-0131, or its jb_overlay V3 copy)";; esac

if [ -e $S/CHECKONLY ]; then
  echo "--- compatibility report (nothing is installed or changed) ---"
  echo "uname:     $(uname -a)"
  echo "cmdline:   $(tr ' ' '\n' < /proc/cmdline | grep -E '^(BL_Ver|mem)=' | tr '\n' ' ')"
  echo "liblp.so:  $(m5 $LIBLP)  (needed $LIBLP_MD5)"
  echo "bdpdrv1:   $($KCHECK 2>&1 | tr '\n' ' ')"
  echo "bdpprog.1: $(m5 $PLAYER)  (region player program, informative)"
  echo "running:   $RUN  (player program in use; subtitles need $RU_PLAYER, the factory menu one of: $MENU_PLAYERS)"
  echo "launcher:  $(m5 $LAUNCHER), starts /mnt/ubi_boot/bdpprog: $(grep -q /mnt/ubi_boot/bdpprog $LAUNCHER 2>/dev/null && echo yes || echo NO)"
  echo "module:    $(grep '^bdpdrv1 ' $MODULES)"
  if [ -e $U/bdpprog ]; then
    if ours; then echo "boot hook: oppo-dv-mkv installed"; elif overlay; then echo "boot hook: jb_overlay mod (oppo-dv-mkv would start first, then hand over to it)"
    else echo "boot hook: /mnt/ubi_boot/bdpprog belongs to ANOTHER mod"; fi
  else echo "boot hook: free"; fi
  [ -n "$DV_WHY" ] && [ -f $S/oppo-dv-mkv/p7kel.sh ] && grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES && $KDIAG 2>&1 | sed 's/^/driver:    /'   # details for porting
  BASE=
  grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || BASE="the launcher does not start /mnt/ubi_boot/bdpprog - this jailbreak is not supported"
  [ -n "$HOOK" ] && BASE=$HOOK
  yn(){ [ -n "$BASE" ] && { echo "no - $BASE"; return; }; [ -z "$1" ] && echo yes || echo "no - $1"; }
  DV_R=$(yn "$DV_WHY"); SUBS_R=$(yn "$SUBS_WHY"); MENU_R=$(yn "$MENU_WHY")
  echo "Dolby Vision MKV fix:   $DV_R"; echo "Subtitle improvements:  $SUBS_R"; echo "Factory menu shortcut:  $MENU_R"
  if [ -n "$BASE" ] || [ -n "$DV_WHY" -a -n "$SUBS_WHY" -a -n "$MENU_WHY" ]; then echo "VERDICT: NOT COMPATIBLE - the installer would refuse (see the lines above)."
    HEAD="compatibility check: NOT COMPATIBLE, the installer would install nothing (nothing was changed)"
  else echo "VERDICT: COMPATIBLE - the parts marked yes can be installed"
    HEAD="compatibility check (nothing was changed): the parts marked yes can be installed"; fi
  result; exit 0
fi

[ -n "$DV$SUBS$MENU" ] || fail "no oppo-dv-mkv parts on the stick (unzip the whole release)"
grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || fail "launcher does not start /mnt/ubi_boot/bdpprog - this jailbreak is not supported"
[ -d $U ] && touch $U/.oppodv && rm -f $U/.oppodv || fail "$U is not writable"

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
  HEAD="UNINSTALLED. Power-cycle the player: it is back to its previous behaviour."
  DV_R="removed"; SUBS_R="removed"; MENU_R="removed"; result
  exit 0
fi

# --- install / update: the parts of this zip that passed their checks ---
[ -n "$HOOK" ] && fail "$HOOK"
[ -n "$CHAIN" ] && ! ours && echo "jb_overlay mod found: it keeps working, oppo-dv-mkv starts first and then hands over to it"
echo "firmware: bdpprog.1 md5 $(m5 $PLAYER), running player program ${RUN:-unknown}"
[ -n "$DV" ] && [ -z "$DV_WHY" ] && echo "video driver: $DVK"
for p in DV SUBS MENU; do
  eval "on=\$$p; why=\$${p}_WHY"
  [ -n "$on" ] || continue
  case $p in DV) n="Dolby Vision MKV fix";; SUBS) n="subtitle improvements";; MENU) n="factory menu shortcut";; esac
  if [ -n "$why" ]; then echo "  $n skipped: $why"; eval "$p=; ${p}_R=\"NOT installed - \$why\""
  else eval "${p}_R=installed"; fi
done
[ -n "$DV$SUBS$MENU" ] || fail "none of the parts in this zip can be installed safely on this player"
FILES="dvmkv.sh${DV:+ dvhook.sh p7kel.sh}${SUBS:+ subs.sh}${MENU:+ fpage.sh}"
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
[ -z "$DV" ] && [ -e $D/p7kel.sh ] && rm -f $D/dvhook.sh $D/p7kel.sh && echo "  Dolby Vision MKV fix not installed now: older copy removed"
[ -z "$MENU" ] && [ -e $D/fpage.sh ] && rm -f $D/fpage.sh && echo "  factory menu shortcut not installed now: older copy removed"
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
elif [ -e $D/subs.sh ] || [ -e $D/image_bdp83.bin ]; then
  rm -f $D/subs.sh $D/image_bdp83.bin; echo "  subtitle improvements not installed now: older copy removed"
fi
rm -f $D/disable $D/bootcount
if [ -n "$CHAIN" ] && ! ours; then   # keep the jb_overlay boot script; our wrapper runs it instead of the player
  put $U/bdpprog $PREV || fail "saving the jb_overlay boot script"
fi
put $S/oppo-dv-mkv/bdpprog $U/bdpprog || fail "writing $U/bdpprog"   # wrapper last: only active once all files are in
sync
WHAT=; [ -n "$DV" ] && WHAT="Dolby Vision MKV fix"; [ -n "$SUBS" ] && WHAT="${WHAT:+$WHAT + }subtitle improvements"
[ -n "$MENU" ] && WHAT="${WHAT:+$WHAT + }factory menu shortcut"
SKIP=; case "$DV_R$SUBS_R$MENU_R" in *NOT*) SKIP=1;; esac
echo "INSTALLED $VERSION ($WHAT$([ -n "$CHAIN" ] && echo ", chained to jb_overlay"))$([ -n "$SKIP" ] && echo "; some parts were skipped, see oppo-dv-mkv-result.txt"). Remove the USB stick and power-cycle the player."
echo "After the restart it is active at every boot; its log is $D/dvmkv.log on the player."
HEAD="INSTALLED. Remove the USB stick and power-cycle the player."; result
