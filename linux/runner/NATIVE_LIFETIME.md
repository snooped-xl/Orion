# Linux companion engine lifetime

Orion opens separate Flutter engines for theme editing and source interfaces'
options, script hubs and consoles. The runner selects GPU Skia through the public
`fl_dart_project_set_enable_impeller(project, FALSE)` API for the main project and
each companion project. `egl_lifetime.cc` keeps compositor-owned engine resources
alive until their renderer releases them and balances EGL display/context use.

## Task timeout ownership

The pinned Flutter SDK is 3.47.7, engine revision
`deb287481e3ce9468f3434937ced4240a70539ca`. Its Linux source file
`engine/src/flutter/shell/platform/linux/fl_task_runner.cc` schedules the sole
Linux embedder `g_timeout_add` call in
`fl_task_runner_tasks_did_change_locked` (lines 117–120). It passes a raw
`FlTaskRunner*` as callback data with no owned reference or destroy notifier.
`fl_task_runner_on_expired_timeout` casts and locks that pointer before taking a
temporary reference (lines 75–91). TaskRunner disposal removes the source, but
that does not keep the raw data alive across an already selected dispatch.

On NVIDIA Wayland, rapidly closing native companion engines reproduced a crash
at the callback's first `g_type_check_instance_cast`, confirmed by a full native
backtrace and disassembly of the bundled release library. Changing EGL teardown
or waiting before closing did not resolve this independent use-after-free.

`task_runner_lifetime.cc` changes only the audited source's callback ownership:

- The executable exports only a `g_timeout_add` adapter. Other timer calls are
  forwarded to the original GLib implementation with their existing semantics.
- The adapter verifies that the callback belongs to the same ELF module as the
  public `fl_dart_project_new` symbol, verifies public GObject type
  `FlTaskRunner`, and caches that exact callback address.
- A matching source uses `g_timeout_add_full`, holds one reference to its runner,
  and releases it through GLib's source destroy notifier after dispatch or
  cancellation. The original callback, interval, priority and source ID behavior
  are preserved. No private Flutter instance fields are accessed.
- The runner contains a weak engine reference. This fix does not retain engines
  in a pool or keep closed windows alive indefinitely.

Set `ORION_TASK_RUNNER_TRACE=1` during a disposable-profile native smoke run to
print created/released timeout counts and observed/finalized TaskRunner counts
on exit. Three repeated Wayland runs and an X11 run of the isolated ownership
adapter exercised all four studios and all auxiliary windows. Every completed
run released every timer reference and finalized all 15 runners.

Re-audit the callback guard and remove this adapter if upstream adopts owned
timeout data when upgrading Flutter. The public type check relies on the audited
fact that the pinned embedder has exactly one `g_timeout_add` caller; it must not
be broadened to arbitrary Flutter callbacks or arbitrary GLib data.
