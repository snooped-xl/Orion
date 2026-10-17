#include "../linux/runner/monaco_host.cc"

#include <cstdio>

namespace {

std::vector<unsigned char> cairo_png(cairo_surface_t* surface) {
  std::vector<unsigned char> bytes;
  const auto status = cairo_surface_write_to_png_stream(
      surface,
      [](void* context, const unsigned char* data,
         unsigned int length) -> cairo_status_t {
        auto* output = static_cast<std::vector<unsigned char>*>(context);
        output->insert(output->end(), data, data + length);
        return CAIRO_STATUS_SUCCESS;
      }, &bytes);
  g_assert(status == CAIRO_STATUS_SUCCESS);
  return bytes;
}

GdkPixbuf* decode(const std::vector<unsigned char>& bytes) {
  auto* loader = gdk_pixbuf_loader_new_with_type("png", nullptr);
  g_assert(gdk_pixbuf_loader_write(loader, bytes.data(), bytes.size(), nullptr));
  g_assert(gdk_pixbuf_loader_close(loader, nullptr));
  auto* image = GDK_PIXBUF(g_object_ref(gdk_pixbuf_loader_get_pixbuf(loader)));
  g_object_unref(loader);
  return image;
}

void check_pixels(cairo_surface_t* surface) {
  const auto before = cairo_png(surface);
  std::vector<unsigned char> after;
  g_assert(encode_preview_png(surface, &after));
  auto* expected = decode(before);
  auto* actual = decode(after);
  const int width = gdk_pixbuf_get_width(expected);
  const int height = gdk_pixbuf_get_height(expected);
  const int channels = gdk_pixbuf_get_n_channels(expected);
  g_assert(width == gdk_pixbuf_get_width(actual));
  g_assert(height == gdk_pixbuf_get_height(actual));
  g_assert(gdk_pixbuf_get_n_channels(actual) == 4);
  for (int y = 0; y < height; ++y) {
    const auto* a = gdk_pixbuf_get_pixels(expected) +
                    y * gdk_pixbuf_get_rowstride(expected);
    const auto* b = gdk_pixbuf_get_pixels(actual) +
                    y * gdk_pixbuf_get_rowstride(actual);
    for (int x = 0; x < width; ++x) {
      for (int c = 0; c < 4; ++c) {
        const int wanted = c == 3 && channels == 3 ? 255 : a[x * channels + c];
        g_assert(wanted == b[x * 4 + c]);
      }
    }
  }
  g_object_unref(expected);
  g_object_unref(actual);
}

void check_raw_pixels(cairo_surface_t* surface) {
  std::vector<unsigned char> raw;
  g_assert(copy_preview_pixels(surface, &raw));
  auto* expected = decode(cairo_png(surface));
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  const int channels = gdk_pixbuf_get_n_channels(expected);
  g_assert(raw.size() == static_cast<size_t>(width) * height * 4);
  for (int y = 0; y < height; ++y) {
    const auto* png = gdk_pixbuf_get_pixels(expected) + y * gdk_pixbuf_get_rowstride(expected);
    for (int x = 0; x < width; ++x) {
      const int alpha = channels == 3 ? 255 : png[x * channels + 3];
      for (int c = 0; c < 3; ++c) {
        const int expected_channel = (png[x * channels + c] * alpha + 127) / 255;
        g_assert(raw[(static_cast<size_t>(y) * width + x) * 4 + c] == expected_channel);
      }
      g_assert(raw[(static_cast<size_t>(y) * width + x) * 4 + 3] == alpha);
    }
  }
  g_object_unref(expected);
}

void pump() {
  while (g_main_context_iteration(nullptr, FALSE)) {}
  g_usleep(200);
}

void wait_for(bool* done) {
  const auto deadline = g_get_monotonic_time() + 10000000;
  while (!*done && g_get_monotonic_time() < deadline) pump();
  g_assert(*done);
  pump();
}

GTask* start_worker(cairo_surface_t* surface,
                    const std::shared_ptr<PreviewState>& state, bool* done,
                    bool raw = false) {
  // No engine/channel is involved: the test completion only examines the
  // worker's owned image/state, rather than sending a platform response.
  auto* call = FL_METHOD_CALL(g_object_new(fl_method_call_get_type(), nullptr));
  auto* request = new PreviewRequest{
      call, state, cairo_surface_reference(surface), 0};
  request->raw = raw;
  auto* task = g_task_new(nullptr, nullptr,
      [](GObject*, GAsyncResult* result, gpointer data) {
        g_assert(g_task_propagate_boolean(G_TASK(result), nullptr));
        *static_cast<bool*>(data) = true;
      }, done);
  g_task_set_task_data(task, request,
      [](gpointer data) { delete static_cast<PreviewRequest*>(data); });
  g_task_run_in_thread(task, encode_preview);
  return task;
}

double worker_frame(cairo_surface_t* surface,
                     const std::shared_ptr<PreviewState>& state,
                     bool raw = false) {
  bool done = false;
  const auto started = g_get_monotonic_time();
  g_object_unref(start_worker(surface, state, &done, raw));
  wait_for(&done);
  g_assert(raw ? !state->pixels.empty() : !state->png.empty());
  return (g_get_monotonic_time() - started) / 1000.;
}

cairo_surface_t* copy_surface(cairo_surface_t* source) {
  const int width = cairo_image_surface_get_width(source);
  const int height = cairo_image_surface_get_height(source);
  auto* copy = cairo_image_surface_create(
      cairo_image_surface_get_format(source), width, height);
  cairo_surface_flush(source);
  for (int y = 0; y < height; ++y) {
    std::memcpy(cairo_image_surface_get_data(copy) +
                    y * cairo_image_surface_get_stride(copy),
                cairo_image_surface_get_data(source) +
                    y * cairo_image_surface_get_stride(source), width * 4);
  }
  cairo_surface_mark_dirty(copy);
  return copy;
}

void check_cache(cairo_surface_t* surface) {
  auto state = std::make_shared<PreviewState>();
  worker_frame(surface, state);
  const auto* previous = state->previous;
  const auto bytes = state->png;
  auto* copy = copy_surface(surface);
  worker_frame(copy, state);
  g_assert(previous == state->previous && bytes == state->png);

  const int last_y = cairo_image_surface_get_height(copy) - 1;
  const int last_x = cairo_image_surface_get_width(copy) - 1;
  auto* pixel = reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(copy) +
      last_y * cairo_image_surface_get_stride(copy)) + last_x;
  *pixel = (*pixel | 0xff000000) ^ 1;
  cairo_surface_mark_dirty(copy);
  g_assert(!same_preview_pixels(surface, copy));
  worker_frame(copy, state);
  g_assert(previous != state->previous && bytes != state->png);
  check_pixels(copy);
  cairo_surface_destroy(copy);

