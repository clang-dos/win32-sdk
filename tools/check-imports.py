#!/usr/bin/env python3
"""Check that 32-bit Windows programs import only what Windows 9x provides.

    check-imports.py [--dlls DIR] [--allow-unicode] [--nt VERSION]
                     FILE.exe|FILE.dll ...

Programs for Windows 9x should be native ANSI builds. Windows 95, 98 and ME
export most Unicode ("W") functions only as stubs that fail with
ERROR_CALL_NOT_IMPLEMENTED, so every W import outside the short list of ones
that work is an error (a warning with --allow-unicode). A Unicode build that
links libunicows imports no W functions; it loads them from unicows.dll at
run time. The wide msvcrt.dll functions that call kernel32's W stubs, such as
_wfopen, fail on 9x even then and are errors too. Without --dlls, the
check also knows a list of NT-only and newer kernel32 functions.

With --dlls, DIR holds one directory per Windows version (for example 95,
98se, me), each with system DLLs copied from that version (kernel32.dll,
user32.dll, gdi32.dll, advapi32.dll, msvcrt.dll, ...). Every import must then
be exported by the DLL of each version that has it. Imports from DLLs that a
version directory does not hold are listed as unchecked.

With --nt VERSION (3.10, 3.50, 3.51, 4.0, 5.0 for Windows 2000, 5.1 for
XP, 5.2 for Server 2003 and XP x64), the program is checked for that
version of Windows NT instead: Unicode functions are fine, but the
subsystem version must not be newer, and the kernel32 functions added in
later versions are errors. msvcrt.dll imports must be in the msvcrt.dll
that version ships (msvcrt-versions.txt); the _l functions, for example,
are from Vista. Before 4.0, msvcrt.dll does not exist yet (link crtdll.dll),
and the section that holds the import address table must be writable: the
NT 3.x loader predates the IAT directory, which later loaders use to make
the table writable while they fill it in.

The exit status is 1 when something is missing, 0 otherwise.
"""
import argparse
import os
import struct
import sys

# W functions that Windows 95, 98 and ME implement natively (Microsoft
# Layer for Unicode documentation, "Unicode support in Windows 95").
WORKING_W = {
    "EnumResourceLanguagesW", "EnumResourceNamesW", "EnumResourceTypesW",
    "ExtTextOutW", "FindResourceExW", "FindResourceW", "GetCharWidthW",
    "GetCommandLineW", "GetTextExtentExPointW", "GetTextExtentPoint32W",
    "GetTextExtentPointW", "lstrlenW", "MessageBoxExW", "MessageBoxW",
    "MultiByteToWideChar", "TextOutW", "WideCharToMultiByte",
}

# kernel32 functions that no 9x version has: NT-only ones and later
# additions. A program that imports one of them does not load on 9x.
NOT_ON_9X = {
    "AcquireSRWLockExclusive", "AcquireSRWLockShared",
    "CreateSymbolicLinkA", "CreateSymbolicLinkW", "FlsAlloc", "FlsFree",
    "FlsGetValue", "FlsSetValue", "GetFileInformationByHandleEx",
    "GetFinalPathNameByHandleA", "GetFinalPathNameByHandleW",
    "GetNativeSystemInfo", "GetProcessId", "GetSystemTimePreciseAsFileTime",
    "GetThreadId", "GetTickCount64", "InitOnceBeginInitialize",
    "InitOnceComplete", "InitOnceExecuteOnce", "InitializeConditionVariable",
    "InitializeSRWLock", "ReleaseSRWLockExclusive", "ReleaseSRWLockShared",
    "SetFileInformationByHandle", "SignalObjectAndWait",
    "SleepConditionVariableCS", "SleepConditionVariableSRW", "SwitchToThread",
    "TryAcquireSRWLockExclusive", "TryAcquireSRWLockShared",
    "TryEnterCriticalSection", "WaitOnAddress", "WakeAllConditionVariable",
    "WakeByAddressAll", "WakeByAddressSingle", "WakeConditionVariable",
}

