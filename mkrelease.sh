#!/bin/sh
# Build everything and assemble the release zips in dist/.
# Needs: zig, lld, llvm, python3, zip   (nix shell nixpkgs#zig nixpkgs#lld nixpkgs#llvm nixpkgs#zip)
set -e
cd "$(dirname "$0")"
V=${1:-$(cat VERSION)}
src/kernel/build.sh; src/liblp/build.sh
python3 src/kernel/mkkinst.py; python3 src/liblp/mkinstall.py
rm -rf dist; mkdir -p dist
mk(){  # $1 = zip name, $2 = uninstall flag
  T=dist/stage; rm -rf $T; mkdir -p $T/AutoScript/oppo-dv-mkv
  cp installer/AutoScript/AutoScript.TSS $T/AutoScript/
  sed "s/@VERSION@/$V/" installer/AutoScript/install.sh > $T/AutoScript/install.sh
  cp installer/payload/bdpprog installer/payload/dvmkv.sh src/liblp/build/dvhook.sh src/kernel/build/p7kel.sh $T/AutoScript/oppo-dv-mkv/
  (cd $T/AutoScript/oppo-dv-mkv && md5sum bdpprog dvmkv.sh dvhook.sh p7kel.sh > MD5SUMS)
  [ -n "$2" ] && echo "Presence of this file makes install.sh UNINSTALL oppo-dv-mkv." > $T/AutoScript/UNINSTALL
  cp installer/README.txt $T/
  (cd $T && zip -qrX ../$1 .)
  rm -rf $T
}
mk oppo-dv-mkv-$V.zip
mk oppo-dv-mkv-$V-uninstall.zip 1
(cd dist && sha256sum *.zip > SHA256SUMS)
ls -l dist; cat dist/SHA256SUMS
