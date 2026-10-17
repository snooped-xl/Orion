#include "orion_native.h"
#include "windows_rain.h"
#include "resource.h"

#include <WebView2.h>
#include <dwmapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <wrl.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <memory>
#include <regex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;
using Channel = flutter::MethodChannel<Value>;
const Value* Get(const Map* args, const char* key) {
  if (!args) return nullptr;
  auto found = args->find(Value(key));
  return found == args->end() ? nullptr : &found->second;
}
double Number(const Value* value, double fallback = 0) {
  if (!value) return fallback;
  double result = fallback;
  if (auto n = std::get_if<double>(value)) result = *n;
  if (auto n = std::get_if<int32_t>(value)) result = *n;
  if (auto n = std::get_if<int64_t>(value)) result = static_cast<double>(*n);
  return std::isfinite(result) ? result : fallback;
}
bool Boolean(const Value* value, bool fallback = false) {
  auto b = value ? std::get_if<bool>(value) : nullptr;
  return b ? *b : fallback;
}
std::string String(const Value* value) {
  auto s = value ? std::get_if<std::string>(value) : nullptr;
  return s ? *s : std::string();
}
std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (n <= 0) return {};
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), out.data(), n);
  return out;
}
std::string Utf8(const wchar_t* value) {
  if (!value) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return {};
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, out.data(), n, nullptr, nullptr);
  out.pop_back();
  return out;
}
std::string JsonString(const std::string& text) {
  std::string out = "\"";
  for (unsigned char c : text) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 32) {
          constexpr char hex[] = "0123456789abcdef";
          out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15];
        } else out += static_cast<char>(c);
    }
  }
  return out + "\"";
}
std::filesystem::path ExecutableDirectory() {
  wchar_t path[32768]{};
  GetModuleFileNameW(nullptr, path, 32768);
  return std::filesystem::path(path).parent_path();
}
std::wstring CacheDirectory() {
  PWSTR path = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &path))) return {};
  std::filesystem::path directory = std::filesystem::path(path) / L"Orion" / L"WebView2";
  CoTaskMemFree(path);
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  return error ? std::wstring() : directory.wstring();
}
template <size_t N> void CopyWide(wchar_t (&target)[N], const std::wstring& text) {
  size_t length = std::min(text.size(), N - 1);
  if (length < text.size() && length > 0 && text[length - 1] >= 0xD800 && text[length - 1] <= 0xDBFF) --length;
  std::copy_n(text.data(), length, target); target[length] = L'\0';
}
constexpr UINT kNotificationMessage = WM_APP + 0x4A3;
std::unordered_map<std::string, HWND> registered_windows;

