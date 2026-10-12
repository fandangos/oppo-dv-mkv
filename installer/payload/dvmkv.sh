#!/bin/sh
# oppo-dv-mkv runtime (started by /mnt/ubi_boot/bdpprog at every boot): wait for the player, apply the RAM patches,
# then mark the boot healthy. Log: /mnt/ubi_boot/oppo-dv-mkv/dvmkv.log
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
D=${OPPODV_D:-/mnt/ubi_boot/oppo-dv-mkv}
log(){ echo "[$(cut -d' ' -f1 /proc/uptime)] $*"; }
n=0; while :; do
  P=$(ps | awk '$4=="bdpprog.1"{print $1; exit}')
  [ -n "$P" ] && grep -q liblp.so /proc/$P/maps 2>/dev/null && break
  n=$((n+1)); [ $n -gt 120 ] && { log "player not found"; exit 1; }; sleep 1
done
log "player pid $P"
sh $D/dvhook.sh on 2>&1 | while read l; do log "dvhook: $l"; done   # MKV Dolby Vision signalling (liblp)
sh $D/p7kel.sh on 2>&1 | while read l; do log "p7kel: $l"; done     # profile 7 decoder fixes (kernel)
[ -f $D/subs.sh ] && sh $D/subs.sh 2>&1 | while read l; do log "subs: $l"; done   # improved subtitles
sleep 90; [ -d /proc/$P ] && { rm -f $D/bootcount; sync; log "boot marked healthy"; }
