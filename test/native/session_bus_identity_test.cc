#include "session_bus_identity.h"
#include "window_process_identity.h"

#include <unistd.h>
#include <sys/wait.h>
#include <cstdio>
#include <cstring>

namespace {
constexpr const char* kService = "org.orion.IdentityTest";
constexpr const char* kPath = "/org/orion/IdentityTest";
constexpr const char* kInterface = "org.orion.IdentityTest1";

guint32 resolve(GDBusConnection* connection, bool* synchronous = nullptr) {
  struct Pending { bool done = false; guint32 pid = 0; } pending;
  orion::resolve_session_bus_pid(connection,
      +[](GDBusConnection*, guint32 pid, gpointer data) {
        auto* pending = static_cast<Pending*>(data);
        pending->pid = pid;
        pending->done = true;
      }, &pending);
  if (synchronous != nullptr) *synchronous = pending.done;
  while (!pending.done) g_main_context_iteration(nullptr, TRUE);
  return pending.pid;
}

void verify_call(GDBusConnection* connection, const gchar* sender, const gchar*,
                 const gchar*, const gchar*, GVariant* parameters,
                 GDBusMethodInvocation* invocation, gpointer) {
  guint32 claim = 0;
  g_variant_get(parameters, "(u)", &claim);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) credentials = g_dbus_connection_call_sync(connection,
      "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
      "GetConnectionUnixProcessID", g_variant_new("(s)", sender),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  guint32 actual = 0;
  g_variant_get(credentials, "(u)", &actual);
  g_dbus_method_invocation_return_value(invocation,
      g_variant_new("(b)", claim >= 2 && actual == claim));
}

void serve(const char* ready_path) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  g_assert_no_error(error);
  g_autoptr(GVariant) owned = g_dbus_connection_call_sync(bus,
      "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
      "RequestName", g_variant_new("(su)", kService, 4), G_VARIANT_TYPE("(u)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  g_assert_nonnull(owned);
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(
      "<node><interface name='org.orion.IdentityTest1'><method name='Verify'>"
      "<arg type='u' direction='in'/><arg type='b' direction='out'/>"
      "</method></interface></node>", &error);
  g_assert_no_error(error);
  const GDBusInterfaceVTable table{verify_call, nullptr, nullptr, {nullptr}};
  g_assert_cmpuint(g_dbus_connection_register_object(bus, kPath, info->interfaces[0],
      &table, nullptr, nullptr, &error), >, 0);
  g_assert_no_error(error);
  g_assert_true(g_file_set_contents(ready_path, "ready", -1, &error));
  g_assert_no_error(error);
  GMainLoop* loop = g_main_loop_new(nullptr, FALSE);
  g_main_loop_run(loop);
}

bool accepted(GDBusConnection* bus, guint32 pid) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(bus, kService, kPath,
      kInterface, "Verify", g_variant_new("(u)", pid), G_VARIANT_TYPE("(b)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_assert_no_error(error);
  gboolean valid = FALSE;
  g_variant_get(reply, "(b)", &valid);
  return valid;
}

void client(bool namespaced) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  g_assert_no_error(error);
  g_assert_cmpuint(orion::cached_session_bus_pid(bus), ==, 0);
  const guint32 host = resolve(bus);
  const guint32 local = static_cast<guint32>(getpid());
  g_assert_cmpuint(host, >, 1);
  if (namespaced) g_assert_cmpuint(host, !=, local);
  else g_assert_cmpuint(host, ==, local);
  g_assert_true(accepted(bus, host));
  g_assert_false(accepted(bus, host + 1));
  g_assert_false(accepted(bus, 0));
  if (namespaced) g_assert_false(accepted(bus, local));
  gtk_init(nullptr, nullptr);
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  // Install before realize, then verify the real X11 property after mapping.
  orion::set_window_process_identity(GTK_WINDOW(window), host);
  gtk_widget_show(window);
  const auto assert_property = [window, host]() {
    GdkAtom type{};
    gint format = 0, length = 0;
    guchar* property = nullptr;
    g_assert_true(gdk_property_get(gtk_widget_get_window(window),
        gdk_atom_intern_static_string("_NET_WM_PID"),
        gdk_atom_intern_static_string("CARDINAL"), 0, 1, FALSE,
        &type, &format, &length, &property));
    g_assert_cmpint(format, ==, 32);
    g_assert_cmpuint(*reinterpret_cast<gulong*>(property), ==, host);
    g_free(property);
  };
  assert_property();
  // Changing an already realized window also updates exactly its own property.
  orion::set_window_process_identity(GTK_WINDOW(window), host);
  assert_property();
  gtk_widget_destroy(window);
  bool cache_hit = false;
  g_assert_cmpuint(resolve(bus, &cache_hit), ==, host);
  g_assert_true(cache_hit);
  g_assert_cmpuint(orion::cached_session_bus_pid(bus), ==, host);

  // A different connection starts empty, despite using the same process.
  g_autoptr(GDBusConnection) second = g_dbus_connection_new_for_address_sync(
      g_getenv("DBUS_SESSION_BUS_ADDRESS"),
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION), nullptr, nullptr, &error);
  g_assert_no_error(error);
  g_assert_cmpstr(g_dbus_connection_get_unique_name(bus), !=,
      g_dbus_connection_get_unique_name(second));
  g_assert_cmpuint(orion::cached_session_bus_pid(second), ==, 0);
  g_assert_cmpuint(resolve(second), ==, host);
  g_assert_true(g_dbus_connection_close_sync(second, nullptr, &error));
  g_assert_no_error(error);
  g_assert_cmpuint(orion::cached_session_bus_pid(second), ==, 0);
  bool failed_closed = false;
  g_assert_cmpuint(resolve(second, &failed_closed), ==, 0);
  g_assert_true(failed_closed);
  g_assert_cmpuint(resolve(nullptr), ==, 0);
  std::printf("{\"namespace\":%s,\"localPid\":%u,\"hostPid\":%u,"
      "\"exactCallerAccepted\":true,\"forgedCallerRejected\":true,"
      "\"connectionCache\":true,\"closedConnectionRejected\":true,\"x11HostPid\":true}\n",
      namespaced ? "true" : "false", local, host);
}
}  // namespace

int main(int argc, char** argv) {
  if (argc == 3 && std::strcmp(argv[1], "--server") == 0) serve(argv[2]);
  else if (argc == 2 && std::strcmp(argv[1], "--namespace-parent") == 0) {
    // Flatpak's init owns PID 1 and the application uses another valid PID.
    // Keep the namespace-local forged claim valid under the helper's shape
    // validation, so rejection proves credential matching rather than pid<2.
    const pid_t child = fork();
    g_assert_cmpint(child, >=, 0);
    if (child == 0) {
      client(true);
      std::fflush(stdout);
      _exit(0);
    }
    int status = 0;
    g_assert_cmpint(waitpid(child, &status, 0), ==, child);
    g_assert_true(WIFEXITED(status));
    g_assert_cmpint(WEXITSTATUS(status), ==, 0);
  }
  else client(argc == 2 && std::strcmp(argv[1], "--namespace") == 0);
  return 0;
}
