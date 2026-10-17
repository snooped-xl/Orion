#include "desktop_glass.h"
#include "session_bus_identity.h"
#include "window_process_identity.h"

#include <cmath>
#include <cstring>
#include <gdk/gdkx.h>

namespace {
constexpr const char* kBus = "org.orion.Glass";
constexpr const char* kPath = "/org/orion/Glass";
constexpr const char* kInterface = "org.orion.Glass1";
constexpr const char* kUnavailable =
    "{\"ok\":false,\"active\":false,\"reason\":\"unavailable\"}";

struct Request {
  FlMethodCall* call;
  GtkWindow* window;
  gchar* title;
  gchar* old_title;
  bool enabled;
  double radius;
};

void finish(Request* request, const char* result) {
  if (g_object_get_data(G_OBJECT(request->window),
                        "orion-desktop-glass-destroyed") == nullptr) {
    g_autoptr(FlValue) value = fl_value_new_string(result);
    fl_method_call_respond_success(request->call, value, nullptr);
  }
  g_object_unref(request->call);
  if (!request->enabled) {
    g_object_set_data(G_OBJECT(request->window), "orion-desktop-glass-bus", nullptr);
  }
  g_object_unref(request->window);
  g_free(request->title);
  g_free(request->old_title);
  delete request;
}

void configured(GObject* connection, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<Request*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(connection), result, &error);
  if (reply == nullptr) {
    finish(request, kUnavailable);
    return;
  }
  const gchar* json = nullptr;
  g_variant_get(reply, "(&s)", &json);
  finish(request, json == nullptr ? kUnavailable : json);
}

void glass_bus_identified(GDBusConnection* connection, guint32 host_pid, gpointer data) {
  auto* request = static_cast<Request*>(data);
  if (host_pid == 0) {
    finish(request, kUnavailable);
    return;
  }
  orion::set_window_process_identity(request->window, host_pid);
  if (g_object_get_data(G_OBJECT(request->window),
                        "orion-desktop-glass-destroyed") != nullptr) {
    // The bus lookup can finish after GTK has destroyed its window. Retire
    // the pending registration instead of leaving an enabled rule behind.
    request->enabled = false;
  }
  if (request->enabled) {
    // The compositor's rule is tied to this bus sender. Retain the shared
    // connection for the window lifetime, including when no other GIO user
    // happens to retain it between polling requests.
    g_object_set_data_full(G_OBJECT(request->window), "orion-desktop-glass-bus",
                          g_object_ref(connection), g_object_unref);
  }
  if (request->old_title != nullptr) {
    // A preserved interface can change its native title without ending the
    // process. Retire only this window's former registration before replacing it.
    g_dbus_connection_call(
        connection, kBus, kPath, kInterface, "Configure",
        g_variant_new("(usbd)", host_pid,
                      request->old_title, FALSE, request->radius),
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr,
        nullptr, nullptr);
  }
  g_dbus_connection_call(
      connection, kBus, kPath, kInterface, "Configure",
      g_variant_new("(usbd)", host_pid, request->title,
                    request->enabled, request->radius),
      G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr,
      configured, request);
}

void bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  orion::resolve_session_bus_pid(connection, glass_bus_identified, data);
}

// Topmost is independent of optical material and retains its own policy
// registration/connection, including while the glass viewport is disabled.
struct TopmostRequest {
  FlMethodCall* call;
  GtkWindow* window;
  gchar* title;
  gchar* old_title;
  bool enabled;
  gsize generation;
};

gsize topmost_generation(GtkWindow* window) {
  return GPOINTER_TO_SIZE(g_object_get_data(G_OBJECT(window), "orion-topmost-generation"));
}

bool topmost_current(TopmostRequest* request) {
  return topmost_generation(request->window) == request->generation;
}

void finish_topmost(TopmostRequest* request, const char* json) {
  const bool current = topmost_current(request);
  if (g_object_get_data(G_OBJECT(request->window), "orion-desktop-glass-destroyed") == nullptr) {
    g_autoptr(FlValue) value = fl_value_new_string(current ? json :
        "{\"ok\":false,\"active\":false,\"reason\":\"superseded\"}");
    fl_method_call_respond_success(request->call, value, nullptr);
  }
  if (current && !request->enabled)
    g_object_set_data(G_OBJECT(request->window), "orion-topmost-bus", nullptr);
  g_object_unref(request->call);
  g_object_unref(request->window);
  g_free(request->title);
  g_free(request->old_title);
  delete request;
}

