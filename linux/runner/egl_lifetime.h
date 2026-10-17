#ifndef ORION_EGL_LIFETIME_H_
#define ORION_EGL_LIFETIME_H_

#include <gtk/gtk.h>

// Install before GTK or Flutter creates a display. Flutter's per-engine EGL
// managers share one EGLDisplay; keep it alive until its final user exits.
void orion_install_egl_lifetime();

// Keep the engine's GL manager alive until its renderer has freed the final
// compositor framebuffer. The reference is owned by renderer finalization.
void orion_bind_renderer_engine_lifetime(GtkWidget* view, GObject* engine);

#endif
