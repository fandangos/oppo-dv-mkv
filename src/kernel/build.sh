#!/bin/sh
# Builds build/elfix.bin (kernel patch blob). Needs zig (cc), lld and llvm (nix: nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm)
set -e
cd "$(dirname "$0")"; mkdir -p build
F="-target arm-freestanding-eabi -mcpu=cortex_a9 -marm -Oz -ffreestanding -fno-builtin -fno-pic -fno-unwind-tables -fno-asynchronous-unwind-tables"
zig cc $F -c elfix.c -o build/elfix.o
zig cc $F -c entry.S -o build/entry.o
ld.lld -static -T link.ld build/entry.o build/elfix.o -o build/elfix.elf
llvm-objcopy -O binary build/elfix.elf build/elfix.bin
TEXT=$(llvm-size -A build/elfix.elf | awk '$1==".text"{print $2}')
[ "$TEXT" -le $((0x7e98c648 - 0x7e98be80)) ] || { echo "code does not fit the cave"; exit 1; }
md5sum build/elfix.bin
