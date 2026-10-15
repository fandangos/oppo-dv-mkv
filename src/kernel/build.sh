#!/bin/sh
# Builds build/elfix.bin (kernel patch blob). Needs zig (cc), lld and llvm (nix: nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm)
set -e
cd "$(dirname "$0")"; mkdir -p build
F="-target arm-freestanding-eabi -mcpu=cortex_a9 -marm -Oz -ffreestanding -fno-builtin -fno-pic -fno-unwind-tables -fno-asynchronous-unwind-tables"
# The installer ships elfix-ru and relocates its data addresses by the offset it measures on the player. The other
# builds are compiled to check that relocation: USA (global data +0x90), a third build seen in the field (+0x50), and
# a probe (+0x1000) from which mkkinst.py finds the relocated words.
for v in ru:0 us:0x90 d50:0x50 rel:0x1000; do
  n=${v%%:*}; o=build/elfix-$n
  zig cc $F -DDSHIFT=${v#*:} -c elfix.c -o $o.o
  zig cc $F -DDSHIFT=${v#*:} -c entry.S -o $o-entry.o
  ld.lld -static -T link.ld $o-entry.o $o.o -o $o.elf
  llvm-objcopy -O binary -j .text -j .data $o.elf $o.bin           # cave 1: _FbmCli_Test_4K
  llvm-objcopy -O binary -j .cave2 -j .cave2d $o.elf $o-c2.bin     # cave 2: _Cmd_ImgResz_TestPerformance
  TEXT=$(llvm-size -A $o.elf | awk '$1==".text"{print $2}')
  [ "$TEXT" -le $((0x7e98c748 - 0x7e98be80)) ] || { echo "code does not fit the cave"; exit 1; }
  [ $(stat -c %s $o-c2.bin) -le 1376 ] || { echo "code does not fit cave 2"; exit 1; }
done
cp build/elfix-ru.bin build/elfix.bin; cp build/elfix-ru.elf build/elfix.elf
md5sum build/elfix-*.bin
