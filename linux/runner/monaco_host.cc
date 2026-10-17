#include "monaco_host.h"

#include <webkit2/webkit2.h>
#include <png.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {

// A view generation owns its immutable snapshot cache. Pending snapshot/tasks
// retain this state rather than the host, which can disappear with the window.
struct PreviewState {
  bool active = true;   // Only accessed on the GTK main context.
  bool pending = false;
  cairo_surface_t* previous = nullptr;  // Only accessed by its single worker.
  std::vector<unsigned char> png;
  std::vector<unsigned char> pixels;
  uint64_t frame = 0;

  ~PreviewState() {
    if (previous != nullptr) cairo_surface_destroy(previous);
  }
};

struct MonacoHost {
  FlMethodChannel* channel = nullptr;
  FlView* flutter_view = nullptr;
  GtkOverlay* overlay = nullptr;
  WebKitWebView* web_view = nullptr;
  WebKitUserContentManager* content_manager = nullptr;
  std::string origin;
  std::string backdrop_geometry;
  bool visible = false;
  bool reduced_motion = false;
  bool visual_mirror = false;
  double ui_scale = 1;
  double shell_opacity = 1;
  double reveal_opacity = 1;
  guint reveal_tick = 0;
  gint64 reveal_started = 0;
  GdkRectangle bounds = {0, 0, 1, 1};
  std::shared_ptr<PreviewState> preview = std::make_shared<PreviewState>();
};

void apply_opacity(MonacoHost* host) {
  if (host->web_view != nullptr) {
    gtk_widget_set_opacity(GTK_WIDGET(host->web_view),
                           host->visual_mirror ? 0 :
                               host->shell_opacity * host->reveal_opacity);
  }
}

void cancel_reveal(MonacoHost* host) {
  if (host->web_view != nullptr) {
    GtkWidget* widget = GTK_WIDGET(host->web_view);
    if (host->reveal_tick != 0) {
      gtk_widget_remove_tick_callback(widget, host->reveal_tick);
    }
    host->reveal_opacity = 1;
    apply_opacity(host);
  }
  host->reveal_tick = 0;
  host->reveal_started = 0;
}

