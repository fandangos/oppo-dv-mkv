#!/bin/sh
# oppo-dv-mkv: improved subtitles (RAM patch, applied at every boot by dvmkv.sh). usage: sh subs.sh
#  - anti-aliased glyphs without hinting (stock: 1-bit monochrome = jagged edges and fringing)
#  - outline (edge) width 2 instead of 1, and a black outline option
#  - grey text colours (slots 9, 11 and the whole 4th row) for dimmer subtitles on HDR / Dolby Vision
#  - the subtitle colour menu squares are recoloured to match (image_bdp83.bin, built at install time)
# Only for the RU 65-0131 player program (bdpprog.1 is region-specific); anything else is skipped untouched.
# Grid is 6x4, slot = row*6+col (0-based). bdpprog.1 ARGB table @0x01238c20 (drives the rendered colour);
# liblp.so RGBA palette mirror, entries 10..33.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
BDP_MD5=49b649bdcffe8b611f1b7bbc0d9fa0b1; LIB_MD5=e39b358c5b0948933f49fd3099f81114
PATCH="9:a0a0a0 11:686868 18:c8c8c8 19:b4b4b4 20:a0a0a0 21:888888 22:686868 23:484848"
log(){ echo "$*"; }
[ "$(md5sum /usr/local/lib/liblp.so | cut -d' ' -f1)" = $LIB_MD5 ] || { log "liblp.so md5 mismatch, subtitle patches skipped"; exit 1; }
n=0; while :; do
  P=$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}')
  [ -n "$P" ] && B=$(grep liblp.so /proc/$P/maps | awk '$2=="r-xp"{split($1,a,"-"); print a[1]; exit}')
  [ -n "$B" ] && break
  n=$((n+1)); [ $n -gt 120 ] && { log "player not found"; exit 1; }; sleep 1
done
[ "$(md5sum /proc/$P/exe | cut -d' ' -f1)" = $BDP_MD5 ] || { log "running player program is not the RU 65-0131 one, subtitle patches skipped"; exit 1; }
M=/proc/$P/mem; L=$((0x$B + 0x6aa790))
for e in $PATCH; do
  i=${e%%:*}; c=${e#*:}; r=${c%????}; g=${c#??}; g=${g%??}; b=${c#????}
  printf "\xff\x$r\x$g\x$b" | dd of=$M bs=1 seek=$((0x01238c20 + 4*i)) conv=notrunc 2>/dev/null
  printf "\x$r\x$g\x$b"     | dd of=$M bs=1 seek=$((L + 4*(10+i)))   conv=notrunc 2>/dev/null
done
log "pid=$P patched: $PATCH"
# Anti-aliased glyphs: FT_Load_Char flags 0x1004 (RENDER|MONOCHROME) -> 6 (RENDER|NO_HINTING) at 0x4cbfdc
A=$((0x4cbfdc)); cur=$(dd if=$M bs=1 skip=$A count=4 2>/dev/null | hexdump -v -e '4/1 "%02x"')
if [ "$cur" = 042001e3 ]; then printf '\x06\x20\xa0\xe3' | dd of=$M bs=1 seek=$A conv=notrunc 2>/dev/null; log "antialias+nohinting on"
else log "antialias: unexpected bytes $cur, skipped"; fi
# Outline colour row: options map to palette 29..34 (was 28..33) so the last option is black (#000000)
A=$((0x8da2a4)); cur=$(dd if=$M bs=1 skip=$A count=2 2>/dev/null | hexdump -v -e '2/1 "%02x"')
if [ "$cur" = 1c33 ]; then printf '\x1d\x33' | dd of=$M bs=1 seek=$A conv=notrunc 2>/dev/null; log "outline shift on"
else log "outline shift: unexpected $cur, skipped"; fi
i=0; for c in b4b4b4 a0a0a0 888888 686868 484848 000000; do   # outline preview colours (ARGB) @0x1238c80
  printf "\xff\x$(echo $c|cut -c1-2)\x$(echo $c|cut -c3-4)\x$(echo $c|cut -c5-6)" | dd of=$M bs=1 seek=$((0x1238c80 + 4*i)) conv=notrunc 2>/dev/null; i=$((i+1)); done
# Outline (edge) width 2 in liblp mrSpsRenderTextOnSurf (stock 1)
S=$((0x$B + 0x584998)); MU=$((0x$B + 0x584ad8))
cur=$(dd if=$M bs=1 skip=$S count=20 2>/dev/null | hexdump -v -e '20/1 "%02x"'); cm=$(dd if=$M bs=1 skip=$MU count=4 2>/dev/null | hexdump -v -e '4/1 "%02x"')
if [ "$cur" = 0030a0e3093046e5243094e5bf80c6e1013046e5 ] && [ "$cm" = 0130a0e3 ]; then
  printf '\x02\x30\xa0\xe3\xbf\x30\xc6\xe1\x24\x30\x94\xe5\x00\x00\xa0\xe1\x01\x30\x46\xe5' | dd of=$M bs=1 seek=$S conv=notrunc 2>/dev/null
  printf '\x02\x30\xa0\xe3' | dd of=$M bs=1 seek=$MU conv=notrunc 2>/dev/null; log "edge width 2 on"
else log "edge width: unexpected bytes, skipped"; fi