# kernel32 functions added after Windows NT 3.1, with the NT version that
# added them. The list is from the Win32 documentation and is not complete;
# --dlls with the DLLs of a real NT 3.x checks every import.
NT_ADDED = {
    "GetSystemTimeAsFileTime": (3, 50),
    "ConvertThreadToFiber": (3, 51), "CreateFiber": (3, 51),
    "DeleteFiber": (3, 51), "SwitchToFiber": (3, 51),
    "CancelIo": (4, 0), "CancelWaitableTimer": (4, 0),
    "CopyFileExA": (4, 0), "CopyFileExW": (4, 0),
    "CreateWaitableTimerA": (4, 0), "CreateWaitableTimerW": (4, 0),
    "FindFirstFileExA": (4, 0), "FindFirstFileExW": (4, 0),
    "GetDiskFreeSpaceExA": (4, 0), "GetDiskFreeSpaceExW": (4, 0),
    "GetFileAttributesExA": (4, 0), "GetFileAttributesExW": (4, 0),
    "InitializeCriticalSectionAndSpinCount": (4, 0),
    "InterlockedCompareExchange": (4, 0), "InterlockedExchangeAdd": (4, 0),
    "IsDebuggerPresent": (4, 0), "IsProcessorFeaturePresent": (4, 0),
    "OpenWaitableTimerA": (4, 0), "OpenWaitableTimerW": (4, 0),
    "ReadDirectoryChangesW": (4, 0), "SetCriticalSectionSpinCount": (4, 0),
    "SetWaitableTimer": (4, 0), "VirtualAllocEx": (4, 0),
    "VirtualFreeEx": (4, 0),
    "CreateToolhelp32Snapshot": (5, 0), "GetConsoleWindow": (5, 0),
    "GetFileSizeEx": (5, 0), "GetLongPathNameA": (5, 0),
    "GetLongPathNameW": (5, 0), "GlobalMemoryStatusEx": (5, 0),
    "Module32First": (5, 0), "Module32Next": (5, 0),
    "Process32First": (5, 0), "Process32Next": (5, 0),
    "SetFilePointerEx": (5, 0), "Thread32First": (5, 0),
    "Thread32Next": (5, 0),
    "AddVectoredExceptionHandler": (5, 1), "DecodePointer": (5, 1),
    "EncodePointer": (5, 1), "GetModuleHandleExA": (5, 1),
    "GetModuleHandleExW": (5, 1), "HeapSetInformation": (5, 1),
    "InitializeSListHead": (5, 1), "InterlockedFlushSList": (5, 1),
    "InterlockedPopEntrySList": (5, 1), "InterlockedPushEntrySList": (5, 1),
    "IsWow64Process": (5, 1), "RemoveVectoredExceptionHandler": (5, 1),
}
NT_ADDED.update({name: (6, 0) for name in NOT_ON_9X if name not in NT_ADDED})
NT_ADDED.update({"GetTickCount64": (6, 0), "SignalObjectAndWait": (4, 0),
                 "SwitchToThread": (4, 0), "TryEnterCriticalSection": (4, 0),
                 "GetSystemTimePreciseAsFileTime": (6, 2)})
