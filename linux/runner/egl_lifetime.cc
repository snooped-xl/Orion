#include "egl_lifetime.h"

#include <epoxy/egl.h>
#include <glib.h>
#include <dlfcn.h>

#include <mutex>
#include <unordered_map>

namespace {
PFNEGLINITIALIZEPROC initialize_display = nullptr;
PFNEGLTERMINATEPROC terminate_display = nullptr;
PFNEGLDESTROYCONTEXTPROC destroy_context = nullptr;
std::mutex display_mutex;
std::unordered_map<EGLDisplay, size_t> display_users;
constexpr char kRendererEngine[] = "orion-engine-until-renderer-finalized";

bool trace_enabled() {
  static const bool enabled = g_getenv("ORION_EGL_TRACE") != nullptr;
  return enabled;
}

void trace(const char* operation, EGLDisplay display, EGLContext context,
           EGLBoolean result, size_t users = 0) {
  if (!trace_enabled()) return;
  g_printerr("Orion EGL %s thread=%p display=%p context=%p current=%p/%p "
             "result=%u users=%zu\n", operation, static_cast<void*>(g_thread_self()),
             display, context, eglGetCurrentDisplay(), eglGetCurrentContext(),
             result, users);
}

void release_renderer_engine(gpointer data) {
  auto* engine = G_OBJECT(data);
  if (trace_enabled()) {
    g_printerr("Orion EGL renderer-finalized releasing engine=%p\n", data);
  }
  g_object_unref(engine);
  if (trace_enabled()) {
    g_printerr("Orion EGL renderer engine reference released=%p\n", data);
  }
}

bool bind_renderer(GtkWidget* widget, GObject* engine) {
  // FlViewRenderer is an internal widget, so inspect its public GObject type
  // and GTK children rather than depending on its private instance layout.
  if (g_strcmp0(G_OBJECT_TYPE_NAME(widget), "FlViewRenderer") == 0) {
    if (g_object_get_data(G_OBJECT(widget), kRendererEngine) == nullptr) {
      // Renderer::dispose drops its ordinary engine reference, but its
      // compositor survives until Renderer::finalize. GObject qdata is freed
      // by the parent finalize, after that compositor's framebuffer cleanup.
      // FlEngine holds only weak view/task-runner references, so this creates
      // no reference cycle and releases the engine when the renderer dies.
      g_object_set_data_full(G_OBJECT(widget), kRendererEngine,
                            g_object_ref(engine), release_renderer_engine);
      if (trace_enabled()) {
        g_printerr("Orion EGL renderer=%p retains engine=%p\n",
                   static_cast<void*>(widget), static_cast<void*>(engine));
      }
    }
    return true;
  }
  if (!GTK_IS_CONTAINER(widget)) return false;
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  bool found = false;
  for (GList* child = children; child != nullptr; child = child->next) {
    found = bind_renderer(GTK_WIDGET(child->data), engine) || found;
  }
  g_list_free(children);
  return found;
}

EGLBoolean EGLAPIENTRY retain_display(EGLDisplay display, EGLint* major,
                                      EGLint* minor) {
  std::lock_guard<std::mutex> lock(display_mutex);
  const EGLBoolean result = initialize_display(display, major, minor);
  if (result == EGL_TRUE) {
    ++display_users[display];
  }
  const auto user = display_users.find(display);
  trace("initialize", display, EGL_NO_CONTEXT, result,
        user == display_users.end() ? 0 : user->second);
  return result;
}

EGLBoolean EGLAPIENTRY release_display(EGLDisplay display) {
  std::lock_guard<std::mutex> lock(display_mutex);
  const auto user = display_users.find(display);
  if (user != display_users.end()) {
    if (--user->second > 0) {
      trace("release-retained", display, EGL_NO_CONTEXT, EGL_TRUE, user->second);
      return EGL_TRUE;
    }
    display_users.erase(user);
  }
  trace("terminate-before", display, EGL_NO_CONTEXT, EGL_TRUE);
  const EGLBoolean result = terminate_display(display);
  trace("terminate-after", display, EGL_NO_CONTEXT, result);
  return result;
}

EGLBoolean EGLAPIENTRY release_context(EGLDisplay display, EGLContext context) {
  trace("destroy-before", display, context, EGL_TRUE);
  // Flutter's compositor shader cleanup leaves its platform context current.
  // Unbind that exact context while it is still valid: doing this later from
  // eglTerminate, or leaving it for GTK's next draw, crashes NVIDIA's EGL
  // pending-delete-context path. A sibling's current context is left alone.
  if (context != EGL_NO_CONTEXT && eglGetCurrentDisplay() == display &&
      eglGetCurrentContext() == context) {
    const EGLBoolean result =
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    trace("destroy-unbound", display, context, result);
  }
  const EGLBoolean result = destroy_context(display, context);
  trace("destroy-after", display, context, result);
  return result;
}
}  // namespace

void orion_bind_renderer_engine_lifetime(GtkWidget* view, GObject* engine) {
  g_return_if_fail(GTK_IS_WIDGET(view));
  g_return_if_fail(G_IS_OBJECT(engine));
  if (bind_renderer(view, engine)) return;
  // Current Flutter constructs the renderer synchronously in fl_view_new().
  // Retain compatibility if a later engine creates it during realization.
  g_signal_connect_object(view, "realize", G_CALLBACK(+[](GtkWidget* widget,
                                                          gpointer data) {
    if (!bind_renderer(widget, G_OBJECT(data))) {
      g_warning("Orion could not bind Flutter renderer engine lifetime.");
    }
  }), engine, static_cast<GConnectFlags>(0));
}

void orion_install_egl_lifetime() {
  if (initialize_display != nullptr) return;
  // Core EGL symbols need not be exposed by eglGetProcAddress on older drivers.
  // Keep the dispatch library loaded for the lifetime of these function pointers.
  static void* library = dlopen("libEGL.so.1", RTLD_LAZY | RTLD_LOCAL);
  initialize_display = reinterpret_cast<PFNEGLINITIALIZEPROC>(
      library != nullptr ? dlsym(library, "eglInitialize") : nullptr);
  terminate_display = reinterpret_cast<PFNEGLTERMINATEPROC>(
      library != nullptr ? dlsym(library, "eglTerminate") : nullptr);
  destroy_context = reinterpret_cast<PFNEGLDESTROYCONTEXTPROC>(
      library != nullptr ? dlsym(library, "eglDestroyContext") : nullptr);
  if (initialize_display == nullptr) {
    initialize_display = reinterpret_cast<PFNEGLINITIALIZEPROC>(
        eglGetProcAddress("eglInitialize"));
  }
  if (terminate_display == nullptr) {
    terminate_display = reinterpret_cast<PFNEGLTERMINATEPROC>(
        eglGetProcAddress("eglTerminate"));
  }
  if (destroy_context == nullptr) {
    destroy_context = reinterpret_cast<PFNEGLDESTROYCONTEXTPROC>(
        eglGetProcAddress("eglDestroyContext"));
  }
  if (initialize_display == nullptr || terminate_display == nullptr ||
      destroy_context == nullptr) {
    g_warning("EGL lifecycle compatibility functions are unavailable.");
    initialize_display = nullptr;
    return;
  }
  // Both GTK and Flutter use libepoxy's EGL dispatch. EGL itself does not count
  // repeated initializes: a child's eglTerminate would invalidate the primary
  // engine's contexts. Preserve ordinary termination for the final user.
  epoxy_eglInitialize = retain_display;
  epoxy_eglTerminate = release_display;
  epoxy_eglDestroyContext = release_context;
}