void topmost_configured(GObject* connection, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<TopmostRequest*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(connection), result, &error);
  const gchar* json = nullptr;
  if (reply != nullptr) g_variant_get(reply, "(&s)", &json);
  finish_topmost(request, json == nullptr ? kUnavailable : json);
}

void topmost_bus_identified(GDBusConnection* connection, guint32 host_pid, gpointer data) {
  auto* request = static_cast<TopmostRequest*>(data);
  if (!topmost_current(request)) { finish_topmost(request, kUnavailable); return; }
  if (host_pid == 0) { finish_topmost(request, kUnavailable); return; }
  orion::set_window_process_identity(request->window, host_pid);
  if (g_object_get_data(G_OBJECT(request->window), "orion-desktop-glass-destroyed") != nullptr)
    request->enabled = false;
  if (request->enabled)
    g_object_set_data_full(G_OBJECT(request->window), "orion-topmost-bus", g_object_ref(connection), g_object_unref);
  if (request->old_title != nullptr)
    g_dbus_connection_call(connection, kBus, kPath, kInterface, "SetAlwaysOnTop",
        g_variant_new("(usb)", host_pid, request->old_title, FALSE),
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr, nullptr, nullptr);
  g_dbus_connection_call(connection, kBus, kPath, kInterface, "SetAlwaysOnTop",
      g_variant_new("(usb)", host_pid, request->title, request->enabled),
      G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr,
      topmost_configured, request);
}

void topmost_bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  orion::resolve_session_bus_pid(connection, topmost_bus_identified, data);
}

bool handle_topmost(GtkWindow* window, FlMethodCall* call) {
  if (std::strcmp(fl_method_call_get_name(call), "setAlwaysOnTop") != 0) return false;
  FlValue* args = fl_method_call_get_args(call);
  FlValue* enabled = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, "enabled") : nullptr;
  if (enabled == nullptr || fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL) {
    fl_method_call_respond_error(call, "invalid_arguments", "Expected an always-on-top boolean.", nullptr, nullptr);
    return true;
  }
  const bool value = fl_value_get_bool(enabled);
  if (GDK_IS_X11_DISPLAY(gtk_widget_get_display(GTK_WIDGET(window)))) {
    gtk_window_set_keep_above(window, value);
    GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window));
    const bool above = native != nullptr && (gdk_window_get_state(native) & GDK_WINDOW_STATE_ABOVE) != 0;
    g_autofree gchar* json = g_strdup_printf(
        "{\"ok\":true,\"active\":%s,\"above\":%s,\"requested\":%s,\"mode\":\"gtk-x11\",\"reason\":\"%s\"}",
        value && above ? "true" : "false", above ? "true" : "false", value ? "true" : "false",
        value == above ? "applied" : "pending-window-manager");
    g_autoptr(FlValue) response = fl_value_new_string(json);
    fl_method_call_respond_success(call, response, nullptr);
    return true;
  }
  const char* current = gtk_window_get_title(window);
  const auto* previous = static_cast<const char*>(g_object_get_data(G_OBJECT(window), "orion-topmost-title"));
  const char* title = !value && previous != nullptr ? previous : current;
  if (title == nullptr || *title == '\0') {
    g_autoptr(FlValue) response = fl_value_new_string("{\"ok\":false,\"active\":false,\"reason\":\"waiting-window\"}");
    fl_method_call_respond_success(call, response, nullptr);
    return true;
  }
  const gsize generation = topmost_generation(window) + 1;
  g_object_set_data(G_OBJECT(window), "orion-topmost-generation", GSIZE_TO_POINTER(generation));
  auto* request = new TopmostRequest{FL_METHOD_CALL(g_object_ref(call)), GTK_WINDOW(g_object_ref(window)),
      g_strdup(title), value && previous != nullptr && std::strcmp(previous, title) != 0 ? g_strdup(previous) : nullptr,
      value, generation};
  g_object_set_data_full(G_OBJECT(window), "orion-topmost-title", value ? g_strdup(title) : nullptr, g_free);
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, topmost_bus_ready, request);
  return true;
}

