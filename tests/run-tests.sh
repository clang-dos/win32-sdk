#!/bin/sh
# Build the Windows 9x tests, check their imports and run them under Wine.
#
#   BIN      directory with clang (with the Windows 9x triple support)
#   SYSROOT  sysroot from build-sysroot.sh or scripts/build-win9x.sh
#   DLLS     optional: one directory of system DLLs per Windows version, for
#            check-imports.py --dlls
#   WINE     optional: wine, to run the console tests (default: wine on PATH)
#   TARGETS  triples (default: 95, 98 and ME). Windows NT 3.x triples, such
#            as i386-pc-windows3.10-gnu, are checked for that NT version
#            (check-imports.py --nt) and run with Wine reporting Windows
#            NT 3.51; they need the crtdll sysroot. Windows 2000 and XP
#            triples (i586-pc-windows5.0-gnu, i586-pc-windows5.1-gnu) are
#            checked for that version and run with Wine reporting it; they
#            need a sysroot built with WINNT=0x0500 or later.
#   OPTS     optimization levels (default: O0 O2 Os)
#
# When the sysroot has libunicows.a (build-unicows.sh), the tests include a
# Unicode build linked with it. When it has libc++.a (build-cxx.sh), the
# tests include C++ programs. Wine reports the target's Windows version to
# each program (95, 98 or ME for the 4.x triples), so libc++ takes the paths
# it takes there.
: "${BIN:?set BIN}" "${SYSROOT:?set SYSROOT}"
here=$(cd "$(dirname "$0")" && pwd)
out=${WORK:-$PWD/build-win9x-tests}
mkdir -p "$out"
cd "$out" || exit 1
WINE=${WINE:-wine}
command -v "$WINE" >/dev/null 2>&1 || WINE=
export WINEDEBUG=${WINEDEBUG:--all}
pass=0
fail=0
tests="hello libc tchar gui"
# crtdll.dll has no wide C library (no wmain startup, no _wfopen).
wide=
"$BIN/llvm-nm" "$SYSROOT/lib/libmsvcrt.a" 2>/dev/null |
  grep -q __wgetmainargs && wide=1
[ -n "$wide" ] && [ -f "$SYSROOT/lib/libunicows.a" ] && tests="$tests unicode"

ok() { pass=$((pass + 1)); }
bad() {
  fail=$((fail + 1))
  echo "FAIL $1"
  sed 's/^/    /' "$1.log" | head -20
}

for target in ${TARGETS:-i386-pc-windows4.0-gnu i486-pc-windows4.10-gnu \
    i586-pc-windows4.90-gnu}; do
  # Windows NT 3.x, 2000 and later are checked as NT; 4.x is 9x.
  nt=
  winver=
  case $target in
    *-windows4.0-*) winver=win95 ;;
    *-windows4.10-*) winver=win98 ;;
    *-windows4.90-*) winver=winme ;;
    *-windows3.*) winver=nt351 ;;
    *-windows5.0*) winver=win2k ;;
    *-windows5.1*) winver=winxp ;;
    *-windows5.2*) winver=win2003 ;;
  esac
  case $target in
    *-windows3.* | *-windows5.*)
      nt=${target#*-windows}
      nt=--nt=${nt%%-*}
      ;;
  esac
  ttests=$tests
  [ -f "$SYSROOT/lib/libc++.a" ] && ttests="$ttests cxx threads fs tlsmain"
  for opt in ${OPTS:-O0 O2 Os}; do
    for t in $ttests; do
      name=$t-$target-$opt
      flags=
      cc="$BIN/clang"
      src=$here/$t.c
      [ $t = gui ] && flags=-mwindows
      [ $t = unicode ] && flags="-municode -lunicows"
      args=
      check=$name.exe
      case $t in
        cxx | threads | fs | tlsmain)
          cc="$BIN/clang++"
          src=$here/$t.cpp
          flags="-std=c++20 -stdlib=libc++"
          ;;
      esac
      # tlsmain loads a C++ DLL with thread_local variables at run time.
      if [ $t = tlsmain ]; then
        args=$name-dll.dll
        check="$check $args"
        if ! "$cc" --target=$target --sysroot="$SYSROOT" -fuse-ld=lld \
            -$opt $flags -shared "$here/tlsdll.cpp" -o $args \
            >$name.log 2>&1; then
          bad $name
          continue
        fi
      fi
      if ! "$cc" --target=$target --sysroot="$SYSROOT" -fuse-ld=lld \
          -$opt $flags "$src" -o $name.exe >$name.log 2>&1; then
        bad $name
        continue
      fi
      if ! python3 "$here/../tools/check-imports.py" ${DLLS:+--dlls "$DLLS"} $nt \
          $check >$name.log 2>&1; then
        bad $name
        continue
      fi
      case $t in
        hello) want="hello, world" ;;
        libc | tchar | unicode | cxx | threads | fs | tlsmain)
          want="ALL PASSED" ;;
        *) want= ;;
      esac
      if [ -n "$want" ] && [ -n "$WINE" ]; then
        # Wine has no NT 3.1 or 3.5; it reports NT 3.51 to the program.
        [ -n "$winver" ] && "$WINE" reg add \
          "HKCU\\Software\\Wine\\AppDefaults\\$name.exe" /v Version \
          /d $winver /f >/dev/null 2>&1
        if ! "$WINE" ./$name.exe $args >$name.log 2>&1 ||
            ! grep -q "$want" $name.log; then
          bad $name
          continue
        fi
      fi
      ok
    done
  done
