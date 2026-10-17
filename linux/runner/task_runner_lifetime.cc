#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <dlfcn.h>
#include <glib-object.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {
using TimeoutAdd = guint (*)(guint, GSourceFunc, gpointer);

TimeoutAdd original_timeout_add = nullptr;
std::once_flag initialized;
std::mutex callback_mutex;
GSourceFunc task_runner_callback = nullptr;
void* flutter_module = nullptr;
bool trace_enabled = false;
std::atomic<unsigned long> timers_created{0};
std::atomic<unsigned long> timers_released{0};
std::atomic<unsigned long> runners_seen{0};
std::atomic<unsigned long> runners_finalized{0};

void report_lifetime_counts() {
  const auto created = timers_created.load();
  const auto released = timers_released.load();
  std::fprintf(stderr,
               "Orion task source ownership: timers=%lu released=%lu active=%lu "
               "runners=%lu finalized=%lu\n",
               created, released, created - released, runners_seen.load(),
               runners_finalized.load());
}

void initialize() {
  // The executable exports just g_timeout_add, so RTLD_NEXT resolves GLib's
  // implementation. All calls outside the one audited Flutter timer pass through.
  *reinterpret_cast<void**>(&original_timeout_add) =
      dlsym(RTLD_NEXT, "g_timeout_add");
  Dl_info info{};
  void* project_new = dlsym(RTLD_DEFAULT, "fl_dart_project_new");
  if (project_new != nullptr && dladdr(project_new, &info) != 0) {
    flutter_module = info.dli_fbase;
  }
  const char* trace = g_getenv("ORION_TASK_RUNNER_TRACE");
  trace_enabled = trace != nullptr && std::strcmp(trace, "1") == 0;
  if (trace_enabled) std::atexit(report_lifetime_counts);
}

bool is_task_runner_timeout(GSourceFunc callback, gpointer data) {
  if (flutter_module == nullptr || data == nullptr || callback == nullptr) {
    return false;
  }
  Dl_info info{};
  if (dladdr(reinterpret_cast<void*>(callback), &info) == 0 ||
      info.dli_fbase != flutter_module) {
    return false;
  }
  std::lock_guard<std::mutex> lock(callback_mutex);
  if (task_runner_callback != nullptr && task_runner_callback != callback) {
    return false;
  }
  // In Flutter 3.47.7's audited Linux embedder the sole g_timeout_add call is
  // fl_task_runner_tasks_did_change_locked. At registration its userdata is a
  // live FlTaskRunner. Inspect only its public GObject type, never its fields.
  // Re-audit this guard when upgrading Flutter; see NATIVE_LIFETIME.md.
  const GType expected = g_type_from_name("FlTaskRunner");
  if (expected == 0 || !G_TYPE_CHECK_INSTANCE_TYPE(data, expected)) return false;
  task_runner_callback = callback;
  return true;
}

struct OwnedTimeout {
  GObject* runner;
  GSourceFunc callback;
};

gboolean dispatch_timeout(gpointer data) {
  auto* timeout = static_cast<OwnedTimeout*>(data);
  return timeout->callback(timeout->runner);
}

void destroy_timeout(gpointer data) {
  auto* timeout = static_cast<OwnedTimeout*>(data);
  if (trace_enabled) ++timers_released;
  // GLib calls this after the selected dispatch finishes, or when a pending
  // source is removed. The runner therefore survives the callback's first cast.
  g_object_unref(timeout->runner);
  delete timeout;
}

void runner_finalized(gpointer, GObject*) {
  ++runners_finalized;
}

void observe_runner(GObject* runner) {
  static const GQuark observed =
      g_quark_from_static_string("orion-task-source-lifetime-observed");
  if (g_object_replace_qdata(runner, observed, nullptr, GINT_TO_POINTER(1),
                            nullptr, nullptr)) {
    ++runners_seen;
    g_object_weak_ref(runner, runner_finalized, nullptr);
  }
}
}  // namespace

// This one explicitly exported ELF symbol intercepts the pinned embedder's raw
// callback-data timer. Unrelated GLib timeouts keep their original semantics.
extern "C" __attribute__((visibility("default"))) guint g_timeout_add(
    guint interval, GSourceFunc function, gpointer data) {
  std::call_once(initialized, initialize);
  if (!is_task_runner_timeout(function, data)) {
    return original_timeout_add != nullptr
               ? original_timeout_add(interval, function, data)
               : g_timeout_add_full(G_PRIORITY_DEFAULT, interval, function, data,
                                    nullptr);
  }
  GObject* runner = G_OBJECT(data);
  if (trace_enabled) observe_runner(runner);
  auto* timeout = new OwnedTimeout{G_OBJECT(g_object_ref(runner)), function};
  if (trace_enabled) ++timers_created;
  return g_timeout_add_full(G_PRIORITY_DEFAULT, interval, dispatch_timeout,
                            timeout, destroy_timeout);
}
