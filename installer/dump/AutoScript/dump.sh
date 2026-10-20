#!/bin/sh
# oppo-dv-mkv full dump. Run by the player at boot through AutoScript/AutoScript.TSS (USB stick, rear port).
# READ-ONLY: nothing on the player is written or changed; everything goes to the stick.
# It collects what is needed to port oppo-dv-mkv (Dolby Vision MKV fix, subtitles, factory menu) to any firmware
# build, jailbreak or jb_overlay setup, without assuming which one runs:
#  - the running player program (found by the liblp library it maps, wherever it runs from) and the libraries it maps
#  - the bdpdrv1, bdpdrv and splitter kernel modules copied from RAM, with their symbols
#  - the boot chain (launcher, /mnt/ubi_boot hook, jb_overlay scripts), kernel and firmware versions
#  - the subtitle resources (image_bdp83.bin, font.bin), also the jb_overlay theme copy when it is in use
#  - a list with md5s of every file of the system partition; unknown programs, libraries and modules are copied
# A file whose md5 is in known.md5 (already held by the developer) is listed but not copied.
# Never collected: network settings, passwords, keys, the jb_overlay config.ini / autostart.sh / rclone / ssh files,
# BD-J storage (BUDA, APDA), network share mounts, process command lines other than the player's.
# Output on the stick: oppo-dv-mkv-dump.tar.gz (the file to send), the folder oppo-dv-mkv-dump/, oppo-dv-mkv-dump.log
# Optional files next to this script: FULL (copy known files too), KMODS (module names to copy from RAM, or "all").
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:$PATH
DUMPVER=2
R=${OPPODV_ROOT:-}                        # test harness: fake root for /proc, /dev/mem, /mnt, /etc, /tmp, /usr, /res
case "$0" in */*) A=${0%/*};; *) A=.;; esac   # the AutoScript folder (no dirname on the player)
case "$A" in /*) ;; *) A=$(pwd)/$A;; esac
STICK=${OPPODV_STICK:-${A%/*}}
if [ -z "$OPPODV_STICK" ]; then   # write only to a mounted USB disk, never to the player's own storage
  case "$STICK" in /mnt/ubi_boot*|/mnt/rootfs*|/) exit 1;; esac
  grep -q " $STICK " /proc/mounts || exit 1
fi
O=$STICK/oppo-dv-mkv-dump
L=$STICK/oppo-dv-mkv-dump.log
TGZ=$STICK/oppo-dv-mkv-dump.tar.gz
if [ "$1" != run ]; then   # return to the player at once, dump in the background at low priority
  if command -v nice >/dev/null 2>&1; then nice -n 10 sh "$0" run </dev/null >>$L 2>&1 &
  else sh "$0" run </dev/null >>$L 2>&1 &
  fi
  exit 0
fi
up(){ cut -d' ' -f1 $R/proc/uptime 2>/dev/null; }
step(){ echo "[$(up)s] $*"; sync; }
echo "=== oppo-dv-mkv full dump v$DUMPVER, $(date), uptime $(up)s"
rm -rf $O $TGZ $TGZ.tmp
mkdir -p $O/proc $O/kmod $O/player $O/files $O/lists $O/.tmp || { echo "FAILED: cannot write to the stick ($O)"; exit 1; }
W=$O/.tmp
KNOWN=$A/known.md5; [ -s $KNOWN ] || { echo "note: $KNOWN missing, every file will be copied"; KNOWN=/dev/null; }
FULL=; [ -e $A/FULL ] && { FULL=1; echo "FULL: known files are copied too"; }
U=$R/mnt/ubi_boot
RFS=$R/mnt/rootfs_normal
INFO=$O/info.txt
info(){ echo "$*" >> $INFO; }
m5(){ md5sum < "$1" 2>/dev/null | cut -d' ' -f1; }
lnk(){ ls -l "$1" 2>/dev/null | sed 's/.* -> //'; }   # symlink target (no readlink on the player)
st(){ awk -v m="$1" '$1 == m {s = $2} END {print s}' $O/files.txt; }   # what grab did with an md5

# grab SRC [NAME [MD5]]: copy the regular file SRC to files/NAME (default: SRC without the test root) unless
# known.md5 has its md5. Every call is recorded in files.txt as "md5  known|copied|same|FAILED  NAME".
grab(){
  s=$1; n=${2:-${1#$R}}
  [ -f "$s" ] || return 1   # never read device nodes, pipes or missing files
  m=${3:-$(m5 "$s")}
  [ -n "$m" ] || { echo "-  unreadable  $n" >> $O/files.txt; return 1; }
  if grep -q "^$m  \(copied\|known\)" $O/files.txt 2>/dev/null; then r=same
  elif [ -z "$FULL" ] && grep -qx "$m" $KNOWN; then r=known
  elif mkdir -p "$O/files${n%/*}" && cat "$s" > "$O/files$n"; then r=copied
  else r=FAILED; fi
  echo "$m  $r  $n" >> $O/files.txt
}
: > $O/files.txt

# --- 1. the player: every process that maps liblp (the overlay and other mods run their own copy of the player) ---
players(){ for d in $R/proc/[0-9]*; do grep -q 'liblp' $d/maps 2>/dev/null && echo ${d##*/}; done; }
n=0; P=$(players)
while [ -z "$P" ] && [ $n -lt 120 ]; do sleep 2; n=$((n+2)); P=$(players); done
if [ -z "$P" ]; then   # unknown firmware: fall back to anything called bdpprog* that is not a shell script
  for d in $R/proc/[0-9]*; do
    case "$(cat $d/comm 2>/dev/null)" in
      bdpprog*) case "$(lnk $d/exe)" in */bash|*/sh|*/busybox|*/dash|"") ;; *) P="$P ${d##*/}";; esac;;
    esac
  done
  echo "note: no process maps liblp; using: ${P:-none}"
