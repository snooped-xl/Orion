#!/usr/bin/env python3
"""Raster-check native frame leaks on a private X server and private bus."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

TEST = r'''
#include "frameless_window.h"
#include <cstdint>
#include <cstdio>
#include <initializer_list>

void check(bool condition, const char* label) {
  if (!condition) g_error("FAIL: %s", label);
}
uint32_t first_pixel(GtkStyleContext* style) {
  auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 200, 120);
  auto* cr = cairo_create(surface);
  gtk_render_background(style, cr, 0, 0, 200, 120);
  gtk_render_frame(style, cr, 0, 0, 200, 120);
  cairo_surface_flush(surface);
  const auto pixel = *reinterpret_cast<const uint32_t*>(cairo_image_surface_get_data(surface));
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  return pixel;
}
void drain() {
  for (int i = 0; i < 25; ++i) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
}
void find_menu_bar(GtkWidget* widget, gpointer data) {
  if (GTK_IS_MENU_BAR(widget) && gtk_widget_get_visible(widget))
    *static_cast<GtkWidget**>(data) = widget;
  if (GTK_IS_CONTAINER(widget))
    gtk_container_forall(GTK_CONTAINER(widget), find_menu_bar, data);
}
void check_empty_application_menu() {
  auto* settings = gtk_settings_get_default();
  // Use the actual theme which exposed the focus-dependent opaque top row.
  // An empty native menu model reproduces app-menu modules without requiring
  // any particular desktop module to be installed on the test machine.
  g_object_set(settings, "gtk-theme-name", "adw-gtk3-dark",
               "gtk-shell-shows-menubar", FALSE,
               "gtk-shell-shows-app-menu", FALSE, nullptr);
  auto* app = gtk_application_new("dev.orion.FramelessFixture",
                                 G_APPLICATION_NON_UNIQUE);
  g_application_register(G_APPLICATION(app), nullptr, nullptr);
  auto* menu = g_menu_new();
  gtk_application_set_menubar(app, G_MENU_MODEL(menu));
  auto* window = GTK_WINDOW(gtk_application_window_new(app));
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_default_size(window, 200, 120);
  gtk_container_add(GTK_CONTAINER(window), gtk_drawing_area_new());
  gtk_widget_show_all(GTK_WIDGET(window));
  drain();
  GtkWidget* bar = nullptr;
  gtk_container_forall(GTK_CONTAINER(window), find_menu_bar, &bar);
  check(bar != nullptr, "empty native application menu is visible before configuration");
  check(gtk_widget_get_allocated_height(bar) == 1,
        "empty native menu reproduces the unwanted one-pixel row");
  auto* menu_style = gtk_widget_get_style_context(bar);
  gtk_style_context_set_state(menu_style, GTK_STATE_FLAG_BACKDROP);
  check(first_pixel(menu_style) == 0xff242424u,
        "real adw-gtk3-dark backdrop paints the exact reported #242424 row");
  orion_configure_frameless_window(window);
  drain();
  bar = nullptr;
  gtk_container_forall(GTK_CONTAINER(window), find_menu_bar, &bar);
  check(!gtk_application_window_get_show_menubar(GTK_APPLICATION_WINDOW(window)) &&
            bar == nullptr,
        "frameless configuration removes the unused native menu slot");
  // The menu guard must also run when native styling was configured already.
  gtk_application_window_set_show_menubar(GTK_APPLICATION_WINDOW(window), TRUE);
  drain();
  bar = nullptr;
  gtk_container_forall(GTK_CONTAINER(window), find_menu_bar, &bar);
  check(bar != nullptr, "re-enabled native menu recreates its empty slot");
  orion_configure_frameless_window(window);
  drain();
  bar = nullptr;
  gtk_container_forall(GTK_CONTAINER(window), find_menu_bar, &bar);
  check(bar == nullptr, "idempotent frame configuration still removes a re-enabled native menu");
  gtk_widget_destroy(GTK_WIDGET(window));
  g_object_unref(menu);
  g_object_unref(app);
  std::puts("PASS real-theme empty application-menu one-pixel backdrop regression");
}
int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  check_empty_application_menu();
  auto* theme = gtk_css_provider_new();
  // A native theme can leave both a top border and a background image even
  // after window_manager has made only its background-color transparent.
  gtk_css_provider_load_from_data(theme,
      "window { background-color: transparent; border-top: 1px solid #242424;"
      " background-image: linear-gradient(to bottom, #242424 0px, #242424 1px, transparent 1px);"
      " padding: 1px 0 0 0; box-shadow: 0 -1px #242424; }", -1, nullptr);
  gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
      GTK_STYLE_PROVIDER(theme), GTK_STYLE_PROVIDER_PRIORITY_THEME + 1);
  auto* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  auto* dialog = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  auto* context = gtk_widget_get_style_context(GTK_WIDGET(window));
  check(first_pixel(context) == 0xff242424u,
        "native theme reproduces the exact opaque single-pixel dark row");
  auto* unrelated = gtk_widget_get_style_context(GTK_WIDGET(dialog));
  orion_configure_frameless_window(window);
  orion_configure_frameless_window(window);  // Initialization stays idempotent.
  for (GtkStateFlags state : {GTK_STATE_FLAG_NORMAL, GTK_STATE_FLAG_BACKDROP,
                             GTK_STATE_FLAG_FOCUSED}) {
    gtk_style_context_set_state(context, state);
    GtkBorder border{}, padding{};
    gtk_style_context_get_border(context, state, &border);
    gtk_style_context_get_padding(context, state, &padding);
    check(first_pixel(context) == 0,
          "Orion native frame stays transparent through focus/backdrop changes");
    check(border.top == 0 && border.left == 0 && border.right == 0 && border.bottom == 0,
          "native border cannot displace Flutter's visible frame");
    check(padding.top == 0 && padding.left == 0 && padding.right == 0 && padding.bottom == 0,
          "native padding cannot leave an exposed row around Flutter");
  }
  check(first_pixel(unrelated) == 0xff242424u,
        "unrelated native file dialog keeps its theme");
  gtk_widget_destroy(GTK_WIDGET(window));
  gtk_widget_destroy(GTK_WIDGET(dialog));
  gtk_style_context_remove_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(theme));
  g_object_unref(theme);
  std::puts("PASS exact dark-row reproduction, transparent native frame, focus states, idempotence and dialog isolation");
}
'''

def main():
    runner = Path(__file__).resolve().parents[1] / 'linux/runner'
    flags = shlex.split(subprocess.check_output(
        ['pkg-config', '--cflags', '--libs', 'gtk+-3.0'], text=True))
    with tempfile.TemporaryDirectory(prefix='orion-native-frame-') as folder:
        folder = Path(folder)
        source, binary = folder / 'check.cc', folder / 'check'
        source.write_text(TEST)
        subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-I' + str(runner), str(source),
                        str(runner / 'frameless_window.cc'), *flags,
                        '-o', str(binary)], check=True)
        runtime = folder / 'runtime'
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ, GDK_BACKEND='x11', NO_AT_BRIDGE='1',
                           GIO_USE_VFS='local', GTK_USE_PORTAL='0', GSETTINGS_BACKEND='memory',
                           XDG_RUNTIME_DIR=str(runtime),
                           XDG_CONFIG_HOME=str(folder / 'config'),
                           XDG_DATA_HOME=str(folder / 'data'),
                           XDG_CACHE_HOME=str(folder / 'cache'))
        for key in ['GNOME_KEYRING_CONTROL', 'SSH_AUTH_SOCK', 'WAYLAND_DISPLAY',
                    'DESKTOP_STARTUP_ID', 'AT_SPI_BUS_ADDRESS']:
            environment.pop(key, None)
        subprocess.run(['xvfb-run', '-a', 'dbus-run-session', '--', str(binary)],
                       env=environment, check=True, timeout=20)

if __name__ == '__main__':
    main()