gboolean reveal_frame(GtkWidget* widget, GdkFrameClock* clock,
                      gpointer user_data) {
  auto* host = static_cast<MonacoHost*>(user_data);
  if (!host->visible || host->reduced_motion ||
      widget != GTK_WIDGET(host->web_view)) {
    host->reveal_tick = 0;
    host->reveal_started = 0;
    host->reveal_opacity = 1;
    apply_opacity(host);
    return G_SOURCE_REMOVE;
  }
  const gint64 now = gdk_frame_clock_get_frame_time(clock);
  if (host->reveal_started == 0) host->reveal_started = now;
  const double progress = std::min(
      1.0, std::max(0.0, (now - host->reveal_started) / 180000.0));
  // Critically damped effects spring (stiffness1600, mass1), normalized at180ms.
  // Opacity stays bounded; spatial spring overshoot would flash the surface.
  const double time = progress * 7.2;
  const double opacity =
      (1 - (1 + time) * std::exp(-time)) / (1 - 8.2 * std::exp(-7.2));
  host->reveal_opacity = std::min(1.0, std::max(0.0, opacity));
  apply_opacity(host);
  if (progress >= 1) {
    host->reveal_opacity = 1;
    apply_opacity(host);
    host->reveal_tick = 0;
    host->reveal_started = 0;
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

void set_reduced_motion(MonacoHost* host, bool reduced_motion) {
  host->reduced_motion = reduced_motion;
  if (reduced_motion) cancel_reveal(host);
}

void view_destroyed(GtkWidget*, gpointer user_data) {
  auto* host = static_cast<MonacoHost*>(user_data);
  host->visible = false;
  cancel_reveal(host);
}

gboolean child_position(GtkOverlay*, GtkWidget* child, GdkRectangle* allocation,
                         gpointer user_data) {
  auto* host = static_cast<MonacoHost*>(user_data);
  if (child != GTK_WIDGET(host->web_view)) {
    return FALSE;
  }
  *allocation = host->bounds;
  return TRUE;
}

void respond_success(FlMethodCall* call) {
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void respond_error(FlMethodCall* call, const char* code, const char* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

// Treat the Flutter command as JSON data, never as JavaScript source.
std::string quote_json(const char* text) {
  std::string quoted = "\"";
  for (const unsigned char* c =
           reinterpret_cast<const unsigned char*>(text);
       *c != '\0'; ++c) {
    switch (*c) {
      case '\\': quoted += "\\\\"; break;
      case '"': quoted += "\\\""; break;
      case '\n': quoted += "\\n"; break;
      case '\r': quoted += "\\r"; break;
      case '\t': quoted += "\\t"; break;
      default:
        if (*c < 0x20) {
          char escaped[7];
          g_snprintf(escaped, sizeof(escaped), "\\u%04x", *c);
          quoted += escaped;
        } else {
          quoted += static_cast<char>(*c);
        }
    }
  }
  return quoted + "\"";
}

void emit_message(MonacoHost* host, const char* message) {
  g_autoptr(FlValue) value = fl_value_new_string(message);
  fl_method_channel_invoke_method(host->channel, "message", value, nullptr,
                                  nullptr, nullptr);
}

void emit_error(MonacoHost* host, const char* message) {
  const std::string payload =
      "{\"type\":\"hostError\",\"message\":" + quote_json(message) + "}";
  emit_message(host, payload.c_str());
}

void update_backdrop_geometry(MonacoHost* host, bool force = false) {
  if (host->web_view == nullptr || host->overlay == nullptr) return;
  const double scale = host->ui_scale;
  gchar x[G_ASCII_DTOSTR_BUF_SIZE], y[G_ASCII_DTOSTR_BUF_SIZE];
  gchar width[G_ASCII_DTOSTR_BUF_SIZE], height[G_ASCII_DTOSTR_BUF_SIZE];
  g_autofree gchar* geometry = g_strdup_printf(
      "{x:%s,y:%s,width:%s,height:%s}",
      g_ascii_dtostr(x, sizeof(x), host->bounds.x / scale),
      g_ascii_dtostr(y, sizeof(y), host->bounds.y / scale),
      g_ascii_dtostr(width, sizeof(width),
                    gtk_widget_get_allocated_width(GTK_WIDGET(host->overlay)) / scale),
      g_ascii_dtostr(height, sizeof(height),
                    gtk_widget_get_allocated_height(GTK_WIDGET(host->overlay)) / scale));
  if (!force && host->backdrop_geometry == geometry) return;
  host->backdrop_geometry = geometry;
  const std::string script =
      "window.orionSetBackdropGeometry && window.orionSetBackdropGeometry(" +
      host->backdrop_geometry + "); undefined;";
  webkit_web_view_evaluate_javascript(host->web_view, script.c_str(), script.size(),
                                    nullptr, nullptr, nullptr, nullptr, nullptr);
}

bool editor_uri(const char* uri, std::string* origin) {
  g_autoptr(GUri) parsed = g_uri_parse(uri, G_URI_FLAGS_NONE, nullptr);
  if (parsed == nullptr || g_strcmp0(g_uri_get_scheme(parsed), "http") != 0 ||
      g_strcmp0(g_uri_get_host(parsed), "127.0.0.1") != 0 ||
      g_uri_get_port(parsed) < 1 || g_uri_get_port(parsed) > 65535 ||
      g_uri_get_userinfo(parsed) != nullptr ||
      g_strcmp0(g_uri_get_path(parsed), "/editor/index.html") != 0 ||
      g_uri_get_query(parsed) != nullptr ||
      g_uri_get_fragment(parsed) != nullptr) {
    return false;
  }
  *origin = "http://127.0.0.1:" + std::to_string(g_uri_get_port(parsed));
  return true;
}

void script_message_received(WebKitUserContentManager*,
                             WebKitJavascriptResult* result,
                             gpointer user_data) {
  auto* host = static_cast<MonacoHost*>(user_data);
  JSCValue* value = webkit_javascript_result_get_js_value(result);
  if (!jsc_value_is_string(value)) {
    return;
  }
  g_autofree gchar* message = jsc_value_to_string(value);
  if (message != nullptr && std::strlen(message) <= 8 * 1024 * 1024) {
    if (std::strstr(message, "\"type\":\"ready\"") != nullptr) {
      update_backdrop_geometry(host, true);
    }
    emit_message(host, message);
  }
}

gboolean decide_policy(WebKitWebView*, WebKitPolicyDecision* decision,
                       WebKitPolicyDecisionType type, gpointer user_data) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }
  auto* host = static_cast<MonacoHost*>(user_data);
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  WebKitNavigationAction* action =
      webkit_navigation_policy_decision_get_navigation_action(
          WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  const char* uri = webkit_uri_request_get_uri(
      webkit_navigation_action_get_request(action));
  std::string origin;
  if (uri == nullptr || !editor_uri(uri, &origin) || origin != host->origin) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  webkit_policy_decision_use(decision);
  return TRUE;
}

WebKitWebView* block_new_view(WebKitWebView*, WebKitNavigationAction*, gpointer) {
  return nullptr;
}

gboolean block_permission(WebKitWebView*, WebKitPermissionRequest* request,
                          gpointer) {
  webkit_permission_request_deny(request);
  return TRUE;
}

gboolean load_failed(WebKitWebView*, WebKitLoadEvent, gchar*, GError* error,
                     gpointer user_data) {
  if (!g_error_matches(error, WEBKIT_NETWORK_ERROR,
                       WEBKIT_NETWORK_ERROR_CANCELLED)) {
    emit_error(static_cast<MonacoHost*>(user_data), error->message);
  }
  // Do not replace the local editor with WebKit's default error page.
  return TRUE;
}

void process_terminated(WebKitWebView*, WebKitWebProcessTerminationReason,
                        gpointer user_data) {
  emit_error(static_cast<MonacoHost*>(user_data),
             "The editor renderer stopped. Reopen the editor to reload it.");
}

void destroy_view(MonacoHost* host) {
  host->visible = false;
  host->preview->active = false;
  host->preview = std::make_shared<PreviewState>();
  cancel_reveal(host);
  if (host->web_view != nullptr) {
    g_signal_handlers_disconnect_by_data(host->web_view, host);
    gtk_widget_destroy(GTK_WIDGET(host->web_view));
    g_clear_object(&host->web_view);
  }
  if (host->content_manager != nullptr) {
    webkit_user_content_manager_unregister_script_message_handler(
        host->content_manager, "orion");
    g_signal_handlers_disconnect_by_data(host->content_manager, host);
    g_clear_object(&host->content_manager);
  }
  host->origin.clear();
  host->visual_mirror = false;
}

void focus_flutter(MonacoHost* host) {
  if (host->flutter_view != nullptr) {
    gtk_widget_grab_focus(GTK_WIDGET(host->flutter_view));
  }
}

void set_visible(MonacoHost* host, bool visible) {
  const bool was_visible = host->visible;
  host->visible = visible;
  if (host->web_view == nullptr) {
    return;
  }
  GtkWidget* widget = GTK_WIDGET(host->web_view);
  if (!visible) {
    // Modal and navigation hides remain immediate, including mid-reveal.
    gtk_widget_hide(widget);
    cancel_reveal(host);
    focus_flutter(host);
  } else if (!was_visible) {
    cancel_reveal(host);
    host->reveal_opacity = host->reduced_motion ? 1 : 0;
    apply_opacity(host);
    gtk_widget_show(widget);
    if (!host->reduced_motion) {
      host->reveal_tick = gtk_widget_add_tick_callback(
          widget, reveal_frame, host, nullptr);
    }
  }
}

void javascript_finished(GObject* object, GAsyncResult* result,
                         gpointer user_data) {
  auto* call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(JSCValue) value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    respond_error(call, "javascript", error->message);
  } else {
    respond_success(call);
  }
  g_object_unref(call);
}

FlValue* map_value(FlValue* args, const char* key) {
  return args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, key)
             : nullptr;
}

bool number(FlValue* value, double* output) {
  if (value == nullptr) {
    return false;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    *output = fl_value_get_float(value);
  } else if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    *output = static_cast<double>(fl_value_get_int(value));
  } else {
    return false;
  }
  return std::isfinite(*output) && *output >= -100000 && *output <= 100000;
}