fi
step "player process(es): ${P:-NONE}"
{
  echo "oppo-dv-mkv full dump v$DUMPVER   $(date)   uptime $(up)s"
  echo "kernel:     $(uname -a)"
  echo "cmdline:    $(tr ' ' '\n' < $R/proc/cmdline | awk -F= '$1 ~ /^(BL_Ver|mem|mt85xx_reserve|drvmem|ch3mem|tz_mem|vmalloc|initrd|console|kgdboc|root|rootfstype|rw|ro|init|lpj|loglevel|quiet)$/ {printf "%s ", $0; next} NF {printf "%s=(not copied) ", $1}')"
} > $INFO
for p in $P; do
  d=$R/proc/$p; e=$(lnk $d/exe); e=${e#$R}; e=${e% (deleted)}
  cat $d/maps > $O/player/$p.maps 2>/dev/null
  tr '\0' ' ' < $d/cmdline > $O/player/$p.cmdline 2>/dev/null
  m=$(m5 $d/exe)
  fw=$(grep -ao '20X[A-Z]*-[0-9][0-9]-[0-9][0-9][0-9][0-9]' $d/exe 2>/dev/null | head -1)
  grab $d/exe "$e" $m
  info "player:     pid $p  $e  md5 $m  firmware ${fw:-unknown}  ($(st $m))"
  # the libraries it maps, and the menu image it really uses (the jb_overlay theme or a mod may supply its own).
  # System locations only: never media files, anything on a stick or share, or the key store (/mnt/rootfs_enc_it).
  for f in $(awk '$6 ~ /^\/(usr|lib|bin|sbin|res|tmp|mnt\/rootfs_normal|mnt\/ubi_boot)\// && $6 ~ /(\.so|\/image_bdp83\.bin$)/ \
                  && $6 !~ /^\/mnt\/ubi_boot\/(BUDA|APDA|var)\// {print $6}' $d/maps | sort -u); do
    grab "$R$f" "$f"
    case "$f" in
      */liblp*) info "liblp:      $f  md5 $(m5 "$R$f")  ($(st $(m5 "$R$f")))";;
      */image_bdp83.bin) info "menu image: $f  md5 $(m5 "$R$f")  ($(st $(m5 "$R$f")))";;
    esac
  done
done
[ -z "$P" ] && info "player:     NOT FOUND"
step "player files done ($(grep -c '  copied  ' $O/files.txt) copied, $(grep -c '  known  ' $O/files.txt) already known)"