  // A replacement cannot inherit a pending old view's pixels, even when its
  // window/host owner disappears while an encoder task still owns the state.
  bool done = false;
  auto replacement = std::make_shared<PreviewState>();
  std::weak_ptr<PreviewState> old = state;
  g_object_unref(start_worker(surface, state, &done));
  state->active = false;
  state.reset();
  g_assert(!old.expired());
  wait_for(&done);
  g_assert(old.expired() && replacement->png.empty());
}

void check_interleaved_formats(cairo_surface_t* surface) {
  auto state = std::make_shared<PreviewState>();
  worker_frame(surface, state, true);
  const auto frame = state->frame;
  const auto pixels = state->pixels;
  g_assert(frame > 0 && state->png.empty());
  worker_frame(surface, state);
  const auto png = state->png;
  g_assert(state->frame == frame && state->pixels == pixels);
  worker_frame(surface, state, true);
  g_assert(state->frame == frame && state->png == png && state->pixels == pixels);
  auto* changed = copy_surface(surface);
  auto* pixel = reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(changed));
  *pixel = 0xff123456;
  cairo_surface_mark_dirty(changed);
  worker_frame(changed, state, true);
  g_assert(state->frame == frame + 1 && state->png.empty());
  g_assert(state->pixels != pixels);
  worker_frame(changed, state);
  g_assert(state->frame == frame + 1 && state->png != png);
  cairo_surface_destroy(changed);
}

struct Heartbeat {
  gint64 previous = 0;
  gint64 maximum_gap = 0;
};

gboolean heartbeat(gpointer data) {
  auto* beat = static_cast<Heartbeat*>(data);
  const auto now = g_get_monotonic_time();
  if (beat->previous != 0) {
    beat->maximum_gap = std::max(beat->maximum_gap, now - beat->previous);
  }
  beat->previous = now;
  return G_SOURCE_CONTINUE;
}

