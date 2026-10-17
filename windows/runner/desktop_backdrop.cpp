#include <inspectable.h>

#include "desktop_backdrop.h"

#include <dcomp.h>
#include <dwmapi.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <unordered_map>
#include <unordered_set>

namespace {
using namespace winrt;
using namespace Windows::UI::Composition;

// Windows' interop compositor implements both the public WinRT compositor and
// IDCompositionDevice2. A native container produced by that device also exposes
// WinRT Visual, so CompositionVisualSurface can texture the DWM backdrop on the
// GPU without desktop readback. ABI verified on Windows 11 build 26100.
// Interop ABI reference: cnbluefire/BlueFire.Toolkit.WinUI3,
// Compositions/InteropCompositor.cs.
struct __declspec(uuid("22118ADF-23F1-4801-BCFA-66CBF48CC51B"))
    InteropCompositorFactory : ::IInspectable {
  virtual HRESULT __stdcall CreateInteropCompositor(
      ::IUnknown* device, ::IUnknown* callback, REFIID iid, void** result) = 0;
  virtual HRESULT __stdcall CheckEnabled(bool* compositor, bool* visual) = 0;
};
constexpr GUID kInteropCompositorPartner = {
    0xE7894C70, 0xAF56, 0x4F52,
    {0xB3, 0x82, 0x4B, 0x3C, 0xD2, 0x63, 0xDC, 0x6F}};
struct __declspec(uuid("E7894C70-AF56-4F52-B382-4B3CD263DC6F"))
    InteropCompositorPartner : ::IUnknown {
  virtual HRESULT __stdcall MarkDirty() = 0;
};

// Shared visual ABI: blog.adeltax.com/dwm-thumbnails-but-with-idcompositionvisual/
// The cloaked helper pattern is also used by VideoLAN VLC's
// modules/gui/qt/maininterface/compositor_dcomp_acrylicsurface.cpp.
using CreateMultiVisual = HRESULT(WINAPI*)(HWND, void*, void**, PHTHUMBNAIL);
using UpdateMultiVisual = HRESULT(WINAPI*)(HTHUMBNAIL, HWND*, DWORD,
    HWND*, DWORD, RECT*, SIZE*, DWORD);
using CreateThumbnailVisual = HRESULT(WINAPI*)(HWND, HWND, DWORD,
    DWM_THUMBNAIL_PROPERTIES*, void*, void**, PHTHUMBNAIL);
struct CompositionAttributeData {
  int attribute;
  void* data;
  DWORD size;
};
using SetCompositionAttribute = BOOL(WINAPI*)(HWND, CompositionAttributeData*);
constexpr int kExcludedFromLivePreview = 0xD;
constexpr DWORD kThumbnailEnable3D = 0x4000000;

template <class T> T Ordinal(HMODULE module, WORD ordinal) {
  const auto procedure = GetProcAddress(module, MAKEINTRESOURCEA(ordinal));
  if (!procedure) throw hresult_error(HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND));
  return reinterpret_cast<T>(procedure);
}

std::string ErrorText(const hresult_error& error) {
  char code[16]{};
  std::snprintf(code, sizeof(code), "0x%08X", static_cast<unsigned>(error.code()));
  return std::string(code) + ": " + to_string(error.message());
}
}  // namespace

struct DesktopBackdrop::Impl {
  explicit Impl(HWND window) : main_window(window) {}
  HWND main_window;
  HWND material_window = nullptr;
  HWND dummy_window = nullptr;
  HWND shell_window = nullptr;
  HMODULE dwm_module = nullptr;
  CreateThumbnailVisual create_thumbnail = nullptr;
  CreateMultiVisual create_multi = nullptr;
  UpdateMultiVisual update_multi = nullptr;
  Compositor compositor{nullptr};
  com_ptr<InteropCompositorPartner> interop_partner;
  com_ptr<IDCompositionDevice2> device;
  com_ptr<IDCompositionVisual2> container;
  com_ptr<IDCompositionVisual2> desktop_visual;
  com_ptr<IDCompositionVisual2> windows_visual;
  Visual visual{nullptr};
  HTHUMBNAIL desktop_thumbnail = nullptr;
  HTHUMBNAIL windows_thumbnail = nullptr;
  const char* phase = "load shared backdrop APIs";
  bool projection_valid = false;
  bool viewport_valid = false;
  RECT projection_bounds{};
  RECT viewport_bounds{};
  std::array<HWND, 3> projection_exclusions{};
  DWORD projection_exclusion_count = 0;
  bool projection_invalidated = true;
  HWINEVENTHOOK object_hook = nullptr;
  HWINEVENTHOOK foreground_hook = nullptr;
  std::unordered_set<HWND> known_top_levels;
  // OUTOFCONTEXT callbacks are delivered on the registering UI thread. Keep
  // registrations local to it when companion Flutter engines use other threads.
  static inline thread_local std::unordered_map<HWINEVENTHOOK, Impl*> hooks;

