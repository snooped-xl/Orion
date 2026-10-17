#!/usr/bin/env python3
"""Exercise the exported native timeout adapter with public GObject fixtures.

Requires c++, pkg-config and gobject-2.0 development headers. No Flutter build,
display server, private instance layouts or user state is involved.
"""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile


FIXTURE = r"""
#include <glib-object.h>
typedef struct _FlTaskRunner { GObject parent; } FlTaskRunner;
typedef struct _FlTaskRunnerClass { GObjectClass parent; } FlTaskRunnerClass;
G_DEFINE_TYPE(FlTaskRunner, fl_task_runner, G_TYPE_OBJECT)
static void fl_task_runner_class_init(FlTaskRunnerClass*) {}
static void fl_task_runner_init(FlTaskRunner*) {}
static gboolean dispatch(gpointer data) {
  auto* runner = G_OBJECT(data);
  auto* calls = static_cast<int*>(g_object_get_data(runner, "calls"));
  ++*calls;
  return G_SOURCE_REMOVE;
}
extern "C" void* fl_dart_project_new() { return nullptr; }
extern "C" GObject* create_runner(int* calls) {
  auto* runner = G_OBJECT(g_object_new(fl_task_runner_get_type(), nullptr));
  g_object_set_data(runner, "calls", calls);
  return runner;
}
extern "C" guint schedule_runner(GObject* runner) {
  return g_timeout_add(1, dispatch, runner);
}
"""

TEST = r"""
#include <glib-object.h>
#include <cstdio>
extern "C" void* fl_dart_project_new();
extern "C" GObject* create_runner(int*);
extern "C" guint schedule_runner(GObject*);
static void finalized(gpointer data, GObject*) {
  ++*static_cast<int*>(data);
}
static gboolean ordinary_timeout(gpointer data) {
  ++*static_cast<int*>(data);
  return G_SOURCE_REMOVE;
}
static void check(bool condition, const char* label) {
  if (!condition) g_error("FAIL: %s", label);
}
int main() {
  fl_dart_project_new(); // Keep the fixture DSO in the dynamic symbol scope.
  int calls = 0, finalizations = 0;
  GObject* runner = create_runner(&calls);
  g_object_weak_ref(runner, finalized, &finalizations);
  schedule_runner(runner);
  g_object_unref(runner);
  check(finalizations == 0, "pending timeout must own the runner");
  while (calls == 0) g_main_context_iteration(nullptr, TRUE);
  check(calls == 1 && finalizations == 1,
        "dispatch must release the runner exactly once");

  runner = create_runner(&calls);
  g_object_weak_ref(runner, finalized, &finalizations);
  const guint id = schedule_runner(runner);
  g_object_unref(runner);
  check(finalizations == 1, "second pending timer owns its runner");
  check(g_source_remove(id), "source ID remains cancellable");
  check(calls == 1 && finalizations == 2,
        "cancellation releases its runner without calling it");

  int ordinary_calls = 0;
  g_timeout_add(1, ordinary_timeout, &ordinary_calls);
  while (ordinary_calls == 0) g_main_context_iteration(nullptr, TRUE);
  check(ordinary_calls == 1, "non-Flutter timer passes through unchanged");
  std::puts("TaskRunner timeout ownership: PASS (dispatch, cancel, pass-through)");
}
"""


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "linux/runner/task_runner_lifetime.cc"
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "gobject-2.0"], text=True))
    compiler = ["c++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror"]
    with tempfile.TemporaryDirectory(prefix="orion-task-lifetime-") as directory:
        directory = Path(directory)
        fixture = directory / "fixture.cc"
        test = directory / "test.cc"
        fixture.write_text(FIXTURE)
        test.write_text(TEST)
        subprocess.run(compiler + ["-shared", "-fPIC", str(fixture), *flags,
                       "-o", str(directory / "libfixture.so")], check=True)
        binary = directory / "lifetime_test"
        subprocess.run(compiler + [str(test), str(source), "-pthread", "-ldl",
                       "-L" + str(directory), "-lfixture", *flags,
                       "-Wl,-rpath," + str(directory),
                       "-Wl,--export-dynamic-symbol=g_timeout_add",
                       "-o", str(binary)], check=True)
        environment = dict(os.environ, ORION_TASK_RUNNER_TRACE="1")
        environment.pop("LD_PRELOAD", None)
        subprocess.run([str(binary)], env=environment, check=True, timeout=10)


if __name__ == "__main__":
    main()
