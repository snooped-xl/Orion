#include "window_configuration.h"
#include "window_shape.h"
#include "desktop_glass.h"
#include "startup_placement_geometry.h"
#include <gdk/gdkx.h>

#include <cmath>
#include <cstring>

namespace {
gboolean destroy_companion_when_idle(gpointer data) {
  auto* window = GTK_WINDOW(data);
  // A sibling's draw can pump the platform message that closes this engine.
  // Release its GLX binding while EGL destroys the child's compositor.
  gdk_gl_context_clear_current();
  gtk_widget_destroy(GTK_WIDGET(window));
  gdk_gl_context_clear_current();
  // Destruction can invalidate a shared GDK context's native drawable even if
  // its owner is still referenced. Each subsequent GTK draw binds its context.
  return G_SOURCE_REMOVE;
}

double number(FlValue* value) {
  if (value == nullptr) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(value);
  }
  return 0;
}

void complete_startup_placement(GtkWindow* window) {
  const auto handler = GPOINTER_TO_SIZE(g_object_get_data(G_OBJECT(window), "orion-startup-resize-handler"));
  if (handler != 0) g_signal_handler_disconnect(window, handler);
  g_object_set_data(G_OBJECT(window), "orion-startup-resize-handler", nullptr);
  g_object_set_data(G_OBJECT(window), "orion-startup-monitor", nullptr);
}

GdkMonitor* startup_monitor(GtkWindow* window) {
  auto* monitor = static_cast<GdkMonitor*>(
      g_object_get_data(G_OBJECT(window), "orion-startup-monitor"));
  if (monitor == nullptr) return nullptr;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  for (int index = 0; index < gdk_display_get_n_monitors(display); ++index)
    if (gdk_display_get_monitor(display, index) == monitor) return monitor;
  // The captured output was unplugged during loading. Do not place offscreen.
  return gdk_display_get_primary_monitor(display);
}

void center_startup_window(GtkWindow* window, int width, int height) {
  GdkMonitor* monitor = startup_monitor(window);
  if (monitor == nullptr) return;
  GdkRectangle geometry{}, workarea{};
  gdk_monitor_get_geometry(monitor, &geometry);
  gdk_monitor_get_workarea(monitor, &workarea);
  const auto frame = orion_center_startup_window(
      {geometry.x, geometry.y, geometry.width, geometry.height},
      {workarea.x, workarea.y, workarea.width, workarea.height}, width, height);
  gtk_window_set_position(window, GTK_WIN_POS_NONE);
  gtk_window_move(window, frame.x, frame.y);
}

void startup_size_allocated(GtkWidget* widget, GtkAllocation* allocation, gpointer) {
  auto* window = GTK_WINDOW(widget);
  const int last_width = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(window), "orion-startup-last-width"));
  const int last_height = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(window), "orion-startup-last-height"));
  if (allocation->width == last_width && allocation->height == last_height) return;
  g_object_set_data(G_OBJECT(window), "orion-startup-last-width", GINT_TO_POINTER(allocation->width));
  g_object_set_data(G_OBJECT(window), "orion-startup-last-height", GINT_TO_POINTER(allocation->height));
  center_startup_window(window, allocation->width, allocation->height);
}