# --- 2. kernel and system information (no network settings, no share mounts, no command lines) ---
for f in version cpuinfo meminfo mtd partitions iomem modules uptime; do cat $R/proc/$f > $O/proc/$f.txt 2>/dev/null; done
grep -vE '^[^ ]+ [^ ]+ (cifs|smbfs|smb3|nfs|nfs4|fuse[.a-z0-9]*|sshfs|davfs) ' $R/proc/mounts > $O/proc/mounts.txt 2>/dev/null
cat $R/proc/kallsyms > $O/proc/kallsyms.txt 2>/dev/null
for d in $R/proc/[0-9]*; do e=$(lnk $d/exe); echo "${d##*/} $(cat $d/comm 2>/dev/null) ${e#$R}"; done > $O/proc/processes.txt
step "system info done"

# --- 3. kernel modules from RAM: virtual -> physical through the kernel page tables, then /dev/mem ---
MEM=$R/dev/mem
u32(){ dd if=$MEM bs=4 skip=$(( $1 / 4 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
# physical RAM range and the kernel page table: PA(swapper_pg_dir) = _text - PAGE_OFFSET + PHYS_OFFSET - 0x4000
RLO=; RHI=
for r in $(awk '/^[0-9a-f]+-[0-9a-f]+ : System RAM/ {print $1}' $R/proc/iomem 2>/dev/null); do
  a=$(( 0x${r%-*} )); b=$(( 0x${r#*-} + 1 ))
  { [ -z "$RLO" ] || [ $a -lt $RLO ]; } && RLO=$a
  { [ -z "$RHI" ] || [ $b -gt $RHI ]; } && RHI=$b
done
[ -n "$RLO" ] || { RLO=0; RHI=$(( 1 << 32 )); }
TXT=$(awk '$3 == "_text" || $3 == "stext" {print $1; exit}' $R/proc/kallsyms 2>/dev/null)
case "$TXT" in ""|00000000) TXT=80008000;; esac
TXT=$(( 0x$TXT )); PO=$(( TXT & 0xf0000000 ))
PGD=$(( TXT - PO + RLO - 0x4000 ))
SW=$(awk '$3 == "swapper_pg_dir" {print $1; exit}' $R/proc/kallsyms 2>/dev/null)
case "$SW" in ""|00000000) ;; *) PGD=$(( 0x$SW - PO + RLO ));; esac
PTOK=
for k in 0 1 2 3; do   # the linear map: a section entry for PAGE_OFFSET + k MB must point to RAM start + k MB
  l1=$(u32 $(( PGD + ((PO >> 20) + k) * 4 )))
  [ -n "$l1" ] && [ $(( l1 & 3 )) = 2 ] && [ $(( l1 & 0xfff00000 )) = $(( RLO + k * 0x100000 )) ] && { PTOK=1; break; }
done
echo "RAM $(printf 0x%x $RLO)-$(printf 0x%x $RHI) PAGE_OFFSET $(printf 0x%x $PO) pgd $(printf 0x%x $PGD) l1 $(printf 0x%x ${l1:-0}) $([ -n "$PTOK" ] && echo OK || echo 'NOT RECOGNISED: modules skipped')" > $O/kmod/pagetables.txt
cat $O/kmod/pagetables.txt
KMODS="bdpdrv1 bdpdrv splitter"; [ -s $A/KMODS ] && KMODS=$(cat $A/KMODS)
[ "$KMODS" = all ] && KMODS=$(awk '{print $1}' $R/proc/modules)
kdump(){   # $1 = module name -> kmod/NAME.bin (RAM image from the load address on, size from /proc/modules), NAME.syms
  ln=$(grep "^$1 " $R/proc/modules) || { echo "$1: not loaded" >> $O/kmod/modules.txt; return; }
  size=$(echo "$ln" | awk '{print $2}'); base=$(echo "$ln" | awk '{for (i = 3; i <= NF; i++) if ($i ~ /^0x/) {print $i; exit}}')
  case "$base" in 0x*[1-9a-f]*) ;; *) echo "$1: no load address in /proc/modules: $ln" >> $O/kmod/modules.txt; return;; esac
  b=$(( base )); pages=$(( (size + 4095) / 4096 ))
  s=$(( b >> 20 )); e=$(( (b + pages * 4096 - 1) >> 20 )); : > $W/pt
  while [ $s -le $e ]; do   # one first-level entry per MB; its second-level table (256 entries) in one read
    l1=$(u32 $(( PGD + s * 4 )))
    case $(( l1 & 3 )) in
      1) dd if=$MEM bs=1024 skip=$(( (l1 & 0xfffffc00) / 1024 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u\n"' \
           | awk -v s=$s '{print s, NR - 1, $1}' >> $W/pt;;
      2) echo "$s S $(( l1 & 0xfff00000 ))" >> $W/pt;;
    esac
    s=$((s+1))
  done
  # physical address of each page, consecutive pages merged into runs: "PA COUNT", or "- COUNT" when not mapped
  awk -v b=$b -v n=$pages -v lo=$RLO -v hi=$RHI -v stf=$W/st '
    $2 == "S" { sec[$1] = $3; next }
    { pt[$1 " " $2] = $3 }
    END {
      for (i = 0; i < n; i++) {
        va = b + i * 4096; s = int(va / 1048576); x = int(va / 4096) % 256; pa = "-"
        if (s in sec) pa = sec[s] + va % 1048576
        else if ((s " " x) in pt) {
          d = pt[s " " x]
          if (int(d / 2) % 2 == 1) pa = d - d % 4096                          # small page
          else if (d % 4 == 1) pa = d - d % 65536 + va % 65536                # large page
        }
        if (pa != "-" && (pa < lo || pa + 4096 > hi)) { pa = "-"; bad++ }
        if (pa == "-") miss++
        if (c && ((pa == "-" && r == "-") || (pa != "-" && r != "-" && pa == r + c * 4096))) c++
        else { if (c) printf "%s %d\n", (r == "-" ? "-" : sprintf("%.0f", r)), c; r = pa; c = 1 }
      }
      if (c) printf "%s %d\n", (r == "-" ? "-" : sprintf("%.0f", r)), c
      printf "%d %d\n", miss, bad > stf
    }' $W/pt > $W/runs
  while read pa c; do
    if [ "$pa" = - ]; then dd if=/dev/zero bs=4096 count=$c 2>/dev/null
    else dd if=$MEM bs=4096 skip=$(( pa / 4096 )) count=$c 2>/dev/null; fi
  done < $W/runs > $O/kmod/$1.bin
  grep "\[$1\]" $O/proc/kallsyms.txt > $O/kmod/$1.syms
  got=$(( $(wc -c < $O/kmod/$1.bin) / 4096 ))
  set -- $1 $(cat $W/st)
  echo "$1 base $base size $size pages $got/$pages not-mapped $2 outside-RAM $3 md5 $(m5 $O/kmod/$1.bin)" >> $O/kmod/modules.txt
  [ $got = $pages ] || echo "$1: SHORT DUMP ($got of $pages pages)" >> $O/kmod/modules.txt
}
: > $O/kmod/modules.txt
if [ -n "$PTOK" ] && [ -r $MEM ]; then
  for k in $KMODS; do step "copying kernel module $k from RAM"; kdump $k; done
fi
cat $O/kmod/modules.txt
sed 's/^/kmod:       /' $O/kmod/modules.txt >> $INFO
step "kernel modules done"

# --- 4. boot chain, jb_overlay, oppo-dv-mkv, subtitle resources ---
LA=$R/usr/local/bin/bdpprog
if [ -f $LA ]; then
  grab $LA
  if head -c 2 $LA | grep -q '#!'; then
    info "launcher:   /usr/local/bin/bdpprog script, starts /mnt/ubi_boot/bdpprog: $(grep -q /mnt/ubi_boot/bdpprog $LA && echo yes || echo no)"
  else info "launcher:   /usr/local/bin/bdpprog is a program (stock firmware: no jailbreak launcher)"; fi
fi
for f in $U/bdpprog $U/bdpprog.*; do
  [ -f "$f" ] || continue
  grab "$f"
  w=other; grep -q "oppo-dv-mkv boot wrapper" "$f" && w=oppo-dv-mkv; grep -q jb_overlay "$f" && w=jb_overlay
  info "boot hook:  ${f#$R}  md5 $(m5 "$f")  ($w)"
done
[ -e $U/bdpprog ] || info "boot hook:  none (/mnt/ubi_boot/bdpprog missing)"
if [ -d $U/jb_overlay ]; then   # scripts and player files only: config.ini, autostart.sh, root/, etc/dropbear are private
  for f in etc/init.sh etc/autostart_wrap.sh etc/version bdp/bdpprog bdp/image_bdp83.bin; do
    [ -f $U/jb_overlay/$f ] && grab $U/jb_overlay/$f
  done
  info "jb_overlay: present, version $(cat $U/jb_overlay/etc/version 2>/dev/null), bdp/: $(ls $U/jb_overlay/bdp 2>/dev/null | tr '\n' ' ')"
fi
if [ -d $U/oppo-dv-mkv ]; then
  for f in $U/oppo-dv-mkv/*; do grab "$f"; done
  info "oppo-dv-mkv: installed: $(ls $U/oppo-dv-mkv | tr '\n' ' ')$([ -e $U/oppo-dv-mkv/disable ] && echo ' (DISABLED)')"
  info "            its RAM patches may be active, so the module images can contain them"
fi
for f in $R/tmp/image_*.bin; do   # jb_overlay theme: the player reads its images through these links
  [ -L "$f" ] || [ -e "$f" ] || continue
  t=$(lnk "$f"); info "theme link: ${f#$R} -> ${t#$R}"
  case "$f" in */image_bdp83.bin) grab "$f" "${t#$R}";; esac
