#!/bin/sh
# oppo-dv-mkv USB installer. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# Installs (or, if AutoScript/UNINSTALL exists, removes) the permanent Dolby Vision MKV fix:
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
FILES="dvmkv.sh dvhook.sh p7kel.sh"
exec >>$L 2>&1
echo "=== oppo-dv-mkv $VERSION installer, $(date), uptime $(cut -d' ' -f1 /proc/uptime)s"
fail(){ echo "FAILED: $*"; [ -n "$WROTE" ] && echo "The boot wrapper was not (re)activated; the player keeps its previous behaviour." || echo "Nothing was changed."; sync; exit 1; }
m5(){ md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
ours(){ grep -q "oppo-dv-mkv boot wrapper" $U/bdpprog 2>/dev/null; }

# --- supported firmware only: Oppo UDP-203 with the RU 65-0131 jailbreak ---
[ "$(m5 $LIBLP)" = e39b358c5b0948933f49fd3099f81114 ] || fail "liblp.so md5 $(m5 $LIBLP) - unsupported firmware"
[ "$(m5 $PLAYER)" = 49b649bdcffe8b611f1b7bbc0d9fa0b1 ] || fail "bdpprog.1 md5 $(m5 $PLAYER) - unsupported firmware"
grep -q "/mnt/ubi_boot/bdpprog" $LAUNCHER 2>/dev/null || fail "launcher does not start /mnt/ubi_boot/bdpprog - unsupported firmware"
grep -q "^bdpdrv1 .* 0x7e8d3000 " $MODULES || fail "bdpdrv1 kernel module not at 0x7e8d3000 - unsupported firmware"
[ -d $U ] && touch $U/.oppodv && rm -f $U/.oppodv || fail "$U is not writable"
echo "firmware OK"

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
for f in $FILES bdpprog; do
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
rm -f $D/disable $D/bootcount
put $S/oppo-dv-mkv/bdpprog $U/bdpprog || fail "writing $U/bdpprog"   # wrapper last: only active once all files are in
sync
echo "INSTALLED $VERSION. Remove the USB stick and power-cycle the player."
echo "After the restart the fix is active at every boot; its log is $D/dvmkv.log on the player."
