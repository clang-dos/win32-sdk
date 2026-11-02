// A DLL that the tlsmain test loads with LoadLibrary. Before Vista, Windows
// sets up native TLS only for DLLs loaded with the program, so this needs
// the emulated TLS that windows5.x triples use.
#include <stdexcept>
#include <string>

static thread_local int counter = 10;
static thread_local std::string name = "initial";

extern "C" __declspec(dllexport) int tls_bump(int by) {
  counter += by;
  name += "+";
  return counter + static_cast<int>(name.size());
}

extern "C" __declspec(dllexport) int tls_throw(int v) {
  try {
    if (v)
      throw std::runtime_error(std::to_string(v));
  } catch (const std::exception &e) {
    return std::stoi(e.what());
  }
  return 0;
}