// Wayland deliberately has no client-side global window positioning. This
// one-shot authenticated request lets Mutter place only the caller's exact
// main window when it maps, after Dart has applied its saved window profile.
struct StartupPlacementRequest {
  FlMethodCall* call;
  GtkWindow* window;
  gchar* title;
  const char* method;
};

void finish_startup_placement(StartupPlacementRequest* request, const char* json) {
  if (g_object_get_data(G_OBJECT(request->window), "orion-desktop-glass-destroyed") == nullptr) {
    g_object_set_data_full(G_OBJECT(request->window), "orion-startup-placement-result",
                          g_strdup(json), g_free);
    g_autoptr(FlValue) response = fl_value_new_string(json);
    fl_method_call_respond_success(request->call, response, nullptr);
  }
  g_object_unref(request->call);
  g_object_unref(request->window);
  g_free(request->title);
  delete request;
}

void startup_placement_configured(GObject* connection, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<StartupPlacementRequest*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(connection), result, &error);
  const gchar* json = nullptr;
  if (reply != nullptr) g_variant_get(reply, "(&s)", &json);
  finish_startup_placement(request, json == nullptr ? kUnavailable : json);
}

void startup_placement_bus_identified(GDBusConnection* connection, guint32 host_pid, gpointer data) {
  auto* request = static_cast<StartupPlacementRequest*>(data);
  if (host_pid == 0 ||
      g_object_get_data(G_OBJECT(request->window), "orion-desktop-glass-destroyed") != nullptr) {
    finish_startup_placement(request, kUnavailable);
    return;
  }
  orion::set_window_process_identity(request->window, host_pid);
  g_object_set_data_full(G_OBJECT(request->window), "orion-startup-placement-bus",
                        g_object_ref(connection), g_object_unref);
  g_dbus_connection_call(connection, kBus, kPath, kInterface, request->method,
      g_variant_new("(us)", host_pid, request->title),
      G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr,
      startup_placement_configured, request);
}

void startup_placement_bus_ready(GObject*, GAsyncResult* result, gpointer data) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  orion::resolve_session_bus_pid(connection, startup_placement_bus_identified, data);
}

bool handle_startup_placement(GtkWindow* window, FlMethodCall* call) {
  const char* method = fl_method_call_get_name(call);
  const bool apply = std::strcmp(method, "applyStartupPlacement") == 0;
  const bool complete = std::strcmp(method, "completeStartupPlacement") == 0;
  FlValue* args = fl_method_call_get_args(call);
  FlValue* follow = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, "followInitialResize") : nullptr;
  const bool tracking = follow != nullptr && fl_value_get_type(follow) == FL_VALUE_TYPE_BOOL &&
      fl_value_get_bool(follow);
  if (apply && !tracking) {
    const auto* result = static_cast<const char*>(
        g_object_get_data(G_OBJECT(window), "orion-startup-placement-result"));
    g_autoptr(FlValue) response = fl_value_new_string(result == nullptr ? kUnavailable : result);
    fl_method_call_respond_success(call, response, nullptr);
    return true;
  }
  if (!apply && !complete && std::strcmp(method, "prepareStartupPlacement") != 0) return false;
  const char* title = gtk_window_get_title(window);
  if (title == nullptr || *title == '\0') {
    g_autoptr(FlValue) response = fl_value_new_string(kUnavailable);
    fl_method_call_respond_success(call, response, nullptr);
    return true;
  }
  auto* request = new StartupPlacementRequest{FL_METHOD_CALL(g_object_ref(call)),
      GTK_WINDOW(g_object_ref(window)), g_strdup(title),
      complete ? "FinishStartupPlacement" : apply ? "TrackStartupResize" : "CenterOnPointerMonitor"};
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, startup_placement_bus_ready, request);
  return true;
}

