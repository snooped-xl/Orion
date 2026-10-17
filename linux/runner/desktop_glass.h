#ifndef ORION_DESKTOP_GLASS_H_
#define ORION_DESKTOP_GLASS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Asynchronous, per-window integration with the optional GNOME compositor
// companion, including independent authenticated topmost window policy.
// No screen pixels cross this control-only D-Bus interface.
bool desktop_glass_handle(GtkWindow* window, FlMethodCall* call);
void desktop_glass_attach(GtkWindow* window);

#endif