done
if [ -L $R/res ]; then t=$(lnk $R/res); info "/res:       link -> ${t#$R}"
else info "/res:       directory: $(ls -l $R/res 2>/dev/null | grep -c ' -> ') links, $(ls -l $R/res 2>/dev/null | grep -c '^-') files"; fi
for f in res/image_bdp83.bin res/font.bin; do grab $RFS/$f; done
for f in $R/etc/init.d/* $R/etc/inittab; do grab "$f"; done
step "boot chain done"

# --- 5. file lists: system partition (with md5s), /etc (names only), /mnt/ubi_boot (private parts left out) ---
(cd $RFS && ls -laR .) > $O/lists/rootfs-ls.txt 2>&1
(cd $RFS && find . -xdev -type f | sort | while IFS= read -r f; do md5sum "$f"; done) > $O/lists/rootfs.md5 2>&1
step "system partition hashed: $(wc -l < $O/lists/rootfs.md5) files"
ls -laR $R/etc > $O/lists/etc-ls.txt 2>&1
PRIV='(^|/)(BUDA|APDA|var|root|dropbear|rclone|\.ssh)(/|$)|config\.ini|autostart|passw|shadow|secret|credential|\.key$|\.pem$'
if [ -d $U ]; then
  (cd $U && find . \( -path ./BUDA -o -path ./APDA -o -path ./var -o -path ./jb_overlay/root -o -path ./jb_overlay/etc/dropbear \) -prune -print -o -print) \
    | sort | while IFS= read -r f; do
      if [ -f "$U/$f" ] && [ ! -L "$U/$f" ] && ! echo "$f" | grep -qE "$PRIV"; then m=$(m5 "$U/$f"); else m=-; fi
      echo "$m  $(ls -ld "$U/$f" | sed "s|$U/||")"
    done > $O/lists/ubi_boot.txt
fi
# programs, libraries, kernel modules and subtitle resources of the system partition that are not known: copied
awk -v kf="$KNOWN" -v full="$FULL" 'BEGIN {while ((getline l < kf) > 0) k[l]} !($1 in k) || full' $O/lists/rootfs.md5 \
  | grep -E '  \./(usr/local/(bin|lib)/|lib/modules/|res/(image_bdp83|font)\.bin$)' | while read m f; do
    grab "$RFS/${f#./}" "/mnt/rootfs_normal/${f#./}" $m
  done
step "files: $(grep -c '  copied  ' $O/files.txt) copied, $(grep -c '  known  ' $O/files.txt) already known, $(grep -c '  FAILED  ' $O/files.txt) failed"

# --- 6. checksums, archive ---
rm -rf $W
(cd $O && find . -type f ! -name MD5SUMS | sort | while IFS= read -r f; do md5sum "$f"; done > MD5SUMS)
echo "=== info.txt"; cat $INFO
step "packing $TGZ"
if (cd $STICK && tar czf $TGZ.tmp oppo-dv-mkv-dump oppo-dv-mkv-dump.log) && mv $TGZ.tmp $TGZ; then
  sync; echo "DONE. Send the file oppo-dv-mkv-dump.tar.gz ($(( $(wc -c < $TGZ) / 1024 )) KB) from the stick."
else
  rm -f $TGZ.tmp; sync; echo "DONE, but packing failed: zip the folder oppo-dv-mkv-dump together with this log and send that."
fi
sync
