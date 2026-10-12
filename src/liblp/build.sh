#!/bin/sh
# Builds build/dvhook.bin (liblp.so patch blob, Thumb C + ARM shims). Same toolchain as ../kernel/build.sh
set -e
cd "$(dirname "$0")"; mkdir -p build
F="-mcpu=cortex_a9 -Os -ffreestanding -fno-builtin -fno-pic -fno-unwind-tables -fno-asynchronous-unwind-tables"
zig cc -target thumb-freestanding-eabi $F -c dvhook.c -o build/dvhook.o
zig cc -target arm-freestanding-eabi $F -c shims.S -o build/shims.o
ld.lld -static -T link.ld build/shims.o build/dvhook.o -o build/dvhook.elf
llvm-objcopy -O binary build/dvhook.elf build/dvhook.bin
[ $(stat -c %s build/dvhook.bin) -le 1024 ] || { echo "blob does not fit the cave"; exit 1; }
md5sum build/dvhook.bin
