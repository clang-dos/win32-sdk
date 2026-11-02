/* A native ANSI build: generic-text (TCHAR) code compiles to the A functions
 * unless UNICODE is defined, which a Windows 9x program must not do.
 * check-imports.py fails the build if a W function slips in.
 * Prints ALL PASSED. */
#include <stdio.h>
#include <string.h>
#include <tchar.h>
#include <windows.h>

#if defined(UNICODE) || defined(_UNICODE)
#error "Windows 9x programs are native ANSI builds; do not define UNICODE"
#endif

static int fails;
#define CHECK(c)                                                              \
  do {                                                                        \
    if (!(c)) {                                                               \
      printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                     \
      fails++;                                                                \
    }                                                                         \
  } while (0)

int _tmain(int argc, TCHAR **argv) {
  CHECK(sizeof(TCHAR) == 1);
  CHECK(argc >= 1 && _tcslen(argv[0]) > 0);

  TCHAR path[MAX_PATH];
  DWORD n = GetModuleFileName(NULL, path, MAX_PATH);
  CHECK(n > 0 && n < MAX_PATH);

  TCHAR dir[MAX_PATH];
  CHECK(GetTempPath(MAX_PATH, dir) > 0);
  TCHAR file[MAX_PATH];
  CHECK(GetTempFileName(dir, _T("w9x"), 0, file) != 0);

  HANDLE h = CreateFile(file, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  CHECK(h != INVALID_HANDLE_VALUE);
  if (h != INVALID_HANDLE_VALUE) {
    DWORD done = 0;
    CHECK(WriteFile(h, "ansi", 4, &done, NULL) && done == 4);
    CloseHandle(h);
  }
  WIN32_FIND_DATA fd;
  HANDLE f = FindFirstFile(file, &fd);
  CHECK(f != INVALID_HANDLE_VALUE && fd.nFileSizeLow == 4);
  if (f != INVALID_HANDLE_VALUE)
    FindClose(f);
  CHECK(DeleteFile(file));

  TCHAR env[64];
  CHECK(SetEnvironmentVariable(_T("W9XTEST"), _T("yes")));
  CHECK(GetEnvironmentVariable(_T("W9XTEST"), env, 64) == 3 &&
        _tcscmp(env, _T("yes")) == 0);

  TCHAR up[] = _T("ansi");
  CharUpper(up);
  CHECK(lstrcmp(up, _T("ANSI")) == 0);

  if (!fails)
    _tprintf(_T("ALL PASSED\n"));
  return fails != 0;
}
