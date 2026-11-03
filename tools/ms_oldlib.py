"""Make the libraries of Microsoft's NT 3.x and 1996 kits usable with LLD.

import-ms-sdk.py runs these on its copies of a kit's libraries; the kit
itself is never changed. Found by building and running programs against the
real kits on Windows 11:

* fix_archive: LIB.EXE of the NT 3.x era padded archive member headers with
  NUL bytes instead of spaces, which LLVM rejects as a malformed archive.
* fix_objects: objects of that era give a section a non-zero VirtualAddress
  and relocation offsets relative to it, where LLD wants them relative to
  the section; and they leave out a section's MEM_EXECUTE/READ/WRITE bits,
  which old linkers derived from its content type, so LLD made a second,
  non-executable .text and a data section with no access.
* convert_import_lib: long-format import libraries (one full object for
  each import, before the short import format of 1998) give LLD a broken
  import table: it lays out the .idata$4/$5 pieces in the order the members
  are pulled in, so a DLL's zero terminator can land in the middle of its
  lookup table and the loader stops binding there. They are rebuilt as
  short-format libraries with llvm-lib, and every import is checked against
  the old library.
* extract_ll64: the 64-bit integer helpers (__alldiv and the like) from a
  newer kit's libcmt.lib, which the 1993 C runtime predates.
"""

import os
import re
import struct
import subprocess
import tempfile

MACHINES = {0x14C: "x86", 0x8664: "x64"}


def members(d):
    """(header offset, name, data) of each member of an archive."""
    off = 8
    while off + 60 <= len(d):
        h = d[off:off + 60]
        if h[58:60] != b"`\n":
            break
        m = re.match(rb"[ \0]*(\d+)", h[48:58])
        if not m:
            break
        size = int(m.group(1))
        yield off, h[:16].decode("latin1").rstrip(" \0"), d[off + 60:off + 60 + size]
        off += 60 + size + (size & 1)


def fix_archive(path):
    """Turn NUL padding in the member headers into spaces. Returns the
    number of headers changed."""
    d = bytearray(open(path, "rb").read())
    if not d.startswith(b"!<arch>\n"):
        return 0
    n = 0
    for off, _, _ in list(members(bytes(d))):
        h = bytes(d[off:off + 58])
        if b"\0" in h:
            d[off:off + 58] = h.replace(b"\0", b" ")
            n += 1
    if n:
        open(path, "wb").write(d)
    return n


def fix_objects(path):
    """Rebase section relocations to the section and add missing MEM_ bits
    in the objects of an archive. Returns the number of sections changed."""
    d = bytearray(open(path, "rb").read())
    if not d.startswith(b"!<arch>\n"):
        return 0
    n = 0
    for off, name, m in list(members(bytes(d))):
        o = off + 60
        if name in ("/", "//") or len(m) < 20:
            continue
        mach, nsec = struct.unpack_from("<HH", d, o)
        if mach not in (0x14C, 0x8664) or nsec == 0xFFFF:
            continue
        opt = struct.unpack_from("<H", d, o + 16)[0]
        for i in range(nsec):
            s = o + 20 + opt + 40 * i
            if s + 40 > o + len(m):
                break
            va, rsz, _, prel = struct.unpack_from("<IIII", d, s + 12)
            nrel = struct.unpack_from("<H", d, s + 32)[0]
            ch = struct.unpack_from("<I", d, s + 36)[0]
            if not ch & 0xE0000000:
                add = 0
                if ch & 0x20:          # code: execute, read
                    add = 0x60000000
                elif ch & 0xC0:        # data or bss: read, write
                    add = 0xC0000000
                if add:
                    struct.pack_into("<I", d, s + 36, ch | add)
                    n += 1
            if not va:
                continue
            rels = [struct.unpack_from("<I", d, o + prel + 10 * r)[0]
                    for r in range(nrel)]
            # Only when every relocation then lands inside the section.
            if all(va <= r < va + rsz for r in rels):
                for r, v in enumerate(rels):
                    struct.pack_into("<I", d, o + prel + 10 * r, v - va)
                struct.pack_into("<I", d, s + 12, 0)
                n += 1
    if n:
        open(path, "wb").write(d)
    return n


def cstr(b, o=0):
    e = b.find(b"\0", o)
    return b[o:e if e >= 0 else len(b)].decode("latin1")


