#!/bin/sh
# oppo-dv-mkv driver dump. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# READ-ONLY: copies the loaded bdpdrv1 video driver from RAM to the stick so it can be compared with the supported
# one (porting to other firmware builds). Nothing on the player is written or changed.
# Output in the root of the stick: oppo-dv-mkv-dump.log and the folder oppo-dv-mkv-dump/
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:$PATH
STICK=${OPPODV_STICK:-/mnt/sda1}
MEM=${OPPODV_MEM:-/dev/mem}
MODULES=${OPPODV_MODULES:-/proc/modules}
KSYMS=${OPPODV_KSYMS:-/proc/kallsyms}
O=$STICK/oppo-dv-mkv-dump
L=$STICK/oppo-dv-mkv-dump.log
if [ "$1" != run ]; then   # return to the player at once, dump in the background
  sh $0 run </dev/null >>$L 2>&1 &
  exit 0
fi
echo "=== oppo-dv-mkv driver dump, $(date), uptime $(cut -d' ' -f1 /proc/uptime)s"
fail(){ echo "FAILED: $*"; sync; exit 1; }
n=0; until grep -q "^bdpdrv1 " $MODULES; do n=$((n+1)); [ $n -gt 60 ] && fail "bdpdrv1 is not loaded"; sleep 1; done
SIZE=$(grep "^bdpdrv1 " $MODULES | awk '{print $2}')
BASE=$(grep "^bdpdrv1 " $MODULES | awk '{for (i = 3; i <= NF; i++) if ($i ~ /^0x/) {print $i; exit}}')
case "$BASE" in 0x*) ;; *) fail "cannot parse the bdpdrv1 line: $(grep '^bdpdrv1 ' $MODULES)";; esac
PAGES=$(( (SIZE + 4095) / 4096 ))
echo "bdpdrv1 base $BASE size $SIZE ($PAGES pages)"
FREE=$(df -k $STICK 2>/dev/null | awk 'NR>1 && $4 ~ /^[0-9]+$/ {print $4; exit}')
[ -n "$FREE" ] && [ "$FREE" -lt $(( PAGES * 4 + 4096 )) ] && fail "not enough free space on the stick (${FREE} KB)"
rm -rf $O; mkdir -p $O || fail "cannot create $O on the stick"

# --- system info (no personal data: versions, md5s and the driver's own symbols only) ---
{
  echo "uname:    $(uname -a)"
  echo "cmdline:  $(tr ' ' '\n' < /proc/cmdline | grep -E '^(BL_Ver|mem)=' | tr '\n' ' ')"
  for f in /usr/local/bin/bdpprog.1 /usr/local/lib/liblp.so /usr/local/bin/bdpprog /mnt/ubi_boot/bdpprog; do
    [ -e $f ] && echo "md5:      $(md5sum $f)"
  done
  P=$(ps | grep bdpprog.1 | grep -v grep | awk '{print $1; exit}')
  [ -n "$P" ] && echo "running:  $(tr '\0' ' ' < /proc/$P/cmdline)  md5 $(md5sum /proc/$P/exe | cut -d' ' -f1)"
  echo "modules:"; cat $MODULES
} > $O/info.txt 2>&1
grep "\[bdpdrv1\]" $KSYMS > $O/bdpdrv1.syms 2>/dev/null
grep -E " (printk|jiffies)$" $KSYMS >> $O/info.txt 2>/dev/null

# --- driver memory: virtual -> physical through the kernel page tables (swapper pgd at PA 0x4000), page by page ---
u32(){ dd if=$MEM bs=4 skip=$(( $1 / 4 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
B=$(( BASE )); i=0; miss=0
: > $O/bdpdrv1.bin
while [ $i -lt $PAGES ]; do
  va=$(( B + i * 4096 ))
  l1=$(u32 $(( 0x4000 + (va >> 20) * 4 )))
  case $(( l1 & 3 )) in
    2) pa=$(( (l1 & 0xfff00000) | (va & 0xff000) ));;
    1) pte=$(u32 $(( (l1 & 0xfffffc00) + ((va >> 12) & 0xff) * 4 )))
       [ $(( pte & 2 )) = 2 ] && pa=$(( pte & 0xfffff000 )) || pa=;;
    *) pa=;;
  esac
  if [ -n "$pa" ]; then dd if=$MEM bs=4096 skip=$(( pa / 4096 )) count=1 2>/dev/null >> $O/bdpdrv1.bin
  else dd if=/dev/zero bs=4096 count=1 2>/dev/null >> $O/bdpdrv1.bin; miss=$((miss+1)); fi
  i=$((i+1))
  [ $(( i % 256 )) = 0 ] && { echo "  $i/$PAGES pages"; sync; }
done
sync
GOT=$(( $(wc -c < $O/bdpdrv1.bin) / 4096 ))
[ $GOT = $PAGES ] || fail "dump has $GOT of $PAGES pages"
echo "pages not mapped (zero-filled): $miss"
(cd $O && md5sum bdpdrv1.bin bdpdrv1.syms info.txt > MD5SUMS)
sync
echo "DONE $(cut -d' ' -f1 $O/MD5SUMS | head -1). Power the player off, remove the stick and zip the oppo-dv-mkv-dump folder + this log."
sync
