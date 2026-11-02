// C++ on Windows 2000 and XP: iostreams, strings and containers, numbers
// through the C locale (msvcrt.dll there has no _l functions), exceptions
// and RTTI. Prints ALL PASSED.
#include <cstdio>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <typeinfo>
#include <vector>

static int fails;
#define CHECK(c)                                                               \
  do {                                                                         \
    if (!(c)) {                                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                 \
      fails++;                                                                 \
    }                                                                          \
  } while (0)

struct Base {
  virtual ~Base() {}
  virtual int f() const { return 1; }
};
struct Derived : Base {
  int f() const override { return 2; }
};

static int destroyed;
struct Guard {
  ~Guard() { destroyed++; }
};

[[gnu::noinline]] static void thrower(int v) {
  Guard g;
  if (v)
    throw std::runtime_error("boom " + std::to_string(v));
}

int main() {
  // Strings and containers.
  std::vector<std::string> v;
  for (int i = 0; i < 100; i++)
    v.push_back("item" + std::to_string(i));
  CHECK(v.size() == 100 && v[42] == "item42");
  std::map<std::string, int> m;
  for (int i = 0; i < 100; i++)
    m[v[i]] = i;
  CHECK(m["item99"] == 99 && m.size() == 100);

  // Numbers through streams and the C locale.
  std::ostringstream os;
  os << 42 << ' ' << -7L << ' ' << 3.25 << ' ' << 1e10 << ' ' << std::hex
     << 255;
  CHECK(os.str() == "42 -7 3.25 1e+10 ff");
  std::istringstream is("12 3.5 -0.125 abc");
  int i = 0;
  double d = 0, e = 0;
  std::string word;
  is >> i >> d >> e >> word;
  CHECK(i == 12 && d == 3.5 && e == -0.125 && word == "abc");
  CHECK(std::stod("2.5e3") == 2500.0);
  CHECK(std::stoi("-123") == -123);
  CHECK(std::to_string(1.5) == "1.500000");

  // Exceptions and unwinding.
  bool caught = false;
  try {
    thrower(7);
  } catch (const std::exception &ex) {
    caught = std::string(ex.what()) == "boom 7";
  }
  CHECK(caught && destroyed == 1);
  try {
    (void)std::vector<int>().at(3);
    CHECK(false);
  } catch (const std::out_of_range &) {
  }
  try {
    throw 42;
  } catch (int x) {
    CHECK(x == 42);
  }

  // RTTI.
  std::unique_ptr<Base> b(new Derived);
  CHECK(dynamic_cast<Derived *>(b.get()) != nullptr && b->f() == 2);
  Base &ref = *b;
  CHECK(typeid(ref) == typeid(Derived));

  std::cout << "cout works" << std::endl;
  if (fails)
    std::printf("%d FAILED\n", fails);
  else
    std::printf("ALL PASSED\n");
  return fails != 0;
}
