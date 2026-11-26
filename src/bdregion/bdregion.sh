#!/bin/sh
# oppo-dv-mkv: Auto Region - the Blu-ray region of each disc is detected and set when it starts (option bd_region).
# usage: sh bdregion.sh check | on [0|1] | off | status | addr
#   on    install the hook (hook/bdhook.bin at 0x1c03a00), then start bdregiond from a copy in /tmp. With 0 the hook is
#         installed switched off (the Extras switch can turn it on). In the background: it waits until the player has
#         used ipcd_exec once (its import is resolved lazily).
#   off   switched off: everything passes through, the player's own region (the hook stays, harmless)
#   addr  the address of the switch, for the Setup > Extras page (0 when the hook is not in)
# The hook: the first instruction of RegisterAccess.nGetPSR (BD-J asks for PSR20) branches to its gate, and the
# player's ipcd_exec import (disc images mounted, folders linked) points at its wrapper. RAM only. RU 65-0131 player
# program and its jailbreak copies: every place used is checked by fingerprint first.
# Idea and places: autoABC by DamnFine815 (MIT).
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
case "$0" in */*) D=${0%/*} ;; *) D=. ;; esac
CMD=$1; PROC=${OPPODV_PROC:-/proc}; BLOB=${OPPODV_BRBIN:-$D/bdhook.bin}
H=$((0x1c03a00)); MAGIC=42445247                        # "BDRG" (bytes in memory order)
GETPSR=$((0x2aefc0)); ORIGW=$((0xe59f3068)); GOT=$((0x11d8e40))
# fingerprints (file offset:length:md5 of the running program): nGetPSR's first instructions and the literal of the
# replaced one, the PLT entries of access, usleep (both used by the hook) and ipcd_exec (it loads the GOT slot above)
FPS="0x2a6fc0:16:76c39bac018ee1d09c4e71ae28e3bc7a 0x2a7030:4:1232cc2c81f7e46e38e9d84cebd3cff3
0x286f8:12:95fa9691a5f971052d53a49486e50c02 0x2a94c:12:f026759f7f63d653e81d170c8e1304f2
0x29d60:12:719e7ca123cea12b14a029f4a2319d3a"
log(){ echo "$*"; }
pid(){ ps 2>/dev/null | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'; }
P=${OPPODV_PID:-$(pid)}
[ -n "$P" ] || { log "player not running"; exit 1; }
X=$PROC/$P/exe; M=$PROC/$P/mem
fp(){ o=${1%%:*}; r=${1#*:}; [ "$(dd if=$X bs=1 skip=$((o)) count=${r%%:*} 2>/dev/null | md5sum | cut -d' ' -f1)" = ${r#*:} ]; }
rdh(){ dd if=$M bs=1 skip=$1 count=$2 2>/dev/null | hexdump -v -e "$2/1 \"%02x\""; }
rd32(){ dd if=$M bs=4 skip=$(($1 / 4)) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
wr32(){ v=$2; printf "\\$(printf %03o $((v & 255)))\\$(printf %03o $((v >> 8 & 255)))\\$(printf %03o $((v >> 16 & 255)))\\$(printf %03o $((v >> 24 & 255)))" \
        | dd of=$M bs=4 seek=$(($1 / 4)) count=1 conv=notrunc 2>/dev/null; }
sym(){ sed -n "s/^\([0-9a-f]*\) T $1\$/\1/p" $D/bdhook.sym; }   # addresses of the hook's entries (from the build)
GATE=$((0x$(sym bdr_gate))); IPCD=$(($((0x$(sym bdr_ipcd))) | 1))
BRANCH=$((0xea000000 | ((GATE - GETPSR - 8) >> 2 & 0xffffff)))
N=$(wc -c < $BLOB); CODE=$(hexdump -v -e '/1 "%02x"' $BLOB)
# the hook after its 44-byte header must be ours, or the whole place still zero
cave(){ c=$(rdh $H $N); [ -n "$c" ] || { echo none; return; }
  if [ "$(echo $c | cut -c89-)" = "$(echo $CODE | cut -c89-)" ] && [ "$(echo $c | cut -c1-8)" = $MAGIC ]; then echo ours
  elif [ -z "$(echo "$c" | tr -d 0)" ]; then echo free; else echo other; fi; }
check(){
  for f in $FPS; do fp $f || { log "the running player program (md5 $(md5sum $X | cut -d' ' -f1)) is not supported"; return 1; }; done
  case $(cave) in free|ours) ;; none) log "no free place in this player program"; return 1;;
  *) log "place $(printf %x $H) in use by something else (autoABC?)"; return 1;; esac
  w=$(rd32 $GETPSR); [ "$w" = $ORIGW ] || [ "$w" = $BRANCH ] || { log "RegisterAccess.nGetPSR changed by something else: not touching it"; return 1; }
  return 0; }
case "$CMD" in
check) check && log "supported";;
addr) [ "$(cave)" = ours ] && [ "$(rd32 $GETPSR)" = $BRANCH ] && echo $((H + 4)) || echo 0;;
status) log "hook $(cave), enable $(rd32 $((H + 4))), mailbox $(printf %x $(rd32 $((H + 8)))), BD-J asked $(rd32 $((H + 12))) answered $(rd32 $((H + 16))) timeouts $(rd32 $((H + 20))), images/folders $(rd32 $((H + 28))) timeouts $(rd32 $((H + 32))), getPSR $(printf %x $(rd32 $GETPSR)) ipcd $(printf %x $(rd32 $GOT)), region byte $(dd if=$M bs=1 skip=$((0x12346fc)) count=1 2>/dev/null | hexdump -v -e '1/1 "%02x"')";;
off) [ "$(cave)" = ours ] || { log "not in"; exit 0; }; wr32 $((H + 4)) 0; log "off";;
on)
  check || exit 1
  [ $(cave) = free ] && { dd if=$BLOB of=$M bs=1 seek=$H conv=notrunc 2>/dev/null; [ $(cave) = ours ] || { log "writing the hook failed"; exit 1; }; }
  wr32 $((H + 4)) ${2:-1}; wr32 $((H + 40)) $ORIGW
  [ "$(rd32 $GETPSR)" = $BRANCH ] || { wr32 $GETPSR $BRANCH; [ "$(rd32 $GETPSR)" = $BRANCH ] || { log "patching nGetPSR failed"; exit 1; }; }
  # the daemon and its tools from /tmp: nothing of ours keeps /mnt/ubi_boot busy (the player's power-off unmounts it)
  T=/tmp/bdregion; mkdir -p $T
  if ! ps ax -o args 2>/dev/null | grep -q "^$T/bdregiond "; then   # (a running daemon keeps its copy)
    for f in bdregiond bdregion bdhdmv bdcallgraph; do cp $D/$f $T/ && chmod 755 $T/$f || { log "copying $f failed"; exit 1; }; done
  fi
  # the redirections on the subshell itself: it can stay as the daemon's parent, and must not hold the caller's
  # output open (dvmkv.sh reads it to the end)
  # "a || ( ... ) &" would put the whole list in the background, in a shell that keeps the caller's output open
  if ! ps ax -o args 2>/dev/null | grep -q "^$T/bdregiond "; then
    ( cd /; trap '' HUP; exec $T/bdregiond $P $T ) </dev/null >/dev/null 2>&1 &
  fi
  # ipcd_exec: once it is resolved (before, its GOT slot holds the lazy resolver's address)
  ( cd /; n=0; while :; do
      g=$(rd32 $GOT); [ "$g" = $IPCD ] && exit 0
      if [ "$g" -ge $((0x40000000)) ]; then wr32 $((H + 36)) $g; wr32 $GOT $IPCD; exit 0; fi
      n=$((n + 1)); [ $n -gt 600 ] && exit 1; sleep 1
    done ) </dev/null >/dev/null 2>&1 &
  log "on (BD-J gate in, disc images and folders once the player has used ipcd_exec)";;
*) log "usage: bdregion.sh check | on [0|1] | off | status | addr"; exit 2;;
esac
