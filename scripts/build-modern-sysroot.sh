#!/bin/sh
# Build a mingw-w64 sysroot for Windows Vista and later: headers, CRT and
# import libraries, compiler-rt builtins, and static libc++, libc++abi and
# libunwind (native TLS).
#
#   LLVM_SRC, MINGW_SRC, BIN, SYSROOT, WORK as for build-win9x.sh
#   ARCH    i686 (default) or x86_64
#   CRT     msvcrt (default; every Vista and later has it) or ucrt
#   WINNT   default _WIN32_WINNT (default 0x0600, Vista)
set -e
: "${LLVM_SRC:?}" "${MINGW_SRC:?}" "${BIN:?}" "${SYSROOT:?}"
ARCH=${ARCH:-i686} CRT=${CRT:-msvcrt} WINNT=${WINNT:-0x0600}
WORK=${WORK:-$PWD/build-modern-$ARCH}
mkdir -p "$WORK" "$SYSROOT"
WORK=$(cd "$WORK" && pwd) SYSROOT=$(cd "$SYSROOT" && pwd)
TARGET=$ARCH-w64-windows-gnu
case $ARCH in
  i686) libs="--enable-lib32 --disable-lib64" rtarch=i386 ;;
  x86_64) libs="--disable-lib32 --enable-lib64" rtarch=x86_64 ;;
esac
CC="$BIN/clang --target=$TARGET --sysroot=$SYSROOT -fuse-ld=lld"
TOOLS="AR=$BIN/llvm-ar RANLIB=$BIN/llvm-ranlib DLLTOOL=$BIN/llvm-dlltool NM=$BIN/llvm-nm"

mkdir -p "$WORK/headers"
(cd "$WORK/headers" &&
  "$MINGW_SRC/mingw-w64-headers/configure" --host=$ARCH-w64-mingw32 \
    --prefix="$SYSROOT" --with-default-win32-winnt=$WINNT \
    --with-default-msvcrt=$CRT >/dev/null && make install >/dev/null)
mkdir -p "$WORK/crt"
(cd "$WORK/crt" &&
  env CC="$CC" CFLAGS="-O2" $TOOLS "$MINGW_SRC/mingw-w64-crt/configure" \
    --host=$ARCH-w64-mingw32 --prefix="$SYSROOT" $libs --disable-libarm32 \
    --disable-libarm64 --with-default-msvcrt=$CRT >/dev/null &&
  make -j"$(nproc)" >/dev/null && make install >/dev/null)

cmake -G Ninja -S "$LLVM_SRC/compiler-rt/lib/builtins" -B "$WORK/builtins" \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$BIN/clang" -DCMAKE_ASM_COMPILER="$BIN/clang" \
  -DCMAKE_C_COMPILER_TARGET=$TARGET -DCMAKE_ASM_COMPILER_TARGET=$TARGET \
  -DCMAKE_C_FLAGS="--sysroot=$SYSROOT" -DCMAKE_ASM_FLAGS="--sysroot=$SYSROOT" \
  -DCMAKE_AR="$BIN/llvm-ar" -DCMAKE_RANLIB="$BIN/llvm-ranlib" -DCMAKE_NM="$BIN/llvm-nm" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_OS_DIR=windows >/dev/null
ninja -C "$WORK/builtins" >/dev/null
builtins=$(find "$WORK/builtins/lib" -name 'libclang_rt.builtins*.a' | head -n 1)
cp "$builtins" "$SYSROOT/lib/libgcc.a"
cp "$builtins" "$SYSROOT/lib/libclang_rt.builtins-$rtarch.a"
"$BIN/llvm-ar" rc "$SYSROOT/lib/libgcc_eh.a"
: > "$WORK/empty.c"
$CC -c "$WORK/empty.c" -o "$SYSROOT/lib/crtbegin.o"
$CC -c "$WORK/empty.c" -o "$SYSROOT/lib/crtend.o"

FLAGS="--sysroot=$SYSROOT"
cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$WORK/cxx" \
  -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
  -DCMAKE_C_COMPILER="$BIN/clang" -DCMAKE_CXX_COMPILER="$BIN/clang++" \
  -DCMAKE_ASM_COMPILER="$BIN/clang" \
  -DCMAKE_C_COMPILER_TARGET=$TARGET -DCMAKE_CXX_COMPILER_TARGET=$TARGET \
  -DCMAKE_ASM_COMPILER_TARGET=$TARGET \
  -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS -fsized-deallocation" \
  -DCMAKE_ASM_FLAGS="$FLAGS" \
  -DCMAKE_C_COMPILER_WORKS=TRUE -DCMAKE_CXX_COMPILER_WORKS=TRUE \
  -DCMAKE_AR="$BIN/llvm-ar" -DCMAKE_RANLIB="$BIN/llvm-ranlib" -DCMAKE_NM="$BIN/llvm-nm" \
  -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
  -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_LIBDIR_SUFFIX="" \
  -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXX_HAS_WIN32_THREAD_API=ON -DLIBCXX_LIBDIR_SUFFIX="" \
  -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_INSTALL_MODULES=OFF -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
  >"$WORK/cxx-cmake.log"
ninja -C "$WORK/cxx" >"$WORK/cxx-build.log"
ninja -C "$WORK/cxx" install >/dev/null
cp "$SYSROOT/lib/libunwind.a" "$SYSROOT/lib/libgcc_eh.a"
cp "$SYSROOT/lib/libunwind.a" "$SYSROOT/lib/libgcc_s.a"
echo "Windows ($ARCH, $CRT, $WINNT) sysroot installed in $SYSROOT"
