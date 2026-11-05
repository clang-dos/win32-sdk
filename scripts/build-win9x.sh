#!/bin/sh
# Build a Windows 95/98/ME sysroot for clang: mingw-w64 headers and CRT
# linked against the system msvcrt.dll, and compiler-rt builtins, all compiled
# for an 80486 without SSE, so they run on any 9x machine with a 486 or later.
#
#   LLVM_SRC   llvm-project checkout (for compiler-rt)
#   MINGW_SRC  mingw-w64 checkout (a recent one: older ones import functions
#              that 9x does not have)
#   BIN        directory with clang, llvm-ar, llvm-ranlib, llvm-dlltool, llvm-nm
#   SYSROOT    output sysroot
#   WORK       build directory (default: ./build-win9x)
#   CPU        -march for the libraries (default: i486; see README.md)
#   CRT        C runtime DLL: msvcrt (default) or crtdll, which every Windows
#              95 has (see ../README.md)
#   WINNT      default _WIN32_WINNT for the headers (default: 0x0400 for 95
#              and NT 4.0; 0x0500 for Windows 2000, 0x0501 for XP)
#
# Use it with:
#   clang --target=i586-pc-windows4.0-gnu --sysroot=$SYSROOT -fuse-ld=lld \
#     hello.c -o hello.exe
set -e
: "${LLVM_SRC:?set LLVM_SRC}" "${MINGW_SRC:?set MINGW_SRC}" \
  "${BIN:?set BIN}" "${SYSROOT:?set SYSROOT}"
WORK=${WORK:-$PWD/build-win9x}
CPU=${CPU:-i486}
CRT=${CRT:-msvcrt}
WINNT=${WINNT:-0x0400}
mkdir -p "$WORK" "$SYSROOT"
WORK=$(cd "$WORK" && pwd)
SYSROOT=$(cd "$SYSROOT" && pwd)

# The libraries are built with the plain MinGW triple and an explicit CPU, so
# that any clang can build them. Programs use the versioned triple.
TARGET=i686-w64-windows-gnu
CC="$BIN/clang --target=$TARGET -march=$CPU --sysroot=$SYSROOT -fuse-ld=lld"
TOOLS="AR=$BIN/llvm-ar RANLIB=$BIN/llvm-ranlib DLLTOOL=$BIN/llvm-dlltool"
TOOLS="$TOOLS NM=$BIN/llvm-nm"

# Headers. _WIN32_WINNT 0x0400 hides APIs newer than Windows 95 and NT 4.0.
# It also picks the libc++ code for Windows without Vista's synchronization
# functions and msvcrt.dll without locale objects (build-cxx.sh).
mkdir -p "$WORK/headers"
(cd "$WORK/headers" &&
  "$MINGW_SRC/mingw-w64-headers/configure" --host=i686-w64-mingw32 \
    --prefix="$SYSROOT" --with-default-win32-winnt=$WINNT \
    --with-default-msvcrt=$CRT >/dev/null &&
  make install >/dev/null)

# CRT and import libraries, against the C runtime DLL that ships with Windows.
mkdir -p "$WORK/crt"
(cd "$WORK/crt" &&
  env CC="$CC" CFLAGS="-O2" $TOOLS \
    "$MINGW_SRC/mingw-w64-crt/configure" --host=i686-w64-mingw32 \
    --prefix="$SYSROOT" --enable-lib32 --disable-lib64 --disable-libarm32 \
    --disable-libarm64 --with-default-msvcrt=$CRT >/dev/null &&
  make -j"$(nproc)" >/dev/null && make install >/dev/null)

# compiler-rt builtins, with the atomic functions: a 486 has no CMPXCHG8B,
# so 64-bit atomics (which libc++ uses) are calls to __atomic_load_8 and so
# on, which take a lock.
cmake -G Ninja -S "$LLVM_SRC/compiler-rt/lib/builtins" -B "$WORK/builtins" \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$BIN/clang" -DCMAKE_ASM_COMPILER="$BIN/clang" \
  -DCMAKE_C_COMPILER_TARGET=$TARGET -DCMAKE_ASM_COMPILER_TARGET=$TARGET \
  -DCMAKE_C_FLAGS="-march=$CPU --sysroot=$SYSROOT" \
  -DCMAKE_ASM_FLAGS="-march=$CPU --sysroot=$SYSROOT" \
  -DCMAKE_AR="$BIN/llvm-ar" -DCMAKE_RANLIB="$BIN/llvm-ranlib" \
  -DCMAKE_NM="$BIN/llvm-nm" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_OS_DIR=windows \
  -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=OFF \
  -DLLVM_CMAKE_DIR="$BIN/../lib/cmake/llvm" >/dev/null
ninja -C "$WORK/builtins" >/dev/null
builtins=$(find "$WORK/builtins/lib" -name 'libclang_rt.builtins*.a' | head -n 1)

# clang links -lgcc -lgcc_eh and crtbegin.o/crtend.o for C by default. The
# builtins take the place of libgcc; C needs nothing from the others.
cp "$builtins" "$SYSROOT/lib/libgcc.a"
cp "$builtins" "$SYSROOT/lib/libclang_rt.builtins-i386.a"
"$BIN/llvm-ar" rc "$SYSROOT/lib/libgcc_eh.a"
: > "$WORK/empty.c"
$CC -c "$WORK/empty.c" -o "$SYSROOT/lib/crtbegin.o"
$CC -c "$WORK/empty.c" -o "$SYSROOT/lib/crtend.o"

echo "Windows 9x sysroot installed in $SYSROOT"
