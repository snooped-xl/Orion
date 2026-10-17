#ifndef RUNNER_WINDOW_PROCESS_IDENTITY_H_
#define RUNNER_WINDOW_PROCESS_IDENTITY_H_

#include <gtk/gtk.h>
#include <gdk/gdkx.h>

namespace orion {

inline void publish_window_process_identity(GtkWidget* window) {
  const guint32 host_pid = GPOINTER_TO_UINT(
      g_object_get_data(G_OBJECT(window), "orion-window-host-pid"));
  GdkWindow* native = gtk_widget_get_window(window);
  if (host_pid < 2 || native == nullptr ||
      !GDK_IS_X11_DISPLAY(gtk_widget_get_display(window))) return;
  // GDK/Xlib use native-long storage for format-32 properties. X11 clients in
  // a Flatpak namespace otherwise advertise their local PID to host Mutter.
  const gulong value = host_pid;
  gdk_property_change(native, gdk_atom_intern_static_string("_NET_WM_PID"),
      gdk_atom_intern_static_string("CARDINAL"), 32, GDK_PROP_MODE_REPLACE,
      reinterpret_cast<const guchar*>(&value), 1);
}

inline void set_window_process_identity(GtkWindow* window, guint32 host_pid) {
  if (host_pid < 2) return;
  g_object_set_data(G_OBJECT(window), "orion-window-host-pid", GUINT_TO_POINTER(host_pid));
  if (g_object_get_data(G_OBJECT(window), "orion-window-host-pid-attached") == nullptr) {
    g_object_set_data(G_OBJECT(window), "orion-window-host-pid-attached", GINT_TO_POINTER(1));
    g_signal_connect(window, "realize", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
      publish_window_process_identity(widget);
    }), nullptr);
  }
  publish_window_process_identity(GTK_WIDGET(window));
}

}  // namespace orion

#endif  // RUNNER_WINDOW_PROCESS_IDENTITY_H_
