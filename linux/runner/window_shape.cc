#include "window_shape.h"

#include <algorithm>
#include <cmath>

namespace {
struct WindowShape {
  GtkWindow* window;
  double radius;
  GdkWindow* applied_window = nullptr;
  int applied_width = 0, applied_height = 0;
  int applied_scale = 0;
  double applied_radius = -1;
  bool applied_expanded = false;
};

void apply_shape_for_state(WindowShape* shape, GdkWindowState state,
                           int width = 0, int height = 0) {
  GtkWidget* widget = GTK_WIDGET(shape->window);
  if (!gtk_widget_get_realized(widget)) return;
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr) return;
  const bool expanded =
      (state & (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN)) != 0;
  if (width <= 0) width = gdk_window_get_width(window);
  if (height <= 0) height = gdk_window_get_height(window);
  const int scale = gtk_widget_get_scale_factor(widget);
  // GTK can allocate the same top-level repeatedly while its child animates.
  // Its stored input region already covers this exact native allocation.
  if (shape->applied_window == window && shape->applied_width == width &&
      shape->applied_height == height && shape->applied_radius == shape->radius &&
      shape->applied_scale == scale &&
      shape->applied_expanded == expanded) {
    return;
  }
  shape->applied_window = window;
  shape->applied_width = width;
  shape->applied_height = height;
  shape->applied_scale = scale;
  shape->applied_radius = shape->radius;
  shape->applied_expanded = expanded;
  if (expanded || shape->radius == 0) {
    gtk_widget_input_shape_combine_region(widget, nullptr);
    return;
  }
  cairo_region_t* region = window_shape_rounded_region(
      width, height, shape->radius);
  // Input only. A visual/bounding Cairo region is one-bit coverage and would
  // cut away Flutter's antialiased ARGB edge instead of preserving its alpha.
  gtk_widget_input_shape_combine_region(widget, region);
  cairo_region_destroy(region);
}

void apply_shape(WindowShape* shape) {
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(shape->window));
  if (window != nullptr) {
    apply_shape_for_state(shape, gdk_window_get_state(window));
  }
}

void allocated(GtkWidget* widget, GtkAllocation* allocation, gpointer data) {
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window != nullptr) {
    apply_shape_for_state(static_cast<WindowShape*>(data),
                          gdk_window_get_state(window), allocation->width,
                          allocation->height);
  }
}

void realized(GtkWidget*, gpointer data) {
  auto* shape = static_cast<WindowShape*>(data);
  shape->applied_window = nullptr;
  apply_shape(shape);
}

void scale_changed(GtkWidget*, GParamSpec*, gpointer data) {
  // A monitor switch can retain the same logical allocation while changing
  // the device-pixel input region required by the backend.
  apply_shape(static_cast<WindowShape*>(data));
}

gboolean state_changed(GtkWidget*, GdkEventWindowState* event, gpointer data) {
  // Read the event's new state directly: backend state queries can still expose
  // the previous state while GTK dispatches the transition.
  auto* shape = static_cast<WindowShape*>(data);
  apply_shape_for_state(shape, event->new_window_state);
  return FALSE;
}
}  // namespace

cairo_region_t* window_shape_rounded_region(int width, int height,
                                           double radius) {
  cairo_region_t* region = cairo_region_create();
  if (width <= 0 || height <= 0) return region;
  radius = std::isfinite(radius)
               ? std::clamp(radius, 0.0, std::min(width, height) / 2.0)
               : 0;
  const int arc_rows = static_cast<int>(std::ceil(radius));
  const int middle_height = height - 2 * arc_rows;
  if (middle_height > 0) {
    const cairo_rectangle_int_t middle{0, arc_rows, width, middle_height};
    cairo_region_union_rectangle(region, &middle);
  }
  for (int y = 0; y < height; ++y) {
    // Every middle scanline is identical. Add that band once, keeping the
    // original per-pixel arc coverage and tiny/overlapping corner behavior.
    if (middle_height > 0 && y == arc_rows) y += middle_height;
    if (y >= height) break;
    const double center_y = y + 0.5;
    const double distance = center_y < radius
                                ? radius - center_y
                                : center_y > height - radius
                                      ? center_y - (height - radius)
                                      : 0;
    const double inset = distance > 0
                             ? radius - std::sqrt(std::max(
                                            0.0, radius * radius -
                                                     distance * distance))
                             : 0;
    const int left = std::max(0, static_cast<int>(std::ceil(inset - 0.5)));
    const cairo_rectangle_int_t row{left, y, width - 2 * left, 1};
    if (row.width > 0) cairo_region_union_rectangle(region, &row);
  }
  return region;
}

void window_shape_set_corner_radius(GtkWindow* window, double radius) {
  constexpr const char* key = "orion-rounded-window-input";
  auto* shape = static_cast<WindowShape*>(
      g_object_get_data(G_OBJECT(window), key));
  if (shape == nullptr) {
    shape = new WindowShape{window, radius};
    g_object_set_data_full(G_OBJECT(window), key, shape, [](gpointer data) {
      delete static_cast<WindowShape*>(data);
    });
    g_signal_connect(window, "size-allocate", G_CALLBACK(allocated), shape);
    g_signal_connect(window, "realize", G_CALLBACK(realized), shape);
    g_signal_connect(window, "notify::scale-factor", G_CALLBACK(scale_changed),
                     shape);
    g_signal_connect(window, "window-state-event", G_CALLBACK(state_changed),
                     shape);
  }
  shape->radius = std::clamp(radius, 0.0, 64.0);
  apply_shape(shape);
}
