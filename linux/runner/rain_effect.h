#ifndef RUNNER_RAIN_EFFECT_H_
#define RUNNER_RAIN_EFFECT_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// A pointer-transparent GTK layer above Flutter and the native Monaco surface.
// Dart supplies a clean live snapshot, excluding this layer, for optical lenses.
void rain_effect_attach(GtkWindow* window, FlView* view, GtkOverlay* overlay);
#endif
