#!/bin/sh
# Test import-ms-sdk.py without Microsoft's kits: make two small fake kits
# laid out as the NT 3.1 and NT 3.51 Win32 SDKs are (upper-case names, a C
# runtime library whose objects ask for /DEFAULTLIB:LIBC), import them into
# a fake package and build a program with a config file. The real kits are
# tested by hand (see README).
#
#   BIN=~/llvm/build/bin sh tests/ms-sdk/run-test.sh
set -e
: "${BIN:?set BIN}"
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
W=${WORK:-$(mktemp -d)}
sdks=$W/sdks pkg=$W/pkg
rm -rf "$sdks" "$pkg"
# The NT 3.1 kit has windows.h and the C runtime in one folder; the NT 3.51
# kit has its C runtime headers in a subfolder and no C runtime library, so
# it takes NT 3.1's.
nt31=$sdks/"3.1 SDK DDK"/sdk/MSTOOLS nt351=$sdks/"3.51 SDK"/sdk/MSTOOLS
mkdir -p "$nt31/H/SYS" "$nt31/LIB/I386" "$nt31/LIB/MIPS" \
  "$nt351/INCLUDE/CRT/SYS" "$nt351/LIB/I386" "$nt351/LIB/WINNT/I386" "$pkg/bin"
cp "$here/WINDOWS.H" "$here/STDIO.H" "$nt31/H/"
cp "$here/TYPES.H" "$nt31/H/SYS/"
cp "$here/WINDOWS.H" "$nt351/INCLUDE/"
cp "$here/STDIO.H" "$nt351/INCLUDE/CRT/"
cp "$here/TYPES.H" "$nt351/INCLUDE/CRT/SYS/"

# kernel32 import library and a C runtime with mainCRTStartup.
printf 'LIBRARY KERNEL32.dll\nEXPORTS\nGetStdHandle@4\nWriteFile@20\nExitProcess@4\n' \
  > "$W/kernel32.def"
"$BIN/llvm-dlltool" -m i386 -k -d "$W/kernel32.def" -l "$W/KERNEL32.LIB"
for d in "$nt31/LIB/I386" "$nt351/LIB/I386"; do
  cp "$W/KERNEL32.LIB" "$d/KERNEL32.LIB"
  cp "$W/KERNEL32.LIB" "$d/USER32.LIB"
done
echo junk > "$nt31/LIB/MIPS/KERNEL32.LIB"
"$BIN/clang" --target=i386-pc-windows-msvc -fms-omit-default-lib \
  -Xclang --dependent-lib=LIBC -c "$here/crt.c" -o "$W/crt.obj"
"$BIN/llvm-lib" /out:"$nt31/LIB/I386/LIBC.LIB" "$W/crt.obj"

python3 "$top/tools/import-ms-sdk.py" --sdks "$sdks" "$pkg"
cfg=$pkg/bin/ms-nt351.cfg
r=$pkg/sysroots/ms-nt351
test -f "$pkg/bin/ms-nt31.cfg"
test ! -e "$pkg/bin/ms-nt40.cfg"
test -f "$r/include/windows.h"
test -f "$r/include/stdio.h"
test -f "$r/include/sys/types.h"
test -f "$r/lib/libc.lib"
grep -q i386-pc-windows3.51-msvc "$cfg"
grep -q "dependent-lib=libc$" "$cfg"

# hello.c includes <Windows.h> and <SYS/Types.h>; LIBC.LIB comes from the
# objects' /DEFAULTLIB:libc, and libc.lib's own crt.obj asks for LIBC.LIB, as
# Microsoft's do, found through the overlay.
"$BIN/clang" --config="$cfg" -Os "$here/hello.c" -o "$W/hello.exe" -Wl,-verbose 2> "$W/link.log" || {
  cat "$W/link.log"; exit 1; }
# Only the overlay finds LIBC.LIB on a case-sensitive file system.
grep -q "Directives:.*/DEFAULTLIB:LIBC" "$W/link.log"
! grep -q "warning" "$W/link.log"
python3 - "$W/hello.exe" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
pe = struct.unpack_from("<I", d, 0x3c)[0]
opt = pe + 24
osv = struct.unpack_from("<HH", d, opt + 40)
subv = struct.unpack_from("<HH", d, opt + 48)
sub = struct.unpack_from("<H", d, opt + 68)[0]
assert subv == (3, 51), subv
assert osv == (3, 51), osv
assert sub == 3, sub  # console
# .rdata writable for the NT 3.x loader
nsec = struct.unpack_from("<H", d, pe + 6)[0]
optsize = struct.unpack_from("<H", d, pe + 20)[0]
for i in range(nsec):
    s = pe + 24 + optsize + 40 * i
    name = d[s:s + 8].rstrip(b"\0")
    flags = struct.unpack_from("<I", d, s + 36)[0]
    if name == b".rdata":
        assert flags & 0x80000000, hex(flags)
print("hello.exe: subsystem console 3.51, OS 3.51, .rdata writable")
EOF
if command -v wine >/dev/null 2>&1; then
  out=$(wine "$W/hello.exe" 2>/dev/null | tr -d '\r')
  test "$out" = "hello from a fake kit" || { echo "wine: $out"; exit 1; }
  echo "hello.exe ran in Wine"
fi
echo "ms-sdk import test passed"