done
# The checker must reject wide C library calls that fail on 9x.
if [ -n "$wide" ]; then
  printf '#include <stdio.h>\nint main(void) { return !_wfopen(L"x", L"r"); }\n' \
    >wfopen.c
  if "$BIN/clang" --target=i386-pc-windows4.0-gnu --sysroot="$SYSROOT" \
      -fuse-ld=lld wfopen.c -o wfopen.exe >wfopen.log 2>&1 &&
      ! python3 "$here/../tools/check-imports.py" wfopen.exe >>wfopen.log 2>&1 &&
      grep -q "_wfopen calls a Unicode stub" wfopen.log; then
    ok
  else
    bad wfopen
  fi
fi
# For NT 3.x the checker must reject later kernel32 functions.
case "${TARGETS:-}" in
  *-windows3.*)
    printf '#include <windows.h>\nint main(void) { return IsDebuggerPresent(); }\n' \
      >nt4only.c
    if "$BIN/clang" --target=i386-pc-windows3.51-gnu --sysroot="$SYSROOT" \
        -fuse-ld=lld nt4only.c -o nt4only.exe >nt4only.log 2>&1 &&
        ! python3 "$here/../tools/check-imports.py" --nt=3.51 nt4only.exe \
          >>nt4only.log 2>&1 &&
        grep -q "IsDebuggerPresent needs Windows NT 4.00" nt4only.log; then
      ok
    else
      bad nt4only
    fi
    ;;
esac
# For Windows 2000 and XP the checker must reject Vista's kernel32 and
# msvcrt.dll functions.
case "${TARGETS:-}" in
  *-windows5.*)
    printf '#include <windows.h>\nint main(void) { SRWLOCK l; InitializeSRWLock(&l); return 0; }\n' \
      >vista-k32.c
    printf '#include <stdlib.h>\n#include <locale.h>\nint main(void) { return (int)_strtod_l("1", 0, 0); }\n' \
      >vista-crt.c
    if "$BIN/clang" --target=i586-pc-windows5.1-gnu --sysroot="$SYSROOT" \
        -D_WIN32_WINNT=0x0600 -fuse-ld=lld vista-k32.c -o vista-k32.exe \
        >vista.log 2>&1 &&
        "$BIN/clang" --target=i586-pc-windows5.1-gnu --sysroot="$SYSROOT" \
        -fuse-ld=lld vista-crt.c -o vista-crt.exe >>vista.log 2>&1 &&
        ! python3 "$here/../tools/check-imports.py" --nt=5.1 vista-k32.exe \
          >>vista.log 2>&1 &&
        ! python3 "$here/../tools/check-imports.py" --nt=5.1 vista-crt.exe \
          >>vista.log 2>&1 &&
        grep -q "InitializeSRWLock needs Windows NT 6.00" vista.log &&
        grep -q "_strtod_l is in the msvcrt.dll of Windows Vista" vista.log; then
      ok
    else
      bad vista
    fi
    ;;
esac
[ -n "$WINE" ] || echo "note: wine not found, so the tests were built and checked but not run"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
