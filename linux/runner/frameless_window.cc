#include "frameless_window.h"

void orion_configure_frameless_window(GtkWindow* window) {
  // Orion draws every menu in Flutter. Desktop app-menu modules can install an
  // empty GtkApplicationWindow menu bar anyway: GTK allocates it a one-pixel
  // row which the system theme fills on :backdrop, above our rounded content.
  // Disable that unused native slot rather than merely recoloring the window.
  if (GTK_IS_APPLICATION_WINDOW(window)) {
    gtk_application_window_set_show_menubar(GTK_APPLICATION_WINDOW(window),
                                           FALSE);
  }
  constexpr const char* key = "orion-frameless-style";
  if (g_object_get_data(G_OBJECT(window), key) != nullptr) return;
  auto* context = gtk_widget_get_style_context(GTK_WIDGET(window));
  gtk_style_context_add_class(context, "orion-frameless-native");
  auto* provider = gtk_css_provider_new();
  // Changing only background-color leaves theme background images, shadows or
  // native border/padding exposed around Flutter's transparent curved frame.
  // In particular, a one-pixel GTK top border becomes a straight dark stripe.
  // Scope this to Orion's frameless toplevel; native file choosers and every
  // Flutter-drawn control retain their own styling and dimensions.
  constexpr const char* css =
      "window.orion-frameless-native {"
      " background-color: transparent; background-image: none;"
      " border: none; box-shadow: none; outline: none;"
      " margin: 0; padding: 0;"
      "}"
      "window.orion-frameless-native decoration {"
      " background-color: transparent; background-image: none;"
      " border: none; box-shadow: none; outline: none;"
      " margin: 0; padding: 0;"
      "}";
  gtk_css_provider_load_from_data(provider, css, -1, nullptr);
  gtk_style_context_add_provider(context, GTK_STYLE_PROVIDER(provider),
                                GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
  g_object_set_data_full(G_OBJECT(window), key, provider, g_object_unref);
}
