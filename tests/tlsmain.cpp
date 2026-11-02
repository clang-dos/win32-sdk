// Loads tlsdll.dll with LoadLibrary and uses its thread_local variables and
// exceptions from several threads. Prints ALL PASSED.
#include <cstdio>
#include <thread>
#include <vector>
#include <windows.h>

static int fails;
#define CHECK(c)                                                               \
  do {                                                                         \
    if (!(c)) {                                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                 \
      fails++;                                                                 \
    }                                                                          \
  } while (0)

int main(int argc, char **argv) {
  const char *dll = argc > 1 ? argv[1] : "tlsdll.dll";
  HMODULE m = LoadLibraryA(dll);
  CHECK(m != nullptr);
  if (!m) {
    std::printf("%d FAILED\n", fails);
    return 1;
  }
  auto bump = reinterpret_cast<int (*)(int)>(GetProcAddress(m, "tls_bump"));
  auto thrower = reinterpret_cast<int (*)(int)>(GetProcAddress(m, "tls_throw"));
  CHECK(bump && thrower);
  // counter + name.size(): 10 + 1 + 8, then 12 + 9.
  CHECK(bump(1) == 19 && bump(1) == 21);
  std::vector<std::thread> ts;
  int results[3] = {};
  for (int i = 0; i < 3; i++)
    ts.emplace_back([&, i] { results[i] = bump(i) + 100 * thrower(i + 1); });
  for (auto &t : ts)
    t.join();
  for (int i = 0; i < 3; i++)
    CHECK(results[i] == 10 + i + 8 + 100 * (i + 1));
  // The main thread's values are untouched: 12 + 10.
  CHECK(bump(0) == 22);
  FreeLibrary(m);
  if (fails)
    std::printf("%d FAILED\n", fails);
  else
    std::printf("ALL PASSED\n");
  return fails != 0;
}