# Later additions that programs and runtimes for Windows 2000 and XP run
# into, from the Win32 documentation. Service packs are not told apart:
# GetProcessId, SetDllDirectory and GetSystemTimes are from XP SP1, and
# GetLogicalProcessorInformation from XP SP3.
for names, version in [
        ("AssignProcessToJobObject BindIoCompletionCallback CreateHardLinkA "
         "CreateHardLinkW CreateJobObjectA CreateJobObjectW CreateTimerQueue "
         "CreateTimerQueueTimer DeleteTimerQueueEx DeleteTimerQueueTimer "
         "FindFirstVolumeA FindFirstVolumeW GetComputerNameExA "
         "GetComputerNameExW GetSystemWindowsDirectoryA "
         "GetSystemWindowsDirectoryW GetVolumePathNameA GetVolumePathNameW "
         "OpenThread ProcessIdToSessionId QueueUserWorkItem "
         "RegisterWaitForSingleObject ReplaceFileA ReplaceFileW "
         "UnregisterWait UnregisterWaitEx VerifyVersionInfoA "
         "VerifyVersionInfoW VerSetConditionMask", (5, 0)),
        ("ActivateActCtx AttachConsole CheckRemoteDebuggerPresent "
         "CreateActCtxA CreateActCtxW CreateMemoryResourceNotification "
         "DeactivateActCtx DebugActiveProcessStop GetDllDirectoryA "
         "GetDllDirectoryW GetLogicalProcessorInformation "
         "GetNativeSystemInfo GetProcessHandleCount GetProcessId "
         "GetSystemTimes GetVolumePathNamesForVolumeNameW HeapQueryInformation "
         "QueryDepthSList ReleaseActCtx RtlCaptureStackBackTrace "
         "SetDllDirectoryA SetDllDirectoryW SetFileValidData "
         "TzSpecificLocalTimeToSystemTime WTSGetActiveConsoleSessionId",
         (5, 1)),
        ("FlsAlloc FlsFree FlsGetValue FlsSetValue GetLargePageMinimum "
         "GetProcessIdOfThread GetThreadId NeedCurrentDirectoryForExePathA "
         "NeedCurrentDirectoryForExePathW SetThreadStackGuarantee "
         "Wow64DisableWow64FsRedirection Wow64RevertWow64FsRedirection",
         (5, 2)),
        ("CancelIoEx CompareStringEx CreateEventExA CreateEventExW "
         "CreateMutexExA CreateMutexExW CreateSemaphoreExA CreateSemaphoreExW "
         "CreateThreadpoolWork FindFirstStreamW FlushProcessWriteBuffers "
         "GetCurrentProcessorNumber GetDynamicTimeZoneInformation "
         "GetErrorMode GetLocaleInfoEx GetQueuedCompletionStatusEx "
         "GetUserDefaultLocaleName InitializeCriticalSectionEx "
         "LCIDToLocaleName LocaleNameToLCID QueryFullProcessImageNameA "
         "QueryFullProcessImageNameW QueryThreadCycleTime", (6, 0)),
        ("GetActiveProcessorCount K32EnumProcessModules K32GetModuleFileNameExA "
         "K32GetModuleFileNameExW QueryUnbiasedInterruptTime "
         "SetThreadErrorMode", (6, 1)),
        ("AddDllDirectory CreateFile2 SetDefaultDllDirectories", (6, 2))]:
    NT_ADDED.update({name: version for name in names.split()})


