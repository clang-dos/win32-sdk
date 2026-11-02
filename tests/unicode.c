/* A Unicode build (-municode, UNICODE) linked with libunicows, so that the W
   functions go through unicows.dll on Windows 9x and to the system on NT. */
#ifndef UNICODE
#error "build with -municode"
#endif
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static int failures;

static void check(int ok, const char *what) {
  if (!ok) {
    printf("FAIL %s (error %lu)\n", what, (unsigned long)GetLastError());
    failures++;
  }
}

int wmain(int argc, wchar_t **argv) {
  wchar_t buf[MAX_PATH], dir[MAX_PATH], path[MAX_PATH];
  const wchar_t text[] = L"Grüße";
  char ansi[64];
  HANDLE h;
  DWORD n;
  WIN32_FIND_DATAW fd;

  check(argc >= 1 && argv[0] != NULL, "wmain arguments");
  check(argc < 2 || wcscmp(argv[1], L"arg") == 0, "argv[1]");

  check(GetModuleFileNameW(NULL, buf, MAX_PATH) > 0, "GetModuleFileNameW");
  check(wcsstr(buf, L".exe") != NULL || wcsstr(buf, L".EXE") != NULL,
        "module name");

  check(GetTempPathW(MAX_PATH, dir) > 0, "GetTempPathW");
  check(GetTempFileNameW(dir, L"uni", 0, path) != 0, "GetTempFileNameW");

  h = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                  FILE_ATTRIBUTE_NORMAL, NULL);
  check(h != INVALID_HANDLE_VALUE, "CreateFileW (write)");
  check(WriteFile(h, "unicows", 7, &n, NULL) && n == 7, "WriteFile");
  CloseHandle(h);

  h = CreateFileW(path, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
  check(h != INVALID_HANDLE_VALUE, "CreateFileW (read)");
  memset(ansi, 0, sizeof ansi);
  check(ReadFile(h, ansi, sizeof ansi - 1, &n, NULL) && n == 7 &&
            strcmp(ansi, "unicows") == 0,
        "ReadFile");
  CloseHandle(h);

  h = FindFirstFileW(path, &fd);
  check(h != INVALID_HANDLE_VALUE, "FindFirstFileW");
  if (h != INVALID_HANDLE_VALUE) {
    check(fd.nFileSizeLow == 7, "FindFirstFileW size");
    FindClose(h);
  }
  check(GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES,
        "GetFileAttributesW");
  check(DeleteFileW(path), "DeleteFileW");

  check(SetEnvironmentVariableW(L"UNICOWS_TEST", L"yes"),
        "SetEnvironmentVariableW");
  check(GetEnvironmentVariableW(L"UNICOWS_TEST", buf, MAX_PATH) == 3 &&
            wcscmp(buf, L"yes") == 0,
        "GetEnvironmentVariableW");

  wcscpy(buf, L"abc");
  CharUpperW(buf);
  check(wcscmp(buf, L"ABC") == 0, "CharUpperW");
  check(lstrcmpiW(L"Hello", L"HELLO") == 0, "lstrcmpiW");
  wsprintfW(buf, L"%d-%s", 42, L"x");
  check(wcscmp(buf, L"42-x") == 0, "wsprintfW");

  /* Text in the ANSI code page goes both ways. */
  n = WideCharToMultiByte(CP_ACP, 0, text, -1, ansi, sizeof ansi, NULL, NULL);
  check(n > 0, "WideCharToMultiByte");
  check(MultiByteToWideChar(CP_ACP, 0, ansi, -1, buf, MAX_PATH) == (int)n &&
            (GetACP() != 1252 || wcscmp(buf, text) == 0),
        "MultiByteToWideChar");

  /* Wide C library functions that need no file system. */
  swprintf(buf, MAX_PATH, L"%ls=%d", L"n", 7);
  check(wcscmp(buf, L"n=7") == 0, "swprintf");
  check(wcstol(L"-123", NULL, 10) == -123, "wcstol");

  if (failures)
    printf("%d FAILED\n", failures);
  else
    printf("ALL PASSED\n");
  return failures != 0;
}
