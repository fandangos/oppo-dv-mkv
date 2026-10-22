#!/bin/sh
# oppo-dv-mkv: black letterbox bars in Dolby Vision (bdpdrv1 kernel RAM patch, part of the Dolby Vision MKV fix).
# usage: on|off|status|check. Found and tested by a user (GitHub issue #5).
# The pixel mixer paints everything outside the video window (the bars of a 3840x1600 film) with a background colour.
# The player sets RGB black, the driver turns it into limited-range YCbCr 16/128/128 and PMX_HalSetBg keeps only the
# top 4 bits of each component: luma 1/16 of full scale. That is black in SDR/HDR10, but in Dolby Vision output the
# mixer works in PQ, where 1/16 is about 0.1 nit: dark grey bars next to true-black video (visible on OLED).
#   0x7e9e1874  ubfx ip, r1, #20, #4 (51cae3e7)  ->  mov ip, #0 (00c0a0e3): every background gets luma 0
# Chroma untouched (neutral). SDR/HDR10 bars become "blacker than black", shown as black. The code is the same in every
# known driver build (only the data moves), so it is checked by the bytes around the site, not by build.
# The background the player already set is applied again through the driver CLI (mixer 0, the only one the HAL
# programs) so the change shows at once.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
grep -q "^bdpdrv1 .* 0x7e8d3000 " /proc/modules || { echo "bdpdrv1 not at 0x7e8d3000 (unsupported firmware)"; exit 1; }
# virtual -> physical through the kernel page tables (swapper pgd at PA 0x4000), then /dev/mem
u32(){ dd if=/dev/mem bs=4 skip=$(( $1 / 4 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
pa(){ l1=$(u32 $((0x4000 + ($1 >> 20) * 4))); [ $((l1 & 3)) = 2 ] && { echo $(( (l1 & 0xfff00000) | ($1 & 0xfffff) )); return; }
      pte=$(u32 $(( (l1 & 0xfffffc00) + (($1 >> 12) & 0xff) * 4 ))); echo $(( (pte & 0xfffff000) | ($1 & 0xfff) )); }
rdm(){ dd if=/dev/mem bs=1 skip=$(pa $1) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }   # within one page
wrm(){ printf "$2" | dd of=/dev/mem bs=1 seek=$(pa $1) conv=notrunc 2>/dev/null; }
SITE=0x7e9e1874; ORIG=51cae3e7; PATCHED=00c0a0e3
# PMX_HalSetBg entry (cmp r0,#0; bxne lr) and the instruction after the site (str lr,[sp,#-4]!). The literal load in
# between is skipped: it points at the driver's data, which differs per build.
state(){ a=$(rdm 0x7e9e1868 8); [ "$a" = 000050e31eff2f11 ] || { echo "unexpected $a at PMX_HalSetBg 0x7e9e1868"; return 1; }
  b=$(rdm 0x7e9e1878 4); [ "$b" = 04e02de5 ] || { echo "unexpected $b at 0x7e9e1878"; return 1; }
  case $(rdm $SITE 4) in $ORIG) echo off;; $PATCHED) echo on;; *) echo "unexpected $(rdm $SITE 4) at $SITE"; return 1;; esac; }
bg(){ o=$(printf "drv.pmx.set.bg 0 0x108080\nquit\n" | cliprog 2>&1 | tr -d '\r' | tr '\n' ' '); echo "background set again (cli: $(echo $o))"; }
s=$(state) || { echo "$s, nothing written"; exit 1; }
case "$1" in
check) echo "compatible ($s)";;
on)  [ $s = on ] && { echo "already on"; exit 0; }
     wrm $SITE '\x00\xc0\xa0\xe3'; s=$(state); echo "on ($s)"; [ "$s" = on ] || exit 1; bg;;
off) [ $s = off ] && { echo "already off"; exit 0; }
     wrm $SITE '\x51\xca\xe3\xe7'; s=$(state); echo "off ($s)"; [ "$s" = off ] || exit 1; bg;;
*)   echo $s;;
esac
