#!/bin/sh
# oppo-dv-mkv: factory menu shortcut (RAM patch, applied at every boot by dvmkv.sh). usage: sh fpage.sh on|off|status|check
# Setup > Playback Setup, cursor on the 2nd item (Gapless Playback), then press 0 0 0 0 on the remote: Oppo's hidden
# "Factory Page" opens. Its stock trigger (FUN_008482f8) wants the factory-remote keys F3 (arm), F5, F11, which no
# normal remote, keyboard or IP command can send; here they are replaced in place by the digit 0 (5 small edits, no
# new code): the 1st 0 arms, 3 more 0s open it, any other key disarms.
# The page itself runs unchanged. Like the stock page, opening it also turns off the firmware-update region check and
# starts inetd (telnet) until the next power cycle. It has "Fmt buda" / "Fmt apda" buttons that FORMAT internal
# storage: never press them. See README "Factory menu".
# Player programs: the player program differs per region, so the five places are listed per layout below (found in
# every regional v65 player program by src/porting; the arming branch is re-encoded per layout). A jailbreak or
# jb_overlay copy of a regional program has the same layout. The layout is chosen by the md5 fingerprint of the patched
# code in the running program file (wherever it runs from), and each place is checked before it is written.
# Some player programs (Cambridge CXUHD 66) still have Oppo's older trigger, which takes normal remote keys: there is
# nothing to patch, every command just names those keys and exits with 2 ("not needed").
# "check" only reports whether the running player program is supported.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
PROC=${OPPODV_PROC:-/proc}; CMD=$1
# Layouts (written by src/porting/mklayouts.py; do not edit by hand): name  fingerprints (file off:len:md5) of the
# patched code and of the read-only "$$$" it will point at,  then per place
# VA:bytes:original:patched in this order: literal F5 key 0xbf010 -> '0' 0x10030 | adds r1,#6 (F11) -> #0 ('0') |
# not armed: beq.w exit -> beq.w arm | memcmp length 2 -> 3 | key pattern pointer {4,10} -> a read-only "$$$" (0x30-0xc)
LAYOUTS="
RU 0x840376:126:44df949483138ca4145dc6dd1756adc1 0xfdf7e5:3:54ce99fa85c92b1d87678436e956a2e8 0x8483bc:4:10f00b00:30000100 0x84838a:2:0631:0031 0x8483cc:4:00f0cb82:3ff4e2af 0x8483e2:2:0222:0322 0x8486a4:4:7a882301:e577fe00   # RU-jb RU-ovl RU USA-jb
EU 0x8403ae:126:2ebdae78fc37be2ea9650c67c498eaf6 0xfdf81d:3:54ce99fa85c92b1d87678436e956a2e8 0x8483f4:4:10f00b00:30000100 0x8483c2:2:0631:0031 0x848404:4:00f0cb82:3ff4e2af 0x84841a:2:0222:0322 0x8486dc:4:7a882301:1d78fe00   # EU
AU 0x840376:126:44df949483138ca4145dc6dd1756adc1 0xfdf7ed:3:54ce99fa85c92b1d87678436e956a2e8 0x8483bc:4:10f00b00:30000100 0x84838a:2:0631:0031 0x8483cc:4:00f0cb82:3ff4e2af 0x8483e2:2:0222:0322 0x8486a4:4:7a882301:ed77fe00   # AU
CN 0x84036e:126:53f9a8f903f3da63a752e8f53227596c 0xfdf7d5:3:54ce99fa85c92b1d87678436e956a2e8 0x8483b4:4:10f00b00:30000100 0x848382:2:0631:0031 0x8483c4:4:00f0cb82:3ff4e2af 0x8483da:2:0222:0322 0x84869c:4:7a882301:d577fe00   # CN
TW 0x840346:126:50a72be4b57fc23983b1094f717a0c57 0xfdf7bd:3:54ce99fa85c92b1d87678436e956a2e8 0x84838c:4:10f00b00:30000100 0x84835a:2:0631:0031 0x84839c:4:00f0cb82:3ff4e2af 0x8483b2:2:0222:0322 0x848674:4:7a882301:bd77fe00   # TW
JP 0x840396:126:e7d8a01a21f3831b6ccb47fb0cbf10ec 0xfdfcbd:3:54ce99fa85c92b1d87678436e956a2e8 0x8483dc:4:10f00b00:30000100 0x8483aa:2:0631:0031 0x8483ec:4:00f0cb82:3ff4e2af 0x848402:2:0222:0322 0x8486c4:4:7a182401:bd7cfe00   # JP
US 0x84068c:124:7f73a3145933c2e868a33ca40305c55b 0xfe00e5:3:54ce99fa85c92b1d87678436e956a2e8 0x8486d0:4:10f00b00:30000100 0x8486a0:2:0631:0031 0x8486e0:4:00f0cb82:3ff4e3af 0x8486f6:2:0222:0322 0x8489b8:4:7a182401:e580fe00   # US"
# Player programs whose own trigger takes normal remote keys (written by mklayouts.py): name  fingerprints of the
# trigger code, its arming key literal and its digit pattern  keys (arming colour key, then the digits)
STOCK="
CXUHD 0x82d3f2:90:c379dcf937d1b0d0f949d183a458b294 0x82d704:4:3c1c06cee0414aed6ab0c2f2a6eee9dc 0x120a355:4:87bff90c45422b7ad151c45e228ac681 BLUE-2-4-5-8   # CXUHD"
log(){ echo "$*"; }
P=${OPPODV_PID:-$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}')}; [ -n "$P" ] || { log "player not running"; exit 1; }
X=$PROC/$P/exe; M=$PROC/$P/mem
fp(){ o=${1%%:*}; r=${1#*:}; [ "$(dd if=$X bs=1 skip=$((o)) count=${r%%:*} 2>/dev/null | md5sum | cut -d' ' -f1)" = ${r#*:} ]; }
LAY=; SITES=; OLDIFS=$IFS; IFS='
'
for l in $LAYOUTS; do
  IFS=$OLDIFS; set -- ${l%%#*}
  fp $2 && fp $3 && { LAY=$1; shift 3; SITES="$*"; break; }
done
IFS='
'
[ -n "$LAY" ] || for l in $STOCK; do
  IFS=$OLDIFS; set -- ${l%%#*}
  fp $2 && fp $3 && fp $4 && { log "not needed: this player's own code opens the factory page: Setup > Playback Setup, cursor on the 2nd item, then $(echo $5 | tr - ' ')"; exit 2; }
done
IFS=$OLDIFS
[ -n "$LAY" ] || { log "player program $(md5sum $X | cut -d' ' -f1) matches no known layout, nothing written"; exit 1; }
[ "$CMD" = check ] && { log "supported (layout $LAY)"; exit 0; }
rd(){ dd if=$M bs=1 skip=$(($1)) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
wr(){ printf "$2" | dd of=$M bs=1 seek=$(($1)) conv=notrunc 2>/dev/null; }
esc(){ echo "$1" | sed 's/../\\x&/g'; }
st(){ s=; for e in $SITES; do a=${e%%:*}; r=${e#*:}; n=${r%%:*}; r=${r#*:}; c=$(rd $a $n)
  if [ "$c" = "${r%%:*}" ]; then s="$s off"; elif [ "$c" = "${r#*:}" ]; then s="$s on"; else echo "unexpected $c at $a"; return; fi; done
  case "$s" in *on*off*|*off*on*) echo mixed;; *on*) echo on;; *) echo off;; esac; }
s=$(st)
case "$CMD" in
on)
  [ "$s" = on ] && { log "already on"; exit 0; }
  [ "$s" = off ] || { log "$s, nothing written"; exit 1; }
  for e in $SITES; do a=${e%%:*}; r=${e#*:}; wr $a "$(esc ${r##*:})"; done
  log "on ($(st))";;
off)
  [ "$s" = off ] && { log "already off"; exit 0; }
  [ "$s" = on ] || [ "$s" = mixed ] || { log "$s, nothing written"; exit 1; }
  for e in $SITES; do a=${e%%:*}; r=${e#*:}; o=${r#*:}; wr $a "$(esc ${o%%:*})"; done
  log "off ($(st))";;
*) log "$s";;
esac
