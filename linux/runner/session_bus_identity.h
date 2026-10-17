#ifndef RUNNER_SESSION_BUS_IDENTITY_H_
#define RUNNER_SESSION_BUS_IDENTITY_H_

#include <gio/gio.h>

namespace orion {

// A Flatpak process has a PID in its own namespace. Mutter and the session bus
// use the host PID, so getpid() cannot identify its windows to the compositor.
// Ask the bus for the credentials of this exact connection instead. No caller
// supplies a host PID and no process-name/app-ID matching is involved.
constexpr const char* kSessionBusPidKey = "orion-authenticated-session-bus-pid";
using SessionBusPidCallback = void (*)(GDBusConnection*, guint32, gpointer);

inline guint32 cached_session_bus_pid(GDBusConnection* connection) {
  if (connection == nullptr || g_dbus_connection_is_closed(connection)) return 0;
  return GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(connection), kSessionBusPidKey));
}

struct SessionBusPidRequest {
  GDBusConnection* connection;
  SessionBusPidCallback callback;
  gpointer data;
};

inline void session_bus_pid_resolved(GObject*, GAsyncResult* result, gpointer data) {
  auto* request = static_cast<SessionBusPidRequest*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(request->connection, result, &error);
  guint32 pid = 0;
  if (reply != nullptr && !g_dbus_connection_is_closed(request->connection)) {
    g_variant_get(reply, "(u)", &pid);
    if (pid < 2) pid = 0;
  }
  if (pid != 0) {
    // The unique name and its kernel credentials belong to this connection's
    // lifetime. A reconnect is a different GDBusConnection with an empty cache.
    g_object_set_data(G_OBJECT(request->connection), kSessionBusPidKey, GUINT_TO_POINTER(pid));
  }
  request->callback(request->connection, pid, request->data);
  g_object_unref(request->connection);
  delete request;
}

inline void resolve_session_bus_pid(GDBusConnection* connection,
                                    SessionBusPidCallback callback,
                                    gpointer data) {
  const guint32 cached = cached_session_bus_pid(connection);
  if (cached != 0) {
    callback(connection, cached, data);
    return;
  }
  const gchar* name = connection == nullptr || g_dbus_connection_is_closed(connection)
      ? nullptr : g_dbus_connection_get_unique_name(connection);
  if (name == nullptr) {
    callback(connection, 0, data);
    return;
  }
  auto* request = new SessionBusPidRequest{
      G_DBUS_CONNECTION(g_object_ref(connection)), callback, data};
  g_dbus_connection_call(connection, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "GetConnectionUnixProcessID", g_variant_new("(s)", name),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, nullptr,
      session_bus_pid_resolved, request);
}

}  // namespace orion

#endif  // RUNNER_SESSION_BUS_IDENTITY_H_
