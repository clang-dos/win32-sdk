#!/usr/bin/env python3
"""Make msvcrt-versions.txt from mingw-w64's msvcrt.def.in.

    gen-msvcrt-versions.py MINGW_SRC/mingw-w64-crt/lib-common/msvcrt.def.in \
        > msvcrt-versions.txt

mingw-w64 lists the exports of the system msvcrt.dll in the order Windows
versions added them, under comments such as "These symbols were added in
Windows XP OS system version of msvcrt.dll". This writes one line per
32-bit x86 export: its name and the first Windows version whose msvcrt.dll
has it, for check-imports.py. Functions that mingw-w64 emulates on i386
(F_NON_I386) are left out, since programs never import them.
"""
import re
import sys

# Section comment -> (version, label). The NT 4.0 set is the base.
SECTIONS = [
    ("Visual C++ 5.0 SP1 and Windows 98 First", "4.10", "Windows 98"),
    ("Visual C++ 6.0 and Windows 98 Second", "4.10", "Windows 98 SE"),
    ("Windows ME and Windows 2000", "5.00", "Windows 2000 and ME"),
    ("Windows 2000 SP4", "5.00", "Windows 2000 SP4 and XP SP2"),
    ("Windows XP OS", "5.01", "Windows XP"),
    ("Windows Server 2003 OS", "5.02", "Windows Server 2003 and Vista"),
    ("Windows Server 2003 SP1", "5.02", "Windows Server 2003 SP1 and Vista"),
    ("Windows Vista", "6.00", "Windows Vista"),
    ("Windows 8 OS", "6.02", "Windows 8"),
    ("Windows 8.1", "6.03", "Windows 8.1"),
    ("i386-chpe32", None, None),
    ("Windows 11 21H2", "10.00", "Windows 11"),
]
I386 = {"F_I386", "F_X86_ANY", "F_NON_ARM64", "F_NON_X64"}


def main():
    version, label = "4.00", "Windows NT 4.0"
    arch = []  # stack of booleans: inside an #ifdef that holds for i386
    out = {}
    for line in open(sys.argv[1], encoding="latin-1"):
        line = line.rstrip("\n")
        if "This is end of the list of symbols available in the Windows OS" in line:
            break
        m = re.match(r"; These symbols were added in .*", line)
        if m:
            for key, v, l in SECTIONS:
                if key in line:
                    version, label = v, l
                    break
            else:
                sys.exit("unknown section: " + line)
            continue
        if line.startswith("#ifdef"):
            arch.append(line.split()[1] == "__i386__")
            continue
        if line.startswith("#ifndef"):
            arch.append(line.split()[1] != "__i386__")
            continue
        if line.startswith("#endif"):
            arch.pop()
            continue
        if line.startswith("#") or not all(arch) or version is None:
            continue
        entry = line.split(";", 1)[0].strip()
        if not entry or entry in ("EXPORTS",) or entry.startswith("LIBRARY"):
            continue
        m = re.match(r"(F\w*)\((.*)\)$", entry)
        if m:
            if m.group(1) not in I386:
                continue
            entry = m.group(2).strip()
        entry = entry.split()
        if "==" in entry:
            name = entry[entry.index("==") + 1]
        else:
            name = entry[0]
        if not name.startswith("?"):
            name = re.sub(r"@\d+$", "", name)
        out.setdefault(name, (version, label))
    for name in sorted(out):
        print("%s %s %s" % (name, out[name][0], out[name][1].replace(" ", "_")))


if __name__ == "__main__":
    main()
