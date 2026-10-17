#ifndef ORION_WINDOW_SHAPE_H_
#define ORION_WINDOW_SHAPE_H_

#include <gtk/gtk.h>

// Logical-pixel input region; the caller owns the returned Cairo region.
cairo_region_t* window_shape_rounded_region(int width, int height,
                                           double radius);

// Only opt-in windows acquire a shape. Allocation/state changes keep it in sync.
void window_shape_set_corner_radius(GtkWindow* window, double radius);

#endif
