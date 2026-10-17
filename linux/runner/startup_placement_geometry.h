#ifndef ORION_STARTUP_PLACEMENT_GEOMETRY_H_
#define ORION_STARTUP_PLACEMENT_GEOMETRY_H_

#include <algorithm>
#include <cmath>

// GDK and Mutter both expose logical desktop coordinates. Do not multiply by
// monitor scale: doing so offsets mixed-DPI and negative-coordinate displays.
struct OrionPlacementRect {
  int x, y, width, height;
};

inline OrionPlacementRect orion_center_startup_window(
    OrionPlacementRect monitor, OrionPlacementRect workarea,
    int width, int height) {
  int x = static_cast<int>(std::floor(
      monitor.x + (static_cast<double>(monitor.width) - width) / 2.0 + 0.5));
  int y = static_cast<int>(std::floor(
      monitor.y + (static_cast<double>(monitor.height) - height) / 2.0 + 0.5));
  // Keep the title bar reachable without changing the user's requested size.
  if (workarea.width > 0 && workarea.height > 0) {
    x = width <= workarea.width
        ? std::max(workarea.x, std::min(x, workarea.x + workarea.width - width))
        : workarea.x;
    y = height <= workarea.height
        ? std::max(workarea.y, std::min(y, workarea.y + workarea.height - height))
        : workarea.y;
  }
  return {x, y, width, height};
}

#endif
