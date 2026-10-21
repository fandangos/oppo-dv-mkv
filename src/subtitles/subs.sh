#!/bin/sh
# oppo-dv-mkv: improved subtitles (RAM patch, applied at every boot by dvmkv.sh). usage: sh subs.sh [check]
#  - anti-aliased glyphs without hinting (stock: 1-bit monochrome = jagged edges and fringing)
#  - outline (edge) width 2 instead of 1, and a black outline option
#  - grey text colours (slots 9, 11 and the whole 4th row) for dimmer subtitles on HDR / Dolby Vision
#  - the subtitle colour menu squares are recoloured to match (image_bdp83.bin, built at install time)
# The player program differs per region, so the patched places are listed per layout below (found in every regional
# v65 player program by src/porting). A jailbreak or jb_overlay copy of a regional program has the same layout. The
# layout is chosen by md5 fingerprints of the two patched functions in the running program file, and each place is
# checked (original or already patched) before it is written; anything else is skipped untouched.
# "check" only reports whether the running player program is supported.
# Grid is 6x4, slot = row*6+col (0-based). bdpprog.1 ARGB table (drives the rendered colour), outline preview table
# right after it; liblp.so RGBA palette mirror, entries 10..33 (liblp.so is identical in every v65 firmware).
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
CMD=$1; PROC=${OPPODV_PROC:-/proc}; LIBLP=${OPPODV_LIBLP:-/usr/local/lib/liblp.so}
LIB_MD5=e39b358c5b0948933f49fd3099f81114
PATCH="9:a0a0a0 11:686868 18:c8c8c8 19:b4b4b4 20:a0a0a0 21:888888 22:686868 23:484848"
PREV="b4b4b4 a0a0a0 888888 686868 484848 000000"   # outline preview colours (the outline option row)
# md5 of the colour + preview tables (120 bytes) and of the liblp palette entries 10..33 (96 bytes): stock, patched
TAB_MD5="63cc6a36c41b4c501be18f3c5d5d6a5e 85366599f02bbf564bea9fc17f62db1f"
LIB_TAB_MD5="593f137ee740c69825d434289c5ea953 63209f5e4f19841d69abb1a8bb10c016"
# Layouts (written by src/porting/mklayouts.py; do not edit by hand):
# name  fingerprints (file off:len:md5) of the glyph function, outline function, stock colour tables  then the VAs of
# the colour table, glyph flags, outline row
LAYOUTS="
RU 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2238:240:6ac9bdc7e9c6718a6b5215871cb81d35 0x1230c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1238c20 0x4cbfdc 0x8da2a4   # RU-jb RU-ovl RU USA-jb
EU 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2268:240:4d28915a740bddec3cb5410f74d5addf 0x1230c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1238c20 0x4cbfdc 0x8da2d4   # EU
AU 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2240:240:d21645cfab5e0876328ddc844bf9ebe3 0x1230c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1238c20 0x4cbfdc 0x8da2ac   # AU
CN 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2220:240:2a630f6efb419dc174a8ad4cf7de179c 0x1230c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1238c20 0x4cbfdc 0x8da28c   # CN
TW 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2210:240:089f72620398101c5e9afae9eda91c70 0x1230c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1238c20 0x4cbfdc 0x8da27c   # TW
JP 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2290:240:ad564090e482526bc65598bcf382d043 0x1231c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1241c20 0x4cbfdc 0x8da2fc   # JP
US 0x4c3c54:1904:2b7c1959abd793af3b8479b80d230d6b 0x8d2550:240:f28a1d6ea4d04f1af5284b70c50c870b 0x1231c20:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x1241c20 0x4cbfdc 0x8da5bc   # US
CXUHD 0x4b859c:1904:2956edf1c52258d295ca41134a31af4b 0x8b9e10:240:b66af797c68525023b7c441fc2853996 0x120a6fc:120:63cc6a36c41b4c501be18f3c5d5d6a5e 0x12126fc 0x4c0924 0x8c1e7c   # CXUHD"
log(){ echo "$*"; }
[ "$(md5sum $LIBLP | cut -d' ' -f1)" = $LIB_MD5 ] || { log "liblp.so md5 mismatch, subtitle patches skipped"; exit 1; }
n=0; while :; do
  P=${OPPODV_PID:-$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}')}
  [ -n "$P" ] && B=$(grep liblp.so $PROC/$P/maps | awk '$2=="r-xp"{split($1,a,"-"); print a[1]; exit}')
  [ -n "$B" ] && break
  n=$((n+1)); [ $n -gt 120 ] && { log "player not found"; exit 1; }; sleep 1
