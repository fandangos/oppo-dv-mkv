#!/bin/sh
# Build everything and assemble the release zips in dist/.
# Needs: zig, lld, llvm, python3, zip   (nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm nixpkgs#zip)
set -e
cd "$(dirname "$0")"
V=${1:-$(cat VERSION)}
src/kernel/build.sh; src/liblp/build.sh
python3 src/kernel/mkkinst.py; python3 src/liblp/mkinstall.py
rm -rf dist; mkdir -p dist
mk(){  # $1 = zip name, $2 = flag file (UNINSTALL / CHECKONLY) or empty
  T=dist/stage; rm -rf $T; mkdir -p $T/AutoScript/oppo-dv-mkv
  cp installer/AutoScript/AutoScript.TSS $T/AutoScript/
  sed "s/@VERSION@/$V/" installer/AutoScript/install.sh > $T/AutoScript/install.sh
  cp installer/payload/bdpprog installer/payload/dvmkv.sh src/liblp/build/dvhook.sh src/kernel/build/p7kel.sh \
     src/subtitles/subs.sh $T/AutoScript/oppo-dv-mkv/
  for q in 09 11 18 19 20 21 22 23; do cp src/subtitles/squares/new$q.png $T/AutoScript/oppo-dv-mkv/sq$q.png; done
  (cd $T/AutoScript/oppo-dv-mkv && md5sum bdpprog dvmkv.sh dvhook.sh p7kel.sh subs.sh sq*.png > MD5SUMS)
  case "$2" in
    UNINSTALL) echo "Presence of this file makes install.sh UNINSTALL oppo-dv-mkv." > $T/AutoScript/UNINSTALL;;
    CHECKONLY) echo "Presence of this file makes install.sh only write a compatibility report (no changes)." > $T/AutoScript/CHECKONLY;;
  esac
  cp installer/README.txt $T/
  (cd $T && zip -qrX ../$1 .)
  rm -rf $T
}
mk oppo-dv-mkv-$V.zip
mk oppo-dv-mkv-$V-uninstall.zip UNINSTALL
mk oppo-dv-mkv-$V-check.zip CHECKONLY
(cd dist && sha256sum *.zip > SHA256SUMS)
ls -l dist; cat dist/SHA256SUMS
