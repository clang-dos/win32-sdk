#!/bin/sh
# Build one of the 32 and 64-bit Windows sysroots of the clang-dos toolchain
# package with the clang-dos tools in BIN.
#
#   build-sysroot.sh NAME OUTPUT
#
#   NAME            win9x-msvcrt    95/98/ME and NT 4.0 (msvcrt.dll), libunicows,
#                                   libc++
#                   win9x-crtdll    NT 3.x, Win32s and bare 95 (crtdll.dll),
#                                   libc++
#                   win2k-xp        2000/XP with libc++, libc++abi, libunwind
#                   win32-picolibc  95/98/ME and NT 3.1 on with picolibc as the C
#                                   library (no C runtime DLL), libc++
#                   win-vista       Vista to 11, 32-bit, with libc++
#                   win-vista-x64   the same, 64-bit
#   OUTPUT          the sysroot directory
#   BIN             directory with clang, llvm-ar and so on
#   LLVM_SRC        clang-dos/llvm checkout
#   MINGW_SRC       mingw-w64 checkout
#   LIBUNICOWS_SRC  unpacked libunicows-1.1.2-src.tar.gz (win9x-msvcrt)
#   PICOLIBC_SRC    clang-dos/picolibc checkout (win32-picolibc)
#   WORK            build directory (default: ./build-sysroot-NAME)
set -e
name=${1:?usage: build-sysroot.sh NAME OUTPUT} out=${2:?}
: "${BIN:?set BIN}" "${LLVM_SRC:?set LLVM_SRC}" "${MINGW_SRC:?set MINGW_SRC}"
here=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$PWD/build-sysroot-$name}
mkdir -p "$out" "$WORK"
SYSROOT=$(cd "$out" && pwd) WORK=$(cd "$WORK" && pwd)
export BIN LLVM_SRC MINGW_SRC SYSROOT WORK
PATH=$BIN:$PATH
export PATH
case $name in
win9x-msvcrt)
  : "${LIBUNICOWS_SRC:?set LIBUNICOWS_SRC}"
  export LIBUNICOWS_SRC
  sh "$here/scripts/build-win9x.sh"
  WORK=$WORK/unicows sh "$here/scripts/build-unicows.sh"
  WORK=$WORK/cxx CPU=i386 sh "$here/scripts/build-cxx.sh"
  ;;
win9x-crtdll)
  CRT=crtdll sh "$here/scripts/build-win9x.sh"
  WORK=$WORK/cxx CPU=i386 sh "$here/scripts/build-cxx.sh"
  ;;
win2k-xp)
  WINNT=0x0500 CPU=i586 sh "$here/scripts/build-win9x.sh"
  WORK=$WORK/cxx CPU=i586 sh "$here/scripts/build-cxx.sh"
  ;;
win32-picolibc)
  : "${PICOLIBC_SRC:?set PICOLIBC_SRC}"
  export PICOLIBC_SRC
  sh "$here/scripts/build-picolibc.sh"
  ;;
win-vista)
  ARCH=i686 sh "$here/scripts/build-modern-sysroot.sh"
  ;;
win-vista-x64)
  ARCH=x86_64 sh "$here/scripts/build-modern-sysroot.sh"
  ;;
*)
  echo "unknown sysroot $name" >&2; exit 1 ;;
esac
# The licences of what the sysroot holds, so that it can be passed on as it
# is: this SDK, mingw-w64 (headers, CRT, import libraries) and LLVM
# (compiler-rt builtins, libc++, libc++abi, libunwind).
lic=$SYSROOT/share/licenses
mkdir -p "$lic/mingw-w64"
cp "$here/LICENSE" "$lic/win32-sdk-LICENSE"
for f in COPYING COPYING.MinGW-w64 COPYING.MinGW-w64-runtime DISCLAIMER \
         DISCLAIMER.PD; do
  if [ -f "$MINGW_SRC/$f" ]; then cp "$MINGW_SRC/$f" "$lic/mingw-w64/"; fi
done
for f in COPYING.MinGW-w64/COPYING.MinGW-w64.txt \
         COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt; do
  if [ -f "$MINGW_SRC/$f" ]; then cp "$MINGW_SRC/$f" "$lic/mingw-w64/"; fi
done
cp "$LLVM_SRC/llvm/LICENSE.TXT" "$lic/LLVM-LICENSE.TXT"
if [ -f "$SYSROOT/share/doc/libunicows/license.txt" ]; then
  cp "$SYSROOT/share/doc/libunicows/license.txt" "$lic/libunicows-LICENSE.txt"
fi
cp "$here/NOTICE.md" "$lic/README.md"
echo "sysroot $name built in $SYSROOT"
