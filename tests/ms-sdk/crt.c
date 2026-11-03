/* A fake C runtime: what the kit's LIBC.LIB would hold. */
#pragma comment(lib, "KERNEL32") /* as in Microsoft's */
typedef void *HANDLE;
typedef unsigned long DWORD;
__declspec(dllimport) HANDLE __stdcall GetStdHandle(DWORD);
__declspec(dllimport) int __stdcall WriteFile(HANDLE, const void *, DWORD,
                                              DWORD *, void *);
__declspec(dllimport) void __stdcall ExitProcess(unsigned);
#define STD_OUTPUT_HANDLE ((DWORD)-11)
int main(void);
int puts(const char *s) {
  DWORD n, len = 0;
  while (s[len]) len++;
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), s, len, &n, 0);
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), "\n", 1, &n, 0);
  return 0;
}
void mainCRTStartup(void) { ExitProcess(main()); }