void window_destroyed(GtkWidget* widget, gpointer) {
  g_object_set_data(G_OBJECT(widget), "orion-desktop-glass-destroyed",
                    GINT_TO_POINTER(1));
  const auto* title = static_cast<const char*>(
      g_object_get_data(G_OBJECT(widget), "orion-desktop-glass-title"));
  auto* connection = static_cast<GDBusConnection*>(
      g_object_get_data(G_OBJECT(widget), "orion-desktop-glass-bus"));
  const guint32 glass_pid = orion::cached_session_bus_pid(connection);
  if (title != nullptr && glass_pid != 0) {
    // Engine teardown need not unmount Dart widgets. The window itself owns
    // the final cleanup, including companions while the main process lives.
    g_dbus_connection_call(
        connection, kBus, kPath, kInterface, "Configure",
        g_variant_new("(usbd)", glass_pid, title, FALSE, 0.0),
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr,
        nullptr, nullptr);
  }
  const auto* top_title = static_cast<const char*>(g_object_get_data(G_OBJECT(widget), "orion-topmost-title"));
  auto* top_bus = static_cast<GDBusConnection*>(g_object_get_data(G_OBJECT(widget), "orion-topmost-bus"));
  const guint32 top_pid = orion::cached_session_bus_pid(top_bus);
  if (top_title != nullptr && top_pid != 0)
    g_dbus_connection_call(top_bus, kBus, kPath, kInterface, "SetAlwaysOnTop",
        g_variant_new("(usb)", top_pid, top_title, FALSE),
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1200, nullptr, nullptr, nullptr);
  g_object_set_data(G_OBJECT(widget), "orion-topmost-title", nullptr);
  g_object_set_data(G_OBJECT(widget), "orion-topmost-bus", nullptr);
  g_object_set_data(G_OBJECT(widget), "orion-desktop-glass-title", nullptr);
  g_object_set_data(G_OBJECT(widget), "orion-desktop-glass-bus", nullptr);
}
}  // namespace

void desktop_glass_attach(GtkWindow* window) {
  if (g_object_get_data(G_OBJECT(window), "orion-desktop-glass-attached")) return;
  g_object_set_data(G_OBJECT(window), "orion-desktop-glass-attached",
                    GINT_TO_POINTER(1));
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroyed), nullptr);
}

bool desktop_glass_handle(GtkWindow* window, FlMethodCall* call) {
  if (handle_startup_placement(window, call)) return true;
  if (handle_topmost(window, call)) return true;
  if (std::strcmp(fl_method_call_get_name(call), "configureDesktopGlass") != 0) {
    return false;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* enabled = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, "enabled") : nullptr;
  FlValue* radius = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(args, "cornerRadius") : nullptr;
  const bool numeric = radius != nullptr &&
      (fl_value_get_type(radius) == FL_VALUE_TYPE_FLOAT ||
       fl_value_get_type(radius) == FL_VALUE_TYPE_INT);
  const double value = !numeric ? -1 :
      fl_value_get_type(radius) == FL_VALUE_TYPE_FLOAT
          ? fl_value_get_float(radius) : fl_value_get_int(radius);
  if (enabled == nullptr || fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL ||
      !numeric || !std::isfinite(value) || value < 0 || value > 64) {
    fl_method_call_respond_error(call, "invalid_arguments",
                                "Expected a glass switch and radius from 0 to 64.",
                                nullptr, nullptr);
    return true;
  }
  const bool is_enabled = fl_value_get_bool(enabled);
  const char* current = gtk_window_get_title(window);
  const auto* previous = static_cast<const char*>(
      g_object_get_data(G_OBJECT(window), "orion-desktop-glass-title"));
  const char* title = !is_enabled && previous != nullptr ? previous : current;
  if (title == nullptr || *title == '\0') {
    g_autoptr(FlValue) result = fl_value_new_string(
        "{\"ok\":false,\"active\":false,\"reason\":\"waiting-window\"}");
    fl_method_call_respond_success(call, result, nullptr);
    return true;
  }
  auto* request = new Request{
      FL_METHOD_CALL(g_object_ref(call)), GTK_WINDOW(g_object_ref(window)),
      g_strdup(title),
      is_enabled && previous != nullptr && std::strcmp(previous, title) != 0
          ? g_strdup(previous) : nullptr,
      is_enabled, value};
  g_object_set_data_full(G_OBJECT(window), "orion-desktop-glass-title",
                        is_enabled ? g_strdup(title) : nullptr, g_free);
  g_bus_get(G_BUS_TYPE_SESSION, nullptr, bus_ready, request);
  return true;
}
