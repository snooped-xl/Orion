Based on desktop_multi_window 0.3.1 (Apache-2.0 LICENSE retained).

Linux delays GtkWindow realization until after WindowCreatedCallback. Orion wraps the FlView in a native GtkOverlay for its per-engine Monaco surface; reparenting an already realized FlView invalidates its GL context. The FlView is explicitly realized after the callback so hidden child engines can produce their first frame without being mapped.

A native window_destroy recovery operation destroys a hidden child allocation if its engine fails before startup completes. Normal closes still flush and acknowledge editor commands before destruction. The upstream Dart public APIs are unchanged.

The root runner chooses an RGBA visual before child realization and registers each child's Monaco/window channels. Upstream Dart APIs are retained. Windows child engines receive the same per-engine native registration. Windows also provides the recovery window_destroy method, acknowledging the platform reply before destroying the child on its next window message.

Linux child creation preserves and temporarily releases the current GTK GL context while its engine initializes. The Flutter application-exit handler is disconnected after child realization so closing a companion only closes that window.

The root runner also applies the pinned Flutter Linux TaskRunner timeout-data ownership fix described in `linux/runner/NATIVE_LIFETIME.md`. It holds a runner only for the lifetime of its pending or dispatching timer through GLib's public destroy-notifier API; it does not pool or permanently retain companion engines.
