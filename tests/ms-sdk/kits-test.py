#!/usr/bin/env python3
"""Build kit-hello.c with every ms-*.cfg in a toolchain package, check the
programs' PE headers and, on Windows or with --wine, run them.

    kits-test.py PACKAGE [--clang CLANG] [--run] [EXTRA CLANG FLAGS]

--stock-clang tests the kits with a clang from llvm.org.
"""
import argparse
import glob
import os
import re
import struct
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))


def pe_info(path):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3c)[0]
    machine = struct.unpack_from("<H", d, pe + 4)[0]
    opt = pe + 24
    osv = struct.unpack_from("<HH", d, opt + 40)
    subv = struct.unpack_from("<HH", d, opt + 48)
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    optsize = struct.unpack_from("<H", d, pe + 20)[0]
    rdata_rw = None
    for i in range(nsec):
        s = pe + 24 + optsize + 40 * i
        if d[s:s + 8].rstrip(b"\0") == b".rdata":
            rdata_rw = bool(struct.unpack_from("<I", d, s + 36)[0] & 0x80000000)
    return machine, osv, subv, rdata_rw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package")
    ap.add_argument("--clang", default="clang")
    ap.add_argument("--run", action="store_true", help="run the programs")
    ap.add_argument("--wine", action="store_true", help="run them in Wine")
    ap.add_argument("--out", default=".")
    ap.add_argument("--stock-clang", action="store_true",
                    help="a clang without clang-dos's MSVC changes: pass the"
                    " subsystem version to the linker by hand")
    a, extra = ap.parse_known_args()
    a.extra = [x for x in extra if x != "--"]
    cfgs = sorted(glob.glob(os.path.join(a.package, "bin", "ms-*.cfg")))
    if not cfgs:
        print("no ms-*.cfg in %s/bin" % a.package)
        return 1
    failed = []
    for cfg in cfgs:
        kit = os.path.basename(cfg)[:-4]
        triple = re.search(r"--target=(\S+)", open(cfg).read()).group(1)
        want = re.search(r"windows(\d+)\.(\d+)", triple)
        want = (int(want.group(1)), int(want.group(2)))
        exe = os.path.join(a.out, kit + "-hello.exe")
        cmd = [a.clang, "--config=" + cfg, "-O2",
               os.path.join(here, "kit-hello.c"), "-o", exe] + a.extra
        if a.stock_clang:
            v = "%d.%d" % want
            # -Xlinker: -Wl would split the version at the comma.
            cmd += ["-Xlinker", "-subsystem:console," + v,
                    "-Xlinker", "-osversion:" + v]
            if want < (4, 0):
                cmd += ["-Xlinker", "-section:.rdata,RW"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            print("%s: BUILD FAILED\n%s%s" % (kit, r.stdout, r.stderr))
            failed.append(kit)
            continue
        machine, osv, subv, rw = pe_info(exe)
        note = "subsystem %d.%d, OS %d.%d" % (subv + osv)
        ok = subv == want and osv == want
        if want < (4, 0):
            ok = ok and rw
            note += ", .rdata %s" % ("writable" if rw else "READ-ONLY")
        if a.run or a.wine:
            run = (["wine"] if a.wine else []) + [exe, "x"]
            p = subprocess.run(run, capture_output=True, text=True)
            out = p.stdout.strip()
            note += "; ran: %r (exit %d)" % (out, p.returncode)
            ok = ok and p.returncode == 0 and out.startswith("hello from kit")
            ok = ok and "3.25 1234567" in out and "argc=2" in out
        print("%s: %s %s" % (kit, "ok" if ok else "FAILED", note))
        if not ok:
            failed.append(kit)
    if failed:
        print("failed: " + " ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
