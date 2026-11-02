#!/bin/sh
# Build one of the 32 and 64-bit Windows sysroots of the clang-dos toolchain
# package with the clang-dos tools in BIN.
#
#   build-sysroot.sh NAME OUTPUT
#
#   NAME            win9x-msvcrt    95/98/ME and NT 4.0 (msvcrt.dll), libunicows
#                   win9x-crtdll    NT 3.x, Win32s and bare 95 (crtdll.dll)
#                   win2k-xp        2000/XP with libc++, libc++abi, libunwind
#                   win-vista       Vista to 11, 32-bit, with libc++
#                   win-vista-x64   the same, 64-bit
#   OUTPUT          the sysroot directory
#   BIN             directory with clang, llvm-ar and so on
#   LLVM_SRC        clang-dos/llvm checkout
#   MINGW_SRC       mingw-w64 checkout
#   LIBUNICOWS_SRC  unpacked libunicows-1.1.2-src.tar.gz (win9x-msvcrt)
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
  ;;
win9x-crtdll)
  CRT=crtdll sh "$here/scripts/build-win9x.sh"
  ;;
win2k-xp)
  WINNT=0x0500 CPU=i586 sh "$here/scripts/build-win9x.sh"
  WORK=$WORK/cxx CPU=i586 sh "$here/scripts/build-cxx.sh"
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
echo "sysroot $name built in $SYSROOT"
