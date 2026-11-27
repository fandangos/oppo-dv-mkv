#!/bin/sh
# oppo-dv-mkv runtime (started by /mnt/ubi_boot/bdpprog at every boot): wait for the player, apply the RAM patches,
# show the result on screen (boot message), then mark the boot healthy. Log: /mnt/ubi_boot/oppo-dv-mkv/dvmkv.log
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
D=${OPPODV_D:-/mnt/ubi_boot/oppo-dv-mkv}
VERSION=@VERSION@
log(){ echo "[$(cut -d' ' -f1 /proc/uptime)] $*"; [ -n "$BT" ] && { echo "[$(cut -d' ' -f1 /proc/uptime)] $*" >> $BT; sync; }; }
# boot debugging (while $D/bootdebug exists): every line also in boot.log, synced at once, with a "start" line before
# each part (a boot that hangs shows where); the previous boot's in boot.log.1; and bootmon.log (below)
BT=; if [ -e $D/bootdebug ] && [ "$1" != relp ]; then mv -f $D/boot.log $D/boot.log.1 2>/dev/null; BT=$D/boot.log; fi
opt(){ [ -f $D/options.txt ] && tr -d '\r' < $D/options.txt | grep -v '^[[:space:]]*#' \
  | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p" | sed -n '$p' | tr A-Z a-z; }
FAIL=   # the parts that did not load this boot (named in the boot message)
# autoABC / standalone UOPfree (DamnFine815) installed: they switch the region and the UOP word themselves; ours stay off
# (two would patch the same places). Their markers: /mnt/ubi_boot/autoABC (BUILD_ID), /mnt/ubi_boot/UOPfree, bluray_uop.
UB=${OPPODV_UBI:-/mnt/ubi_boot}
abc(){ [ -d $UB/autoABC ] && echo "autoABC $(head -c 20 $UB/autoABC/BUILD_ID 2>/dev/null | tr -cd '0-9A-Za-z._-')"; }
uopf(){ abc || { { [ -e $UB/UOPfree ] || [ -L $UB/UOPfree ] || [ -e $UB/bluray_uop ] || [ -L $UB/bluray_uop ]; } && echo "UOPfree"; }; }
# run NAME LABEL COMMAND...: log the command's lines as "NAME: ..."; a non-zero exit, or a line that reports a failure,
# means the part did not load. "not supported on this player program" is not a failure: that is known at install time.
run(){ n=$1; t=$2; shift 2
  [ -n "$BT" ] && log "$n: start"
  o=$("$@" 2>&1); r=$?
  printf '%s\n' "$o" | while read l; do [ -n "$l" ] && log "$n: $l"; done
  if [ $r != 0 ] || printf '%s\n' "$o" | grep -v "not supported on this player program" \
       | grep -qiE "unexpected|fail|mismatch|unknown driver|not found|refus|not ready|not running|in use by"; then
    FAIL="${FAIL:+$FAIL, }$t"; return 1
  fi; return 0; }
# The options that live in liblp.so (after dvhook.sh on): at boot, and again whenever the player has loaded liblp anew
# (it unloads it while a disc plays and loads it at another address afterwards, without any of these patches).
lp_opts(){ [ -f $D/dvhook.sh ] || return 0
  # dv_mkv = off: no Dolby Vision from MKV (the player's own way); everything else dvhook does stays
  [ "$(opt dv_mkv)" = off ] && run dvhook "DV MKV off" sh $D/dvhook.sh dv off
  # native_25p, the liblp half: tell the player which MKV/MP4 videos are progressive (it takes HD 25/30 fps for interlaced)
  [ -f $D/vidopt.sh ] && [ "$(sh $D/vidopt.sh get native_25p $D/options.txt)" = on ] \
    && run video "25p/30p" sh -c "sh $D/dvhook.sh scan on | grep -v '^sites='"
  [ -n "$HVCC" ] && run dvhook "hvcC" sh $D/dvhook.sh hvcc on
  if [ -f $D/dvhook.sh ]; then   # hdr10plus = off: MKV as HDR10; dynamic_hdr = hdr10plus: before Dolby Vision when a file has both
    x=on; [ "$(opt hdr10plus)" = off ] && x=off; y=dv; [ "$(opt dynamic_hdr)" = hdr10plus ] && y=hdr10plus
    [ $x$y = ondv ] || run dvhook "HDR10+ options" sh -c "sh $D/dvhook.sh h10 $x $y | grep -v '^sites='"
  fi
  if [ -f $D/dvhook.sh ] && [ -f $D/languages.txt ]; then   # MP4 / MKV: which audio/subtitle tracks to keep (languages.txt)
    c=$(tr -d '\r' < $D/languages.txt | grep -v '^[[:space:]]*#' | awk 'NF{print $1}')
    [ -n "$c" ] && run dvhook "languages" sh $D/dvhook.sh langs $c
  fi
  [ -f $D/dvhook.sh ] && [ "$(opt forced_subs)" = on ] && run dvhook "forced subtitles" sh $D/dvhook.sh forced on   # MKV: forced subtitles only
  return 0; }
lpbase(){ grep liblp.so /proc/$P/maps 2>/dev/null | awk '$2=="r-xp"{split($1,a,"-"); print a[1]; exit}'; }
# relp: run by the liblp watcher (below, from /tmp) when liblp.so has gone or come back at another address
if [ "$1" = relp ]; then
  P=$(ps 2>/dev/null | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}'); [ -n "$P" ] || exit 0
  b=$(lpbase)
  if [ -z "$b" ]; then log "liblp: unloaded (a disc plays)"
  else
    log "liblp: loaded again at $b (or the splitter module)"
    # the splitter kernel module is unloaded and loaded again together with liblp: its patches (hvcC, MP4 stop, MP4
    # profile 7) are gone too. It can come back a moment after liblp.
    n=0; until grep -q '^splitter ' /proc/modules || [ $n -ge 10 ]; do sleep 1; n=$((n + 1)); done
    HVCC=; [ -f $D/hvccfix.sh ] && run hvccfix "hvcC" sh $D/hvccfix.sh on && HVCC=1
    [ -f $D/ftrfix.sh ] && run ftrfix "MP4 stop" sh $D/ftrfix.sh on
    [ -f $D/mp4elfix.sh ] && run mp4elfix "MP4 profile 7" sh $D/mp4elfix.sh on
    run dvhook "Dolby Vision MKV/MP4" sh $D/dvhook.sh on && lp_opts
    [ -f $D/subs.sh ] && run subs "subtitles" sh $D/subs.sh
    [ -n "$FAIL" ] && log "liblp: not everything is back: $FAIL"
  fi
  [ -f $D/xtmenu.sh ] && [ "$(opt setup_extras)" != off ] && run xtmenu "Setup page" sh $D/xtmenu.sh live
  exit 0
fi
# SMB2/SMB3 in the Network menu: first (it does not need the player, and the player looks for servers soon after it starts)
if [ -f $D/smbbr.sh ]; then
  if [ "$(opt smb23)" = off ]; then log "smb23: off (smb23 = off)"
  else run smb23 "SMB2/SMB3" sh $D/smbbr.sh on; fi
fi
n=0; while :; do
  P=$(ps 2>/dev/null | awk '$4 ~ /(^|\/)bdpprog\.1$/{print $1; exit}')
  [ -n "$P" ] && break
  n=$((n+1)); [ $n -gt 120 ] && { log "player not found"; exit 1; }; sleep 1
done
log "player pid $P"
if [ -n "$BT" ]; then   # bootmon.log: the player every 2 s for 180 s, from /tmp (no file of ours held on /mnt/ubi_boot)
  mv -f $D/bootmon.log $D/bootmon.log.1 2>/dev/null
  cat > /tmp/oppodv-bootmon.sh <<'EOM'
cd /; P=$1; O=$2; M=/proc/$P/mem; H=$((0x1c03a00))
kl(){ $DM | tr -cd '\11\12\40-\176' | grep .; }   # kernel log: printable, no empty lines
DM=dmesg; command -v dmesg >/dev/null || { DM=:; for b in /mnt/sda1/AutoScript/busybox /mnt/ubi_boot/oppo-dv-mkv-extras/*/busybox; do
  [ -x $b ] && mkdir -p /tmp/oppodv-bb && cp $b /tmp/oppodv-bb/busybox && { DM="/tmp/oppodv-bb/busybox dmesg"; break; }; done; }
rd32(){ dd if=$M bs=4 skip=$(($1 / 4)) count=1 2>/dev/null | hexdump -v -e '1/4 "%u"'; }
snap(){ for t in /proc/$P/task/*; do s=$(cat $t/stat 2>/dev/null) || continue; s=${s#*) }; set -- $s
  echo "${t##*/} $(( ${12} + ${13} )) $1 $(tr ' ' _ < $t/comm) $(cat $t/wchan 2>/dev/null)"; done; }
snap > /tmp/oppodv-bm.a; dl=$(kl | sed -n '$p'); i=0
while [ $i -lt 90 ]; do
  sleep 2; i=$((i + 1)); u=$(cut -d' ' -f1 /proc/uptime)
  if [ ! -d /proc/$P ]; then echo "$u player $P GONE" >> $O; sync; break; fi
  snap > /tmp/oppodv-bm.b
  top=$(awk 'NR==FNR{a[$1]=$2; next}{d=$2-a[$1]; if(d>0) print d, $4}' /tmp/oppodv-bm.a /tmp/oppodv-bm.b | sort -rn | head -3 | tr '\n' ' ')
  rd=$(awk '$3=="R"||$3=="D"{printf "%s:%s:%s ", $4, $3, $5}' /tmp/oppodv-bm.b)
  mv /tmp/oppodv-bm.b /tmp/oppodv-bm.a
  g=; [ "$(dd if=$M bs=1 skip=$H count=4 2>/dev/null | hexdump -v -e '4/1 "%02x"')" = 42445247 ] && g="gate asked $(rd32 $((H + 12))) answered $(rd32 $((H + 16))) timeouts $(rd32 $((H + 20)))"
  echo "$u thr $(ls /proc/$P/task | wc -l) top[$top] RD[$rd] $g" >> $O
  kl > /tmp/oppodv-bm.k; k=$(grep -n -F -x -- "$dl" /tmp/oppodv-bm.k | sed -n '$s/:.*//p')   # new kernel lines (the buffer is full)
  [ -n "$k" ] && sed -n "$((k + 1)),\$p" /tmp/oppodv-bm.k | head -6 | sed "s/^/$u dmesg: /" >> $O; dl=$(sed -n '$p' /tmp/oppodv-bm.k)
  sync
done
EOM
  sh /tmp/oppodv-bootmon.sh $P $D/bootmon.log </dev/null >/dev/null 2>&1 &
  log "boot debugging: boot.log, bootmon.log"
fi
# Auto Region: early, before a disc in the tray starts (its BD-J asks for the region through the hook's gate)
if [ -f $D/bdregion.sh ] && [ "$(opt bd_region)" = on ]; then
  a=$(abc); if [ -n "$a" ]; then log "bdregion: off ($a is installed and switches the region)"; else run bdregion "Auto Region" sh $D/bdregion.sh on; fi
fi
# video options at once (they patch the program itself, no library needed): the player picks its first HDMI output
# (home menu refresh) a few seconds after it starts and keeps it until something is played
[ -f $D/vidopt.sh ] && run video "video options" sh $D/vidopt.sh apply $D/options.txt   # 25p/30p, menu refresh, default language
n=0; until grep -q liblp.so /proc/$P/maps 2>/dev/null; do
  n=$((n+1)); [ $n -gt 120 ] && { log "player not ready"; exit 1; }; sleep 1
done
log "player ready"
[ -f $D/dvhook.sh ] && run dvhook "Dolby Vision MKV/MP4" sh $D/dvhook.sh on   # MKV Dolby Vision signalling (liblp)
[ -f $D/p7kel.sh ] && run p7kel "profile 7 decoder" sh $D/p7kel.sh on     # profile 7 decoder fixes (kernel)
[ -f $D/bgfix.sh ] && run bgfix "black bars" sh $D/bgfix.sh on            # black letterbox bars in Dolby Vision (kernel)
[ -f $D/sarfix.sh ] && run sarfix "pixel aspect" sh $D/sarfix.sh on       # non-square pixels stretched to ~16:9 (kernel)
[ -f $D/arflag.sh ] && run arflag "SD 4:3/16:9 flag" sh $D/arflag.sh on   # 4:3 / 16:9 flag of SD pictures in Source Direct (kernel)
[ -f $D/dvexit.sh ] && run dvexit "DV exit" sh $D/dvexit.sh on            # Dolby Vision left on after playback, black menu (kernel)
[ -f $D/dvcm.sh ] && run dvcm "DV metadata" sh $D/dvcm.sh on              # TV-led Dolby Vision: CM 2.9 / CM 4.0 metadata lost on the way to the TV (kernel)
[ -f $D/dvcm.sh ] && [ "$(opt dv_l5)" = off ] && run dvcm "L5 off" sh $D/dvcm.sh l5 off   # dv_l5 = off: no L5 to the TV, Oppo's way
HVCC=   # MKVs whose hvcC has no VPS/SPS/PPS (kernel); DV is signalled for them (lp_opts) only once it is on
[ -f $D/hvccfix.sh ] && run hvccfix "hvcC" sh $D/hvccfix.sh on && HVCC=1
[ -f $D/ftrfix.sh ] && run ftrfix "MP4 stop" sh $D/ftrfix.sh on           # hang at the next file after an MP4 with audio was stopped (kernel)
[ -f $D/mp4elfix.sh ] && run mp4elfix "MP4 profile 7" sh $D/mp4elfix.sh on   # profile 7 MP4s that stop after a second (kernel)
[ -f $D/hdr10p.sh ] && run hdr10p "HDR10+" sh $D/hdr10p.sh on              # HDR10+ lost at keyframes (kernel)
[ -f $D/audedid.sh ] && [ "$(opt audio_edid_override)" = on ] && run audedid "audio EDID override" sh $D/audedid.sh on
lp_opts
if [ -f $D/uopfree.sh ] && [ "$(opt uop_free)" = on ]; then   # remote keys where a disc prohibits them
  a=$(uopf); if [ -n "$a" ]; then log "uopfree: off ($a is installed)"; else run uopfree "UOP Free" sh $D/uopfree.sh on; fi
fi
[ -f $D/isomusic.sh ] && run isomusic "ISO under Music" sh $D/isomusic.sh on   # ISO files in the Music lists too (jailbreak programs)
[ -f $D/bdpaudec.db ] && log "audio: /res/bdpaudec.db -> $(ls -l /res/bdpaudec.db 2>/dev/null | sed 's/.*-> //')"   # set by the wrapper
[ -f $D/subs.sh ] && run subs "subtitles" sh $D/subs.sh                   # improved subtitles
[ -f $D/fpage.sh ] && run menu "factory menu" sh $D/fpage.sh on           # factory menu shortcut
if [ -f $D/dlnaiso.sh ]; then                                             # DLNA disc images (server + player hook)
  if [ "$(opt dlna_iso)" = off ]; then log "dlnaiso: off (dlna_iso = off)"
  else run dlnaiso "DLNA ISO" sh $D/dlnaiso.sh --boot; fi
fi
# the "Extras" page in Setup (the options above, changed on the player): before the boot message, which uses the same
# usleep hook for a moment. setup_extras = off leaves Oppo's Setup menu as it is.
if [ -f $D/xtmenu.sh ]; then
  if [ "$(opt setup_extras)" = off ]; then log "xtmenu: off (setup_extras = off)"
  else run xtmenu "Setup page" sh $D/xtmenu.sh on "$VERSION"; fi
fi
# external subtitles of disc images / Blu-ray folders: tags, LF line ends, several files (Title.en.srt ...). After
# the Extras page: the several-files code is mapped through its loader stub.
if [ -f $D/extsub.sh ]; then
  if [ "$(opt ext_subs)" = off ]; then log "extsub: off (ext_subs = off)"
  else run extsub "external subtitles" sh $D/extsub.sh on; fi
fi
# boot message: what loaded, in the player's own tip popup. A failure is always shown; "all loaded" unless
# boot_message = off. In the background: it waits until the popup has gone again (about 10 s).
if [ -f $D/bootmsg.sh ]; then
  if [ -n "$FAIL" ]; then m="oppo-dv-mkv: NOT loaded: $FAIL (see dvmkv.log)"
  elif [ "$(opt boot_message)" != off ]; then m="OPPO-DV-MKV $VERSION\nby Vitor Dall'Acqua"; else m=; fi
  [ -n "$FAIL" ] && log "not loaded: $FAIL"
  [ -n "$m" ] && ( sh $D/bootmsg.sh show "$m" 10000 2>&1 | while read l; do log "message: $l"; done ) &
fi
# liblp.so watcher: the player unloads liblp (and the splitter kernel module) while a disc plays and loads them again
# afterwards, liblp at another address, both without our patches; then "dvmkv.sh relp" puts them back (and tells the Extras page where its bytes are now). From a
# copy in /tmp and with no file open: nothing of ours may hold /mnt/ubi_boot while the player is switched off.
if [ -f $D/dvhook.sh ] && [ -z "$OPPODV_D" ]; then
  cat > /tmp/oppodv-lpwatch.sh <<'EOW'
cd /; P=$1; D=$2
lpb(){ grep liblp.so /proc/$P/maps 2>/dev/null | awk '$2=="r-xp"{print $1; exit}'; awk '$1=="splitter"{print $6}' /proc/modules; }
last=$(lpb)
while [ -d /proc/$P ]; do
  sleep 1; b=$(lpb); [ "$b" = "$last" ] && continue
  last=$b; OPPODV_D=$D sh $D/dvmkv.sh relp >> $D/dvmkv.log 2>&1
done
EOW
  sh /tmp/oppodv-lpwatch.sh $P $D </dev/null >/dev/null 2>&1 &
  log "liblp watcher: started"
fi
# extras: separate add-ons, each in its own folder (README: Extras). Started in the background so a slow or stuck
# one never holds up the others or the health mark; a "disable" file in its folder skips it.
for x in ${OPPODV_EXTRAS:-/mnt/ubi_boot/oppo-dv-mkv-extras}/*/start.sh; do
  [ -f "$x" ] || continue; xd=${x%/start.sh}; n=${xd##*/}
  [ -e "$xd/disable" ] && { log "$n: skipped (disable file)"; continue; }
  ( sh "$x" 2>&1 | while read l; do log "$n: $l"; done ) &
done
sleep 90; [ -d /proc/$P ] && { rm -f $D/bootcount; sync; log "boot marked healthy"; }
