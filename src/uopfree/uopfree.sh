#!/bin/sh
# oppo-dv-mkv: UOP Free - remote keys work where a disc prohibits them (user operation prohibitions, UOPs). RAM only.
# usage: sh uopfree.sh check | on | off | status | addr
# The player keeps a mode word for the UOP mask at 0x1281638: 0 the disc's own rules, 1 an empty mask (nothing
# prohibited), 2 everything prohibited. It is read at every key, so the change works at once. Idea and address:
# UOPfree by DamnFine815 (MIT). Only the RU 65-0131 player program and its jailbreak copies: the code that reads the
# word is checked first (two sites by fingerprint, all eight literal loads of its address), and a value other than
# 0 or 1 (set by something else) is left alone. "off" writes 0 only where this script had written 1 (or the user asks).
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
CMD=$1; PROC=${OPPODV_PROC:-/proc}
W=$((0x1281638))
# fingerprints (file offset:length:md5 of the running program): two of the places that read the word (load, cmp #1, cmp #2)
FPS="0x28bffa:24:c506824cefd10c74bd920796f6b8fb31 0x31f424:12:cfd46b79791da6371c6c6439d0561688"
# file offsets of the literal pool words that hold the address (every reader of the word)
LITS="0x28c178 0x31f4a4 0x374034 0x389758 0x3931f8 0x39daec 0x3cd11c 0x3cfe10"
log(){ echo "$*"; }
pid(){ ps 2>/dev/null | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'; }
P=${OPPODV_PID:-$(pid)}
[ -n "$P" ] || { log "player not running"; exit 1; }
X=$PROC/$P/exe; M=$PROC/$P/mem
fp(){ o=${1%%:*}; r=${1#*:}; [ "$(dd if=$X bs=1 skip=$((o)) count=${r%%:*} 2>/dev/null | md5sum | cut -d' ' -f1)" = ${r#*:} ]; }
rdf(){ dd if=$X bs=4 skip=$(($1 / 4)) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
rd32(){ dd if=$M bs=4 skip=$(($1 / 4)) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
wr32(){ v=$2; printf "\\$(printf %03o $((v & 255)))\\$(printf %03o $((v >> 8 & 255)))\\$(printf %03o $((v >> 16 & 255)))\\$(printf %03o $((v >> 24 & 255)))" \
        | dd of=$M bs=4 seek=$(($1 / 4)) count=1 conv=notrunc 2>/dev/null; }
check(){
  for f in $FPS; do fp $f || { log "the running player program (md5 $(md5sum $X | cut -d' ' -f1)) is not supported"; return 1; }; done
  for l in $LITS; do [ "$(rdf $((l)))" = $W ] || { log "the running player program (md5 $(md5sum $X | cut -d' ' -f1)) is not supported"; return 1; }; done
  v=$(rd32 $W); case "$v" in 0|1) ;; *) log "UOP mode $v set by something else: not touching it"; return 1;; esac
  return 0; }
case "$CMD" in
check) check && log "supported";;
addr) check >/dev/null && echo $W || echo 0;;   # for the Extras page (switch at once)
status) log "UOP mode $(rd32 $W) (0 the disc's rules, 1 free, 2 all prohibited)";;
on|off)
  check || exit 1
  [ $CMD = on ] && v=1 || v=0
  wr32 $W $v
  [ "$(rd32 $W)" = $v ] || { log "write failed"; exit 1; }
  [ $CMD = on ] && log "on: remote keys work where a disc prohibits them" || log "off: the disc's own rules";;
*) log "usage: uopfree.sh check | on | off | status | addr"; exit 2;;
esac