// The regular source-UI preview keeps its original resolution. Rain requests
// a bounded texture because its small optical lenses do not need a full HiDPI
// screenshot; cap physical pixels before PNG encoding and native transfer.
cairo_surface_t* bounded_preview(cairo_surface_t* surface, int maximum) {
  if (maximum < 1 || cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) return surface;
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  if (std::max(width, height) <= maximum) return surface;
  const double ratio = static_cast<double>(maximum) / std::max(width, height);
  cairo_surface_t* scaled = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
      std::max(1, static_cast<int>(std::floor(width*ratio))),
      std::max(1, static_cast<int>(std::floor(height*ratio))));
  if (cairo_surface_status(scaled) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(scaled); return surface;
  }
  // Snapshot device scales are implicit logical-to-physical transforms. PNG
  // limits concern physical pixels, so sample the complete raw image once.
  cairo_surface_set_device_scale(surface, 1, 1);
  cairo_t* cr = cairo_create(scaled);
  cairo_scale(cr, ratio, ratio);
  cairo_set_source_surface(cr, surface, 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR);
  cairo_paint(cr);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  return scaled;
}

constexpr size_t kMaximumPreviewBytes = 16 * 1024 * 1024;

// Flutter accepts premultiplied RGBA directly. Keep Cairo's exact channel
// values: live frames need neither PNG compression nor decoding/unpremultiply.
bool copy_preview_pixels(cairo_surface_t* surface,
                         std::vector<unsigned char>* output) {
  if (cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) return false;
  const auto format = cairo_image_surface_get_format(surface);
  if (format != CAIRO_FORMAT_ARGB32 && format != CAIRO_FORMAT_RGB24) return false;
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  if (width < 1 || height < 1 ||
      static_cast<uint64_t>(width) * height > kMaximumPreviewBytes / 4) return false;
  cairo_surface_flush(surface);
  const auto* source = cairo_image_surface_get_data(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  output->resize(static_cast<size_t>(width) * height * 4);
  for (int y = 0; y < height; ++y) {
    const auto* row = reinterpret_cast<const uint32_t*>(source + y * stride);
    auto* target = output->data() + static_cast<size_t>(y) * width * 4;
    for (int x = 0; x < width; ++x) {
      const uint32_t pixel = row[x];
      target[x * 4] = (pixel >> 16) & 255;
      target[x * 4 + 1] = (pixel >> 8) & 255;
      target[x * 4 + 2] = pixel & 255;
      target[x * 4 + 3] = format == CAIRO_FORMAT_RGB24 ? 255 : pixel >> 24;
    }
  }
  return true;
}

// PNG filter selection otherwise scans every row repeatedly on every frame.
// NONE + fast deflate is lossless, and especially efficient for sparse text.
// Keep Cairo's exact ARGB unpremultiplication so glyph edges/alpha are unchanged.
bool encode_preview_png(cairo_surface_t* surface,
                        std::vector<unsigned char>* output) {
  if (cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) return false;
  const cairo_format_t format = cairo_image_surface_get_format(surface);
  if (format != CAIRO_FORMAT_ARGB32 && format != CAIRO_FORMAT_RGB24) return false;
  cairo_surface_flush(surface);
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  if (width < 1 || height < 1) return false;
  const unsigned char* pixels = cairo_image_surface_get_data(surface);
  std::vector<unsigned char> row(static_cast<size_t>(width) * 4);
  png_structp encoder = png_create_write_struct(
      PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
  if (encoder == nullptr) return false;
  png_infop info = png_create_info_struct(encoder);
  if (info == nullptr) {
    png_destroy_write_struct(&encoder, nullptr);
    return false;
  }
  // Objects with C++ destructors are constructed above libpng's error boundary.
  if (setjmp(png_jmpbuf(encoder))) {
    png_destroy_write_struct(&encoder, &info);
    output->clear();
    return false;
  }
  png_set_write_fn(encoder, output,
      [](png_structp png, png_bytep buffer, png_size_t length) {
        auto* bytes = static_cast<std::vector<unsigned char>*>(png_get_io_ptr(png));
        if (length >= kMaximumPreviewBytes ||
            bytes->size() >= kMaximumPreviewBytes - length) {
          png_error(png, "Editor preview exceeds its byte limit");
        }
        bytes->insert(bytes->end(), buffer, buffer + length);
      }, nullptr);
  png_set_IHDR(encoder, info, width, height, 8, PNG_COLOR_TYPE_RGBA,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
               PNG_FILTER_TYPE_DEFAULT);
  png_set_compression_level(encoder, 1);
  png_set_filter(encoder, PNG_FILTER_TYPE_BASE, PNG_FILTER_NONE);
  png_write_info(encoder, info);
  for (int y = 0; y < height; ++y) {
    const auto* source = reinterpret_cast<const uint32_t*>(pixels + y * stride);
    for (int x = 0; x < width; ++x) {
      const uint32_t pixel = source[x];
      const unsigned int alpha = format == CAIRO_FORMAT_RGB24 ? 255 : pixel >> 24;
      unsigned char* target = row.data() + static_cast<size_t>(x) * 4;
      target[3] = alpha;
      if (alpha == 255) {
        target[0] = (pixel >> 16) & 255;
        target[1] = (pixel >> 8) & 255;
        target[2] = pixel & 255;
      } else if (alpha == 0) {
        target[0] = target[1] = target[2] = 0;
      } else {
        target[0] = (((pixel >> 16) & 255) * 255 + alpha / 2) / alpha;
        target[1] = (((pixel >> 8) & 255) * 255 + alpha / 2) / alpha;
        target[2] = ((pixel & 255) * 255 + alpha / 2) / alpha;
      }
    }
    png_write_row(encoder, row.data());
  }
  png_write_end(encoder, info);
  png_destroy_write_struct(&encoder, &info);
  return true;
}

bool same_preview_pixels(cairo_surface_t* left, cairo_surface_t* right) {
  if (left == nullptr || right == nullptr ||
      cairo_surface_get_type(left) != CAIRO_SURFACE_TYPE_IMAGE ||
      cairo_surface_get_type(right) != CAIRO_SURFACE_TYPE_IMAGE ||
      cairo_image_surface_get_format(left) != cairo_image_surface_get_format(right) ||
      cairo_image_surface_get_width(left) != cairo_image_surface_get_width(right) ||
      cairo_image_surface_get_height(left) != cairo_image_surface_get_height(right)) {
    return false;
  }
  const auto format = cairo_image_surface_get_format(left);
  if (format != CAIRO_FORMAT_ARGB32 && format != CAIRO_FORMAT_RGB24) return false;
  cairo_surface_flush(left);
  cairo_surface_flush(right);
  const int width = cairo_image_surface_get_width(left);
  const int height = cairo_image_surface_get_height(left);
  const int left_stride = cairo_image_surface_get_stride(left);
  const int right_stride = cairo_image_surface_get_stride(right);
  const unsigned char* a = cairo_image_surface_get_data(left);
  const unsigned char* b = cairo_image_surface_get_data(right);
  for (int y = 0; y < height; ++y) {
    if (std::memcmp(a + y * left_stride, b + y * right_stride,
                    static_cast<size_t>(width) * 4) != 0) return false;
  }
  return true;
}

// WebKit can return a clear snapshot while its backing store is being rebuilt
// after a resize or remap. Monaco still paints a gutter for an empty document;
// a completely transparent frame must not replace the last painted text.
bool preview_has_content(cairo_surface_t* surface) {
  if (cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) return false;
  const auto format = cairo_image_surface_get_format(surface);
  if (format == CAIRO_FORMAT_RGB24) return true;
  if (format != CAIRO_FORMAT_ARGB32) return false;
  cairo_surface_flush(surface);
  const int width = cairo_image_surface_get_width(surface);
  const int height = cairo_image_surface_get_height(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  const auto* pixels = cairo_image_surface_get_data(surface);
  for (int y = 0; y < height; ++y) {
    const auto* row = reinterpret_cast<const uint32_t*>(pixels + y * stride);
    for (int x = 0; x < width; ++x) {
      if ((row[x] >> 24) != 0) return true;
    }
  }
  return false;
}

struct PreviewRequest {
  FlMethodCall* call;
  std::shared_ptr<PreviewState> state;
  cairo_surface_t* surface = nullptr;
  int maximum = 0;
  bool raw = false;
  uint64_t previous_frame = 0;
  bool valid = false;

  ~PreviewRequest() {
    if (surface != nullptr) cairo_surface_destroy(surface);
    g_object_unref(call);
  }
};

// The snapshot is an owned image, independent of WebKit after finish(). Only
// pixel comparison/PNG encoding run here; all GTK/Flutter calls stay on GTK's
// main context. This lets scrolling/input proceed while a frame is encoded.
void encode_preview(GTask* task, gpointer, gpointer data, GCancellable*) {
  auto* request = static_cast<PreviewRequest*>(data);
  auto& cache = *request->state;
  request->surface = bounded_preview(request->surface, request->maximum);
  request->valid = preview_has_content(request->surface);
  if (!request->valid) {
    g_task_return_boolean(task, TRUE);
    return;
  }
  if (!same_preview_pixels(cache.previous, request->surface)) {
    cache.png.clear();
    cache.pixels.clear();
    ++cache.frame;
    if (cache.previous != nullptr) cairo_surface_destroy(cache.previous);
    cache.previous = request->surface;
    request->surface = nullptr;
  }
  if (request->raw) {
    if (cache.pixels.empty()) copy_preview_pixels(cache.previous, &cache.pixels);
  } else if (cache.png.empty()) {
    std::vector<unsigned char> bytes;
    bytes.reserve(cache.png.capacity());
    if (!encode_preview_png(cache.previous, &bytes)) {
      bytes.clear();
      const auto status = cairo_surface_write_to_png_stream(
          cache.previous,
          [](void* context, const unsigned char* buffer,
              unsigned int length) -> cairo_status_t {
            auto* output = static_cast<std::vector<unsigned char>*>(context);
            if (length >= kMaximumPreviewBytes ||
                output->size() >= kMaximumPreviewBytes - length) {
              return CAIRO_STATUS_WRITE_ERROR;
            }
            output->insert(output->end(), buffer, buffer + length);
            return CAIRO_STATUS_SUCCESS;
          }, &bytes);
      if (status != CAIRO_STATUS_SUCCESS) bytes.clear();
    }
    cache.png = std::move(bytes);
  }
  g_task_return_boolean(task, TRUE);
}

void preview_encoded(GObject*, GAsyncResult* result, gpointer) {
  auto* task = G_TASK(result);
  auto* request = static_cast<PreviewRequest*>(g_task_get_task_data(task));
  g_task_propagate_boolean(task, nullptr);
  request->state->pending = false;
  if (!request->valid) {
    respond_success(request->call);
    return;
  }
  if (request->raw && request->state->active && !request->state->pixels.empty()) {
    const auto& state = *request->state;
    g_autoptr(FlValue) value = fl_value_new_map();
    fl_value_set_string_take(value, "frame", fl_value_new_int(state.frame));
    fl_value_set_string_take(value, "width", fl_value_new_int(cairo_image_surface_get_width(state.previous)));
    fl_value_set_string_take(value, "height", fl_value_new_int(cairo_image_surface_get_height(state.previous)));
    if (request->previous_frame != state.frame) {
      fl_value_set_string_take(value, "pixels",
          fl_value_new_uint8_list(state.pixels.data(), state.pixels.size()));
    }
    fl_method_call_respond_success(request->call, value, nullptr);
    return;
  }
  const auto& bytes = request->state->png;
  if (request->state->active && !bytes.empty() &&
      bytes.size() < kMaximumPreviewBytes) {
    g_autoptr(FlValue) value = fl_value_new_uint8_list(bytes.data(), bytes.size());
    fl_method_call_respond_success(request->call, value, nullptr);
  } else {
    respond_success(request->call);
  }
}

void method_called(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto* host = static_cast<MonacoHost*>(user_data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (std::strcmp(method, "capturePreview") == 0 ||
      std::strcmp(method, "capturePreviewPixels") == 0) {
    if (host->web_view == nullptr || !host->visible || host->preview->pending) {
      respond_success(call);
      return;
    }
    auto* request = new PreviewRequest{FL_METHOD_CALL(g_object_ref(call)), host->preview};
    request->raw = std::strcmp(method, "capturePreviewPixels") == 0;
    FlValue* previous = map_value(args, "frame");
    if (previous != nullptr && fl_value_get_type(previous) == FL_VALUE_TYPE_INT &&
        fl_value_get_int(previous) > 0) {
      request->previous_frame = fl_value_get_int(previous);
    }
    double maximum;
    if (number(map_value(args, "maxDimension"), &maximum) &&
        maximum >= 1 && maximum <= 4096) {
      request->maximum = static_cast<int>(maximum);
    }
    request->state->pending = true;
    webkit_web_view_get_snapshot(
        host->web_view, WEBKIT_SNAPSHOT_REGION_VISIBLE,
        WEBKIT_SNAPSHOT_OPTIONS_TRANSPARENT_BACKGROUND, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
          auto* request = static_cast<PreviewRequest*>(data);
          g_autoptr(GError) error = nullptr;
          request->surface = webkit_web_view_get_snapshot_finish(
              WEBKIT_WEB_VIEW(object), result, &error);
          if (request->surface == nullptr || !request->state->active) {
            request->state->pending = false;
            respond_success(request->call);
            delete request;
            return;
          }
          g_autoptr(GTask) task = g_task_new(nullptr, nullptr, preview_encoded, nullptr);
          g_task_set_task_data(task, request,
              [](gpointer data) { delete static_cast<PreviewRequest*>(data); });
          g_task_run_in_thread(task, encode_preview);
        }, request);
    // The asynchronous snapshot callback owns the single method response.
    return;
  } else if (std::strcmp(method, "create") == 0) {
    FlValue* url = map_value(args, "url");
    std::string origin;
    if (url == nullptr || fl_value_get_type(url) != FL_VALUE_TYPE_STRING ||
        !editor_uri(fl_value_get_string(url), &origin) ||
        host->overlay == nullptr) {
      respond_error(call, "invalid_url", "Expected the local Orion editor URL.");
      return;
    }
    destroy_view(host);
    host->origin = origin;
    host->content_manager = webkit_user_content_manager_new();
    g_signal_connect(host->content_manager, "script-message-received::orion",
                     G_CALLBACK(script_message_received), host);
    webkit_user_content_manager_register_script_message_handler(
        host->content_manager, "orion");
    host->web_view = WEBKIT_WEB_VIEW(
        webkit_web_view_new_with_user_content_manager(host->content_manager));
    // Keep our reference until explicit disposal; GtkOverlay holds its own.
    g_object_ref_sink(host->web_view);
    // HTML paints every opaque editor theme itself. A clear backing surface
    // lets Classic Orion's transparent DOM reveal the Flutter window backdrop
    // underneath, while retaining full opacity for text and floating widgets.
    GdkRGBA background{0, 0, 0, 0};
    webkit_web_view_set_background_color(host->web_view, &background);
    webkit_web_view_set_zoom_level(host->web_view, host->ui_scale);
    WebKitSettings* settings = webkit_web_view_get_settings(host->web_view);
    // This text surface also runs on Linux software-rendered display sessions.
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
    webkit_settings_set_enable_write_console_messages_to_stdout(settings, FALSE);
    webkit_settings_set_javascript_can_open_windows_automatically(settings, FALSE);
    webkit_settings_set_enable_developer_extras(settings, FALSE);
    g_signal_connect(host->web_view, "decide-policy", G_CALLBACK(decide_policy),
                     host);
    g_signal_connect(host->web_view, "create", G_CALLBACK(block_new_view), host);
    g_signal_connect(host->web_view, "permission-request",
                     G_CALLBACK(block_permission), host);
    g_signal_connect(host->web_view, "load-failed", G_CALLBACK(load_failed), host);
    g_signal_connect(host->web_view, "web-process-terminated",
                     G_CALLBACK(process_terminated), host);
    g_signal_connect(host->web_view, "destroy", G_CALLBACK(view_destroyed), host);
    gtk_widget_set_no_show_all(GTK_WIDGET(host->web_view), TRUE);
    host->bounds = {0, 0, 1, 1};
    gtk_overlay_add_overlay(host->overlay, GTK_WIDGET(host->web_view));
    gtk_overlay_set_overlay_pass_through(host->overlay,
                                         GTK_WIDGET(host->web_view), FALSE);
    gtk_widget_set_size_request(GTK_WIDGET(host->web_view), 1, 1);
    gtk_widget_hide(GTK_WIDGET(host->web_view));
    webkit_web_view_load_uri(host->web_view, fl_value_get_string(url));
    g_autoptr(FlValue) capabilities = fl_value_new_map();
    fl_value_set_string_take(capabilities, "pixelPreview", fl_value_new_bool(true));
    fl_method_call_respond_success(call, capabilities, nullptr);
    return;
  }
  if (std::strcmp(method, "dispose") == 0) {
    destroy_view(host);
    focus_flutter(host);
    respond_success(call);
    return;
  }
  if (host->web_view == nullptr) {
    respond_error(call, "not_created", "The native editor has not been created.");
    return;
  }
  if (std::strcmp(method, "setBounds") == 0) {
    double x, y, width, height;
    double ui_scale = host->ui_scale;
    FlValue* visible = map_value(args, "visible");
    FlValue* reduced_motion = map_value(args, "reducedMotion");
    FlValue* scale_value = map_value(args, "uiScale");
    if (!number(map_value(args, "x"), &x) ||
        !number(map_value(args, "y"), &y) ||
        !number(map_value(args, "width"), &width) ||
        !number(map_value(args, "height"), &height) || width < 0 || height < 0 ||
        visible == nullptr || fl_value_get_type(visible) != FL_VALUE_TYPE_BOOL ||
        (reduced_motion != nullptr &&
         fl_value_get_type(reduced_motion) != FL_VALUE_TYPE_BOOL) ||
        (scale_value != nullptr &&
         (!number(scale_value, &ui_scale) || ui_scale < .8 || ui_scale > 1.25))) {
      respond_error(call, "invalid_bounds", "Expected finite editor bounds.");
      return;
    }
    const GdkRectangle next_bounds = {
        static_cast<int>(std::floor(x)), static_cast<int>(std::floor(y)),
        std::max(1, static_cast<int>(std::ceil(width))),
        std::max(1, static_cast<int>(std::ceil(height)))};
    const bool size_changed = next_bounds.width != host->bounds.width ||
                              next_bounds.height != host->bounds.height;
    const bool position_changed = next_bounds.x != host->bounds.x ||
                                  next_bounds.y != host->bounds.y;
    host->bounds = next_bounds;
    if (size_changed) {
      gtk_widget_set_size_request(GTK_WIDGET(host->web_view),
                                  host->bounds.width, host->bounds.height);
    }
    if (size_changed || position_changed) {
      gtk_widget_queue_resize(GTK_WIDGET(host->overlay));
    }
    if (host->ui_scale != ui_scale) {
      host->ui_scale = ui_scale;
      webkit_web_view_set_zoom_level(host->web_view, ui_scale);
    }
    update_backdrop_geometry(host);
    if (reduced_motion != nullptr) {
      set_reduced_motion(host, fl_value_get_bool(reduced_motion));
    }
    set_visible(host, fl_value_get_bool(visible) && width > 0 && height > 0);
    respond_success(call);
  } else if (std::strcmp(method, "setVisualMirror") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      respond_error(call, "invalid_mirror", "Expected a visual-mirror boolean.");
      return;
    }
    // WebKit remains mapped, sensitive and focused for real Monaco input. Its
    // clean alpha snapshots are painted by Flutter in compositor Glass mode,
    // avoiding GTK software backing-store retention of transparent dirty tiles.
    host->visual_mirror = fl_value_get_bool(args);
    apply_opacity(host);
    respond_success(call);
  } else if (std::strcmp(method, "setOpacity") == 0) {
    double opacity;
    if (!number(args, &opacity) || opacity < 0 || opacity > 1) {
      respond_error(call, "invalid_opacity", "Expected opacity between zero and one.");
      return;
    }
    host->shell_opacity = opacity;
    apply_opacity(host);
    respond_success(call);
  } else if (std::strcmp(method, "setVisible") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      respond_error(call, "invalid_visibility", "Expected a visibility boolean.");
      return;
    }
    set_visible(host, fl_value_get_bool(args));
    respond_success(call);
  } else if (std::strcmp(method, "setTheme") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      respond_error(call, "invalid_theme", "Expected a dark-theme boolean.");
      return;
    }
    g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme",
                 fl_value_get_bool(args), nullptr);
    respond_success(call);
  } else if (std::strcmp(method, "focus") == 0) {
    if (host->visible) {
      gtk_widget_grab_focus(GTK_WIDGET(host->web_view));
    }
    respond_success(call);
  } else if (std::strcmp(method, "send") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_STRING) {
      respond_error(call, "invalid_command", "Expected a JSON command string.");
      return;
    }
    const char* json = fl_value_get_string(args);
    if (std::strlen(json) > 8 * 1024 * 1024) {
      respond_error(call, "command_size", "The editor command is too large.");
      return;
    }
    const std::string script =
        "window.orionReceive(JSON.parse(" + quote_json(json) + ")); undefined;";
    webkit_web_view_evaluate_javascript(
        host->web_view, script.c_str(), script.size(), nullptr, nullptr, nullptr,
        javascript_finished, g_object_ref(call));
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