// Capture only this main engine's launch target. Companion engines never call
// this method and therefore retain their existing owned-window positioning.
bool handle_startup_placement(GtkWindow* window, FlMethodCall* call) {
  const char* method = fl_method_call_get_name(call);
  const bool prepare = std::strcmp(method, "prepareStartupPlacement") == 0;
  const bool complete = std::strcmp(method, "completeStartupPlacement") == 0;
  if (!prepare && !complete && std::strcmp(method, "applyStartupPlacement") != 0) return false;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (!GDK_IS_X11_DISPLAY(display)) return false;  // Mutter owns Wayland moves.
  if (complete) {
    complete_startup_placement(window);
    g_autoptr(FlValue) response = fl_value_new_string("{\"ok\":true,\"reason\":\"completed\"}");
    fl_method_call_respond_success(call, response, nullptr);
    return true;
  }
  if (prepare) {
    // Repeated preparation must not chase a pointer which moved during loading.
    if (g_object_get_data(G_OBJECT(window), "orion-startup-monitor") == nullptr) {
      GdkSeat* seat = gdk_display_get_default_seat(display);
      GdkDevice* pointer = seat == nullptr ? nullptr : gdk_seat_get_pointer(seat);
      gint x = 0, y = 0;
      if (pointer != nullptr) gdk_device_get_position(pointer, nullptr, &x, &y);
      GdkMonitor* monitor = pointer == nullptr ? nullptr :
          gdk_display_get_monitor_at_point(display, x, y);
      if (monitor == nullptr) monitor = gdk_display_get_primary_monitor(display);
      if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0)
        monitor = gdk_display_get_monitor(display, 0);
      if (monitor != nullptr)
        g_object_set_data_full(G_OBJECT(window), "orion-startup-monitor",
                              g_object_ref(monitor), g_object_unref);
    }
  } else {
    auto* monitor = startup_monitor(window);
    if (monitor != nullptr) {
      gint width = 0, height = 0;
      gtk_window_get_size(window, &width, &height);
      center_startup_window(window, width, height);
      FlValue* args = fl_method_call_get_args(call);
      FlValue* follow = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(args, "followInitialResize") : nullptr;
      const bool tracking = follow != nullptr && fl_value_get_type(follow) == FL_VALUE_TYPE_BOOL &&
          fl_value_get_bool(follow);
      if (tracking) {
        const auto handler = g_signal_connect(window, "size-allocate", G_CALLBACK(startup_size_allocated), nullptr);
        g_object_set_data(G_OBJECT(window), "orion-startup-resize-handler", GSIZE_TO_POINTER(handler));
        g_object_set_data(G_OBJECT(window), "orion-startup-last-width", GINT_TO_POINTER(width));
        g_object_set_data(G_OBJECT(window), "orion-startup-last-height", GINT_TO_POINTER(height));
      } else {
        // Normal main UI startup consumes the captured target immediately.
        complete_startup_placement(window);
      }
      g_autoptr(FlValue) response = fl_value_new_string("{\"ok\":true,\"mode\":\"gtk-x11\"}");
      fl_method_call_respond_success(call, response, nullptr);
      return true;
    }
  }
  const bool captured = g_object_get_data(G_OBJECT(window), "orion-startup-monitor") != nullptr;
  g_autoptr(FlValue) response = fl_value_new_string(captured
      ? "{\"ok\":true,\"mode\":\"gtk-x11\",\"reason\":\"prepared\"}"
      : "{\"ok\":false,\"reason\":\"no-startup-monitor\"}");
  fl_method_call_respond_success(call, response, nullptr);
  return true;
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (handle_startup_placement(GTK_WINDOW(data), call)) return;
  if (desktop_glass_handle(GTK_WINDOW(data), call)) return;
  const char* method = fl_method_call_get_name(call);
  if (std::strcmp(method, "setCornerRadius") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* value = args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP
        ? nullptr : fl_value_lookup_string(args, "radius");
    if (value == nullptr ||
        (fl_value_get_type(value) != FL_VALUE_TYPE_FLOAT &&
         fl_value_get_type(value) != FL_VALUE_TYPE_INT)) {
      fl_method_call_respond_error(call, "invalid_arguments",
                                  "Expected a numeric corner radius.", nullptr,
                                  nullptr);
      return;
    }
    const double radius = number(value);
    if (!std::isfinite(radius) || radius < 0 || radius > 64) {
      fl_method_call_respond_error(call, "invalid_arguments",
                                  "Expected a corner radius from 0 to 64.",
                                  nullptr, nullptr);
      return;
    }
    window_shape_set_corner_radius(GTK_WINDOW(data), radius);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (std::strcmp(method, "destroyCompanion") == 0) {
    // Reply while the engine is alive, then retain only its native window.
    fl_method_call_respond_success(call, nullptr, nullptr);
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, destroy_companion_when_idle,
                    g_object_ref(data), g_object_unref);
    return;
  }
  if (std::strcmp(method, "registerWindow") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* id = args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP
        ? nullptr : fl_value_lookup_string(args, "id");
    if (id == nullptr || fl_value_get_type(id) != FL_VALUE_TYPE_STRING) {
      fl_method_call_respond_error(call, "invalid_arguments", "Expected a window id.", nullptr, nullptr);
      return;
    }
    auto* window = GTK_WINDOW(data);
    g_object_set_data_full(G_OBJECT(window), "orion-window-id",
                          g_strdup(fl_value_get_string(id)), g_free);
    FlValue* parent_id = fl_value_lookup_string(args, "parentId");
    if (parent_id == nullptr || fl_value_get_type(parent_id) == FL_VALUE_TYPE_NULL) {
      g_object_set_data(G_OBJECT(window), "orion-primary-window", GINT_TO_POINTER(1));
    }
    FlValue* owned = fl_value_lookup_string(args, "owned");
    if (parent_id != nullptr && fl_value_get_type(parent_id) == FL_VALUE_TYPE_STRING &&
        owned != nullptr && fl_value_get_bool(owned)) {
      GtkApplication* app = gtk_window_get_application(window);
      for (GList* p = gtk_application_get_windows(app); p != nullptr; p = p->next) {
        auto* parent = GTK_WINDOW(p->data);
        const auto* registered_id = static_cast<const char*>(
            g_object_get_data(G_OBJECT(parent), "orion-window-id"));
        if (registered_id != nullptr &&
            std::strcmp(registered_id, fl_value_get_string(parent_id)) == 0) {
          gtk_window_set_transient_for(window, parent);
          gtk_window_set_destroy_with_parent(window, TRUE);
          break;
        }
      }
    }
    FlValue* modal = fl_value_lookup_string(args, "modal");
    gtk_window_set_modal(window, modal != nullptr && fl_value_get_bool(modal));
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  const bool minimum = std::strcmp(method, "setMinimumSize") == 0;
  if (!minimum && std::strcmp(method, "setResizable") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(call, "invalid_arguments",
                                "Expected window configuration.", nullptr, nullptr);
    return;
  }
  auto* window = GTK_WINDOW(data);
  if (minimum) {
    const double width = number(fl_value_lookup_string(args, "width"));
    const double height = number(fl_value_lookup_string(args, "height"));
    if (!std::isfinite(width) || !std::isfinite(height) ||
        width < 1 || height < 1 || width > 16384 || height > 16384) {
      fl_method_call_respond_error(call, "invalid_arguments",
                                  "Expected finite positive minimum size.",
                                  nullptr, nullptr);
      return;
    }
    // The plugin writes GDK hints directly. GTK recomputes them when a
    // window's default size or resizability changes, so preserve the minimum
    // in GtkWindow's own geometry as well.
    GdkGeometry geometry{};
    geometry.min_width = static_cast<gint>(std::round(width));
    geometry.min_height = static_cast<gint>(std::round(height));
    gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  FlValue* resizable = fl_value_lookup_string(args, "resizable");
  if (resizable == nullptr ||
      fl_value_get_type(resizable) != FL_VALUE_TYPE_BOOL) {
    fl_method_call_respond_error(call, "invalid_arguments",
                                "Expected a resizable boolean.", nullptr, nullptr);
    return;
  }
  gint width = 0, height = 0;
  gtk_window_get_size(window, &width, &height);
  const double requested_width = number(fl_value_lookup_string(args, "width"));
  const double requested_height = number(fl_value_lookup_string(args, "height"));
  const bool requested = std::isfinite(requested_width) &&
                         std::isfinite(requested_height) &&
                         requested_width >= 1 && requested_width <= 16384 &&
                         requested_height >= 1 && requested_height <= 16384;
  if (requested) {
    width = static_cast<gint>(std::round(requested_width));
    height = static_cast<gint>(std::round(requested_height));
  }
  if (!gtk_window_is_maximized(window)) {
    gtk_window_set_default_size(window, width, height);
  }
  gtk_window_set_resizable(window, fl_value_get_bool(resizable));
  if (requested && !gtk_window_is_maximized(window)) {
    gtk_window_resize(window, width, height);
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void window_destroyed(GtkWidget* widget, gpointer) {
  // Unregister while the child FlView's engine is still alive.
  g_object_set_data(G_OBJECT(widget), "orion-window-channel", nullptr);
}
}  // namespace

void window_configuration_attach(GtkWindow* window, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "orion/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, window, nullptr);
  g_object_set_data_full(G_OBJECT(window), "orion-window-channel", channel,
                         g_object_unref);
  desktop_glass_attach(window);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroyed), nullptr);
}
