/* A declaration as in the Server 2003 DDK's winnt.h. */
unsigned char _interlockedbittestandset(long *a, long b);
#pragma intrinsic(_interlockedbittestandset)
long x; int f(void){ return _interlockedbittestandset(&x, 3); }
