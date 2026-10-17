#ifndef ORION_FRAMELESS_WINDOW_H_
#define ORION_FRAMELESS_WINDOW_H_

#include <gtk/gtk.h>

// Flutter owns the complete visible frame, including its antialiased border.
void orion_configure_frameless_window(GtkWindow* window);

#endif  // ORION_FRAMELESS_WINDOW_H_
