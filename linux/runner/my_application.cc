#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include "monaco_host.h"
#include "window_configuration.h"
#include "bridge_notification_native.h"
#include "rain_effect.h"
#include "egl_lifetime.h"
#include "frameless_window.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void companion_window_created(FlPluginRegistry* registry) {
  fl_register_plugins(registry);
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OrionCompanion");
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view == nullptr) return;
  orion_bind_renderer_engine_lifetime(
      GTK_WIDGET(view), G_OBJECT(fl_view_get_engine(view)));
  auto* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_titlebar(window, nullptr);
  orion_configure_frameless_window(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkRGBA transparent{0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  // Every editor engine needs its own native surface and configuration channel.
  // Reparent with a reference held while GtkWindow releases the original child.
  g_object_ref(view);
  gtk_container_remove(GTK_CONTAINER(window), GTK_WIDGET(view));
  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_set_size_request(overlay, 1, 1);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_widget_show(overlay);
  g_object_unref(view);
  monaco_host_attach(window, view, GTK_OVERLAY(overlay));
  window_configuration_attach(window, view);
  bridge_notification_attach(window, view);
  rain_effect_attach(window, view, GTK_OVERLAY(overlay));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Let Flutter draw the frame. An RGBA visual keeps its rounded corners clear.
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  gtk_window_set_decorated(window, FALSE);
  orion_configure_frameless_window(window);
  gtk_window_set_title(window, "Orion");
  gtk_window_set_default_size(window, 822, 523);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  // Keep GPU rendering through Skia. Impeller currently crashes during NVIDIA
  // EGL teardown when this Linux host closes multiple Flutter engines.
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  orion_bind_renderer_engine_lifetime(
      GTK_WIDGET(view), G_OBJECT(fl_view_get_engine(view)));
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  GtkWidget* overlay = gtk_overlay_new();
  // Flutter has no GTK natural requisition. A zero-sized child makes GTK use
  // its 200px fallback when locking tiny source loader windows. A nonzero
  // content requisition permits their exact 117px / 171px heights; Dart still
  // supplies the real default size and the window manager's minimum hints.
  gtk_widget_set_size_request(overlay, 1, 1);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  monaco_host_attach(window, view, GTK_OVERLAY(overlay));
  window_configuration_attach(window, view);
  bridge_notification_attach(window, view);
  rain_effect_attach(window, view, GTK_OVERLAY(overlay));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(companion_window_created);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  // Match the desktop entry and hicolor icon on both Wayland and X11.
  gtk_window_set_default_icon_name(APPLICATION_ID);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