def load_msvcrt_versions():
    """Map each msvcrt.dll export to (version, label) of the first Windows
    whose system msvcrt.dll has it (msvcrt-versions.txt, which
    gen-msvcrt-versions.py makes from mingw-w64's list)."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "msvcrt-versions.txt")
    out = {}
    with open(path) as f:
        for line in f:
            name, version, label = line.split()
            major, minor = version.split(".")
            out[name] = ((int(major), int(minor)), label.replace("_", " "))
    return out

# Wide msvcrt.dll functions that call a kernel32 W stub (CreateFileW,
# FindFirstFileW, CreateProcessW, ...) with no ANSI fallback, found by walking
# the call graph of the msvcrt.dll of Windows 98 SE and ME. They fail on 9x
# even with unicows, which redirects only the program's own imports. The other
# wide functions (__wgetmainargs, _wgetenv, wcscoll, towupper, ...) fall back
# to the A functions.
MSVCRT_NO_FALLBACK = {
    "_waccess", "_wchdir", "_wchmod", "_wcreat", "_wfindfirst",
    "_wfindfirst64", "_wfindfirsti64", "_wfindnext", "_wfindnext64",
    "_wfindnexti64", "_wfopen", "_wfreopen", "_wfsopen", "_wfullpath",
    "_wgetcwd", "_wgetdcwd", "_wmkdir", "_wmktemp", "_wopen", "_wpopen",
    "_wremove", "_wrename", "_wrmdir", "_wsearchenv", "_wsopen", "_wstat",
    "_wstat64", "_wstati64", "_wsystem", "_wtempnam", "_wtmpnam", "_wunlink",
    "_wutime", "_wutime64",
} | {"_w%s%s" % (f, s) for f in ("exec", "spawn")
     for s in ("l", "le", "lp", "lpe", "v", "ve", "vp", "vpe")}

SYSTEM_DLLS = {"kernel32.dll", "user32.dll", "gdi32.dll", "advapi32.dll",
               "shell32.dll", "comctl32.dll", "comdlg32.dll", "ole32.dll",
               "oleaut32.dll", "winmm.dll", "wsock32.dll", "ws2_32.dll",
               "version.dll", "mpr.dll", "ntdll.dll"}


class PE:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()
        d = self.data
        if d[:2] != b"MZ":
            raise ValueError("not an MZ file")
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        if d[pe:pe + 4] != b"PE\0\0":
            raise ValueError("not a PE file")
        nsect, = struct.unpack_from("<H", d, pe + 6)
        optsize, = struct.unpack_from("<H", d, pe + 20)
        opt = pe + 24
        magic, = struct.unpack_from("<H", d, opt)
        if magic != 0x10B:
            raise ValueError("not a 32-bit PE file")
        self.subsystem_version = struct.unpack_from("<HH", d, opt + 48)
        ndirs, = struct.unpack_from("<I", d, opt + 92)
        self.dirs = [struct.unpack_from("<II", d, opt + 96 + 8 * i)
                     for i in range(min(ndirs, 16))]
        self.sections = []
        s = opt + optsize
        self.writable = []
        for i in range(nsect):
            vsize, va, rawsize, rawptr = struct.unpack_from(
                "<IIII", d, s + 40 * i + 8)
            flags, = struct.unpack_from("<I", d, s + 40 * i + 36)
            self.sections.append((va, max(vsize, rawsize), rawptr))
            self.writable.append(bool(flags & 0x80000000))

    def off(self, rva):
        for va, size, raw in self.sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError("RVA 0x%x is outside every section" % rva)

    def is_writable(self, rva):
        for (va, size, _), w in zip(self.sections, self.writable):
            if va <= rva < va + size:
                return w
        return False

    def import_tables(self):
        """Yield the RVA of each DLL's import address table."""
        if len(self.dirs) < 2 or not self.dirs[1][0]:
            return
        o = self.off(self.dirs[1][0])
        while True:
            _, _, _, name, iat = struct.unpack_from("<IIIII", self.data, o)
            if not name:
                break
            yield iat
            o += 20

    def cstr(self, rva):
        o = self.off(rva)
        return self.data[o:self.data.index(b"\0", o)].decode("latin-1")

    def imports(self):
        """Yield (dll, name) pairs; name is "#ordinal" for ordinal imports."""
        if len(self.dirs) < 2 or not self.dirs[1][0]:
            return
        o = self.off(self.dirs[1][0])
        while True:
            ilt, _, _, name, iat = struct.unpack_from("<IIIII", self.data, o)
            if not name:
                break
            dll = self.cstr(name)
            t = self.off(ilt or iat)
            while True:
                e, = struct.unpack_from("<I", self.data, t)
                if not e:
                    break
                if e & 0x80000000:
                    yield dll, "#%d" % (e & 0xFFFF)
                else:
                    yield dll, self.cstr(e + 2)
                t += 4
            o += 20

    def exports(self):
        """Return the set of exported names and "#ordinal" strings."""
        out = set()
        if not self.dirs or not self.dirs[0][0]:
            return out
        o = self.off(self.dirs[0][0])
        base, nfuncs, nnames, _, names = struct.unpack_from(
            "<IIIII", self.data, o + 16)
        for i in range(nfuncs):
            out.add("#%d" % (base + i))
        if nnames:
            n = self.off(names)
            for i in range(nnames):
                out.add(self.cstr(struct.unpack_from("<I", self.data,
                                                     n + 4 * i)[0]))
        return out


def is_unicode_stub(ldll, name, versions):
    """Whether NAME is a W function that Windows 9x does not implement."""
    if ldll not in SYSTEM_DLLS or not name.endswith("W") or name in WORKING_W:
        return False
    if versions is None:
        return True
    # With real DLLs, a W function is one whose A twin exists too.
    twin = name[:-1] + "A"
    return any(twin in dlls.get(ldll, ()) for dlls in versions.values())


