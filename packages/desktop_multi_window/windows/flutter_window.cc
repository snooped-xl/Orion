#include "flutter_window.h"
#include "flutter_window_wrapper.h"

#include "flutter_windows.h"

#include "tchar.h"

#include <iostream>
#include <utility>

#include "multi_window_manager.h"
#include "multi_window_plugin_internal.h"

FlutterWindow::FlutterWindow(const std::string& id,
                             const WindowConfiguration config)
    : id_(id), window_argument_(config.arguments) {}

bool FlutterWindow::OnCreate() {
  // Called when the window is created
  RECT frame = GetClientArea();

  flutter::DartProject project(L"data");
  // Avoid Windows fullscreen freezes in recent Flutter engines when
  // window_manager changes styles from a platform-channel call.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
  std::vector<std::string> entrypoint_args = {"multi_window", id_,
                                              window_argument_};
  project.set_dart_entrypoint_arguments(entrypoint_args);
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);

  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
    return false;
  }

  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view_handle);

  return true;
}

void FlutterWindow::OnDestroy() {
  const bool had_controller = flutter_controller_ != nullptr;
  auto controller = std::move(flutter_controller_);
  controller.reset();
  if (had_controller && !destroying_object_) {
    MultiWindowManager::Instance()->RemoveManagedFlutterWindowLater(id_);
  }
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == kDestroyOrionCompanionMessage) {
    ::DestroyWindow(hwnd);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

FlutterWindow::~FlutterWindow() {
  // Detach the controller before member destruction: destroying the Flutter
  // child HWND synchronously re-enters this parent's window procedure.
  destroying_object_ = true;
  Destroy();
}
