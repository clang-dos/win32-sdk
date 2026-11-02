// Threads on Windows 2000 and XP, which have no SRW locks, condition
// variables, one-time initialization or fiber local storage: libc++'s
// fallbacks for them, thread_local with emulated TLS, and exceptions in
// threads. Prints ALL PASSED.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <future>
#include <mutex>
#include <shared_mutex>
#include <stdexcept>
#include <thread>
#include <vector>

static int fails;
#define CHECK(c)                                                               \
  do {                                                                         \
    if (!(c)) {                                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);                 \
      fails++;                                                                 \
    }                                                                          \
  } while (0)

static std::atomic<int> tls_dtors;
struct PerThread {
  int value = 0;
  ~PerThread() { tls_dtors++; }
};
static thread_local PerThread per_thread;
static thread_local int tls_counter = 5;

int main() {
  // Mutex.
  std::mutex mu;
  long counter = 0;
  {
    std::vector<std::thread> ts;
    for (int t = 0; t < 4; t++)
      ts.emplace_back([&] {
        for (int i = 0; i < 20000; i++) {
          std::lock_guard<std::mutex> lock(mu);
          counter++;
        }
      });
    for (auto &t : ts)
      t.join();
  }
  CHECK(counter == 80000);
  CHECK(mu.try_lock());
  mu.unlock();

  // Condition variable: a producer and two consumers.
  std::deque<int> queue;
  std::condition_variable cv;
  bool done = false;
  std::atomic<long> sum{0};
  {
    auto consumer = [&] {
      for (;;) {
        std::unique_lock<std::mutex> lock(mu);
        cv.wait(lock, [&] { return !queue.empty() || done; });
        if (queue.empty())
          return;
        sum += queue.front();
        queue.pop_front();
      }
    };
    std::thread c1(consumer), c2(consumer);
    for (int i = 1; i <= 1000; i++) {
      {
        std::lock_guard<std::mutex> lock(mu);
        queue.push_back(i);
      }
      cv.notify_one();
    }
    {
      std::lock_guard<std::mutex> lock(mu);
      done = true;
    }
    cv.notify_all();
    c1.join();
    c2.join();
  }
  CHECK(sum == 500500);

  // A timed wait that times out.
  {
    std::unique_lock<std::mutex> lock(mu);
    auto start = std::chrono::steady_clock::now();
    bool woke = cv.wait_for(lock, std::chrono::milliseconds(50),
                            [] { return false; });
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                  std::chrono::steady_clock::now() - start)
                  .count();
    CHECK(!woke && ms >= 40);
  }

  // call_once, recursive and shared mutexes.
  std::once_flag once;
  std::atomic<int> once_runs{0};
  {
    std::vector<std::thread> ts;
    for (int t = 0; t < 4; t++)
      ts.emplace_back([&] { std::call_once(once, [&] { once_runs++; }); });
    for (auto &t : ts)
      t.join();
  }
  CHECK(once_runs == 1);
  std::recursive_mutex rm;
  rm.lock();
  CHECK(rm.try_lock());
  rm.unlock();
  rm.unlock();
  std::shared_mutex sm;
  {
    std::shared_lock<std::shared_mutex> r1(sm), r2(sm);
    CHECK(!sm.try_lock());
  }
  CHECK(sm.try_lock());
  sm.unlock();

  // Thread IDs: GetThreadId is from Server 2003.
  std::thread::id inner;
  std::thread t([&] { inner = std::this_thread::get_id(); });
  std::thread::id outer = t.get_id();
  t.join();
  CHECK(inner == outer && inner != std::this_thread::get_id());

  // thread_local: each thread has its own, and destructors run when the
  // thread exits.
  tls_counter = 100;
  per_thread.value = 1;
  int before = tls_dtors;
  {
    std::vector<std::thread> ts;
    for (int t = 0; t < 3; t++)
      ts.emplace_back([t] {
        CHECK(tls_counter == 5);
        tls_counter += t;
        per_thread.value = t;
      });
    for (auto &t : ts)
      t.join();
  }
  CHECK(tls_counter == 100 && per_thread.value == 1);
  CHECK(tls_dtors - before == 3);

  // Exceptions in threads and futures.
  auto f = std::async(std::launch::async, [] {
    throw std::runtime_error("from a thread");
    return 0;
  });
  bool caught = false;
  try {
    (void)f.get();
  } catch (const std::runtime_error &e) {
    caught = std::string(e.what()) == "from a thread";
  }
  CHECK(caught);
  std::promise<int> p;
  std::thread setter([&] { p.set_value(7); });
  CHECK(p.get_future().get() == 7);
  setter.join();

  // atomic wait and notify: WaitOnAddress is from Windows 8, so this polls.
  std::atomic<int> flag{0};
  std::thread waker([&] {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    flag = 1;
    flag.notify_one();
  });
  flag.wait(0);
  waker.join();
  CHECK(flag == 1);

  if (fails)
    std::printf("%d FAILED\n", fails);
  else
    std::printf("ALL PASSED\n");
  return fails != 0;
}
