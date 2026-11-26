#!/bin/sh
# oppo-dv-mkv: external subtitles of discs (Blu-ray ISO or folder + Title.srt / .ssa / .ass / .smi), RAM only.
# usage: sh extsub.sh check | on | off | status
# 1. tags: <i> </i> <b> <font ...> are no longer drawn as text. The player's cue clean-up (RU 65-0131 player program
#    0x93fc58, 142 bytes) is replaced by extsub.bin: the same work (\N line breaks, {\...} blocks) and every <tag>
#    / </tag> removed.
#    LF-only files: the player's SRT parser overwrote the last character of every line (it put a space at len-2 for
#    "\n" endings as well as for "\r\n"); the branch at 0x940148 (bne -> b) now replaces it only when it is the '\r'.
# 2. several files: Title.srt, Title.en.srt, Title.pt-BR.srt, Title.eng.forced.ass ... each its own subtitle menu
#    entry named by its language. extmulti.bin goes to a 64 KiB RWX region at 0x1b90000 that the Extras page's loader
#    stub (xtmenu.sh, 0x1c07b00) maps; 9 places of the player's code jump there (8-byte "ldr.w pc, [pc, #k]" + address).
# Every place is checked against the original bytes first; "off" puts them back.
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
case "$0" in */*) D=${0%/*} ;; *) D=. ;; esac
CMD=$1; PROC=${OPPODV_PROC:-/proc}; BLOB=${OPPODV_ESBIN:-$D/extsub.bin}; MBIN=${OPPODV_EMBIN:-$D/extmulti.bin}
LF=$((0x940148)); A=$((0x93fc58)); FP="0x937c58:142:21918ea16da00b5660d680f554b75234"
XL=$((0x1c07b00)); GOT=$((0x11d9224)); XM=$((0x1b90000)); XMLEN=$((0x10000))
# place:original 8 bytes:index of the target in extmulti's header (0 = es_setpath at +8, 1..8 = stubs t1..t8 at +12)
SITES="93f464:f8b50446002800f0:0 a93c58:0133049302b10593:1 a94772:069e0123ab70eb78:2 a93748:a3780bb10137bfb2:3
a93768:b7420ad14bb18a4b:4 a942ac:bdf82630013b0a93:5 a94344:013a904583f804a0:6 8f4806:9c4b1a7802f54252:7
8f4b90:33880133338003e0:8"
log(){ echo "$*"; }
pid(){ ps 2>/dev/null | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'; }
P=${OPPODV_PID:-$(pid)}
[ -n "$P" ] || { log "player not running"; exit 1; }
X=$PROC/$P/exe; M=$PROC/$P/mem
N=$(wc -c < $BLOB)
fp(){ o=${1%%:*}; r=${1#*:}; [ "$(dd if=$X bs=1 skip=$((o)) count=${r%%:*} 2>/dev/null | md5sum | cut -d' ' -f1)" = ${r#*:} ]; }
rdh(){ dd if=$M bs=1 skip=$1 count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
xrdh(){ dd if=$X bs=1 skip=$(($1 - 0x8000)) count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
rd32(){ dd if=$M bs=4 skip=$(($1 / 4)) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
wr32(){ v=$2; printf "\\$(printf %03o $((v & 255)))\\$(printf %03o $((v >> 8 & 255)))\\$(printf %03o $((v >> 16 & 255)))\\$(printf %03o $((v >> 24 & 255)))" \
        | dd of=$M bs=4 seek=$(($1 / 4)) count=1 conv=notrunc 2>/dev/null; }
le32(){ hexdump -v -s $2 -n 4 -e '1/4 "%u"' $1; }
hx(){ v=$1; printf '%02x%02x%02x%02x' $((v & 255)) $((v >> 8 & 255)) $((v >> 16 & 255)) $((v >> 24 & 255)); }
# the 8 bytes, from hex (the shell's arithmetic is signed 32-bit: no word values here)
wr8(){ h=$2; s=""; while [ -n "$h" ]; do s="$s\\$(printf %03o 0x${h%${h#??}})"; h=${h#??}; done
       printf "$s" | dd of=$M bs=1 count=8 seek=$1 conv=notrunc 2>/dev/null; }
state(){ m=$(dd if=$M bs=1 skip=$A count=$N 2>/dev/null | md5sum | cut -d' ' -f1)
  if [ "$m" = "$(md5sum < $BLOB | cut -d' ' -f1)" ]; then echo ours
  elif [ "$(dd if=$M bs=1 skip=$A count=142 2>/dev/null | md5sum | cut -d' ' -f1)" = ${FP##*:} ]; then echo stock; else echo other; fi; }
mapped(){ m=$(cat $PROC/$P/maps) || return 2
  while read r x; do case $r in *-*) s=$((0x${r%-*})); e=$((0x${r#*-})); [ $s -lt $2 ] && [ $e -gt $1 ] && return 0;; esac; done <<EOF
$m
EOF
  return 1; }
loaded(){ [ "$(rdh $XM 4)" = 45584d53 ]; }
jump(){ a=$((0x$1)); [ $((a % 4)) = 0 ] && i=dff800f0 || i=dff802f0; echo $i$(hx $(rd32 $((XM + 8 + 4 * $2)))); }
sites(){ ok=0; st=0; ot=0; for s in $SITES; do a=${s%%:*}; r=${s#*:}; o=${r%%:*}; t=${r#*:}
    c=$(rdh $((0x$a)) 8); if [ "$c" = "$o" ]; then st=$((st + 1)); elif loaded && [ "$c" = "$(jump $a $t)" ]; then ok=$((ok + 1)); else ot=$((ot + 1)); fi
  done; echo "$ok $st $ot"; }
# the loader stub (xtmenu.sh): request mmap from the player's own thread
call(){ wr32 $((XL + 12)) $1; wr32 $((XL + 16)) ${2:-0}; wr32 $((XL + 20)) ${3:-0}; wr32 $((XL + 24)) ${4:-0}; wr32 $((XL + 28)) ${5:-0}
  wr32 $((XL + 4)) 1; wr32 $GOT $HOOK; n=0
  while [ "$(rd32 $((XL + 4)))" != 3 ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  wr32 $GOT $ORIG; RET=$(rd32 $((XL + 32)))
  [ "$(rd32 $((XL + 4)))" = 3 ] && { wr32 $((XL + 4)) 0; return 0; }
  log "the player did not run the request (state $(rd32 $((XL + 4))))"; return 1; }
multi_on(){
  set -- $(sites); [ $3 = 0 ] || { log "several files: $3 places changed by something else: not touching them"; return 1; }
  [ $2 = 0 ] && { log "several files: on"; return 0; }
  if loaded; then dd if=$MBIN of=$M bs=1 seek=$XM conv=notrunc 2>/dev/null   # all places stock: nothing runs it, update
  else
    [ "$(rdh $XL 4)" = 58544c44 ] || { log "several files: needs the Setup Extras page (setup_extras = on)"; return 0; }
    ORIG=$(rd32 $((XL + 8))); HOOK=$(rd32 $((XL + 40))); MM=$(rd32 $((XL + 44)))
    [ $ORIG -ge $((0x40000000)) ] && [ "$(rd32 $GOT)" = $ORIG ] && [ "$(rd32 $((XL + 4)))" = 0 ] || { log "several files: loader stub busy"; return 1; }
    if mapped $XM $((XM + XMLEN)); then          # mapped by an earlier run that stopped before the copy: still empty?
      [ "$(rdh $XM 64 | tr -d 0)" = "" ] || { log "several files: place $(printf %x $XM) already in use"; return 1; }
    else
      call $MM $XM $XMLEN 7 $((0x32)) || return 1
      [ "$RET" = $XM ] || { log "several files: mmap failed ($(printf %x $RET))"; return 1; }
    fi
    dd if=$MBIN of=$M bs=1 seek=$XM conv=notrunc 2>/dev/null
    loaded || { log "several files: writing the code failed"; return 1; }
  fi
  for s in $SITES; do a=${s%%:*}; r=${s#*:}; o=${r%%:*}; t=${r#*:}
    [ "$(rdh $((0x$a)) 8)" = "$o" ] && wr8 $((0x$a)) $(jump $a $t); done
  set -- $(sites); [ $1 = 9 ] && log "several files: on" || { log "several files: only $1 of 9 places"; return 1; }; }
multi_off(){ for s in $SITES; do a=${s%%:*}; r=${s#*:}; o=${r%%:*}; t=${r#*:}
    loaded && [ "$(rdh $((0x$a)) 8)" = "$(jump $a $t)" ] && wr8 $((0x$a)) $o; done; set -- $(sites); log "several files: $2 of 9 places stock"; }
lfst(){ c=$(rdh $LF 2); if [ "$c" = 08e0 ]; then echo ours; elif [ "$c" = 08d1 ]; then echo stock; else echo other; fi; }
mst(){ set -- $(sites); loaded || { echo "several files: not loaded ($2 of 9 places stock)"; return; }
  echo "several files: $1 of 9 places ours, $2 stock, $3 other; files $(rd32 $((XM + 44))) current $(rd32 $((XM + 48))) setpath $(rd32 $((XM + 56))) scans $(rd32 $((XM + 60))) switches $(rd32 $((XM + 64))) names $(rd32 $((XM + 68)))"; }
case "$CMD" in
check) fp $FP || { log "the running player program (md5 $(md5sum $X | cut -d' ' -f1)) is not supported"; exit 1; }
       [ "$(xrdh $LF 2)" = 08d1 ] || { log "the running player program is not supported (LF)"; exit 1; }
       for s in $SITES; do a=${s%%:*}; r=${s#*:}; [ "$(xrdh $((0x$a)) 8)" = "${r%%:*}" ] || { log "the running player program is not supported ($a)"; exit 1; }; done
       case $(state) in stock|ours) log "supported";; *) log "changed by something else"; exit 1;; esac;;
status) log "external subtitle tags: $(state), LF line ends: $(lfst)"; mst;;
on) fp $FP || { log "the running player program is not supported"; exit 1; }
    case $(state) in
    ours) log "tags: on";;
    stock) dd if=$BLOB of=$M bs=1 seek=$A conv=notrunc 2>/dev/null; [ $(state) = ours ] && log "tags: on" || { log "writing failed"; exit 1; };;
    *) log "tags: changed by something else: not touching it"; exit 1;;
    esac
    case $(rdh $LF 2) in 08e0) ;; 08d1) printf '\010\340' | dd of=$M bs=1 seek=$LF conv=notrunc 2>/dev/null
      [ "$(rdh $LF 2)" = 08e0 ] && log "LF line ends: on" || log "LF line ends: writing failed";; *) log "LF line ends: changed by something else";; esac
    [ -f $MBIN ] && { multi_on || exit 1; };;
off) multi_off;;
*) log "usage: extsub.sh check | on | off | status"; exit 2;;
esac
