#!/bin/sh
# Build a sysroot whose C library is picolibc instead of msvcrt.dll or
# crtdll.dll, for every 32-bit Windows: 95, 98, ME and NT 3.1 and later.
# Programs import only kernel32.dll (and what they use themselves) and need
# no C runtime DLL. libc++ is built on picolibc, so C++ gets picolibc's
# C99/C11 printf, long double, wide characters and locale functions, which
# msvcrt.dll lacks.
#
#   LLVM_SRC      clang-dos/llvm checkout
#   MINGW_SRC     mingw-w64 checkout (the Windows API headers and import
#                 libraries; its C library headers and CRT are left out)
#   PICOLIBC_SRC  clang-dos/picolibc checkout (with libos/win32)
#   BIN           directory with clang, llvm-ar, llvm-ranlib, llvm-dlltool,
#                 llvm-nm
#   SYSROOT       output sysroot
#   WORK          build directory (default: ./build-picolibc)
#   CPU           -march for the libraries (default: i386)
#
# Use it with cfg/win32-picolibc.cfg, or:
#   clang --target=i386-pc-windows4.0-gnu --sysroot=$SYSROOT -fuse-ld=lld \
#     -fno-emulated-tls -nostartfiles -nodefaultlibs hello.c \
#     -lc -lclang_rt.builtins-i386 -lkernel32 -o hello.exe
set -e
: "${LLVM_SRC:?set LLVM_SRC}" "${MINGW_SRC:?set MINGW_SRC}" \
  "${PICOLIBC_SRC:?set PICOLIBC_SRC}" "${BIN:?set BIN}" "${SYSROOT:?set SYSROOT}"
here=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$PWD/build-picolibc}
CPU=${CPU:-i386}
mkdir -p "$WORK" "$SYSROOT"
WORK=$(cd "$WORK" && pwd)
SYSROOT=$(cd "$SYSROOT" && pwd)
PATH=$BIN:$PATH
export PATH

# The Windows API headers, import libraries and compiler-rt builtins come
# from a Windows 95 sysroot (_WIN32_WINNT 0x0400, so programs and libc++
# take the paths that work on every version).
base=$WORK/base
rm -rf "$base"
SYSROOT=$base WORK=$WORK/base-build CPU=$CPU sh "$here/build-win9x.sh"

# Headers: mingw-w64's, without its C library headers, with picolibc's.
# mingw-w64's API headers include a few of the C library's internal
# headers, which stay.
rm -rf "$SYSROOT/include"
cp -R "$base/include" "$SYSROOT/include"
keep=" _mingw.h _mingw_mac.h _mingw_secapi.h _mingw_unicode.h _mingw_off_t.h
 _mingw_stat64.h _bsd_types.h _timeval.h corecrt.h crtdefs.h excpt.h
 vadefs.h intrin.h _mingw_stdarg.h "
keep=" $(echo $keep) "
(cd "$MINGW_SRC/mingw-w64-headers/crt" &&
  find . -type f \( -name '*.h' -o -name '*.h.in' \)) | sed 's|^\./||; s|\.in$||' |
  while read -r h; do
    case $keep in *" $h "*) continue ;; esac
    rm -f "$SYSROOT/include/$h"
  done
# Where those headers would disagree with picolibc's: time_t and off_t are
# 64 bits, and mbstate_t is picolibc's. stralign.h calls wcscpy, which
# mingw-w64's string.h declares and picolibc's wchar.h does.
sub() {
  python3 - "$1" "$2" "$3" <<'EOF'
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
if old not in s:
    sys.exit("%s: %r not found" % (p, old))
open(p, "w").write(s.replace(old, new, 1))
EOF
}
sub "$SYSROOT/include/_mingw.h" \
  ' && !(defined (_TIME_BITS) && _TIME_BITS == 64)' \
  ' && 0 /* picolibc: time_t is 64-bit */'
sub "$SYSROOT/include/corecrt.h" '  typedef int mbstate_t;' \
  '#include <sys/_types.h>
  typedef __mbstate_t mbstate_t;'
sub "$SYSROOT/include/_mingw_off_t.h" \
  '#if (defined(_FILE_OFFSET_BITS) && (_FILE_OFFSET_BITS == 64))' \
  '#if 1 /* picolibc: off_t is 64-bit */'
sub "$SYSROOT/include/stralign.h" '#define __STRALIGN_H_' \
  '#define __STRALIGN_H_
#include <wchar.h> /* picolibc: wcscpy is not in string.h */'

# Libraries: the import libraries and builtins, without mingw-w64's C
# runtime (the CRT DLLs' import libraries, libmingw*, libm and crt*.o).
mkdir -p "$SYSROOT/lib"
for f in "$base"/lib/*.a; do
  case ${f##*/} in
  libmsvcr*.a | libucrt*.a | libcrtdll.a | libntdllcrt.a | libmingw*.a | \
    libmoldname.a | libm.a | libgcc*.a | libpthread.a | libwinpthread*.a) ;;
  *) cp "$f" "$SYSROOT/lib/" ;;
  esac
done

# picolibc with libos/win32.
cross=$WORK/cross-picolibc.txt
sed "s|'clang', '--target=i386-pc-windows4.0-gnu', '-march=i386'|'$BIN/clang', '--target=i386-pc-windows4.0-gnu', '-march=$CPU'|;
     s|^ar = 'llvm-ar'|ar = '$BIN/llvm-ar'|; s|^nm = 'llvm-nm'|nm = '$BIN/llvm-nm'|;
     s|^strip = 'llvm-strip'|strip = '$BIN/llvm-strip'|" \
  "$PICOLIBC_SRC/scripts/cross-clang-i386-windows.txt" >"$cross"
rm -rf "$WORK/picolibc" "$WORK/picolibc-install"
meson setup "$WORK/picolibc" "$PICOLIBC_SRC" --cross-file "$cross" \
  -Dc_std=c11 -Dos-win32=true -Denable-malloc=false -Dinitfini-array=false \
  -Dmultilib=false -Dpicocrt=false -Dsemihost=false -Dtests=false \
  -Dspecsdir=none -Dposix-console=true -Dmb-capable=true -Dio-wchar=true \
  -Dio-pos-args=true -Dio-long-double=true \
  --prefix="$WORK/picolibc-install" >"$WORK/picolibc-setup.log"
ninja -C "$WORK/picolibc" install >"$WORK/picolibc-build.log"
cp -R "$WORK/picolibc-install/include/." "$SYSROOT/include/"
cp "$WORK/picolibc-install/lib/libc.a" "$WORK/picolibc-install/lib/libm.a" \
  "$SYSROOT/lib/"

# libc++, libc++abi and libunwind on picolibc.
WORK=$WORK/cxx CPU=$CPU LIBC=picolibc SYSROOT=$SYSROOT sh "$here/build-cxx.sh"
rm -f "$SYSROOT/lib/libgcc_eh.a" "$SYSROOT/lib/libgcc_s.a"

# picolibc's licence, with the others build-sysroot.sh adds.
mkdir -p "$SYSROOT/share/licenses"
cp "$PICOLIBC_SRC/COPYING.picolibc" "$SYSROOT/share/licenses/picolibc-COPYING"
echo "picolibc sysroot built in $SYSROOT"
