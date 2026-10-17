#ifndef ORION_MONACO_HOST_H_
#define ORION_MONACO_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The native web view occupies only the editor's Flutter-reported rectangle.
// Its lifetime is attached to the containing window.
void monaco_host_attach(GtkWindow* window, FlView* flutter_view,
                        GtkOverlay* overlay);

#endif  // ORION_MONACO_HOST_H_
