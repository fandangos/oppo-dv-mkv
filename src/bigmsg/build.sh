#!/bin/sh
# build: nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm -c sh build.sh   ->  build/bigmsg.bin (load at 0x1c07c00)
set -e
BASE=${1:-0x1c07c00}
cd "$(dirname "$0")"; mkdir -p build
zig cc -target thumb-freestanding-eabi -mcpu=cortex_a9 -mthumb -Os -ffreestanding -fno-builtin -fno-pic \
  -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -c bigmsg.c -o build/bigmsg.o
sed "s/0x1c07c00;/$BASE;/" link.ld > build/link.ld
ld.lld -static -T build/link.ld build/bigmsg.o -o build/bigmsg.elf 2>/dev/null
llvm-objcopy -O binary build/bigmsg.elf build/bigmsg.bin
U=$(llvm-nm -u build/bigmsg.elf); [ -z "$U" ] || { echo "undefined symbols: $U"; exit 1; }
llvm-nm -n build/bigmsg.elf
ls -l build/bigmsg.bin; md5sum build/bigmsg.bin
