#!/bin/sh
# build: nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm -c sh build.sh   ->  build/bdhook.bin (load at 0x1c03a00)
set -e
cd "$(dirname "$0")"; mkdir -p build
zig cc -target thumb-freestanding-eabi -mcpu=cortex_a9 -mthumb -Os -ffreestanding -fno-builtin -fno-pic \
  -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -c hook.c -o build/hook.o
zig cc -target arm-freestanding-eabi -mcpu=cortex_a9 -c gate.S -o build/gate.o
ld.lld -static -T link.ld build/gate.o build/hook.o -o build/bdhook.elf 2>/dev/null
llvm-objcopy -O binary build/bdhook.elf build/bdhook.bin
U=$(llvm-nm -u build/bdhook.elf); [ -z "$U" ] || { echo "undefined symbols: $U"; exit 1; }
llvm-nm -n build/bdhook.elf | tee build/bdhook.sym
ls -l build/bdhook.bin; md5sum build/bdhook.bin
s=$(stat -c %s build/bdhook.bin); [ $s -le 1536 ] || { echo "too big: $s"; exit 1; }
