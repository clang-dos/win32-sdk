#!/bin/sh
# Build libunicows (https://libunicows.sourceforge.net, MIT license) into a
# Windows 9x sysroot, for Unicode builds that run on 9x through unicows.dll.
#
#   LIBUNICOWS_SRC  unpacked libunicows-1.1.2-src.tar.gz
#   BIN             directory with clang and llvm-ar
#   SYSROOT         sysroot from build-win9x.sh
#   WORK            build directory (default: ./build-unicows)
#   CPU             -march (default: i386)
#
# It needs nasm. Link programs with -lunicows (see ../README.md).
set -e
: "${LIBUNICOWS_SRC:?set LIBUNICOWS_SRC}" "${BIN:?set BIN}" \
  "${SYSROOT:?set SYSROOT}"
WORK=${WORK:-$PWD/build-unicows}
CPU=${CPU:-i386}
mkdir -p "$WORK"
CC="$BIN/clang --target=i686-w64-windows-gnu -march=$CPU --sysroot=$SYSROOT"
src=$LIBUNICOWS_SRC/src

for f in unicows_import unicows_vars0; do
  $CC -O2 -c "$src/$f.c" -o "$WORK/$f.o"
done
nasm -f win32 -I"$src/" -o "$WORK/unicows_mutex.o" "$src/unicows_mutex.asm"
# One object per function, so that a program pulls in only what it calls.
for f in "$src"/gen_asm/mslu*.asm; do
  nasm -f win32 -I"$src/" -o "$WORK/$(basename "$f" .asm).o" "$f"
done
rm -f "$SYSROOT/lib/libunicows.a"
"$BIN/llvm-ar" rcs "$SYSROOT/lib/libunicows.a" "$WORK"/*.o
mkdir -p "$SYSROOT/share/doc/libunicows"
cp "$LIBUNICOWS_SRC/docs/license.txt" "$SYSROOT/share/doc/libunicows/"
echo "libunicows installed in $SYSROOT/lib"
