#!/bin/sh
# build: nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm -c sh build.sh
#   build/extsub.bin  (copied over the player's cue clean-up 0x93fc58)
#   build/extmulti.bin (several files per disc, loaded at 0x1b90000; its .bss is the zeroed rest of the region)
set -e
cd "$(dirname "$0")"; mkdir -p build
zig cc -target thumb-freestanding-eabi -mcpu=cortex_a9 -mthumb -Oz -ffreestanding -fno-builtin -fpic \
  -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -c extsub.c -o build/extsub.o
llvm-objcopy -O binary -j .text.extsub build/extsub.o build/extsub.bin
llvm-objdump -dr build/extsub.o | grep -cE "R_ARM|bl " | { read n; [ "$n" = 0 ] || { echo "relocations or calls: not position independent"; exit 1; }; }
s=$(stat -c %s build/extsub.bin); echo "extsub.bin $s bytes (room 142)"; [ $s -le 142 ] || { echo "too big"; exit 1; }
md5sum build/extsub.bin
F="-target thumb-freestanding-eabi -mcpu=cortex_a9 -mthumb -Os -ffreestanding -fno-builtin -fno-pic -fomit-frame-pointer
   -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -Wno-unused-function"
zig cc $F -c multi.c -o build/multi.o
zig cc -target thumb-freestanding-eabi -mcpu=cortex_a9 -c multi.S -o build/multis.o
ld.lld -static -T multi.ld build/multi.o build/multis.o -o build/extmulti.elf
U=$(llvm-nm -u build/extmulti.elf); [ -z "$U" ] || { echo "undefined symbols: $U"; exit 1; }
llvm-objcopy -O binary -j .text build/extmulti.elf build/extmulti.bin
llvm-size -A build/extmulti.elf | grep -E 'text|bss'
llvm-nm -n build/extmulti.elf | grep -E ' (es|es_setpath|t[1-8])$'
ls -l build/extmulti.bin; md5sum build/extmulti.bin