  bool IsOwnWindow(HWND window) const noexcept {
    if (window == dummy_window || window == main_window ||
        window == material_window) return true;
    const auto root = GetAncestor(window, GA_ROOT);
    if (root && (root == main_window || root == material_window ||
                 root == dummy_window)) return true;
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    DWORD cloaked = 0;
    return process == GetCurrentProcessId() &&
        SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED,
                                       &cloaked, sizeof(cloaked))) && cloaked;
  }

  static void CALLBACK WindowChanged(HWINEVENTHOOK hook, DWORD event,
      HWND window, LONG object, LONG, DWORD, DWORD) noexcept {
    const auto found = hooks.find(hook);
    if (found == hooks.end() || !window) return;
    auto& backdrop = *found->second;
    try {
      if (event == EVENT_SYSTEM_FOREGROUND) {
        // Reactivation is the refresh point used by VLC. The foreground event
        // occurs once, unlike paint/position notifications from our own app.
        if (GetAncestor(window, GA_ROOT) != window) return;
        if (window != backdrop.dummy_window &&
            (window == backdrop.main_window || !backdrop.IsOwnWindow(window))) {
          backdrop.projection_invalidated = true;
        }
        return;
      }
      const bool desktop_reorder = event == EVENT_OBJECT_REORDER &&
          object == OBJID_CLIENT && window == GetDesktopWindow();
      if (object != OBJID_WINDOW && !desktop_reorder) return;
      if (backdrop.IsOwnWindow(window)) return;
      if (event == EVENT_OBJECT_DESTROY) {
        // Out-of-context destroy events can arrive after the HWND has gone.
        // Retain the known top-level set so child WebView teardown is ignored.
        if (!backdrop.known_top_levels.erase(window)) return;
      } else if (!desktop_reorder) {
        if (GetAncestor(window, GA_ROOT) != window) return;
        backdrop.known_top_levels.insert(window);
        if (event == EVENT_OBJECT_CREATE && !IsWindowVisible(window)) return;
      }
      backdrop.projection_invalidated = true;
    } catch (...) {
      // A missed membership update is recoverable on the next foreground event.
      backdrop.projection_invalidated = true;
    }
  }

  void WatchWindows() {
    EnumWindows([](HWND window, LPARAM context) -> BOOL {
      auto& backdrop = *reinterpret_cast<Impl*>(context);
      if (!backdrop.IsOwnWindow(window)) {
        try { backdrop.known_top_levels.insert(window); } catch (...) {}
      }
      return TRUE;
    }, reinterpret_cast<LPARAM>(this));
    object_hook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_REORDER,
        nullptr, WindowChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (!object_hook) throw_last_error();
    hooks.emplace(object_hook, this);
    foreground_hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
        EVENT_SYSTEM_FOREGROUND, nullptr, WindowChanged, 0, 0,
        WINEVENT_OUTOFCONTEXT);
    if (!foreground_hook) throw_last_error();
    hooks.emplace(foreground_hook, this);
  }

  ~Impl() noexcept {
    for (const auto hook : {object_hook, foreground_hook}) {
      if (hook) {
        hooks.erase(hook);
        UnhookWinEvent(hook);
      }
    }
    // The shared visuals own the private thumbnail handles. Releasing their
    // visuals, then the destination window, follows the shared API's contract;
    // the public DwmUnregisterThumbnail API is not used for these handles.
    visual = nullptr;
    container = nullptr;
    windows_visual = nullptr;
    desktop_visual = nullptr;
    device = nullptr;
    interop_partner = nullptr;
    compositor = nullptr;
    if (dummy_window) DestroyWindow(dummy_window);
    if (dwm_module) FreeLibrary(dwm_module);
  }

  void Initialize(HWND material) {
    // Ordinal 164 has a different ABI on Windows 10. Verify the real kernel
    // version before resolving or calling the Windows 11 shared-visual APIs.
    phase = "check Windows desktop composition ABI";
    using RtlGetVersion = LONG(WINAPI*)(OSVERSIONINFOW*);
    const auto get_version=reinterpret_cast<RtlGetVersion>(
        GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"RtlGetVersion"));
    OSVERSIONINFOW version{};
    version.dwOSVersionInfoSize=sizeof(version);
    if (!get_version || get_version(&version)<0 || version.dwBuildNumber<22000) {
      throw hresult_error(HRESULT_FROM_WIN32(ERROR_OLD_WIN_VERSION),
          L"Native desktop glass requires Windows 11 or newer.");
    }
    material_window = material;
    dwm_module = LoadLibraryExW(L"dwmapi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!dwm_module) throw_last_error();
    create_thumbnail = Ordinal<CreateThumbnailVisual>(dwm_module, 147);
    create_multi = Ordinal<CreateMultiVisual>(dwm_module, 163);
    update_multi = Ordinal<UpdateMultiVisual>(dwm_module, 164);
    const auto user_module = GetModuleHandleW(L"user32.dll");
    const auto set_attribute = reinterpret_cast<SetCompositionAttribute>(
        GetProcAddress(user_module, "SetWindowCompositionAttribute"));
    if (!set_attribute) throw hresult_error(E_NOINTERFACE);

    phase = "create interop compositor";
    const auto factory = get_activation_factory<Compositor>()
        .as<InteropCompositorFactory>();
    com_ptr<::IUnknown> partner;
    check_hresult(factory->CreateInteropCompositor(nullptr, nullptr,
        kInteropCompositorPartner, partner.put_void()));
    compositor = partner.as<Compositor>();
    interop_partner = partner.as<InteropCompositorPartner>();
    device = compositor.as<IDCompositionDevice2>();
    check_hresult(device->CreateVisual(container.put()));
    visual = container.as<Visual>();
    visual.Clip(compositor.CreateInsetClip());

    // Multi-window shared visuals require a preview-excluded destination. Keep
    // that property on a cloaked helper, leaving the actual app capturable.
    phase = "create backdrop helper";
    dummy_window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"STATIC", L"Orion backdrop source", WS_POPUP,
        0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!dummy_window) throw_last_error();
    const BOOL cloak = TRUE;
    check_hresult(DwmSetWindowAttribute(dummy_window, DWMWA_CLOAK,
                                       &cloak, sizeof(cloak)));
    ShowWindow(dummy_window, SW_SHOWNOACTIVATE);
    BOOL exclude_preview = TRUE;
    CompositionAttributeData attribute{
        kExcludedFromLivePreview, &exclude_preview, sizeof(exclude_preview)};
    if (!set_attribute(dummy_window, &attribute)) {
      const DWORD error = GetLastError();
      throw hresult_error(error ? HRESULT_FROM_WIN32(error) : E_FAIL);
    }
    phase = "create shared multi-window visual";
    check_hresult(create_multi(dummy_window, device.get(),
        windows_visual.put_void(), &windows_thumbnail));

    shell_window = GetShellWindow();
    if (shell_window) {
      DWM_THUMBNAIL_PROPERTIES thumbnail{};
      thumbnail.dwFlags = DWM_TNP_SOURCECLIENTAREAONLY | DWM_TNP_VISIBLE |
          DWM_TNP_RECTDESTINATION | DWM_TNP_RECTSOURCE | DWM_TNP_OPACITY |
          kThumbnailEnable3D;
      thumbnail.opacity = 255;
      thumbnail.fVisible = TRUE;
      thumbnail.fSourceClientAreaOnly = FALSE;
      RECT shell_rect{};
      if (!GetWindowRect(shell_window, &shell_rect)) throw_last_error();
      thumbnail.rcDestination = {0, 0, shell_rect.right - shell_rect.left,
                                 shell_rect.bottom - shell_rect.top};
      thumbnail.rcSource = thumbnail.rcDestination;
      phase = "create shared desktop visual";
      check_hresult(create_thumbnail(dummy_window, shell_window, 2, &thumbnail,
          device.get(), desktop_visual.put_void(), &desktop_thumbnail));
      check_hresult(container->AddVisual(desktop_visual.get(), FALSE, nullptr));
    }
    phase = "attach shared visuals";
    check_hresult(container->AddVisual(windows_visual.get(), TRUE,
                                       desktop_visual.get()));
    phase = "watch backdrop window membership";
    WatchWindows();
  }

  void Resize(RECT screen) {
    const LONG width = std::max(screen.right - screen.left, 1L);
    const LONG height = std::max(screen.bottom - screen.top, 1L);
    // Keep the private shared visual in desktop coordinates at native scale.
    // VLC uses a full-desktop shared visual and translates it beneath the
    // client clip. Matching that arrangement keeps the source and destination
    // at the same desktop extent and avoids app-sized viewport resampling.
    const LONG desktop_left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    const LONG desktop_top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    const LONG desktop_width = std::max(GetSystemMetrics(SM_CXVIRTUALSCREEN), 1);
    const LONG desktop_height = std::max(GetSystemMetrics(SM_CYVIRTUALSCREEN), 1);
    RECT source{desktop_left, desktop_top, desktop_left + desktop_width,
                 desktop_top + desktop_height};
    SIZE destination{desktop_width, desktop_height};
    std::array<HWND, 3> exclusions{main_window, dummy_window, material_window};
    const DWORD exclusion_count=material_window==main_window?2:3;
    const bool projection_changed = projection_invalidated || !projection_valid ||
        !EqualRect(&projection_bounds, &source) ||
        exclusions != projection_exclusions ||
        exclusion_count != projection_exclusion_count;
    const bool viewport_changed = !viewport_valid ||
        !EqualRect(&viewport_bounds, &screen);
    if (!projection_changed && !viewport_changed) return;
    if (projection_changed) {
      // The shared visual's pixel stream is intrinsically live. Rebuilding its
      // projection on a timer can expose an intermediate empty frame to the
      // sampling surface; only replace it when desktop geometry or exclusions
      // change, as in VLC's shared compositor path.
      phase = "update shared multi-window viewport";
      check_hresult(update_multi(windows_thumbnail, nullptr, 0,
          exclusions.data(), exclusion_count,
          &source, &destination, 1));
    }
    check_hresult(windows_visual->SetOffsetX(
        static_cast<float>(desktop_left - screen.left)));
    check_hresult(windows_visual->SetOffsetY(
        static_cast<float>(desktop_top - screen.top)));
    if (desktop_thumbnail) {
      RECT shell_rect{};
      if (!GetWindowRect(shell_window, &shell_rect)) throw_last_error();
      phase = "update shared desktop viewport";
      check_hresult(desktop_visual->SetOffsetX(
          static_cast<float>(shell_rect.left - screen.left)));
      check_hresult(desktop_visual->SetOffsetY(
          static_cast<float>(shell_rect.top - screen.top)));
    }
    visual.Size({static_cast<float>(width), static_cast<float>(height)});
    phase = "commit shared backdrop";
    check_hresult(device->Commit());
    projection_bounds = {desktop_left, desktop_top,
        desktop_left + desktop_width, desktop_top + desktop_height};
    projection_exclusions = exclusions;
    projection_exclusion_count = exclusion_count;
    projection_valid = true;
    projection_invalidated = false;
    viewport_bounds = screen;
    viewport_valid = true;
  }
};

