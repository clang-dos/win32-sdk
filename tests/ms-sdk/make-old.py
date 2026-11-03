"""Make a modern object or library look like one from the NT 3.1 SDK, or
check that ms_oldlib fixed one (run-test.sh).

    make-old.py obj FILE.obj   give .text a VirtualAddress and relocation
                               offsets relative to it; drop the MEM_ bits
    make-old.py lib FILE.lib   pad the archive member headers with NULs
    make-old.py check FILE.lib fail unless both are undone"""
import re
import struct
import sys

what, path = sys.argv[1], sys.argv[2]
d = bytearray(open(path, "rb").read())


def sections(o):
    nsec = struct.unpack_from("<H", d, o + 2)[0]
    opt = struct.unpack_from("<H", d, o + 16)[0]
    for i in range(nsec):
        yield o + 20 + opt + 40 * i


if what == "obj":
    for s in sections(0):
        if d[s:s + 5] == b".text":
            va = 0x1000
            prel, = struct.unpack_from("<I", d, s + 24)
            nrel, = struct.unpack_from("<H", d, s + 32)
            assert nrel, "no relocations in .text"
            for r in range(nrel):
                v, = struct.unpack_from("<I", d, prel + 10 * r)
                struct.pack_into("<I", d, prel + 10 * r, v + va)
            struct.pack_into("<I", d, s + 12, va)
            ch, = struct.unpack_from("<I", d, s + 36)
            struct.pack_into("<I", d, s + 36, ch & ~0xE0000000)
    open(path, "wb").write(d)
elif what == "lib":
    off = 8
    while off + 60 <= len(d):
        size = int(re.match(rb"\s*(\d+)", d[off + 48:off + 58]).group(1))
        h = bytes(d[off:off + 58])
        # Pad every field after its value with NULs, as old LIB.EXE did.
        d[off:off + 58] = re.sub(rb"(?<=\S) +", lambda m: b"\0" * len(m.group()), h)
        off += 60 + size + (size & 1)
    open(path, "wb").write(d)
else:
    assert b"\0" not in bytes(d[8:8 + 58]), "NUL in archive header"
    i = d.find(b".text\0\0\0")
    assert i > 0
    va, = struct.unpack_from("<I", d, i + 12)
    ch, = struct.unpack_from("<I", d, i + 36)
    assert va == 0, "section address left"
    assert ch & 0x60000000 == 0x60000000, "no MEM_EXECUTE|MEM_READ"
