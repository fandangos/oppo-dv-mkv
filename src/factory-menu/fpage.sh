#!/bin/sh
# oppo-dv-mkv: factory menu shortcut (RAM patch, applied at every boot by dvmkv.sh). usage: sh fpage.sh on|off|status
# Setup > Playback Setup, cursor on the 2nd item (Gapless Playback), then press 0 0 0 0 on the remote: Oppo's hidden
# "Factory Page" opens. Its stock trigger (FUN_008482f8) wants the factory-remote keys F3 (arm), F5, F11, which no
# normal remote, keyboard or IP command can send; here they are replaced in place by the digit 0 (5 small edits, no
# new code): the 1st 0 arms, 3 more 0s open it, any other key disarms.
# The page itself runs unchanged. Like the stock page, opening it also turns off the firmware-update region check and
# starts inetd (telnet) until the next power cycle. It has "Fmt buda" / "Fmt apda" buttons that FORMAT internal
# storage: never press them. See README "Factory menu".
# Player programs: the RU 65-0131 free jailbreak bdpprog.1 (49b649bd) and the jb_overlay V3 copy (82e04bcf: the same
# program with 40 bytes changed, none near these sites). Checked against the running program, wherever it runs from.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
BDP_MD5="49b649bdcffe8b611f1b7bbc0d9fa0b1 82e04bcfc60a53892668ea325311b3a6"
log(){ echo "$*"; }
P=$(ps | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'); [ -n "$P" ] || { log "player not running"; exit 1; }
m=$(md5sum /proc/$P/exe | cut -d' ' -f1)
case " $BDP_MD5 " in *" $m "*) ;; *) log "player program $m not supported, nothing written"; exit 1;; esac
M=/proc/$P/mem
rd(){ dd if=$M bs=1 skip=$(($1)) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
wr(){ printf "$2" | dd of=$M bs=1 seek=$(($1)) conv=notrunc 2>/dev/null; }
# VA:bytes:original:patched
SITES="0x8483bc:4:10f00b00:30000100 0x84838a:2:0631:0031 0x8483cc:4:00f0cb82:3ff4e2af 0x8483e2:2:0222:0322 0x8486a4:4:7a882301:e577fe00"
#  0x8483bc literal F5 key 0xbf010 -> '0' 0x10030 | 0x84838a adds r1,#6 (F11) -> #0 ('0')
#  0x8483cc not armed: beq.w exit -> beq.w 0x848394 (arm) | 0x8483e2 memcmp length 2 -> 3
#  0x8486a4 pattern {4,10} @0x123887a -> "$$$" @0xfe77e5 (0x30 - 0xc = 0x24, in a read-only table)
esc(){ echo "$1" | sed 's/../\\x&/g'; }
st(){ s=; for e in $SITES; do a=${e%%:*}; r=${e#*:}; n=${r%%:*}; r=${r#*:}; c=$(rd $a $n)
  if [ "$c" = "${r%%:*}" ]; then s="$s off"; elif [ "$c" = "${r#*:}" ]; then s="$s on"; else echo "unexpected $c at $a"; return; fi; done
  case "$s" in *on*off*|*off*on*) echo mixed;; *on*) echo on;; *) echo off;; esac; }
s=$(st)
case "$1" in
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
