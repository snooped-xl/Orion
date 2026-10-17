#ifndef RUNNER_BRIDGE_NOTIFICATION_NATIVE_H_
#define RUNNER_BRIDGE_NOTIFICATION_NATIVE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Per-engine bridge toast methods; the owner resolves its actual GdkMonitor,
// while a separate non-activating XWayland worker owns the expressive card.
void bridge_notification_attach(GtkWindow* window, FlView* view);

#endif  // RUNNER_BRIDGE_NOTIFICATION_NATIVE_H_
