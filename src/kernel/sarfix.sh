#!/bin/sh
# oppo-dv-mkv: pictures with non-square pixels stretched to ~16:9 (bdpdrv1 kernel RAM patch, part of the Dolby Vision
# MKV fix). usage: on|off|status|check
# Some streams (for example films cropped to 3840x1744) set an HEVC sample aspect ratio such as 1199:1200 so
# the picture is exactly 2.20:1. When a picture has no aspect-ratio code (MKV), the video plane describes the source
# shape as (SAR_w * width, SAR_h * height) without reducing it, and VDP_GetFixedRegion multiplies that by the picture
# size in 32 bits. For 1199:1200 at 3840x1744 the product wraps: the letterbox comes out 17 lines instead of 207 and the
# picture is drawn 2125 lines tall. Square pixels give (3840, 1744) and are fine.
# Two branches (_VdpUpdateFrameInfo: video plane regions; u4VDP_DesiredResolution: decoder pre-downscale size) go to
# stubs (source: sar.S) that redo the multiplies and scale both values down, rounded, until they fit in 12 bits (the
# range of a 1:1 picture size; the ratio stays within 0.05%). Pairs that already fit are unchanged. The stubs live in
# the unused tail of _Cmd_ImgResz_TestPerformance, a test command that only the driver CLI calls (p7kel.sh uses the
# start of the same function, up to 0x7e94d3e0). The code is the same in every known driver build (RU, USA, CXUHD;
# only the data moves), so it is checked by its bytes.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
grep -q "^bdpdrv1 .* 0x7e8d3000 " /proc/modules || { echo "bdpdrv1 not at 0x7e8d3000 (unsupported firmware)"; exit 1; }
# virtual -> physical through the kernel page tables (swapper pgd at PA 0x4000), then /dev/mem
u32(){ dd if=/dev/mem bs=4 skip=$(( $1 / 4 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
pa(){ l1=$(u32 $((0x4000 + ($1 >> 20) * 4))); [ $((l1 & 3)) = 2 ] && { echo $(( (l1 & 0xfff00000) | ($1 & 0xfffff) )); return; }
      pte=$(u32 $(( (l1 & 0xfffffc00) + (($1 >> 12) & 0xff) * 4 ))); echo $(( (pte & 0xfffff000) | ($1 & 0xfff) )); }
rdm(){ dd if=/dev/mem bs=1 skip=$(pa $1) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }   # within one page
wrm(){ printf "$(echo $2 | sed 's/../\\x&/g')" | dd of=/dev/mem bs=1 seek=$(pa $1) conv=notrunc 2>/dev/null; }   # hex string
S1=0x7e9b8538; S1ORIG=fc3098e5; S1PAT=3054feea            # _VdpUpdateFrameInfo: ldr r3,[r8,#0xfc] -> b sar_frame
S2=0x7e9c187c; S2ORIG=b820d6e1; S2PAT=682ffeea            # u4VDP_DesiredResolution: ldrh r2,[r6,#8] -> b sar_desired
CAVE=0x7e94d600                                           # 30 words
STUB=fc3098e550109de5930903e0002198e5920101e00c0000eb5c308de560108de5d3ab01eab820d6e1b431d6e1920303e0ba20d6e1b611d6e1920101e0020000eb68308de56c108de59dd001ea012083e1122f6fe1142072e21eff2fd101c042e20100a0e3103c83e0101c81e03332a0e13112a0e11eff2fe1
CORIG=38208de538008de2602196e53c109de5022081e044119fe5010052e13d2942825c119685092d4282602186956021868538209d855c21969538109d950220818001208282022081900010a0e35c2186e50820a0e3b3affbeb0010a0e30820a0e3f4009fe5afaffbebf4009fe50010a0e30820a0e3abaffbeb
# fingerprints: each branch with its aspect-code test and the code up to the first instruction after the join (the
# registers and stack slots the stubs use)
state(){
  a=$(rdm 0x7e9b8530 8)$(rdm 0x7e9b853c 60)
  [ "$a" = 000052e30600001a50109de5930903e05c308de5003198e5930103e0f4ffffea0d0052e3fc3098055c308d0500319805efffff0a5c008de260108de22adbffeb5c209de5 ] || { echo "unexpected code at _VdpUpdateFrameInfo 0x7e9b8530"; return 1; }
  a=$(rdm 0x7e9c1870 12)$(rdm 0x7e9c1880 72)
  [ "$a" = 1c2096e5000052e30700001ab431d6e1920303e0ba20d6e168308de5b631d6e1920303e0040000ea0d0052e30400001ab431d6e168308de5b631d6e16c308de5020000ea68008de26c108de256b6ffeb2531d7e5 ] || { echo "unexpected code at u4VDP_DesiredResolution 0x7e9c1870"; return 1; }
  s1=$(rdm $S1 4); s2=$(rdm $S2 4); c=$(rdm $CAVE 120)
  case "$s1 $s2" in "$S1ORIG $S2ORIG"|"$S1PAT $S2PAT"|"$S1PAT $S2ORIG"|"$S1ORIG $S2PAT") ;;
    *) echo "unexpected $s1 at $S1 / $s2 at $S2"; return 1;; esac
  if [ "$c" = $STUB ]; then
    case "$s1 $s2" in "$S1PAT $S2PAT") echo on;; "$S1ORIG $S2ORIG") echo off;; *) echo partial;; esac   # partial: an interrupted on/off
  elif [ "$c" = $CORIG ] && [ "$s1 $s2" = "$S1ORIG $S2ORIG" ]; then echo off
  else echo "unexpected bytes in the cave at $CAVE"; return 1; fi; }
s=$(state) || { echo "$s, nothing written"; exit 1; }
case "$1" in
check) echo "compatible ($s)";;
on)  [ $s = on ] && { echo "already on"; exit 0; }
     wrm $CAVE $STUB; [ "$(rdm $CAVE 120)" = $STUB ] || { echo "cave write failed"; exit 1; }
     wrm $S1 $S1PAT; wrm $S2 $S2PAT; s=$(state); echo "on ($s)"; [ "$s" = on ] || exit 1;;
off) [ $s = off ] && [ "$(rdm $CAVE 120)" = $CORIG ] && { echo "already off"; exit 0; }
     wrm $S2 $S2ORIG; wrm $S1 $S1ORIG; wrm $CAVE $CORIG; s=$(state); echo "off ($s)"; [ "$s" = off ] || exit 1;;
*)   echo $s;;
esac
