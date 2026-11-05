#!/bin/sh
# Make the redistributable Win32 SDK archive from an assembled clang-dos
# package (dos-sdk's packaging/assemble.sh):
#
#   tools/make-dist.sh PACKAGE OUTPUT.tar.xz
#
# The archive unpacks over a clang-dos package (or next to its bin/):
#   bin/<target>.cfg                the --config files of the Windows targets
#   sysroots/<name>/                the five mingw-w64 sysroots and the
#                                   picolibc one, each with share/licenses/
#   share/clang-dos/                check-imports.py, msvcrt-versions.txt,
#                                   build-modern-sysroot.sh, README
#   share/licenses/win32-sdk/       the licences (see NOTICE.md)
# Sysroots made by tools/import-ms-sdk.py from Microsoft's kits are left
# out, as they cannot be passed on.
set -e
pkg=${1:?usage: make-dist.sh PACKAGE OUTPUT.tar.xz} out=${2:?}
here=$(cd "$(dirname "$0")/.." && pwd)
names="win9x-msvcrt win9x-crtdll win2k-xp win-vista win-vista-x64"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
d=$stage/win32-sdk
mkdir -p "$d/bin" "$d/sysroots" "$d/share/clang-dos/docs" \
  "$d/share/licenses/win32-sdk"
for f in "$here"/cfg/*.cfg; do cp "$f" "$d/bin/"; done
for n in $names; do
  [ -d "$pkg/sysroots/$n" ] || { echo "no sysroot $n in $pkg" >&2; exit 1; }
  cp -R "$pkg/sysroots/$n" "$d/sysroots/"
done
# Packages made before it have no picolibc sysroot.
if [ -d "$pkg/sysroots/win32-picolibc" ]; then
  cp -R "$pkg/sysroots/win32-picolibc" "$d/sysroots/"
  cp "$pkg/sysroots/win32-picolibc/share/licenses/picolibc-COPYING" \
    "$d/share/licenses/win32-sdk/"
else
  rm -f "$d/bin/win32-picolibc.cfg" "$d/bin/nt31-picolibc.cfg"
fi
cp "$here/tools/check-imports.py" "$here/tools/msvcrt-versions.txt" \
  "$here/scripts/build-modern-sysroot.sh" "$d/share/clang-dos/"
cp "$here/README.md" "$d/share/clang-dos/docs/win32-README.md"
cp "$here/LICENSE" "$d/share/licenses/win32-sdk/LICENSE"
cp "$here/NOTICE.md" "$d/share/licenses/win32-sdk/NOTICE.md"
# The licences that every sysroot carries (build-sysroot.sh), once more at
# the top, where they are easy to find.
s=$d/sysroots/win-vista/share/licenses
[ -d "$s" ] || { echo "$s is missing: sysroots too old" >&2; exit 1; }
cp -R "$s"/. "$d/share/licenses/win32-sdk/"
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
tar -C "$d" -cf - . | xz -T0 -9 >"$out"
echo "$out: $(du -h "$out" | cut -f1)"
