/* Included (-include) before the Windows Server 2003 SP1 DDK's headers by
   the ms-ws03 and ms-ws03-x64 config files of import-ms-sdk.py.

   Their winnt.h declares _interlockedbittestandset and
   _interlockedbittestandreset (and the 64-bit forms on x64) without
   "volatile", which clang rejects as conflicting with its builtins. Route
   winnt.h's names to wrappers with the header's signature that call the
   builtins, so InterlockedBitTestAndSet and the like still work. */
#ifndef CLANG_DOS_MS_INTRIN_SHIM_H
#define CLANG_DOS_MS_INTRIN_SHIM_H
#if defined(__clang__) && defined(_MSC_VER)
#ifdef __cplusplus
extern "C" {
#endif
unsigned char _interlockedbittestandset(long volatile *, long);
unsigned char _interlockedbittestandreset(long volatile *, long);
static __inline unsigned char __clang_dos_ibts(long *b, long o)
{ return _interlockedbittestandset(b, o); }
static __inline unsigned char __clang_dos_ibtr(long *b, long o)
{ return _interlockedbittestandreset(b, o); }
#define _interlockedbittestandset __clang_dos_ibts
#define _interlockedbittestandreset __clang_dos_ibtr
#if defined(_M_X64) || defined(_M_AMD64)
unsigned char _interlockedbittestandset64(long long volatile *, long long);
unsigned char _interlockedbittestandreset64(long long volatile *, long long);
static __inline unsigned char __clang_dos_ibts64(long long *b, long long o)
{ return _interlockedbittestandset64(b, o); }
static __inline unsigned char __clang_dos_ibtr64(long long *b, long long o)
{ return _interlockedbittestandreset64(b, o); }
#define _interlockedbittestandset64 __clang_dos_ibts64
#define _interlockedbittestandreset64 __clang_dos_ibtr64
#endif
#ifdef __cplusplus
}
#endif
#endif
#endif
