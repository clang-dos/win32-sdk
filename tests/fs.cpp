// <filesystem> on Windows 2000 and XP, which have no
// GetFileInformationByHandleEx, SetFileInformationByHandle or
// GetFinalPathNameByHandleW: libc++ calls ntdll there. Prints ALL PASSED.
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <set>
#include <string>
#include <system_error>

namespace fs = std::filesystem;

static int fails;
#define CHECK(c)                                                               \
  do {                                                                         \
    if (!(c)) {                                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                 \
      fails++;                                                                 \
    }                                                                          \
  } while (0)

int main() {
  std::error_code ec;
  fs::path dir = fs::temp_directory_path(ec) / "cxxfs-test";
  CHECK(!ec);
  fs::remove_all(dir, ec);
  CHECK(fs::create_directories(dir / "sub"));
  {
    std::ofstream(dir / "a.txt") << "hello";
  }
  CHECK(fs::exists(dir / "a.txt"));
  CHECK(fs::is_regular_file(dir / "a.txt") && fs::is_directory(dir / "sub"));
  CHECK(fs::file_size(dir / "a.txt") == 5);
  auto t = fs::last_write_time(dir / "a.txt");
  CHECK(t.time_since_epoch().count() != 0);

  // Permissions are the read-only attribute.
  const fs::perms all_write =
      fs::perms::owner_write | fs::perms::group_write | fs::perms::others_write;
  fs::permissions(dir / "a.txt", all_write, fs::perm_options::remove);
  CHECK((fs::status(dir / "a.txt").permissions() & all_write) ==
        fs::perms::none);
  fs::permissions(dir / "a.txt", fs::perms::owner_write, fs::perm_options::add);
  CHECK((fs::status(dir / "a.txt").permissions() & fs::perms::owner_write) !=
        fs::perms::none);

  fs::copy_file(dir / "a.txt", dir / "b.txt");
  fs::rename(dir / "b.txt", dir / "sub" / "c.txt");
  CHECK(!fs::exists(dir / "b.txt") && fs::exists(dir / "sub" / "c.txt"));
  CHECK(fs::equivalent(dir / "sub" / ".." / "a.txt", dir / "a.txt"));

  std::set<std::string> names;
  for (auto &e : fs::recursive_directory_iterator(dir))
    names.insert(e.path().filename().string());
  CHECK(names == std::set<std::string>({"a.txt", "c.txt", "sub"}));

  fs::path canon = fs::canonical(dir / "sub" / ".." / "a.txt");
  CHECK(canon.filename() == "a.txt" && fs::exists(canon));

  // Symbolic links to files are from Vista: on XP this fails cleanly.
  fs::create_symlink(dir / "a.txt", dir / "link", ec);
  std::printf("create_symlink: %s\n", ec ? ec.message().c_str() : "ok");

  CHECK(fs::remove(dir / "sub" / "c.txt"));
  CHECK(fs::remove_all(dir, ec) >= 2 && !ec);
  CHECK(!fs::exists(dir));

  if (fails)
    std::printf("%d FAILED\n", fails);
  else
    std::printf("ALL PASSED\n");
  return fails != 0;
}