done
X=$PROC/$P/exe; M=$PROC/$P/mem
fp(){ o=${1%%:*}; r=${1#*:}; [ "$(dd if=$X bs=1 skip=$((o)) count=${r%%:*} 2>/dev/null | md5sum | cut -d' ' -f1)" = ${r#*:} ]; }
LAY=; OLDIFS=$IFS; IFS='
'
for l in $LAYOUTS; do
  IFS=$OLDIFS; set -- ${l%%#*}
  fp $2 && fp $3 && fp $4 && { LAY=$1; COL=$(($5)); AA=$(($6)); OUT=$(($7)); break; }
done
IFS=$OLDIFS
if [ -z "$LAY" ]; then log "the running player program (md5 $(md5sum $X | cut -d' ' -f1)) matches no known layout, subtitle patches skipped"; exit 1; fi
[ "$CMD" = check ] && { log "supported (layout $LAY)"; exit 0; }
rd(){ dd if=$M bs=1 skip=$1 count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
md(){ dd if=$M bs=1 skip=$1 count=$2 2>/dev/null | md5sum | cut -d' ' -f1; }
# Colours: bdpprog ARGB table + preview table, liblp RGBA palette mirror. Written only over the stock values.
L=$((0x$B + 0x6aa790)); t=$(md $COL 120); lt=$(md $((L + 40)) 96)
if [ "$t" = "${TAB_MD5#* }" ] && [ "$lt" = "${LIB_TAB_MD5#* }" ]; then log "layout $LAY, pid=$P: colours already patched"
elif [ "$t" = "${TAB_MD5%% *}" ] && [ "$lt" = "${LIB_TAB_MD5%% *}" ]; then
  for e in $PATCH; do
    i=${e%%:*}; c=${e#*:}; r=${c%????}; g=${c#??}; g=${g%??}; b=${c#????}
    printf "\xff\x$r\x$g\x$b" | dd of=$M bs=1 seek=$((COL + 4*i)) conv=notrunc 2>/dev/null
    printf "\x$r\x$g\x$b"     | dd of=$M bs=1 seek=$((L + 4*(10+i))) conv=notrunc 2>/dev/null
  done
  i=0; for c in $PREV; do   # outline preview colours (ARGB), right after the 24-entry table
    printf "\xff\x$(echo $c|cut -c1-2)\x$(echo $c|cut -c3-4)\x$(echo $c|cut -c5-6)" | dd of=$M bs=1 seek=$((COL + 0x60 + 4*i)) conv=notrunc 2>/dev/null; i=$((i+1)); done
  log "layout $LAY, pid=$P patched: $PATCH"
else log "colour tables: unexpected content ($t $lt), skipped"; fi
# Anti-aliased glyphs: FT_Load_Char flags 0x1004 (RENDER|MONOCHROME) -> 6 (RENDER|NO_HINTING)
cur=$(rd $AA 4)
if [ "$cur" = 042001e3 ]; then printf '\x06\x20\xa0\xe3' | dd of=$M bs=1 seek=$AA conv=notrunc 2>/dev/null; log "antialias+nohinting on"
elif [ "$cur" = 0620a0e3 ]; then log "antialias+nohinting already on"
else log "antialias: unexpected bytes $cur, skipped"; fi
# Outline colour row: options map to palette 29..34 (was 28..33) so the last option is black (#000000)
cur=$(rd $OUT 2)
if [ "$cur" = 1c33 ]; then printf '\x1d\x33' | dd of=$M bs=1 seek=$OUT conv=notrunc 2>/dev/null; log "outline shift on"
elif [ "$cur" = 1d33 ]; then log "outline shift already on"
else log "outline shift: unexpected $cur, skipped"; fi
# Outline (edge) width 2 in liblp mrSpsRenderTextOnSurf (stock 1)
S=$((0x$B + 0x584998)); MU=$((0x$B + 0x584ad8))
cur=$(rd $S 20); cm=$(rd $MU 4)
if [ "$cur" = 0030a0e3093046e5243094e5bf80c6e1013046e5 ] && [ "$cm" = 0130a0e3 ]; then
  printf '\x02\x30\xa0\xe3\xbf\x30\xc6\xe1\x24\x30\x94\xe5\x00\x00\xa0\xe1\x01\x30\x46\xe5' | dd of=$M bs=1 seek=$S conv=notrunc 2>/dev/null
  printf '\x02\x30\xa0\xe3' | dd of=$M bs=1 seek=$MU conv=notrunc 2>/dev/null; log "edge width 2 on"
elif [ "$cur" = 0230a0e3bf30c6e1243094e50000a0e1013046e5 ] && [ "$cm" = 0230a0e3 ]; then log "edge width 2 already on"
else log "edge width: unexpected bytes, skipped"; fi
