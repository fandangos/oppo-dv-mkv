#!/bin/sh
# build: nix shell nixpkgs#zig -c sh build.sh   ->  build/bdhdmv, build/bdregion, build/bdcallgraph (static ARM, the player)
set -e
cd "$(dirname "$0")"; mkdir -p build
for p in hdmv:bdhdmv detect:bdregion cg:bdcallgraph daemon:bdregiond; do
  zig cc -target arm-linux-musleabihf -mcpu=cortex_a9 -Os -Wall -Wextra -static -s -ffunction-sections -Wl,--gc-sections ${p%%:*}.c -o build/${p#*:}
done
ls -l build