DesktopBackdrop::DesktopBackdrop(HWND window) : impl_(std::make_unique<Impl>(window)) {}
DesktopBackdrop::~DesktopBackdrop() noexcept = default;

bool DesktopBackdrop::Initialize(HWND material, std::string* error) {
  if (impl_->compositor) return true;
  try {
    impl_->Initialize(material);
    POINT origin{};
    RECT client{};
    if (!GetClientRect(impl_->main_window, &client) ||
        !ClientToScreen(impl_->main_window, &origin)) throw_last_error();
    impl_->Resize({origin.x, origin.y, origin.x + client.right,
                   origin.y + client.bottom});
    return true;
  } catch (const hresult_error& failure) {
    if (error) *error = std::string(impl_->phase) + ": " + ErrorText(failure);
    const auto window = impl_->main_window;
    impl_ = std::make_unique<Impl>(window);
    return false;
  }
}

void DesktopBackdrop::Resize(RECT screen_physical) {
  if (impl_->compositor) impl_->Resize(screen_physical);
}
void DesktopBackdrop::Refresh() {
  // Refresh the WinRT sampling cache without replacing DWM's live projection.
  if (impl_->projection_invalidated && impl_->viewport_valid) {
    impl_->Resize(impl_->viewport_bounds);
  }
  if (impl_->interop_partner) check_hresult(impl_->interop_partner->MarkDirty());
}
Compositor DesktopBackdrop::compositor() const { return impl_->compositor; }
Visual DesktopBackdrop::visual() const { return impl_->visual; }