def parse_obj(m):
    """(machine, [(section name, data)], [(symbol, section, class)]) of a
    COFF object, or None for a short import member."""
    mach, nsec, _, psym, nsym, opt, _ = struct.unpack_from("<HHIIIHH", m, 0)
    if mach == 0 and nsec == 0xFFFF:
        return None
    strtab = psym + 18 * nsym

    def name(raw):
        if raw[:4] == b"\0\0\0\0":
            return cstr(m, strtab + struct.unpack_from("<I", raw, 4)[0])
        return raw.rstrip(b"\0").decode("latin1")
    secs = []
    for i in range(nsec):
        s = 20 + opt + 40 * i
        raw, _, _, rsz, praw = struct.unpack_from("<8sIIII", m, s)
        sn = raw.rstrip(b"\0").decode("latin1")
        if sn.startswith("/") and sn[1:].isdigit():
            sn = cstr(m, strtab + int(sn[1:]))
        secs.append((sn, m[praw:praw + rsz] if praw else b"\0" * rsz))
    syms = []
    i = 0
    while i < nsym:
        raw = m[psym + 18 * i:psym + 18 * i + 8]
        _, sec, _, cls, aux = struct.unpack_from("<IhHBB", m, psym + 18 * i + 8)
        syms.append((name(raw), sec, cls))
        i += 1 + aux
    return mach, secs, syms


def analyse_import_lib(d):
    """Read a long-format import library: (machine, {descriptor: dll},
    {__imp_ symbol: (name, ordinal, descriptor)}, {thunk: __imp_ symbol},
    [other members to keep]), or a string saying why it can't be converted
    (or None when it isn't a long-format import library)."""
    descs, imps, thunks, keep, other = {}, {}, {}, [], []
    machine = None
    for _, name, m in members(d):
        if name in ("/", "//") or len(m) < 20:
            continue
        p = parse_obj(m)
        if p is None:
            return None                        # short format already
        mach, secs, syms = p
        machine = machine or mach
        sn = [s for s, _ in secs]
        core = [x for x in sn if not x.startswith(".debug")]
        defined = [(s, sec) for s, sec, cls in syms if sec > 0 and cls == 2]
        undef = [s for s, sec, cls in syms if sec == 0 and cls == 2]
        if ".idata$2" in sn:
            dll = cstr(secs[sn.index(".idata$6")][1]) if ".idata$6" in sn else None
            key = [s for s, _ in defined if "IMPORT_DESCRIPTOR" in s]
            descs[key[0] if key else "#"] = dll
            continue
        if set(core) <= {".idata$3"} or (
                set(core) <= {".idata$4", ".idata$5"} and
                not any(s.startswith("__imp_") for s, _ in defined)):
            continue                           # null descriptor or thunk
        if ".edata" in sn:
            continue                           # exports: not for importing
        imp = [s for s, _ in defined if s.startswith("__imp_")]
        if imp:
            i4 = secs[sn.index(".idata$4")][1] if ".idata$4" in sn else b""
            ordv = iname = None
            if len(i4) >= 4 and struct.unpack_from("<I", i4)[0] & 0x80000000:
                ordv = struct.unpack_from("<I", i4)[0] & 0xFFFF
            elif ".idata$6" in sn:
                iname = cstr(secs[sn.index(".idata$6")][1], 2)
            ref = [s for s in undef if "IMPORT_DESCRIPTOR" in s]
            for s in imp:
                imps[s] = (iname, ordv, ref[0] if ref else None)
            for s, sec in defined:
                if not s.startswith("__imp_") and secs[sec - 1][0].startswith(".text"):
                    thunks[s] = imp[0]
            continue
        th = [s for s, sec in defined if secs[sec - 1][0].startswith(".text")]
        ri = [s for s in undef if s.startswith("__imp_")]
        if th and len(ri) == 1 and core and all(x.startswith(".text") for x in core):
            for t in th:
                thunks[t] = ri[0]
            continue
        if any(x.startswith(".idata$") for x in core):
            # An old DATA import whose IAT slot itself carries the symbol
            # (crtdll.lib's _iob and the like): no short-format equivalent.
            other.append(name)
            continue
        if not defined:
            continue    # a leftover with nothing in it (shell32's shellprv)
        keep.append(m)  # a real object, such as shell32's GUIDs
    if not imps:
        return None
    if other:
        return "%d old-style DATA imports (%s...)" % (len(other), other[0])
    return machine, descs, imps, thunks, keep


