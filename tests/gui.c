/* A Windows 9x GUI program: shows a message box. Build with -mwindows. */
#include <windows.h>

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show) {
  (void)inst;
  (void)prev;
  (void)cmd;
  (void)show;
  MessageBoxA(NULL, "Built with clang for Windows 9x.", "clang",
              MB_OK | MB_ICONINFORMATION);
  return 0;
}
