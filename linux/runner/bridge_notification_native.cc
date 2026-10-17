#include "bridge_notification_native.h"

#include <cmath>
#include <cstring>
#include <signal.h>
#include <sys/prctl.h>
#include <unistd.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

namespace {
double number(FlValue* value, double fallback) {
  if (value == nullptr) return fallback;
  double result = fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    result = fl_value_get_float(value);
  } else if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    result = fl_value_get_int(value);
  }
  return std::isfinite(result) ? result : fallback;
}

void put_number(FlValue* map, const char* key, double value) {
  fl_value_set_string_take(map, key, fl_value_new_float(value));
}

void notification_finished(GObject* connection, GAsyncResult* result,
                           gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(connection), result, &error);
  if (reply == nullptr) {
    fl_method_call_respond_error(call, "notification_failed", error->message,
                                 nullptr, nullptr);
  } else {
    fl_method_call_respond_success(call, nullptr, nullptr);
  }
  g_object_unref(call);
}

void bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  if (connection == nullptr) {
    fl_method_call_respond_error(call, "notification_unavailable", error->message,
                                 nullptr, nullptr);
    g_object_unref(call);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* user = fl_value_lookup_string(args, "username");
  const gchar* username = fl_value_get_string(user);
  FlValue* subject_value = fl_value_lookup_string(args, "subject");
  const gchar* subject = subject_value != nullptr && fl_value_get_type(subject_value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(subject_value) : "Executor Connected!";
  g_autofree gchar* escaped_user = g_markup_escape_text(username, -1);
  g_autofree gchar* escaped_subject = g_markup_escape_text(subject, -1);
  g_autofree gchar* body = g_strdup_printf("%s\n%s", escaped_subject, escaped_user);
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "transient", g_variant_new_boolean(TRUE));
  g_variant_builder_add(&hints, "{sv}", "suppress-sound", g_variant_new_boolean(TRUE));
  g_variant_builder_add(&hints, "{sv}", "desktop-entry", g_variant_new_string("dev.snooped.orion"));
  g_variant_builder_add(&hints, "{sv}", "x", g_variant_new_int32(static_cast<gint32>(number(fl_value_lookup_string(args, "x"), 0))));
  g_variant_builder_add(&hints, "{sv}", "y", g_variant_new_int32(static_cast<gint32>(number(fl_value_lookup_string(args, "y"), 0))));
  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  g_dbus_connection_call(
      connection, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify",
      g_variant_new("(susssasa{sv}i)", "Orion", 0u, "network-connect",
                    "Orion Bridge", body, &actions, &hints, 4000),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr,
      notification_finished, call);
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* window = GTK_WINDOW(data);
  const char* method = fl_method_call_get_name(call);
  if (std::strcmp(method, "monitor") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkWindow* surface = gtk_widget_get_window(GTK_WIDGET(window));
    GdkMonitor* monitor = surface == nullptr
        ? gdk_display_get_primary_monitor(display)
        : gdk_display_get_monitor_at_window(display, surface);
    if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
      monitor = gdk_display_get_monitor(display, 0);
    }
    GdkRectangle area{0, 0, 1920, 1080};
    if (monitor != nullptr) gdk_monitor_get_workarea(monitor, &area);
    g_autoptr(FlValue) result = fl_value_new_map();
    put_number(result, "x", area.x);
    put_number(result, "y", area.y);
    put_number(result, "width", area.width);
    put_number(result, "height", area.height);
    const gchar* backend = "x11";
#ifdef GDK_WINDOWING_WAYLAND
    if (GDK_IS_WAYLAND_DISPLAY(display)) backend = "wayland";
#endif
    fl_value_set_string_take(result, "backend", fl_value_new_string(backend));
    fl_method_call_respond_success(call, result, nullptr);
    return;
  }
  if (std::strcmp(method, "configure") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(call, "invalid_arguments", "Expected toast bounds.", nullptr, nullptr);
      return;
    }
    const double x = number(fl_value_lookup_string(args, "x"), 0);
    const double y = number(fl_value_lookup_string(args, "y"), 0);
    const double width = number(fl_value_lookup_string(args, "width"), 396);
    const double height = number(fl_value_lookup_string(args, "height"), 120);
    if (std::abs(x) > 131072 || std::abs(y) > 131072 ||
        width < 200 || width > 800 || height < 80 || height > 400) {
      fl_method_call_respond_error(call, "invalid_arguments", "Invalid toast bounds.", nullptr, nullptr);
      return;
    }
    // A forced owner exit must not leave a paused notification worker alive.
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) _exit(0);
    // Configure these before the first frame maps the worker's GtkWindow.
    gtk_window_set_accept_focus(window, FALSE);
    gtk_window_set_focus_on_map(window, FALSE);
    gtk_window_set_decorated(window, FALSE);
    gtk_window_set_skip_taskbar_hint(window, TRUE);
    gtk_window_set_skip_pager_hint(window, TRUE);
    gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_NOTIFICATION);
    gtk_window_set_keep_above(window, TRUE);
    gtk_window_set_resizable(window, FALSE);
    gtk_window_set_title(window, "Orion Bridge");
    gtk_window_set_default_size(window, static_cast<gint>(width), static_cast<gint>(height));
    gtk_window_resize(window, static_cast<gint>(width), static_cast<gint>(height));
    gtk_window_move(window, static_cast<gint>(x), static_cast<gint>(y));
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (std::strcmp(method, "notify") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* user = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(args, "username") : nullptr;
    if (user == nullptr || fl_value_get_type(user) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(call, "invalid_arguments", "Expected a username.", nullptr, nullptr);
      return;
    }
    // Fallback for a compositor without XWayland. The shell owns appearance and
    // placement in that exceptional path; never attempt to steal focus instead.
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, bus_ready, g_object_ref(call));
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}
}  // namespace

void bridge_notification_attach(GtkWindow* window, FlView* view) {
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "orion/bridge_notification", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, window, nullptr);
  g_object_set_data_full(G_OBJECT(window), "orion-bridge-notification-channel", channel, g_object_unref);
}
