/* The C library on Windows 9x: memory, stdio, files, strings, floating
 * point, 64-bit integers (compiler-rt), setjmp, constructors, atexit,
 * thread-local variables, time and the Win32 API. Prints ALL PASSED. */
#include <math.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <windows.h>

static int fails;
#define CHECK(c)                                                              \
  do {                                                                        \
    if (!(c)) {                                                               \
      printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                     \
      fails++;                                                                \
    }                                                                         \
  } while (0)

static int ctor_ran;
__attribute__((constructor)) static void ctor(void) { ctor_ran = 1; }
static void at_exit(void) { printf("atexit ran\n"); }

static jmp_buf jb;
static void jump(int v) { longjmp(jb, v); }

static int cmp(const void *a, const void *b) {
  return *(const int *)a - *(const int *)b;
}

/* Static TLS in an EXE works on 9x (only TLS callbacks do not run). */
static __thread int tls_value = 42;

static DWORD WINAPI thread_main(LPVOID arg) {
  tls_value = (int)(intptr_t)arg;
  return (DWORD)tls_value;
}

int main(void) {
  CHECK(ctor_ran);
  atexit(at_exit);

  /* Memory. */
  char *p = malloc(100000);
  CHECK(p != NULL);
  memset(p, 0x5a, 100000);
  p = realloc(p, 200000);
  CHECK(p && p[99999] == 0x5a);
  free(p);

  /* Strings and formatting. */
  char buf[128];
  snprintf(buf, sizeof buf, "%d %u %ld %s %c %5.2f %e %llx", -7, 7u, 123456L,
           "str", 'c', 3.14159, 1.5e10, 0x123456789abcdefULL);
  CHECK(strcmp(buf, "-7 7 123456 str c  3.14 1.500000e+10 123456789abcdef") ==
        0);
  CHECK(strtod("2.5e3", NULL) == 2500.0);
  CHECK(strtol("-0x10", NULL, 16) == -16);

  /* Floating point on the x87. */
  volatile double x = 2.0;
  CHECK(fabs(sqrt(x) - 1.41421356) < 1e-6);
  CHECK(fabs(sin(0.5) - 0.47942554) < 1e-6);
  CHECK(fabs(pow(x, 10) - 1024.0) < 1e-9);
  CHECK((int)floor(-2.5) == -3);

  /* 64-bit integers: division calls the compiler-rt builtins. */
  volatile uint64_t a = 0x123456789abcdefULL, b = 12345;
  CHECK(a / b == 0x60a45f5207dULL);
  CHECK(a % b == 0x221aULL);
  volatile int64_t n = -1000000000000LL;
  CHECK(n / 7 == -142857142857LL);

  /* Sorting. */
  int v[] = {5, 3, 9, 1, 7};
  qsort(v, 5, sizeof v[0], cmp);
  CHECK(v[0] == 1 && v[4] == 9);

  /* setjmp and longjmp. */
  int r = setjmp(jb);
  if (r == 0)
    jump(3);
  CHECK(r == 3);

  /* Files. */
  FILE *f = fopen("w9xtest.tmp", "w+b");
  CHECK(f != NULL);
  if (f) {
    CHECK(fwrite("abcdef", 1, 6, f) == 6);
    CHECK(fseek(f, 2, SEEK_SET) == 0);
    CHECK(fread(buf, 1, 4, f) == 4 && memcmp(buf, "cdef", 4) == 0);
    fclose(f);
  }
  CHECK(remove("w9xtest.tmp") == 0);

  /* Time. */
  time_t t = time(NULL);
  CHECK(t > 0);
  struct tm *tm = gmtime(&t);
  CHECK(tm && tm->tm_year >= 70);

  /* Threads and TLS. */
  CHECK(tls_value == 42);
  HANDLE h = CreateThread(NULL, 0, thread_main, (LPVOID)7, 0, NULL);
  CHECK(h != NULL);
  if (h) {
    DWORD code = 0;
    WaitForSingleObject(h, INFINITE);
    CHECK(GetExitCodeThread(h, &code) && code == 7);
    CloseHandle(h);
  }
  CHECK(tls_value == 42);

  /* The Win32 API, ANSI side. */
  char path[MAX_PATH];
  CHECK(GetModuleFileNameA(NULL, path, sizeof path) > 0);
  OSVERSIONINFOA vi = {sizeof vi};
  CHECK(GetVersionExA(&vi));
  printf("Windows %lu.%lu build %lu, platform %lu\n", vi.dwMajorVersion,
         vi.dwMinorVersion, vi.dwBuildNumber & 0xffff, vi.dwPlatformId);

  if (!fails)
    printf("ALL PASSED\n");
  return fails != 0;
}
