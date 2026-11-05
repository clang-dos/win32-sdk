# win32-sdk

The 32 and 64-bit Windows part of the clang-dos SDK: scripts that build
mingw-w64 sysroots for clang from [clang-dos/llvm](https://github.com/clang-dos/llvm)
that run on Win32s, Windows NT 3.1 to 4.0, Windows 95, 98 and ME, 2000 and
XP, and Vista to 11, the `--config` files for each, an import checker and
the tests. It was split out of [clang-dos/dos-sdk](https://github.com/clang-dos/dos-sdk)
(its `win9x/` directory and the Windows parts of `packaging/`), which still
builds the toolchain packages and takes these sysroots from here.

```
build-sysroot.sh                 builds one of the package's sysroots (below)
scripts/build-win9x.sh           mingw-w64 sysroot for 9x, NT 3.x/4.0, 2000/XP
scripts/build-unicows.sh         adds libunicows to it
scripts/build-cxx.sh             adds libc++, libc++abi and libunwind (9x to XP)
scripts/build-modern-sysroot.sh  sysroot for Vista and later, with libc++
cfg/                             --config files for the toolchain package
tools/check-imports.py           checks a program's imports for a Windows version
tools/import-ms-sdk.py           sysroots from your own copies of Microsoft's kits
tools/ms_oldlib.py               its fixes for the libraries of 1993-96 kits
tools/ms-intrin-shim.h           its fix for the Server 2003 DDK's winnt.h
tools/msvcrt-versions.txt        which msvcrt.dll has each function
tools/gen-msvcrt-versions.py     makes msvcrt-versions.txt
tests/                           the tests, run in Wine
```

## The package's sysroots

```sh
BIN=~/llvm/build/bin LLVM_SRC=~/llvm MINGW_SRC=~/mingw-w64 \
LIBUNICOWS_SRC=~/libunicows-1.1.2 sh build-sysroot.sh NAME OUTPUT
```

| NAME | For | Config files |
| --- | --- | --- |
| `win9x-msvcrt` | 95/98/ME and NT 4.0 (msvcrt.dll), with libunicows and libc++ | `nt4`, `win95`, `win98`, `winme` |
| `win9x-crtdll` | NT 3.x, Win32s and 95 without msvcrt.dll (crtdll.dll), with libc++ | `win32s`, `nt31`, `nt35`, `nt351`, `win95-crtdll` |
| `win2k-xp` | 2000 and XP, with libc++, libc++abi and libunwind | `win2000`, `winxp` |
| `win-vista` | Vista to 11, 32-bit, with libc++ | `vista`, `win7`, `win8`, `win81`, `win10` |
| `win-vista-x64` | the same, 64-bit | `vista-x64`, `win7-x64`, ... |

dos-sdk's toolchain workflow checks out this repository at `main` (or the
`win32_sdk_ref` it is given), builds these five sysroots with
`build-sysroot.sh` and puts them and `cfg/` in the package, whose smoke
test builds a program for each Windows version, checks it with
`check-imports.py` and runs it in Wine.

## Windows 95, 98, ME, NT and 2000/XP

clang builds 32-bit programs for Windows 95, 98 and ME with a Windows
version in the target triple and a sysroot made from mingw-w64.

| Windows | Triple | Default CPU |
| --- | --- | --- |
| 95 (and NT 4.0) | `i386-pc-windows4.0-gnu` | 80386 |
| 98 | `i486-pc-windows4.10-gnu` | 80486 |
| ME | `i586-pc-windows4.90-gnu` | Pentium |

The version in the triple is the oldest Windows the program runs on. clang
then:

* targets the CPU of the arch name (`i386`, `i486`, `i586` for a Pentium,
  `i686` for a Pentium Pro) instead of a Pentium 4, so no SSE. Windows 95 and
  NT 4.0 do not save SSE registers. `-march` still overrides it.
* tells the linker to write that subsystem and OS version. Windows 9x refuses
  programs that ask for Windows 5.0 or later, and LLD's default is 6.0.
  `-Wl,--subsystem,console:4.0` and the like still override it.

### Building the sysroot

```sh
LLVM_SRC=~/llvm MINGW_SRC=~/mingw-w64 BIN=~/llvm/build/bin \
  SYSROOT=~/win9x-sysroot sh scripts/build-win9x.sh
```

Use `llvm-dlltool`, `lld` and `clang` from the same new build. LLVM 18's
`llvm-dlltool` turns renamed imports in mingw-w64's `.def` files into weak
aliases, so `atexit` calls itself and programs hang at startup; a new
`llvm-dlltool` with LLVM 18's `lld` imports functions by ordinal 0.

It needs a recent mingw-w64 (current master works): recent mingw-w64 calls
newer Windows functions only through `GetProcAddress` with fallbacks, and
its own test suite runs on Windows 9x. The sysroot holds:

* mingw-w64 headers with `_WIN32_WINNT` defaulting to `0x0400`, so APIs
  newer than Windows 95 and NT 4.0 are hidden unless a program asks for them;
* the mingw-w64 CRT and import libraries, linked against the `msvcrt.dll`
  that ships with Windows (`libmsvcrt.a` is `libmsvcrt-os.a`);
* compiler-rt builtins, as `libgcc.a` so clang links them by default, and
  empty `libgcc_eh.a`, `crtbegin.o` and `crtend.o`, which C does not need.

Everything is compiled for an 80386 (`CPU=i386`), which Windows 95 and NT
run on. An 80386 has no `BSWAP`, `XADD` or `CMPXCHG`. For `-march=i386`
clang-dos/llvm swaps bytes with shifts and makes atomic writes calls to
`__sync_*` functions in compiler-rt's builtins (`libgcc.a`). On an 80486
or later those use `LOCK XADD` and `LOCK CMPXCHG`; on an 80386 they take a
lock, which costs a `Sleep` only when two threads write atomics at once.
Atomic loads stay plain moves. `CPU=i486` builds libraries that need a
486.

### Building programs

```sh
clang --target=i386-pc-windows4.0-gnu --sysroot=$SYSROOT -fuse-ld=lld \
  hello.c -o hello.exe
clang --target=i386-pc-windows4.0-gnu --sysroot=$SYSROOT -fuse-ld=lld \
  -mwindows gui.c -o gui.exe
```

### The C runtime DLL

Programs import `msvcrt.dll`. Windows 98 and ME ship it; Windows 95 has it
only when something installed it (Internet Explorer 4, Office, many other
programs). For a bare Windows 95, ship Microsoft's redistributable
`msvcrt.dll` 6.0 with the program, or build a second sysroot with
`CRT=crtdll`, whose programs import `crtdll.dll`, which every Windows 95 has.

### Native ANSI builds

Windows 9x programs are native ANSI builds: they call the `A` functions
directly, with no unicows layer. Windows 95, 98 and ME implement only a
few `W` functions (`MessageBoxW`, `TextOutW`, `lstrlenW`,
`MultiByteToWideChar` and a handful more); the others exist only as stubs
that fail with `ERROR_CALL_NOT_IMPLEMENTED`.

* Generic-text code (`TCHAR`, `_T()`, `CreateFile`, `_tmain`) compiles to
  the `A` functions, because nothing defines `UNICODE` or `_UNICODE`. Don't
  pass `-municode` or `-DUNICODE` for a 9x program, unless it is a Unicode
  build with unicows (below).
* The sysroot's own startup code and C library import no `W` functions;
  `check-imports.py` confirms it for every test program.
* `check-imports.py` fails a build that imports a `W` stub. A program that
  checks the Windows version and picks `W` functions only on NT can pass
  `--allow-unicode` to see those as warnings instead.
* Text is in the system's ANSI code page (`GetACP()`), as in any ANSI
  program.

### Unicode builds with unicows

A Unicode program (`-municode`, `wmain`, `CreateFileW`) runs on 9x through
Microsoft's Layer for Unicode, `unicows.dll`, which turns W calls into A
calls. Native ANSI builds remain the default; this is for code that is
Unicode already.

```sh
LIBUNICOWS_SRC=~/libunicows-1.1.2 BIN=~/llvm/build/bin \
  SYSROOT=~/win9x-sysroot sh scripts/build-unicows.sh
clang --target=i386-pc-windows4.0-gnu --sysroot=$SYSROOT -fuse-ld=lld \
  -municode prog.c -lunicows -o prog.exe
```

`build-unicows.sh` builds [libunicows](https://libunicows.sourceforge.net)
(MIT license; it needs `nasm`) into the sysroot. The program then imports no
W functions. At its first W call, libunicows loads `unicows.dll` on 9x or the
system DLLs on NT, so one exe runs on both.

* Ship `unicows.dll` with the program. Microsoft's MSLU redistributable
  (`unicows.exe`) has it; it is not in this repository. Without it, the
  program stops at its first W call with a message box naming the missing
  DLL.
* [opencow](https://opencow.sourceforge.net) (MPL) is an open-source
  `unicows.dll`, which libunicows loads when `unicows.dll` is absent. It has
  only about 130 of MSLU's 500 functions (not `lstrcmpiW` or `wsprintfW`,
  for example), so it fits only programs that use what it has.
* unicows covers the program's own Win32 calls, not the C library's. The
  9x `msvcrt.dll` calls W stubs directly in about 50 wide functions:
  `_wfopen`, `_wopen`, `_wstat`, `_wfindfirst`, `_waccess`, `_wremove`,
  `_wrename`, `_wmkdir`, `_wgetcwd`, `_wfullpath`, `_wsystem`, `_wspawn*`,
  `_wexec*` and the like. They fail on 9x with or without unicows, and
  `check-imports.py` reports them. Use `CreateFileW` and the other Win32
  functions for files instead. `wmain`'s arguments, `_wgetenv` and the wide
  string, character and formatting functions work, because msvcrt falls
  back to the A functions there.
* A `crtdll.dll` sysroot has no wide C library, so it can't build
  `-municode` programs.

### Windows NT 3.1, 3.5 and 3.51

The same sysroot, built with `CRT=crtdll`, makes programs for Windows NT
3.x with an NT version in the triple. Windows NT 3.x has no `msvcrt.dll`,
but every version has `crtdll.dll`.

| Windows | Triple | Subsystem version |
| --- | --- | --- |
| NT 3.1 | `i386-pc-windows3.10-gnu` | 3.10 |
| NT 3.5 | `i386-pc-windows3.50-gnu` | 3.50 |
| NT 3.51 | `i386-pc-windows3.51-gnu` | 3.51 |

```sh
clang --target=i386-pc-windows3.10-gnu --sysroot=$CRTDLL_SYSROOT \
  -fuse-ld=lld hello.c -o hello.exe
```

* NT 3.x refuses programs with a newer subsystem version than its own
  ("not a valid Windows NT application"); the triple sets it, as for 9x.
  A GUI program with subsystem 3.x looks like a 3.x program on later
  Windows too (no 3D frames from Windows 95 on).
* Write the minor version with two digits: `windows3.1` asks for 3.01,
  which loads too, but `windows3.5` asks for 3.05.
* An `i386` triple targets the 80386, which NT 3.x runs on, like the
  sysroot's libraries.
* LLD puts the import address table in `.rdata`, which is read-only. The
  NT 3.x loader predates the IAT directory that NT 4.0 and later use to make
  the table writable while they fill it in, so for a version before 4.0
  clang tells LLD to make `.rdata` writable.
* `check-imports.py --nt 3.10` (or `3.50`, `3.51`) checks a program for
  NT 3.x: its subsystem version, a writable import address table, no
  `msvcrt.dll`, and no kernel32 function from its list of ones added in
  later versions (`GetSystemTimeAsFileTime` is from 3.5, fibers from 3.51,
  `InterlockedCompareExchange`, `IsDebuggerPresent` and
  `TryEnterCriticalSection` from 4.0, and so on). The list is not complete:
  `--dlls` with DLLs copied from a real NT 3.x checks every import.
* Unicode functions work on NT, so `-municode` programs need no unicows,
  but a crtdll sysroot has no wide C startup (`wmain`).
* Win32s also wants subsystem 3.10, but it is a different system (Win32 on
  Windows 3.1, with no threads and a shared address space) and is not
  tested.

Wine has no NT 3.1 or 3.5 mode; `run-tests.sh` runs NT 3.x programs with
Wine reporting NT 3.51. Wine does not limit programs to the NT 3.x API, and
no NT 3.x loader has run these programs yet.

### Windows 2000 and XP

A sysroot built with `WINNT=0x0500` (or `0x0501`) makes C and C++ programs
for Windows 2000 and XP with an NT 5 version in the triple.

| Windows | Triple | Subsystem version |
| --- | --- | --- |
| 2000 | `i586-pc-windows5.0-gnu` | 5.00 |
| XP | `i586-pc-windows5.1-gnu` | 5.01 |
| Server 2003 | `i586-pc-windows5.2-gnu` | 5.02 |

```sh
LLVM_SRC=~/llvm MINGW_SRC=~/mingw-w64 BIN=~/llvm/build/bin \
  SYSROOT=~/xp-sysroot WINNT=0x0501 CPU=i586 sh scripts/build-win9x.sh
LLVM_SRC=~/llvm BIN=~/llvm/build/bin SYSROOT=~/xp-sysroot CPU=i586 \
  sh scripts/build-cxx.sh
clang --target=i586-pc-windows5.1-gnu --sysroot=$SYSROOT -fuse-ld=lld \
  hello.c -o hello.exe
clang++ --target=i586-pc-windows5.1-gnu --sysroot=$SYSROOT -fuse-ld=lld \
  -stdlib=libc++ hello.cpp -o hello.exe
```

* Programs import the system `msvcrt.dll`, which both versions ship. It
  is older than Vista's: it has no `_l` functions (`_strtod_l`,
  `_snprintf_l`, ...), no `_create_locale` and no `_s` functions such as
  `wcrtomb_s`, and the 2000 one lacks a few XP additions.
  `check-imports.py --nt 5.0` (or `5.1`) checks each `msvcrt.dll` import
  against the version that first shipped it (`msvcrt-versions.txt`, made
  from mingw-w64's annotated list with `gen-msvcrt-versions.py`), and
  each kernel32 import against a list of functions added in XP, Server
  2003, Vista and 7 (SRW locks, condition variables, `InitOnce`, `Fls*`,
  `GetThreadId`, `GetTickCount64`, `GetActiveProcessorCount`, ...).
* Use `i586` (Pentium) triples: 2000 and XP run on a Pentium, and `i686`
  code has CMOV, which a Pentium MMX or K6 lacks. As for 9x, there is no
  SSE unless `-march` asks for it.
* `__thread` and `thread_local` use emulated TLS, as with GCC: the clang
  in clang-dos/llvm uses it by default for MinGW triples below 6.0, since
  before Vista Windows sets up native TLS only for the program and the
  DLLs loaded with it, not for one loaded with `LoadLibrary`.
  `-fno-emulated-tls` turns it off.
* `build-cxx.sh` adds a static libc++, libc++abi and libunwind (DWARF
  unwinding). With the sysroot's `_WIN32_WINNT` below 0x0600, the libc++
  in clang-dos/llvm uses no Vista functions:
  * threads: `std::mutex` is a `CRITICAL_SECTION` and
    `std::condition_variable` a queue of waiting threads with an event
    each; `call_once` is an interlocked flag; thread-specific data uses
    `TlsAlloc` with destructors run from the mingw-w64 runtime's thread
    exit callback; `std::thread::get_id` uses `NtQueryInformationThread`
    when there is no `GetThreadId`; `atomic::wait` polls.
  * locales: a locale is its name, set with `setlocale` for each call that
    takes one. The "C" locale costs a `setlocale(LC_ALL, NULL)` per call.
    A named locale changes the process locale for the call, so
    formatting with a non-"C" locale in two threads at once can race.
  * `<filesystem>`: file information comes from `NtQueryInformationFile`.
    Windows before Vista has no symbolic links to files, so
    `create_symlink` fails with an error and `canonical` does not resolve
    junctions.
* Windows 2000 needs Service Pack 4 for `msvcrt.dll`'s
  `_get_heap_handle`, which XP has only from SP2; nothing in the sysroot
  imports it.
* Wine runs the tests reporting Windows 2000 or XP, but Wine does not limit
  programs to that API, and no real 2000 or XP machine has run them yet.
  `--dlls` with DLLs copied from a real system checks every import.

### C++ on 9x, NT 3.x, NT 4.0 and Win32s

The `win9x-msvcrt` and `win9x-crtdll` sysroots have libc++, libc++abi and
libunwind too, built by `build-cxx.sh` for a 386, and their config files
pass `-stdlib=libc++`:

```sh
clang++ --config=win98.cfg -O2 hello.cpp -o hello.exe
clang++ --config=nt351.cfg -O2 hello.cpp -o hello.exe
```

Their headers are for Windows before 2000 (`_WIN32_WINNT` 0x0400), for
which the libc++ in clang-dos/llvm also does without what 9x, NT 3.x and
NT 4.0 lack. On top of the 2000/XP code (below):

* threads: a mutex is a count of waiting threads and a semaphore, since 9x
  has no `TryEnterCriticalSection`; `this_thread::yield` is `Sleep(0)`. On
  9x, which can't get a thread's ID from its handle, `std::thread` keeps
  the IDs of the threads it makes.
* files: `<filesystem>` and `fstream`s opened with a wide name call the
  Unicode functions on NT, found at run time, so no program imports a 9x
  stub. On 9x and Win32s they convert the name to the ANSI code page (a
  name that doesn't fit is refused) and call the ANSI function. Status
  comes from `GetFileAttributes` and `FindFirstFile`, as 9x can't open a
  directory; `rename` over a file deletes it first; there are no hard
  links. `SetFilePointerEx` and `CreateHardLinkW` (2000) and
  `GetSystemTimeAsFileTime` (NT 3.5) are looked up at run time.
* crtdll.dll (NT 3.x, Win32s, bare 95): no per-thread locales, so a named
  locale changes the process locale for each call, and files seek with
  32-bit positions.
* atomics: a 486 has no `CMPXCHG8B`, so 64-bit ones are calls to the
  compiler-rt atomic functions in `libgcc.a`, which take a lock. The
  others are calls to its `__sync_*` functions, which work on a 386 too
  (see above).

The C runtime is still the system one, `msvcrt.dll` or `crtdll.dll`, with
what it lacks (no `_l` functions, an old `printf`).

### What does not work

* PE TLS callbacks never run on 9x. `__thread` variables work in an EXE;
  with clang-dos/llvm's default of emulated TLS for versions before 6.0
  they work in DLLs too. C++ `thread_local` destructors do not run on 9x.

### Checking imports

`check-imports.py` lists the functions a program imports that Windows 9x
lacks or has only as Unicode stubs. Without DLLs it uses a built-in list of
NT-only and newer functions. With `--dlls DIR`, where `DIR` holds one
directory of system DLLs per Windows version (for example `95osr2/` and
`98se/` with `KERNEL32.DLL`, `USER32.DLL`, `GDI32.DLL`, `ADVAPI32.DLL` and
`MSVCRT.DLL` copied from those systems), it checks every import against
the real export tables.

```sh
python3 tools/check-imports.py --dlls ~/win9x-dlls hello.exe
```

### Tests

```sh
BIN=~/llvm/build/bin SYSROOT=~/win9x-sysroot DLLS=~/win9x-dlls \
  sh tests/run-tests.sh
```

(`TARGETS="i586-pc-windows5.0-gnu i586-pc-windows5.1-gnu"` with a 2000/XP
sysroot, `TARGETS="i386-pc-windows3.10-gnu i386-pc-windows3.51-gnu
i386-pc-windows4.0-gnu"` with the crtdll one) builds `tests/hello.c`,
`tests/libc.c`, `tests/tchar.c` (a native ANSI build of generic-text code),
`tests/gui.c` and, when the sysroot has libunicows, `tests/unicode.c` (a
Unicode build with unicows) for 95, 98 and ME at `-O0`, `-O2` and `-Os`,
checks their imports and runs the console tests under Wine when it is
installed, with Wine reporting each target's Windows version. When the
sysroot has libc++, it also builds `tests/cxx.cpp` (iostreams, numbers through the C locale,
exceptions, RTTI), `tests/threads.cpp` (mutexes, condition variables,
`call_once`, thread IDs, `thread_local` destructors, futures,
`atomic::wait`), `tests/fs.cpp` (`<filesystem>`) and `tests/tlsmain.cpp`,
which loads `tests/tlsdll.cpp` with `LoadLibrary` and uses its
`thread_local` variables from several threads, and checks that the import
checker rejects a Vista kernel32 function and a Vista `msvcrt.dll` one. Wine does not limit programs to the
9x API, so a real Windows 9x machine is still the final test.

## Redistributing the SDK

The sysroots hold no Microsoft files and can be passed on freely: see
`NOTICE.md` for what each part is and its licence. `build-sysroot.sh`
puts the licences in each sysroot's `share/licenses/`. Programs built
with them should come with mingw-w64's runtime notice
(`share/licenses/mingw-w64/COPYING.MinGW-w64-runtime.txt`), as with any
mingw-w64 build.

```sh
sh tools/make-dist.sh ~/clang-dos-linux-x86_64 win32-sdk.tar.xz
```

makes the SDK on its own from an unpacked clang-dos package: the five
sysroots, their config files, the checkers and the licences, laid out to
unpack over a clang-dos package. dos-sdk's toolchain workflow makes it
with every package. Sysroots imported from Microsoft's own kits
(`tools/import-ms-sdk.py`, below) are never put in it.

## Microsoft's SDKs and DDKs

The sysroots above are made from mingw-w64. `tools/import-ms-sdk.py` makes
sysroots from Microsoft's own Win32 SDKs and DDKs instead, with their
headers, import libraries and C runtime, for code written against them.
Microsoft's kits can't be redistributed, so neither this repository nor
the toolchain package has any of their files: run the script once on your
own copies to add them to an unpacked toolchain package.

```sh
python3 tools/import-ms-sdk.py --sdks /path/to/WindowsSDKs ~/clang-dos
clang --config=ms-nt351.cfg -O2 hello.c -o hello.exe
```

`--sdks` is a folder holding the kits under the folder names below (an
installed tree or the unpacked CD; `--kit-dir KIT=FOLDER` gives one kit's
folder instead), and every kit found there is imported. Each one becomes
`sysroots/ms-KIT` and `bin/ms-KIT.cfg` in the package.

| Kit | Folder | Triple | From |
| --- | --- | --- | --- |
| `nt31` | `3.1 SDK DDK` | `i386-pc-windows3.10-msvc` | Win32 SDK for NT 3.1 (MSDN, October 1994) |
| `nt351` | `3.51 SDK` | `i386-pc-windows3.51-msvc` | Win32 SDK, June 1995, with NT 3.1's C runtime |
| `nt40` | `4.0 W95 SDK (expanded)` | `i486-pc-windows4.0-msvc` | Win32 SDK for NT 4.0 and 95, August 1996, with NT 3.1's C runtime |
| `w2k` | `5.2.3970.1830 DDK (unpacked)` | `i586-pc-windows5.0-msvc` | Server 2003 SP1 DDK, Windows 2000 headers and libraries |
| `xp` | `5.2.3970.1830 DDK (unpacked)` | `i586-pc-windows5.1-msvc` | Server 2003 SP1 DDK, XP headers and libraries |
| `ws03` | `5.2.3970.1830 DDK (unpacked)` | `i586-pc-windows5.2-msvc` | Server 2003 SP1 DDK |
| `ws03-x64` | `5.2.3970.1830 DDK (unpacked)` | `x86_64-pc-windows5.2-msvc` | Server 2003 SP1 DDK, x64 |

* The kits are used as Microsoft shipped them, so the 1996 SDK's
  compressed `.LI_` files must be expanded first (`expand -r`) and the
  DDKs' CABs unpacked into the tree their setup installs (`WINDDK\`).
  The Aug 1996 SDK and the June 1995 one have no i386 C runtime library,
  so they take the NT 3.1 SDK's, which also runs on 95 and NT 4.0.
* The triples are MSVC ones, so programs use Microsoft's ABI and C
  runtime (statically, `libcmt.lib` or `libc.lib`, whichever the kit has),
  not mingw-w64's. As with the MinGW triples, the Windows version in the
  triple sets the default CPU and, with LLD, the subsystem and OS version
  the linker writes, and for NT 3.x a writable `.rdata`.
* The config file sets `-fms-compatibility-version` to the compiler the
  kit came with, defines `_X86_` (or `_AMD64_`), which early headers want
  from the makefile, and links the kit's C runtime instead of clang's
  default `libcmt` and `oldnames`.
* On a case-sensitive file system the headers and libraries are copied
  with lower-case names, and `vfs.yaml`, a case-insensitive overlay the
  config file passes with `-vfsoverlay`, lets `#include <Windows.h>` and a
  library's `/DEFAULTLIB:LIBC` find them, as on Windows.
* The libraries of the 1993 to 1996 kits need fixing for LLD, which
  `ms_oldlib.py` does to the sysroot's copies (with the package's
  `llvm-lib`, or `--llvm-lib`): their archive headers are padded with
  NULs; their objects give sections an address, with relocations relative
  to it, and leave out the sections' access bits; and their long-format
  import libraries (a whole object per import) make LLD build an import
  table with a DLL's terminator in the middle, so they are rebuilt as
  short-format ones and checked against the originals. NT 3.1's
  `crtdll.lib` stays as it is, since its data imports (`_iob` and the
  like) have no short-format equivalent: use `libcmt`, the default.
* Those kits' C runtime predates `__int64` and asks for neither kernel32
  nor SafeSEH: their config files link `kernel32`, pass `-safeseh:no` and
  link `ll64.lib`, the 64-bit integer helpers (`__alldiv` and the like)
  taken from the Server 2003 DDK's `libcmt.lib` when that kit is imported
  too. Without it, 64-bit division doesn't link.
* The XP and Server 2003 kits' C runtime is built with `/GS`, so their
  config files link `bufferoverflowu`. The Server 2003 `winnt.h` declares
  `_interlockedbittestandset` and the like without `volatile`, which clang
  rejects, so `ms-ws03` and `ms-ws03-x64` include `ms-intrin-shim.h`
  first. The DDK's `inc/w2k` and `inc/wxp` lack four headers `windows.h`
  includes, which come from `inc/wnet`.
* C only: the kits' C++ libraries are for Microsoft's compilers of the
  time.

`tests/ms-sdk/run-test.sh` tests the script with two small fake kits.
`tests/ms-sdk/kits-test.py PACKAGE --run` builds and runs a program with
each imported kit, for testing with the real ones: all seven built and ran
on Windows 11 at `-O0` and `-O2`.

## License

BSD 3-Clause (see `LICENSE`). `scripts/build-unicows.sh` installs
libunicows's license (MIT) with it.
