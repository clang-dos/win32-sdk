/* Built against each imported Microsoft kit by kits-test.py: the kit's
   windows.h and C runtime headers, its C runtime library and its import
   libraries. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  char buf[64];
  DWORD v = GetVersion();
  char *p = malloc(16);
  long long big = 1234567890123LL;
  strcpy(p, "kit");
  sprintf(buf, "%s %d.%d %.2f %ld", p, (int)LOBYTE(LOWORD(v)),
          (int)HIBYTE(LOWORD(v)), 3.25, (long)(big / 1000000));
  free(p);
  printf("hello from %s argc=%d\n", buf, argc);
  return strcmp(argv[0], "") == 0;
}