void destroy_host(gpointer data) {
  auto* host = static_cast<MonacoHost*>(data);
  fl_method_channel_set_method_call_handler(host->channel, nullptr, nullptr,
                                           nullptr);
  destroy_view(host);
  if (host->overlay != nullptr) {
    g_signal_handlers_disconnect_by_data(host->overlay, host);
    g_object_remove_weak_pointer(G_OBJECT(host->overlay),
                                 reinterpret_cast<gpointer*>(&host->overlay));
  }
  if (host->flutter_view != nullptr) {
    g_object_remove_weak_pointer(
        G_OBJECT(host->flutter_view),
        reinterpret_cast<gpointer*>(&host->flutter_view));
  }
  g_clear_object(&host->channel);
  delete host;
}

}  // namespace

void monaco_host_attach(GtkWindow* window, FlView* flutter_view,
                        GtkOverlay* overlay) {
  auto* host = new MonacoHost();
  host->flutter_view = flutter_view;
  host->overlay = overlay;
  g_signal_connect(overlay, "get-child-position", G_CALLBACK(child_position),
                   host);
  g_signal_connect(overlay, "size-allocate",
                   G_CALLBACK(+[](GtkWidget*, GtkAllocation*, gpointer data) {
                     update_backdrop_geometry(static_cast<MonacoHost*>(data));
                   }), host);
  g_object_add_weak_pointer(G_OBJECT(flutter_view),
                            reinterpret_cast<gpointer*>(&host->flutter_view));
  g_object_add_weak_pointer(G_OBJECT(overlay),
                            reinterpret_cast<gpointer*>(&host->overlay));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  host->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(flutter_view)),
      "orion/monaco", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(host->channel, method_called, host,
                                           nullptr);
  g_object_set_data_full(G_OBJECT(window), "orion-monaco-host", host,
                         destroy_host);
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
    // Unregister before GtkContainer destroys the FlView and its engine.
    g_object_set_data(G_OBJECT(widget), "orion-monaco-host", nullptr);
  }), nullptr);
}