void benchmark(cairo_surface_t* surface, const char* label) {
  std::vector<double> before, changed, identical, raw;
  for (int n = 0; n < 20; ++n) {
    const auto started = g_get_monotonic_time();
    cairo_png(surface);
    before.push_back((g_get_monotonic_time() - started) / 1000.);
  }
  auto state = std::make_shared<PreviewState>();
  Heartbeat beat;
  const guint timer = g_timeout_add(1, heartbeat, &beat);
  for (int n = 0; n < 20; ++n) {
    state->png.clear();
    changed.push_back(worker_frame(surface, state));
    identical.push_back(worker_frame(surface, state));
    state->pixels.clear();
    raw.push_back(worker_frame(surface, state, true));
  }
  g_source_remove(timer);
  for (auto* values : {&before, &changed, &identical, &raw}) {
    std::sort(values->begin(), values->end());
  }
  std::printf("%s cairoMedianMs=%.3f workerChangedMedianMs=%.3f "
      "identicalCacheMedianMs=%.3f rawWorkerMedianMs=%.3f mainLoopMaxGapMs=%.3f exactPixels=true\n",
      label, before[10], changed[10], identical[10], raw[10], beat.maximum_gap / 1000.);
}

}  // namespace

int main(int argc, char** argv) {
  // All alpha values, with valid premultiplied RGB channel combinations.
  auto* alpha = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 256, 256);
  auto* pixels = reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(alpha));
  for (unsigned a = 0; a < 256; ++a) {
    for (unsigned c = 0; c < 256; ++c) {
      const unsigned r = c * (a + 1) / 256;
      const unsigned g = (255 - c) * (a + 1) / 256;
      const unsigned b = (c * 73 % 256) * (a + 1) / 256;
      pixels[a * 256 + c] = (a << 24) | (r << 16) | (g << 8) | b;
    }
  }
  cairo_surface_mark_dirty(alpha);
  check_pixels(alpha);
  check_raw_pixels(alpha);
  check_cache(alpha);
  check_interleaved_formats(alpha);

  auto* rgb = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 400, 213);
  auto* cr = cairo_create(rgb);
  auto* gradient = cairo_pattern_create_linear(0, 0, 400, 213);
  cairo_pattern_add_color_stop_rgb(gradient, 0, .05, .2, .4);
  cairo_pattern_add_color_stop_rgb(gradient, 1, .9, .5, .1);
  cairo_set_source(cr, gradient);
  cairo_paint(cr);
  cairo_pattern_destroy(gradient);
  cairo_destroy(cr);
  check_pixels(rgb);
  check_raw_pixels(rgb);
  g_assert(!same_preview_pixels(alpha, rgb));

  // Padding and distinct strides do not affect pixel equivalence.
  uint32_t a[6] = {0x80402010, 0xffffffff, 1, 0, 0x20100804, 2};
  uint32_t b[8] = {0x80402010, 0xffffffff, 8, 9, 0, 0x20100804, 10, 11};
  auto* padded_a = cairo_image_surface_create_for_data(
      reinterpret_cast<unsigned char*>(a), CAIRO_FORMAT_ARGB32, 2, 2, 12);
  auto* padded_b = cairo_image_surface_create_for_data(
      reinterpret_cast<unsigned char*>(b), CAIRO_FORMAT_ARGB32, 2, 2, 16);
  g_assert(same_preview_pixels(padded_a, padded_b));
  check_pixels(padded_a);
  check_pixels(padded_b);
  check_raw_pixels(padded_a);
  check_raw_pixels(padded_b);
  cairo_surface_destroy(padded_a);
  cairo_surface_destroy(padded_b);
  cairo_surface_destroy(alpha);
  cairo_surface_destroy(rgb);

  for (int index = 1; index < argc; ++index) {
    auto* surface = cairo_image_surface_create_from_png(argv[index]);
    g_assert(cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS);
    check_pixels(surface);
    check_raw_pixels(surface);
    check_cache(surface);
    check_interleaved_formats(surface);
    benchmark(surface, argv[index]);
    cairo_surface_destroy(surface);
  }
  std::puts("PASS lossless alpha/RGB fidelity, last-pixel changes, cache reuse, "
             "strides, worker responsiveness and pending view destruction");
}
