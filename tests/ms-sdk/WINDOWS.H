/* A fake windows.h, as an SDK CD has it. */
#ifndef _X86_
#error the kit's headers need _X86_
#endif
#include <sys/TYPES.H>
typedef void *HANDLE;
typedef unsigned long DWORD;
typedef int BOOL;
#define STD_OUTPUT_HANDLE ((DWORD)-11)
__declspec(dllimport) HANDLE __stdcall GetStdHandle(DWORD);
__declspec(dllimport) BOOL __stdcall WriteFile(HANDLE, const void *, DWORD,
                                               DWORD *, void *);
__declspec(dllimport) void __stdcall ExitProcess(unsigned);
