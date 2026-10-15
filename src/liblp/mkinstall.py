#!/usr/bin/env python3
# Generate build/dvhook.sh: RAM installer for build/dvhook.bin into the running player (bdpprog.1 / liblp.so md5 e39b358c...).
# dvhook.sh on|off|status. Checks liblp's md5, the 5 original call instructions and verifies the written blob.
import os, struct, subprocess
os.chdir(os.path.dirname(os.path.abspath(__file__)))
blob = open('build/dvhook.bin', 'rb').read()
syms = {}
for l in subprocess.run(['llvm-nm', 'build/dvhook.elf'], capture_output=True, text=True).stdout.split('\n'):
    p = l.split()
    if len(p) == 3: syms[p[2]] = int(p[0], 16)
def bl(src, dst):
    off = (dst - (src + 8)) >> 2
    assert -(1 << 23) <= off < (1 << 23)
    return struct.pack('<I', 0xeb000000 | (off & 0xffffff))
sites = [(0x3c57ec, 0x158dd8, 'h0_tracks'), (0x3c2ff0, 0x158dd8, 'h0_tracks'),
         (0x3c00d4, 0x16863c, 'h1_skip'), (0x3d252c, 0x163164, 'h2_mmed'), (0x3c99a4, 0x157f98, 'h3_vinfo')]
CAVE, ST, STLEN = 0x6cdc00, 0x757e00, 0x40
assert len(blob) <= 0x400   # cave = zero padding at the end of liblp's code segment
hx = lambda b: ''.join('\\x%02x' % c for c in b)
rows = []
for va, orig, h in sites:
    o = bl(va, orig)
    n = bl(va, syms[h]); rows.append((va, o.hex(), n.hex(), hx(o), hx(n)))
out = f'''#!/bin/sh
# oppo-dv-mkv: Dolby Vision from MKV (P5/P8 single layer, P7 BL+EL single track; dvcC/dvvC-detected) - RAM patch for liblp.so. usage: on|off|status
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
LIB_MD5=e39b358c5b0948933f49fd3099f81114
[ "$(md5sum /usr/local/lib/liblp.so | cut -d' ' -f1)" = $LIB_MD5 ] || {{ echo "liblp md5 mismatch"; exit 1; }}
P=$(ps | awk '$4 ~ /(^|\\/)bdpprog\\.1$/{{print $1; exit}}'); [ -n "$P" ] || {{ echo "no player"; exit 1; }}
B=$(grep liblp.so /proc/$P/maps | awk '$2=="r-xp"{{split($1,a,"-"); print a[1]; exit}}')
M=/proc/$P/mem; B=$((0x$B))
rd(){{ dd if=$M bs=1 skip=$1 count=$2 2>/dev/null | hexdump -v -e "$2/1 \\"%02x\\""; }}
w4(){{ printf "$2" | dd of=$M bs=4 seek=$(( $1 / 4 )) conv=notrunc 2>/dev/null; }}
SITES="{' '.join(f'{r[0]:#x}:{r[1]}:{r[2]}' for r in rows)}"
esc(){{ case $1 in {' '.join(f"{r[1]}) echo '{r[3]}';; {r[2]}) echo '{r[4]}';;" for r in rows)} esac; }}
state(){{ s=ok; for e in $SITES; do a=$((B + ${{e%%:*}})); r=${{e#*:}}; c=$(rd $a 4); [ "$c" = "${{r#*:}}" ] && continue; [ "$c" = "${{r%%:*}}" ] && {{ s=off; continue; }}; echo "site ${{e%%:*}} has unexpected $c"; return 2; done; echo $s; }}
case "$1" in
on)
  st=$(state) || {{ echo "$st"; exit 1; }}
  [ "$st" = ok ] && {{ echo "already on"; exit 0; }}
  for e in $SITES; do a=$((B + ${{e%%:*}})); r=${{e#*:}}; [ "$(rd $a 4)" = "${{r#*:}}" ] && w4 $a "$(esc ${{r%%:*}})"; done
  printf '{hx(blob)}' | dd of=$M bs=1 seek=$((B + {CAVE:#x})) conv=notrunc 2>/dev/null
  [ "$(rd $((B + {CAVE:#x})) {len(blob)})" = "{blob.hex()}" ] || {{ echo "blob verify failed"; exit 1; }}
  dd if=/dev/zero of=$M bs=1 seek=$((B + {ST:#x})) count={STLEN} conv=notrunc 2>/dev/null
  for e in $SITES; do a=$((B + ${{e%%:*}})); r=${{e#*:}}; w4 $a "$(esc ${{r#*:}})"; done
  echo "dvhook ON";;
off)
  for e in $SITES; do a=$((B + ${{e%%:*}})); r=${{e#*:}}; [ "$(rd $a 4)" = "${{r#*:}}" ] && w4 $a "$(esc ${{r%%:*}})"; done
  echo "dvhook OFF";;
esac
echo "sites=$(state) state=$(rd $((B + {ST:#x})) {STLEN})"
'''
open('build/dvhook.sh', 'w').write(out)
print('ok', [(hex(r[0]), r[1], r[2]) for r in rows])
