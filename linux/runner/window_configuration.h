#ifndef ORION_WINDOW_CONFIGURATION_H_
#define ORION_WINDOW_CONFIGURATION_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void window_configuration_attach(GtkWindow* window, FlView* view);

#endif
