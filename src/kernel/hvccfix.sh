#!/bin/sh
# oppo-dv-mkv: Dolby Vision for P5/P8 MKVs whose hvcC has no parameter sets (splitter.ko kernel RAM patch, part of the
# Dolby Vision MKV fix). usage: on|off|status|check
# MKVs remuxed from an hev1 MP4 carry a 23-byte HEVC CodecPrivate (hvcC) without VPS/SPS/PPS; those are only in the
# keyframes. The splitter's hvcC reader then finds nothing to parse but still queues one parameter-set packet with a
# length left over from an earlier file. A length of 0 restarts parsing at file offset 0: demux error, and the player
# restarts the video at the next keyframe (such files start a few seconds late). With Dolby Vision signalled that
# restart hard-locked the player, so dvhook.sh refused DV for these files.
# The patch sends the "nothing left to parse" case to a 17-word stub (source: hvcc.S) that ends the header like the
# normal path after the last parameter set, without queueing a packet. The decoder takes the parameter sets from the
# first keyframe, as it does for MPEG-TS files. The stub lives in cli_cfamkv_debug_off, a debug command that only the
# driver CLI calls. dvmkv.sh lets dvhook.sh signal DV for 23-byte hvcC files only once this patch is on.
# The patched code is the same in every known firmware (RU, USA, CXUHD), so it is checked by its bytes.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
T=$(awk '$1=="splitter" && $2==978326 {print $6; exit}' /proc/modules)
[ -n "$T" ] || { echo "splitter module not found or not the known size 978326 (unsupported firmware)"; exit 1; }
T=$((T))
# virtual -> physical through the kernel page tables (swapper pgd at PA 0x4000), then /dev/mem
u32(){ dd if=/dev/mem bs=4 skip=$(( $1 / 4 )) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
pa(){ l1=$(u32 $((0x4000 + ($1 >> 20) * 4))); [ $((l1 & 3)) = 2 ] && { echo $(( (l1 & 0xfff00000) | ($1 & 0xfffff) )); return; }
      pte=$(u32 $(( (l1 & 0xfffffc00) + (($1 >> 12) & 0xff) * 4 ))); echo $(( (pte & 0xfffff000) | ($1 & 0xfff) )); }
rdm(){ dd if=/dev/mem bs=1 skip=$(pa $1) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }   # within one page
wrm(){ printf "$(echo $2 | sed 's/../\\x&/g')" | dd of=/dev/mem bs=1 seek=$(pa $1) conv=notrunc 2>/dev/null; }   # hex string
SITE=$((T + 0x5f340)); SORIG=1c00002a; SPAT=6f05002a      # bcs .text+0x5f3b8 -> bcs stub
CAVE=$((T + 0x60904))                                     # 16 code words + run counter
STUB=38008fe2001090e5011081e2001080e538c500e308c040e308304ce2d30088e1dc2088e1002092e00130a3e0f820c8e10020a0e30030a0e3fc2088e13bf6ffea
# original cave words: three of them are calls to UTIL_Printf (another module), rebuilt from the untouched call at +0x48
corig(){ w=$(rdm $((CAVE + 0x48)) 4); [ "${w#??????}" = eb ] || return 1
  i=$(( 0x${w%??????} + 0x$(echo $w | cut -c3-4) * 256 + 0x$(echo $w | cut -c5-6) * 65536 ))
  b(){ v=$(( (i + $1) & 0xffffff )); printf '%02x%02x%02xeb' $((v & 255)) $((v >> 8 & 255)) $((v >> 16)); }
  echo "000051e301005013f8432de90050a0e1050000da0160a0e10140a0e3ec709fe5ec809fe5ec909fe5100000eae8009fe5$(b 6)e4009fe5$(b 4)e0009fe5$(b 2)"; }
# fingerprints: the hvcC reader around the site, the struct offsets the stub relies on (literals), the shared tail
state(){
  a=$(rdm $((T + 0x5f318)) 40); [ "$a" = f4351fe50330d8e7000053e30600001aac351fe504261fe5033098e7022098e7013043e2030052e1 ] || { echo "unexpected code at splitter+0x5f318"; return 1; }
  a=$(rdm $((T + 0x5f344)) 4); [ "$a" = 1c461fe5 ] || { echo "unexpected code at splitter+0x5f344"; return 1; }
  a=$(rdm $((T + 0x5ed2c)) 8)$(rdm $((T + 0x5ed5c)) 4)$(rdm $((T + 0x5ed84)) 4); [ "$a" = bc040800c40408003005080038050800 ] || { echo "unexpected literals at splitter+0x5ed2c"; return 1; }
  a=$(rdm $((T + 0x5e234)) 32); [ "$a" = 0230a0e30900a0e100308de50810a0e10520a0e30030a0e3e9f2ffeb290900ea ] || { echo "unexpected code at splitter+0x5e234"; return 1; }
  o=$(corig) || { echo "unexpected code at splitter+0x6094c"; return 1; }
  s=$(rdm $SITE 4); c=$(rdm $CAVE 68)
  if [ $s = $SORIG ] && [ $c = $o ]; then echo off
  elif [ $s = $SPAT ] && [ ${c%????????} = $STUB ]; then echo on
  elif [ $s = $SORIG ] && [ ${c%????????} = $STUB ]; then echo off   # stub written, site not redirected: inactive
  else echo "unexpected $s at splitter+0x5f340 / cave"; return 1; fi; }
runs(){ r=$(rdm $((CAVE + 0x40)) 4); echo $(( 0x$(echo $r | cut -c1-2) + 0x$(echo $r | cut -c3-4) * 256 + 0x$(echo $r | cut -c5-6) * 65536 )); }
s=$(state) || { echo "$s, nothing written"; exit 1; }
case "$1" in
check) echo "compatible ($s)";;
on)  [ $s = on ] && { echo "already on (stub runs: $(runs))"; exit 0; }
     wrm $CAVE ${STUB}00000000; [ "$(rdm $CAVE 68)" = ${STUB}00000000 ] || { echo "cave write failed"; exit 1; }
     wrm $SITE $SPAT; s=$(state); echo "on ($s)"; [ "$s" = on ] || exit 1;;
off) [ $s = off ] && [ "$(rdm $CAVE 68)" = "$(corig)" ] && { echo "already off"; exit 0; }
     wrm $SITE $SORIG; wrm $CAVE $(corig); s=$(state); echo "off ($s)"; [ "$s" = off ] || exit 1;;
*)   [ $s = on ] && echo "on (stub runs: $(runs))" || echo $s;;
esac
