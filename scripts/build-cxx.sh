#!/bin/sh
# Add libc++, libc++abi and libunwind to a sysroot from build-win9x.sh, for
# C++ programs on Windows 2000 and XP (and later).
#
#   LLVM_SRC  llvm-project checkout with the Windows 2000/XP changes to libc++
#             and libunwind (clang-dos/llvm)
#   BIN       directory with clang, llvm-ar, llvm-ranlib, llvm-nm
#   SYSROOT   sysroot from build-win9x.sh, built with WINNT=0x0500 or later
#             and the default msvcrt.dll
#   WORK      build directory (default: ./build-win32-cxx)
#   CPU       -march for the libraries (default: i686)
#
# The libraries are static. They use emulated TLS, like programs for
# versions before Vista (see ../README.md), and the threading and locale code
# for a Windows and msvcrt.dll without SRW locks, condition variables and _l
# functions, chosen by the sysroot's _WIN32_WINNT.
#
# Use it with:
#   clang++ --target=i686-pc-windows5.1-gnu --sysroot=$SYSROOT \
#     -fuse-ld=lld -stdlib=libc++ hello.cpp -o hello.exe
set -e
: "${LLVM_SRC:?set LLVM_SRC}" "${BIN:?set BIN}" "${SYSROOT:?set SYSROOT}"
WORK=${WORK:-$PWD/build-win32-cxx}
CPU=${CPU:-i686}
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
SYSROOT=$(cd "$SYSROOT" && pwd)

TARGET=i686-w64-windows-gnu
FLAGS="-march=$CPU --sysroot=$SYSROOT -femulated-tls"
# clang turns sized deallocation off for MinGW, but libc++'s
# memory_resource.cpp calls the sized aligned operator delete.
CXXFLAGS="$FLAGS -fsized-deallocation"
cmake -G Ninja -S "$LLVM_SRC/runtimes" -B "$WORK" \
  -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
  -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SYSROOT" \
  -DCMAKE_C_COMPILER="$BIN/clang" -DCMAKE_CXX_COMPILER="$BIN/clang++" \
  -DCMAKE_ASM_COMPILER="$BIN/clang" \
  -DCMAKE_C_COMPILER_TARGET=$TARGET -DCMAKE_CXX_COMPILER_TARGET=$TARGET \
  -DCMAKE_ASM_COMPILER_TARGET=$TARGET \
  -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCMAKE_ASM_FLAGS="$FLAGS" \
  -DCMAKE_C_COMPILER_WORKS=TRUE -DCMAKE_CXX_COMPILER_WORKS=TRUE \
  -DCMAKE_AR="$BIN/llvm-ar" -DCMAKE_RANLIB="$BIN/llvm-ranlib" \
  -DCMAKE_NM="$BIN/llvm-nm" \
  -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
  -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_LIBDIR_SUFFIX="" \
  -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXX_HAS_WIN32_THREAD_API=ON -DLIBCXX_LIBDIR_SUFFIX="" \
  -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_INSTALL_MODULES=OFF -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
  >"$WORK/cmake.log"
ninja -C "$WORK" >"$WORK/build.log"
ninja -C "$WORK" install >/dev/null

# clang links -lgcc_s (or -lgcc_eh with -static-libgcc) for C++ on MinGW;
# the static libunwind takes their place.
cp "$SYSROOT/lib/libunwind.a" "$SYSROOT/lib/libgcc_eh.a"
cp "$SYSROOT/lib/libunwind.a" "$SYSROOT/lib/libgcc_s.a"

echo "libc++ installed in $SYSROOT"