def convert_import_lib(path, llvm_lib):
    """Rebuild a long-format import library as a short-format one in place.
    Returns a note, or None when there was nothing to do."""
    d = open(path, "rb").read()
    if not d.startswith(b"!<arch>\n"):
        return None
    info = analyse_import_lib(d)
    if info is None:
        return None
    if isinstance(info, str):
        return "left as it is: " + info
    machine, descs, imps, thunks, keep = info
    arch = MACHINES.get(machine)
    if not arch:
        return None
    bydll = {}
    for imp, (iname, ordv, ref) in imps.items():
        dll = descs.get(ref) or (list(descs.values())[0] if len(descs) == 1 else None)
        if not dll:
            return "left as it is: no DLL for " + imp
        bydll.setdefault(dll, []).append((imp, iname, ordv))
    funcs = {}
    for t, imp in thunks.items():
        funcs.setdefault(imp, []).append(t)
    with tempfile.TemporaryDirectory() as tmp:
        parts = []
        for n, (dll, entries) in enumerate(sorted(bydll.items())):
            lines = ['LIBRARY "%s"' % dll, "EXPORTS"]
            want = {}
            for imp, iname, ordv in sorted(entries):
                sym = imp[6:]
                data = sym not in funcs.get(imp, [])
                if arch == "x86":
                    # llvm-lib takes names with '@' or a leading '?' as the
                    # symbol and adds the '_' prefix to the others.
                    if sym.startswith("?") or "@" in sym:
                        dname = sym
                    elif sym.startswith("_"):
                        dname = sym[1:]
                    else:
                        return "left as it is: can't express " + sym
                else:
                    dname = sym
                line = "  " + dname
                if ordv is not None:
                    line += " @%d NONAME" % ordv
                if data:
                    line += " DATA"
                if ordv is None and iname is not None and iname != dname:
                    line += " EXPORTAS %s" % iname
                lines.append(line)
                want[sym] = (("#", ordv) if ordv is not None else iname, data)
            deff = os.path.join(tmp, "%d.def" % n)
            out = os.path.join(tmp, "%d.lib" % n)
            open(deff, "w").write("\n".join(lines) + "\n")
            r = subprocess.run([llvm_lib, "/def:" + deff, "/machine:" + arch,
                                "/out:" + out], capture_output=True, text=True)
            if r.returncode:
                return "left as it is: llvm-lib failed: " + r.stdout + r.stderr
            bad = check_short(open(out, "rb").read(), dll, want)
            if bad:
                return "left as it is: %d imports differ (%s)" % (len(bad), bad[0])
            parts.append(out)
        for i, m in enumerate(keep):
            obj = os.path.join(tmp, "keep%d.obj" % i)
            open(obj, "wb").write(m)
            parts.append(obj)
        out = os.path.join(tmp, "all.lib")
        r = subprocess.run([llvm_lib, "/out:" + out] + parts,
                           capture_output=True, text=True)
        if r.returncode:
            return "left as it is: llvm-lib failed: " + r.stdout + r.stderr
        open(path, "wb").write(open(out, "rb").read())
    return "converted %d imports%s" % (
        len(imps), ", kept %d objects" % len(keep) if keep else "")


def check_short(d, dll, want):
    """Compare the short import members of a new library with the imports
    {symbol: (name or ("#", ordinal), is data)} it should have."""
    got = {}
    for _, _, m in members(d):
        if len(m) < 20:
            continue
        s1, s2, _, _, _, sz, oh, tinfo = struct.unpack_from("<HHHHIIHH", m, 0)
        if (s1, s2) != (0, 0xFFFF):
            continue
        rest = m[20:20 + sz]
        sym = cstr(rest)
        dllname = cstr(rest, len(sym) + 1)
        typ, nt = tinfo & 3, (tinfo >> 2) & 7
        if nt == 0:
            imp = ("#", oh)
        elif nt == 1:
            imp = sym
        elif nt == 2:
            imp = sym[1:] if sym[:1] in "?@_" else sym
        elif nt == 3:
            imp = sym.lstrip("?@_").split("@")[0]
        else:
            imp = cstr(rest, len(sym) + len(dllname) + 2)
        got[sym] = (imp, typ == 1, dllname)
    return [(s, w, got.get(s)) for s, w in want.items()
            if got.get(s) != (w[0], w[1], dll)]


LL64 = {"lldiv", "lldvrm", "llmul", "llrem", "llshl", "llshr",
        "ulldiv", "ulldvrm", "ullrem", "ullshr"}


def extract_ll64(libcmt, outdir):
    """Write the 64-bit integer helper objects of an i386 libcmt.lib to
    outdir. Returns their paths."""
    d = open(libcmt, "rb").read()
    longnames = b""
    out = []
    for _, name, m in members(d):
        if name == "//":
            longnames = m
            continue
        if name.startswith("/") and name[1:].isdigit():
            name = cstr(longnames, int(name[1:]))
        base = re.split(r"[\\/]", name.rstrip("/"))[-1].lower()
        if base.endswith(".obj") and base[:-4] in LL64:
            p = os.path.join(outdir, base)
            if p not in out:
                open(p, "wb").write(m)
                out.append(p)
    return out