struct State {
  bool alive = true;
  uint64_t generation = 0;
  HWND root = nullptr, flutter = nullptr, editor_host = nullptr, modal_owner = nullptr;
  flutter::FlutterViewController* view_controller = nullptr;
  ComPtr<ICoreWebView2Environment> environment;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
  std::unique_ptr<Channel> editor_channel;
  std::string origin, id;
  RECT bounds{0, 0, 1, 1};
  double ui_scale = 1, opacity = 1, corner_radius = 16;
  bool visible = false, mirror = false, capture_pending = false;
  HMONITOR startup_monitor = nullptr;
  bool follow_resize = false, centering = false;
  NOTIFYICONDATAW fallback_notification{};
  bool fallback_notification_added = false;
  RECT previous_shape{};
  int previous_shape_radius = -1;
  bool desktop_frame_cleared = false;
  std::string backdrop_geometry;
  void ClearNotification() {
    if (fallback_notification_added) Shell_NotifyIconW(NIM_DELETE, &fallback_notification);
    fallback_notification_added = false;
  }
  double dpi() const { return static_cast<double>(GetDpiForWindow(root)) / 96.0; }
  void Emit(const std::string& message) {
    if (alive) editor_channel->InvokeMethod("message", std::make_unique<Value>(message));
  }
  void Error(const std::string& message) {
    Emit("{\"type\":\"hostError\",\"message\":" + JsonString(message) + "}");
  }
  void ClearEditor() {
    ++generation;
    webview.Reset();
    if (controller) controller->Close();
    controller.Reset(); environment.Reset();
    if (editor_host) DestroyWindow(editor_host);
    editor_host = nullptr;
    visible = false; capture_pending = false; backdrop_geometry.clear();
  }
  void ApplyEditor() {
    if (!controller || !editor_host) return;
    const double scale = dpi();
    int x = static_cast<int>(std::floor(bounds.left * scale));
    int y = static_cast<int>(std::floor(bounds.top * scale));
    int width = std::max(1, static_cast<int>(std::ceil((bounds.right - bounds.left) * scale)));
    int height = std::max(1, static_cast<int>(std::ceil((bounds.bottom - bounds.top) * scale)));
    SetWindowPos(editor_host, HWND_TOP, x, y, width, height, SWP_NOACTIVATE);
    RECT area{0, 0, width, height};
    controller->put_Bounds(area);
    controller->put_ZoomFactor(ui_scale);
    // Preserve real Monaco focus/input in mirror mode; only its native pixels
    // become transparent while Flutter presents alpha-correct WebView captures.
    SetLayeredWindowAttributes(editor_host, 0, static_cast<BYTE>(std::round((mirror ? .004 : opacity) * 255)), LWA_ALPHA);
    controller->put_IsVisible(visible ? TRUE : FALSE);
    ShowWindow(editor_host, visible ? SW_SHOWNA : SW_HIDE);
    RECT client{}; GetClientRect(root, &client);
    std::string script = "window.orionSetBackdropGeometry && window.orionSetBackdropGeometry({x:" +
      std::to_string(bounds.left / ui_scale) + ",y:" + std::to_string(bounds.top / ui_scale) +
      ",width:" + std::to_string(client.right / scale / ui_scale) + ",height:" +
      std::to_string(client.bottom / scale / ui_scale) + "});void 0;";
    if (script != backdrop_geometry) {
      backdrop_geometry = script;
      webview->ExecuteScript(Wide(script).c_str(), nullptr);
    }
  }
  void CenterStartup() {
    if (!startup_monitor || centering) return;
    MONITORINFO info{sizeof(info)};
    if (!GetMonitorInfoW(startup_monitor, &info)) {
      startup_monitor = MonitorFromWindow(root, MONITOR_DEFAULTTOPRIMARY);
      if (!GetMonitorInfoW(startup_monitor, &info)) return;
    }
    RECT window{}; GetWindowRect(root, &window);
    int width = window.right - window.left, height = window.bottom - window.top;
    int x = info.rcMonitor.left + ((info.rcMonitor.right - info.rcMonitor.left) - width) / 2;
    int y = info.rcMonitor.top + ((info.rcMonitor.bottom - info.rcMonitor.top) - height) / 2;
    if (width <= info.rcWork.right - info.rcWork.left) x = static_cast<int>(std::clamp<LONG>(x, info.rcWork.left, info.rcWork.right - width));
    if (height <= info.rcWork.bottom - info.rcWork.top) y = static_cast<int>(std::clamp<LONG>(y, info.rcWork.top, info.rcWork.bottom - height));
    centering = true;
    SetWindowPos(root, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    // Moving to another DPI output may synchronously apply WM_DPICHANGED's
    // suggested size. Center that final physical size, not the old monitor's.
    RECT settled{}; GetWindowRect(root, &settled);
    const int settled_width = settled.right - settled.left;
    const int settled_height = settled.bottom - settled.top;
    if (settled_width != width || settled_height != height) {
      x = info.rcMonitor.left + ((info.rcMonitor.right-info.rcMonitor.left)-settled_width)/2;
      y = info.rcMonitor.top + ((info.rcMonitor.bottom-info.rcMonitor.top)-settled_height)/2;
      if (settled_width <= info.rcWork.right-info.rcWork.left) x = static_cast<int>(std::clamp<LONG>(x,info.rcWork.left,info.rcWork.right-settled_width));
      if (settled_height <= info.rcWork.bottom-info.rcWork.top) y = static_cast<int>(std::clamp<LONG>(y,info.rcWork.top,info.rcWork.bottom-settled_height));
      SetWindowPos(root,nullptr,x,y,0,0,SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE);
    }
    centering = false;
  }
  void Shape() {
    if (!IsWindow(root)) return;
    RECT area{}; GetWindowRect(root, &area);
    const int radius = IsZoomed(root) ? 0 : static_cast<int>(std::round(corner_radius * dpi()));
    if (previous_shape_radius == radius && previous_shape.right == area.right - area.left && previous_shape.bottom == area.bottom - area.top) return;
    previous_shape_radius = radius;
    previous_shape = RECT{0, 0, area.right - area.left, area.bottom - area.top};
    // This also makes transparent corners stop accepting input on Windows 10.
    HRGN region = CreateRoundRectRgn(0, 0, area.right - area.left + 1, area.bottom - area.top + 1, radius * 2, radius * 2);
    if (!SetWindowRgn(root, region, TRUE)) DeleteObject(region);
    DWORD corner = radius > 0 ? 2 : 1;  // DWMWCP_ROUND / DWMWCP_DONOTROUND
    DwmSetWindowAttribute(root, 33, &corner, sizeof(corner));
  }
};

bool LocalEditorUrl(const std::string& url, std::string* origin) {
  static const std::regex pattern(R"(^(http://127\.0\.0\.1:([0-9]{1,5}))/editor/index\.html$)");
  std::smatch match;
  if (!std::regex_match(url, match, pattern)) return false;
  const int port = std::stoi(match[2].str());
  if (port < 1 || port > 65535) return false;
  *origin = match[1].str(); return true;
}

class OrionNative : public flutter::Plugin {
 public:
  explicit OrionNative(flutter::PluginRegistrarWindows* registrar, flutter::FlutterViewController* view_controller)
      : registrar_(registrar), state_(std::make_shared<State>()),
        rain_(GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT)) {
    state_->view_controller = view_controller;
    state_->flutter = registrar->GetView()->GetNativeWindow();
    state_->root = GetAncestor(state_->flutter, GA_ROOT);
    state_->editor_channel = MakeChannel("orion/monaco");
    state_->editor_channel->SetMethodCallHandler([this](const auto& call, auto result) { Editor(call, std::move(result)); });
    window_channel_ = MakeChannel("orion/window");
    window_channel_->SetMethodCallHandler([this](const auto& call, auto result) { Window(call, std::move(result)); });
    notification_channel_ = MakeChannel("orion/bridge_notification");
    notification_channel_->SetMethodCallHandler([this](const auto& call, auto result) { Notification(call, std::move(result)); });
    rain_channel_ = MakeChannel("orion/rain");
    rain_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) { result->Error("invalid_arguments", "Expected rain configuration."); return; }
      const auto& method = call.method_name();
      if (method == "configure") {
        std::string error;
        if (!rain_.Configure(*args, &error)) { result->Error("rain_shader_unavailable", error); return; }
        result->Success(Value(Map{{Value("nativeRain"), Value(true)}, {Value("backend"), Value("Direct3D 11")}}));
      } else if (method == "frame") {
        if (rain_.Frame(*args)) result->Success(); else result->Error("invalid_frame", "Expected a bounded PNG frame.");
      } else if (method == "drops") {
        if (rain_.Drops(*args)) result->Success(); else result->Error("invalid_drops", "Expected finite eight-float droplet rows.");
      } else result->NotImplemented();
    });
    delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate([this](HWND window, UINT message, WPARAM, LPARAM lparam) -> std::optional<LRESULT> {
      if (window == state_->root && message == kNotificationMessage) {
        if (lparam == NIN_BALLOONHIDE || lparam == NIN_BALLOONTIMEOUT || lparam == NIN_BALLOONUSERCLICK) state_->ClearNotification();
        return 0;
      }
      if (window == state_->root && (message == WM_SIZE || message == WM_DPICHANGED)) {
        state_->ApplyEditor(); state_->Shape(); rain_.Resize();
        if (state_->follow_resize) state_->CenterStartup();
      }
      if (window == state_->root &&
          (message == WM_DWMCOMPOSITIONCHANGED || message == WM_THEMECHANGED)) {
        state_->desktop_frame_cleared = false;
      }
      return std::nullopt;
    });
  }
  ~OrionNative() override {
    registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
    if (!state_->id.empty()) registered_windows.erase(state_->id);
    state_->alive = false;
    state_->ClearNotification();
    if (state_->modal_owner && IsWindow(state_->modal_owner)) {
      EnableWindow(state_->modal_owner, TRUE);
      if (GetForegroundWindow() == state_->root) SetForegroundWindow(state_->modal_owner);
    }
    state_->ClearEditor();
  }
 private:
  std::unique_ptr<Channel> MakeChannel(const char* name) {
    return std::make_unique<Channel>(registrar_->messenger(), name, &flutter::StandardMethodCodec::GetInstance());
  }
  void CreateEditor(const Map* args, std::unique_ptr<Result> unique_result) {
    const std::string url = String(Get(args, "url"));
    std::string origin;
    if (!LocalEditorUrl(url, &origin)) { unique_result->Error("invalid_url", "Expected the local Orion editor URL."); return; }
    state_->ClearEditor(); state_->origin = origin;
    const uint64_t generation = state_->generation;
    auto result = std::shared_ptr<Result>(std::move(unique_result));
    std::weak_ptr<State> weak = state_;
    const auto runtime = ExecutableDirectory() / L"data" / L"webview2";
    std::error_code runtime_error;
    const bool bundled = std::filesystem::exists(runtime / L"msedgewebview2.exe", runtime_error);
    const auto user_data = CacheDirectory();
    if (user_data.empty()) {
      result->Error("webview2_cache", "Could not prepare the WebView2 cache in Local AppData.");
      return;
    }
    HRESULT start = CreateCoreWebView2EnvironmentWithOptions(bundled ? runtime.c_str() : nullptr,
      user_data.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([weak, result, url, generation](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
        auto state = weak.lock();
        if (!state || !state->alive || generation != state->generation) { result->Error("disposed", "The editor was closed."); return S_OK; }
        if (FAILED(status) || !environment) { result->Error("webview2_unavailable", "Microsoft Edge WebView2 Runtime is missing. Use the complete Orion portable build."); return S_OK; }
        state->environment = environment;
        state->editor_host = CreateWindowExW(WS_EX_LAYERED, L"STATIC", L"Orion Monaco", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
          0, 0, 1, 1, state->flutter, nullptr, GetModuleHandleW(nullptr), nullptr);
        if (!state->editor_host) { result->Error("webview2_window", "Could not create the editor surface."); return S_OK; }
        HRESULT created = environment->CreateCoreWebView2Controller(state->editor_host,
          Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([weak, result, url, generation](HRESULT controller_status, ICoreWebView2Controller* controller) -> HRESULT {
            auto state = weak.lock();
            if (!state || !state->alive || generation != state->generation) { if (controller) controller->Close(); result->Error("disposed", "The editor was closed."); return S_OK; }
            if (FAILED(controller_status) || !controller) { result->Error("webview2_controller", "Could not start the WebView2 editor."); return S_OK; }
            state->controller = controller;
            controller->get_CoreWebView2(&state->webview);
            if (!state->webview) { result->Error("webview2_controller", "The editor renderer is unavailable."); return S_OK; }
            ComPtr<ICoreWebView2Controller2> alpha;
            if (SUCCEEDED(controller->QueryInterface(IID_PPV_ARGS(&alpha)))) alpha->put_DefaultBackgroundColor(COREWEBVIEW2_COLOR{0, 0, 0, 0});
            ComPtr<ICoreWebView2Settings> settings;
            state->webview->get_Settings(&settings);
            settings->put_AreDevToolsEnabled(FALSE); settings->put_AreDefaultContextMenusEnabled(FALSE);
            settings->put_IsStatusBarEnabled(FALSE); settings->put_IsZoomControlEnabled(FALSE);
            settings->put_IsBuiltInErrorPageEnabled(FALSE);
            ComPtr<ICoreWebView2Settings3> settings3;
            if (SUCCEEDED(settings.As(&settings3))) settings3->put_AreBrowserAcceleratorKeysEnabled(FALSE);
            EventRegistrationToken token{};
            state->webview->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>([weak, generation](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
              auto state = weak.lock(); if (!state || !state->alive || state->generation != generation) return S_OK;
              LPWSTR source = nullptr, message = nullptr; args->get_Source(&source);
              const bool allowed = Utf8(source).rfind(state->origin + "/editor/", 0) == 0; CoTaskMemFree(source);
              if (allowed && SUCCEEDED(args->TryGetWebMessageAsString(&message))) {
                std::string text = Utf8(message); CoTaskMemFree(message);
                if (text.size() <= 8 * 1024 * 1024) {
                  if (text.find("\"type\":\"ready\"") != std::string::npos) {
                    state->backdrop_geometry.clear(); state->ApplyEditor();
                  }
                  state->Emit(text);
                }
              }
              return S_OK;
            }).Get(), &token);
            state->webview->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>([weak, generation](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
              auto state = weak.lock(); LPWSTR uri = nullptr; args->get_Uri(&uri);
              bool allowed = state && state->alive && state->generation == generation && Utf8(uri) == state->origin + "/editor/index.html"; CoTaskMemFree(uri);
              args->put_Cancel(allowed ? FALSE : TRUE); return S_OK;
            }).Get(), &token);
            state->webview->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>([](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT { args->put_Handled(TRUE); return S_OK; }).Get(), &token);
            state->webview->add_PermissionRequested(Callback<ICoreWebView2PermissionRequestedEventHandler>([](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT { args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); return S_OK; }).Get(), &token);
            state->webview->add_ProcessFailed(Callback<ICoreWebView2ProcessFailedEventHandler>([weak, generation](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs*) -> HRESULT { auto state = weak.lock(); if (state && state->alive && state->generation == generation) state->Error("The editor renderer stopped. Reopen Orion to restart it."); return S_OK; }).Get(), &token);
            state->webview->AddWebResourceRequestedFilter(L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
            state->webview->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>([weak, generation](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
              auto state = weak.lock(); if (!state || !state->alive || state->generation != generation) return S_OK;
              ComPtr<ICoreWebView2WebResourceRequest> request; args->get_Request(&request); LPWSTR uri = nullptr; request->get_Uri(&uri);
              std::string address = Utf8(uri); CoTaskMemFree(uri);
              if (address.rfind(state->origin + "/editor/", 0) != 0 && address.rfind("data:", 0) != 0 && address.rfind("blob:" + state->origin + "/", 0) != 0) {
                ComPtr<ICoreWebView2WebResourceResponse> denied;
                state->environment->CreateWebResourceResponse(nullptr, 403, L"Blocked", L"Content-Type: text/plain", &denied);
                args->put_Response(denied.Get());
              }
              return S_OK;
            }).Get(), &token);
            state->ApplyEditor();
            HRESULT navigation = state->webview->Navigate(Wide(url).c_str());
            if (FAILED(navigation)) result->Error("webview2_navigation", "Could not load the offline editor.");
            else result->Success(Value(Map{{Value("pixelPreview"), Value(false)}, {Value("backend"), Value("WebView2")}}));
            return S_OK;
          }).Get());
        if (FAILED(created)) result->Error("webview2_controller", "Could not create the editor controller.");
        return S_OK;
      }).Get());
    if (FAILED(start)) result->Error("webview2_unavailable", "Could not load Microsoft Edge WebView2. Use the complete Orion portable build.");
  }
  void Editor(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    const auto& method = call.method_name();
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (method == "create") { CreateEditor(args, std::move(result)); return; }
    if (method == "dispose") { state_->ClearEditor(); SetFocus(state_->flutter); result->Success(); return; }
    if (!state_->webview) { result->Error("not_created", "The native editor has not been created."); return; }
    if (method == "capturePreview" || method == "capturePreviewPixels") {
      if (!state_->visible || state_->capture_pending) { result->Success(); return; }
      if (method == "capturePreviewPixels") { result->Success(); return; }
      ComPtr<IStream> stream; CreateStreamOnHGlobal(nullptr, TRUE, &stream);
      if (!stream) { result->Success(); return; }
      state_->capture_pending = true;
      auto response = std::shared_ptr<Result>(std::move(result));
      std::weak_ptr<State> weak = state_;
      const auto generation = state_->generation;
      HRESULT capture = state_->webview->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
        Callback<ICoreWebView2CapturePreviewCompletedHandler>([weak, response, stream, generation](HRESULT status) -> HRESULT {
          auto state = weak.lock();
          if (!state || !state->alive || state->generation != generation) { response->Success(); return S_OK; }
          state->capture_pending = false;
          if (FAILED(status)) { response->Success(); return S_OK; }
          STATSTG stat{}; stream->Stat(&stat, STATFLAG_NONAME);
          if (stat.cbSize.QuadPart > 32 * 1024 * 1024 || stat.cbSize.QuadPart == 0) { response->Success(); return S_OK; }
          LARGE_INTEGER start{}; stream->Seek(start, STREAM_SEEK_SET, nullptr);
          std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart)); ULONG read = 0;
          if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) || read != bytes.size()) response->Success();
          else response->Success(Value(bytes));
          return S_OK;
        }).Get());
      if (FAILED(capture)) { state_->capture_pending = false; response->Success(); }
      return;
    }
    if (method == "setBounds") {
      double x = Number(Get(args, "x"), NAN), y = Number(Get(args, "y"), NAN);
      double width = Number(Get(args, "width"), NAN), height = Number(Get(args, "height"), NAN);
      double scale = Number(Get(args, "uiScale"), 1);
      if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width) || !std::isfinite(height) || std::abs(x) > 65536 || std::abs(y) > 65536 || width < 0 || width > 16384 || height < 0 || height > 16384 || scale < .8 || scale > 1.25) { result->Error("invalid_bounds", "Expected finite editor bounds."); return; }
      state_->bounds = RECT{static_cast<LONG>(std::floor(x)), static_cast<LONG>(std::floor(y)), static_cast<LONG>(std::ceil(x + width)), static_cast<LONG>(std::ceil(y + height))};
      state_->ui_scale = scale; state_->visible = Boolean(Get(args, "visible")) && width > 0 && height > 0;
      const bool reduced = Boolean(Get(args, "reducedMotion"));
      state_->webview->ExecuteScript(reduced ? L"document.documentElement.classList.add('orion-reduced-motion');void 0;" : L"document.documentElement.classList.remove('orion-reduced-motion');void 0;", nullptr);
      state_->ApplyEditor(); result->Success();
    } else if (method == "setVisible") {
      state_->visible = Boolean(call.arguments()); state_->ApplyEditor();
      if (!state_->visible) SetFocus(state_->flutter);
      result->Success();
    } else if (method == "setOpacity") {
      const double opacity = Number(call.arguments(), NAN);
      if (!std::isfinite(opacity) || opacity < 0 || opacity > 1) { result->Error("invalid_opacity", "Expected opacity between zero and one."); return; }
      state_->opacity = opacity; state_->ApplyEditor(); result->Success();
    } else if (method == "setVisualMirror") {
      state_->mirror = Boolean(call.arguments()); state_->ApplyEditor(); result->Success();
    } else if (method == "setTheme") { result->Success();
    } else if (method == "focus") {
      if (state_->visible) state_->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
      result->Success();
    } else if (method == "send") {
      const auto command = String(call.arguments());
      if (command.size() > 8 * 1024 * 1024) { result->Error("command_size", "The editor command is too large."); return; }
      auto response = std::shared_ptr<Result>(std::move(result));
      const std::wstring script = Wide("window.orionReceive(JSON.parse(" + JsonString(command) + "));void 0;");
      HRESULT sent = state_->webview->ExecuteScript(script.c_str(), Callback<ICoreWebView2ExecuteScriptCompletedHandler>([response](HRESULT status, LPCWSTR) -> HRESULT {
        if (FAILED(status)) response->Error("javascript_failed", "The editor command failed."); else response->Success(); return S_OK;
      }).Get());
      if (FAILED(sent)) response->Error("javascript_failed", "Could not send the editor command.");
    } else result->NotImplemented();
  }
  void Window(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    const auto& method = call.method_name();
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (method == "prepareStartupPlacement") {
      POINT point{}; GetCursorPos(&point); state_->startup_monitor = MonitorFromPoint(point, MONITOR_DEFAULTTOPRIMARY);
      result->Success(Value("{\"ok\":true,\"mode\":\"win32\",\"reason\":\"prepared\"}"));
    } else if (method == "applyStartupPlacement") {
      state_->follow_resize = Boolean(Get(args, "followInitialResize")); state_->CenterStartup();
      if (!state_->follow_resize) state_->startup_monitor = nullptr;
      result->Success(Value("{\"ok\":true,\"mode\":\"win32\"}"));
    } else if (method == "completeStartupPlacement") {
      state_->follow_resize = false; state_->startup_monitor = nullptr;
      result->Success(Value("{\"ok\":true,\"reason\":\"completed\"}"));
    } else if (method == "registerWindow") {
      const std::string id = String(Get(args, "id"));
      if (id.empty()) { result->Error("invalid_arguments", "Expected a window id."); return; }
      state_->id = id; registered_windows[id] = state_->root;
      auto parent = registered_windows.find(String(Get(args, "parentId")));
      if (parent != registered_windows.end() && Boolean(Get(args, "owned"))) {
        SetWindowLongPtr(state_->root, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(parent->second));
        if (Boolean(Get(args, "modal"))) {
          state_->modal_owner = parent->second;
          EnableWindow(state_->modal_owner, FALSE);
        }
      }
      result->Success();
    } else if (method == "destroyCompanion") {
      // Dart has already flushed the child and released modal ownership.
      // Bypass window_manager's WM_CLOSE prevention after acknowledging it.
      result->Success(); PostMessageW(state_->root, WM_APP + 0x4A2, 0, 0);
    } else if (method == "setCornerRadius") {
      state_->corner_radius = std::clamp(Number(Get(args, "radius"), 16), 0.0, 64.0); state_->Shape(); result->Success();
    } else if (method == "configureDesktopGlass") {
      const bool enabled = Boolean(Get(args, "enabled"));
      state_->corner_radius = std::clamp(Number(Get(args, "cornerRadius"), 16), 0.0, 64.0); state_->Shape();
      // A DWM system backdrop sits behind Flutter's child HWND, so reporting
      // it active suppresses Orion's own refractive scene without showing any
      // desktop glass. Extending that backdrop into a layered window also
      // destabilizes theme changes on some Windows 11 drivers. Keep the native
      // frame clear and let the shared Flutter glass and opacity path render.
      if (!state_->desktop_frame_cleared) {
        // Polling the optional backend should not repeatedly rebuild DWM's
        // frame while opacity and the Flutter glass scene are changing.
        state_->desktop_frame_cleared = true;
        DWORD backdrop = 1;  // DWMSBT_NONE
        DwmSetWindowAttribute(state_->root, 38, &backdrop, sizeof(backdrop));
        MARGINS margins{0, 0, 0, 0};
        DwmExtendFrameIntoClientArea(state_->root, &margins);
      }
      result->Success(Value(enabled
          ? "{\"ok\":true,\"active\":false,\"mode\":\"flutter-glass\",\"reason\":\"windows-authored-glass\"}"
          : "{\"ok\":true,\"active\":false,\"mode\":\"none\"}"));
    } else result->NotImplemented();
  }
  void Notification(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    const auto& method = call.method_name();
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (method == "monitor") {
      MONITORINFO monitor{sizeof(monitor)}; GetMonitorInfoW(MonitorFromWindow(state_->root, MONITOR_DEFAULTTOPRIMARY), &monitor);
      double scale = state_->dpi();
      result->Success(Value(Map{{Value("x"), Value(monitor.rcWork.left / scale)}, {Value("y"), Value(monitor.rcWork.top / scale)},
        {Value("width"), Value((monitor.rcWork.right - monitor.rcWork.left) / scale)}, {Value("height"), Value((monitor.rcWork.bottom - monitor.rcWork.top) / scale)}, {Value("backend"), Value("windows")}, {Value("scale"), Value(scale)}}));
    } else if (method == "configure") {
      const double x = Number(Get(args, "x")), y = Number(Get(args, "y"));
      const double width = Number(Get(args, "width"), 396), height = Number(Get(args, "height"), 120);
      if (std::abs(x) > 131072 || std::abs(y) > 131072 || width < 200 || width > 800 || height < 80 || height > 400) { result->Error("invalid_arguments", "Invalid notification bounds."); return; }
      LONG_PTR style = GetWindowLongPtr(state_->root, GWL_EXSTYLE);
      SetWindowLongPtr(state_->root, GWL_EXSTYLE, (style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) & ~WS_EX_APPWINDOW);
      SetWindowLongPtr(state_->root, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
      SetWindowTextW(state_->root, L"Orion Bridge");
      const double scale = std::clamp(Number(Get(args, "scale"), state_->dpi()), .5, 8.0);
      // The supplied scale belongs to Orion's monitor, not the worker's
      // initial primary output. Commit once more after any WM_DPICHANGED.
      SetWindowPos(state_->root, HWND_TOPMOST, static_cast<int>(x * scale), static_cast<int>(y * scale), static_cast<int>(width * scale), static_cast<int>(height * scale), SWP_NOACTIVATE | SWP_FRAMECHANGED);
      SetWindowPos(state_->root, HWND_TOPMOST, static_cast<int>(x * scale), static_cast<int>(y * scale), static_cast<int>(width * scale), static_cast<int>(height * scale), SWP_NOACTIVATE);
      std::weak_ptr<State> weak = state_;
      state_->view_controller->engine()->SetNextFrameCallback([weak]() {
        auto state = weak.lock(); if (state && state->alive) ShowWindow(state->root, SW_SHOWNOACTIVATE);
      });
      result->Success();
    } else if (method == "notify") {
      // The themed worker is the ordinary path. If that process cannot start,
      // retain a real OS notification rather than silently losing the event.
      auto& toast = state_->fallback_notification;
      toast = NOTIFYICONDATAW{}; toast.cbSize = sizeof(toast); toast.hWnd = state_->root; toast.uID = 1;
      toast.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE | NIF_INFO;
      toast.uCallbackMessage = kNotificationMessage;
      toast.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
      toast.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
      CopyWide(toast.szTip, L"Orion Bridge"); CopyWide(toast.szInfoTitle, L"Orion Bridge");
      std::string subject = String(Get(args, "subject"));
      if (subject.empty()) subject = "Executor Connected!";
      CopyWide(toast.szInfo, Wide(subject + "\n" + String(Get(args, "username"))));
      if (Shell_NotifyIconW(state_->fallback_notification_added ? NIM_MODIFY : NIM_ADD, &toast)) {
        state_->fallback_notification_added = true; result->Success();
      } else result->Error("notification_unavailable", "Windows could not show the fallback notification.");
    } else result->NotImplemented();
  }
  flutter::PluginRegistrarWindows* registrar_;
  std::shared_ptr<State> state_;
  WindowsRain rain_;
  std::unique_ptr<Channel> window_channel_, notification_channel_, rain_channel_;
  int delegate_id_ = -1;
};
}  // namespace

void RegisterOrionNative(flutter::FlutterViewController* controller) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(controller->engine()->GetRegistrarForPlugin("OrionNative"));
  registrar->AddPlugin(std::make_unique<OrionNative>(registrar, controller));
}
