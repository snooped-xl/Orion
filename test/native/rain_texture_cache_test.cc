#include "../../linux/runner/rain_effect.cc"

#include <cassert>
#include <cstdio>

namespace {
FlValue* image_bytes(int width, int height, bool alternate = false) {
  g_autoptr(GdkPixbuf) pixels =
      gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, width, height);
  uint8_t* data = gdk_pixbuf_get_pixels(pixels);
  const int stride = gdk_pixbuf_get_rowstride(pixels);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      uint8_t* pixel = data + y * stride + x * 4;
      pixel[0] = (x / 4) % 2 ? 220 : 30;
      pixel[1] = alternate ? 210 : 60;
      pixel[2] = (y / 7) % 2 ? 210 : 25;
      pixel[3] = 255;
    }
  }
  gchar* png = nullptr;
  gsize size = 0;
  assert(gdk_pixbuf_save_to_buffer(pixels, &png, &size, "png", nullptr,
                                   nullptr));
  FlValue* result =
      fl_value_new_uint8_list(reinterpret_cast<uint8_t*>(png), size);
  g_free(png);
  return result;
}

void independent_textures() {
  RainEffect host;
  g_autoptr(FlValue) scene = image_bytes(822, 523);
  g_autoptr(FlValue) replacement = image_bytes(822, 523, true);
  g_autoptr(FlValue) editor = image_bytes(410, 260);
  assert(update_image(&host, 0, scene));
  assert(update_image(&host, 1, editor));
  GdkPixbuf* retained_scene = host.frame;
  GdkPixbuf* retained_editor = host.editor;
  host.texture_dirty[0] = host.texture_dirty[1] = false;
  assert(update_image(&host, 0, scene));
  assert(update_image(&host, 1, editor));
  assert(host.frame == retained_scene && host.editor == retained_editor);
  assert(!host.texture_dirty[0] && !host.texture_dirty[1]);

  assert(update_image(&host, 0, replacement));
  assert(host.texture_dirty[0] && !host.texture_dirty[1]);
  assert(host.editor == retained_editor);
  host.texture_dirty[0] = false;
  assert(update_image(&host, 1, scene));
  assert(!host.texture_dirty[0] && host.texture_dirty[1]);

  // A malformed required scene preserves the last valid frame. An unavailable
  // optional editor removes only that editor, matching the frame protocol.
  const uint8_t invalid[] = {1, 2, 3};
  g_autoptr(FlValue) invalid_png =
      fl_value_new_uint8_list(invalid, sizeof(invalid));
  retained_scene = host.frame;
  assert(!update_image(&host, 0, invalid_png));
  assert(host.frame == retained_scene);
  host.texture_dirty[0] = host.texture_dirty[1] = false;
  assert(update_image(&host, 1, invalid_png));
  assert(host.editor == nullptr && host.png_bytes[1].empty());
  assert(!host.texture_dirty[0] && host.texture_dirty[1]);
  host.texture_dirty[1] = false;
  assert(update_image(&host, 1, nullptr));
  assert(!host.texture_dirty[1]);
  g_clear_object(&host.frame);
  g_clear_object(&host.editor);
}

std::vector<uint8_t> read_pixels(int width, int height) {
  std::vector<uint8_t> pixels(width * height * 4);
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
  assert(glGetError() == GL_NO_ERROR);
  return pixels;
}

void gl_context_and_pixels() {
  RainEffect host;
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget* canvas = gtk_gl_area_new();
  gtk_gl_area_set_required_version(GTK_GL_AREA(canvas), 3, 3);
  gtk_gl_area_set_has_alpha(GTK_GL_AREA(canvas), TRUE);
  gtk_window_set_default_size(GTK_WINDOW(window), 500, 350);
  gtk_container_add(GTK_CONTAINER(window), canvas);
  gtk_widget_show_all(window);
  while (gtk_events_pending()) gtk_main_iteration();
  gtk_gl_area_make_current(GTK_GL_AREA(canvas));
  assert(gtk_gl_area_get_error(GTK_GL_AREA(canvas)) == nullptr);
  gtk_gl_area_attach_buffers(GTK_GL_AREA(canvas));
  const int width = gtk_widget_get_allocated_width(canvas);
  const int height = gtk_widget_get_allocated_height(canvas);
  glViewport(0, 0, width, height);
  assert(initialize_gl(&host));
  host.enabled = true;
  host.packet_width = width;
  host.packet_height = height;
  host.drops = {240, 140, 18, 25, 1, 1, .5, 100,
                120, 200, 14, 20, .9, 1, .3, 80};
  g_autoptr(FlValue) scene = image_bytes(width, height);
  g_autoptr(FlValue) editor = image_bytes(100, 100, true);
  assert(update_image(&host, 0, scene));
  assert(update_image(&host, 1, editor));
  host.editor_bounds = {200, 90, 100, 100};
  assert(render_gl(&host, width, height));
  const auto expected = read_pixels(width, height);
  assert(std::any_of(expected.begin(), expected.end(),
                     [](uint8_t value) { return value != 0; }));
  for (int sample = 0; sample < 12; sample++) {
    assert(update_image(&host, 0, scene));
    assert(update_image(&host, 1, editor));
    assert(!host.texture_dirty[0] && !host.texture_dirty[1]);
    assert(render_gl(&host, width, height));
    assert(read_pixels(width, height) == expected);
  }
  // CPU images outlive GL resource release. Identical PNGs after a recreated
  // GL program must still populate both freshly allocated texture objects.
  release_gl(&host);
  assert(host.texture_dirty[0] && host.texture_dirty[1]);
  assert(update_image(&host, 0, scene));
  assert(update_image(&host, 1, editor));
  assert(render_gl(&host, width, height));
  assert(read_pixels(width, height) == expected);
  release_gl(&host);
  g_clear_object(&host.frame);
  g_clear_object(&host.editor);
  gtk_widget_destroy(window);
  puts("Rain texture reuse preserves exact GPU pixels and GL recreation.");
}

void decode_benchmark() {
  constexpr int samples = 100;
  RainEffect host;
  g_autoptr(FlValue) scene = image_bytes(822, 523);
  const gint64 before_start = g_get_monotonic_time();
  for (int sample = 0; sample < samples; sample++) {
    g_autoptr(GdkPixbuf) image = decode_png(scene);
    assert(image != nullptr);
  }
  const gint64 before = g_get_monotonic_time() - before_start;
  assert(update_image(&host, 0, scene));
  host.texture_dirty[0] = false;
  const gint64 after_start = g_get_monotonic_time();
  for (int sample = 0; sample < samples; sample++) {
    assert(update_image(&host, 0, scene));
    assert(!host.texture_dirty[0]);
  }
  const gint64 after = g_get_monotonic_time() - after_start;
  printf("Identical 822x523 PNG samples=%d, old decode=%lld us, exact-byte reuse=%lld us.\n",
         samples, static_cast<long long>(before),
         static_cast<long long>(after));
  g_clear_object(&host.frame);
}
}  // namespace

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  independent_textures();
  gl_context_and_pixels();
  decode_benchmark();
  puts("Independent Flutter/editor cache, invalid frames and dirty state passed.");
}
