# What the Win32 SDK is made of

Every file in the Windows sysroots that this repository builds can be
passed on freely. None of them is taken from Microsoft's SDKs: the headers, the C
runtime start-up code and the import libraries are mingw-w64's, built
from source.

| Part | Where it is | From | Licence |
| --- | --- | --- | --- |
| Build scripts, config files, checkers | `bin/*.cfg`, `share/clang-dos/` | clang-dos/win32-sdk | BSD 3-Clause (`win32-sdk-LICENSE`) |
| Windows API headers | `include/` | mingw-w64 | Mostly public domain (`mingw-w64/DISCLAIMER.PD`); a few files carry notices of their own: ZPL 2.1 or LGPL 2.1 (some DirectX headers taken from Wine), and `dxcapi.h`, which Microsoft published under the University of Illinois licence (`mingw-w64/COPYING`) |
| C runtime start-up and import libraries | `lib/crt*.o`, `lib/lib*.a` | mingw-w64 | ZPL 2.1 and public domain (`mingw-w64/COPYING.MinGW-w64-runtime.txt`) |
| Compiler builtins, libc++, libc++abi, libunwind | `lib/libgcc.a`, `lib/libc++*.a`, `lib/libunwind.a`, `include/c++/` | LLVM | Apache 2.0 with LLVM exception (`LLVM-LICENSE.TXT`) |
| libunicows (95/98/ME sysroot) | `lib/libunicows.a` | libunicows 1.1.2 | MIT (`libunicows-LICENSE.txt`) |
| C library (`win32-picolibc` sysroot) | `lib/libc.a`, `lib/libm.a`, its C headers in `include/` | picolibc | BSD-style licences (`picolibc-COPYING`) |

Passing the SDK on means keeping these notices with it (they are in
`share/licenses/`). Programs built with it link the mingw-w64 start-up
code, and mingw-w64 asks that a program shipped in binary form comes with
`mingw-w64/COPYING.MinGW-w64-runtime.txt` (the same is true of any
mingw-w64 build). The LLVM parts that programs link (builtins, libc++)
need no notice, thanks to the LLVM exception.

Programs built with the `win32-picolibc` sysroot link picolibc instead of
the mingw-w64 start-up code. Its licences are BSD-style: a program shipped
in binary form should come with `picolibc-COPYING` (in its documentation,
for example).

The DLLs that programs call (`kernel32.dll`, `msvcrt.dll`, `crtdll.dll`,
`unicows.dll`, ...) are part of Windows and are not in the SDK.

`tools/import-ms-sdk.py` builds extra sysroots from copies
of Microsoft's own SDKs that the user already has. Those sysroots are for
the user's own use; they are never put in the SDK archives.