def load_versions(root):
    versions = {}
    for v in sorted(os.listdir(root)):
        vdir = os.path.join(root, v)
        if not os.path.isdir(vdir):
            continue
        dlls = {}
        for f in os.listdir(vdir):
            if f.lower().endswith((".dll", ".drv", ".exe")):
                dlls[f.lower()] = PE(os.path.join(vdir, f)).exports()
        versions[v] = dlls
    return versions


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dlls", help="directory with one subdirectory of "
                    "system DLLs per Windows version")
    ap.add_argument("--allow-unicode", action="store_true",
                    help="report Unicode stubs as warnings, for programs "
                    "that check for them at run time")
    ap.add_argument("--nt", metavar="VERSION",
                    help="check for this Windows NT version (3.10 to 5.2) "
                    "instead of Windows 9x")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    nt = None
    if args.nt:
        major, _, minor = args.nt.partition(".")
        nt = (int(major), int(minor or 0))
    versions = load_versions(args.dlls) if args.dlls else None
    bad = False
    for path in args.files:
        pe = PE(path)
        major, minor = pe.subsystem_version
        print("%s: subsystem version %d.%02d" % (path, major, minor))
        if nt is not None:
            bad = check_nt(pe, nt, versions) or bad
            continue
        if major > 4:
            print("  error: Windows 9x loads only subsystem version 4.x "
                  "or older")
            bad = True
        unchecked = set()
        absent = {}
        for dll, name in pe.imports():
            ldll = dll.lower()
            if ldll == "kernel32.dll" and name in NOT_ON_9X:
                print("  error: %s!%s does not exist on Windows 9x"
                      % (dll, name))
                bad = True
                continue
            if is_unicode_stub(ldll, name, versions):
                level = "warning" if args.allow_unicode else "error"
                print("  %s: %s!%s is a Unicode function, which Windows 9x "
                      "only has as a stub; use the A function, or link "
                      "-lunicows and ship unicows.dll"
                      % (level, dll, name))
                bad = bad or not args.allow_unicode
            if ldll == "msvcrt.dll" and name in MSVCRT_NO_FALLBACK:
                level = "warning" if args.allow_unicode else "error"
                print("  %s: %s!%s calls a Unicode stub on Windows 9x and "
                      "fails there, even with unicows; use the narrow "
                      "function" % (level, dll, name))
                bad = bad or not args.allow_unicode
            if versions is None:
                continue
            missing = [v for v, dlls in versions.items()
                       if ldll in dlls and name not in dlls[ldll]]
            if not any(ldll in dlls for dlls in versions.values()):
                unchecked.add(dll)
            else:
                for v, dlls in versions.items():
                    if ldll not in dlls:
                        absent.setdefault(dll, set()).add(v)
            if missing:
                print("  error: %s!%s is missing on %s"
                      % (dll, name, ", ".join(missing)))
                bad = True
        for dll in sorted(absent):
            print("  note: %s is not in %s: install or ship it there"
                  % (dll, ", ".join(sorted(absent[dll]))))
        for dll in sorted(unchecked):
            print("  note: no copy of %s to check against" % dll)
    return 1 if bad else 0


def check_nt(pe, nt, versions):
    """Check PE for Windows NT version NT; return whether something is bad."""
    bad = False
    want = "%d.%02d" % nt
    if tuple(pe.subsystem_version) > nt:
        print("  error: Windows NT %s loads only subsystem version %s or "
              "older" % (want, want))
        bad = True
    if nt < (4, 0) and any(not pe.is_writable(iat)
                           for iat in pe.import_tables()):
        print("  error: the import address table is in a read-only section; "
              "the NT 3.x loader predates the IAT directory that later "
              "loaders use to make it writable while they fill it in")
        bad = True
    msvcrt = load_msvcrt_versions() if nt >= (4, 0) else None
    for dll, name in pe.imports():
        ldll = dll.lower()
        if ldll == "msvcrt.dll" and msvcrt is None:
            print("  error: %s!%s: Windows NT 3.x has no msvcrt.dll; use the "
                  "crtdll sysroot" % (dll, name))
            bad = True
            continue
        if ldll == "msvcrt.dll" and not name.startswith("#"):
            added = msvcrt.get(name)
            if added is None:
                print("  warning: %s!%s is not in any system msvcrt.dll "
                      "that msvcrt-versions.txt knows" % (dll, name))
            elif added[0] > nt:
                print("  error: %s!%s is in the msvcrt.dll of %s and later, "
                      "not Windows NT %s" % (dll, name, added[1], want))
                bad = True
        added = NT_ADDED.get(name) if ldll == "kernel32.dll" else None
        if added and added > nt:
            print("  error: %s!%s needs Windows NT %d.%02d"
                  % ((dll, name) + added))
            bad = True
        if versions:
            missing = [v for v, dlls in versions.items()
                       if ldll in dlls and name not in dlls[ldll]]
            if missing:
                print("  error: %s!%s is missing on %s"
                      % (dll, name, ", ".join(missing)))
                bad = True
    return bad


if __name__ == "__main__":
    sys.exit(main())
