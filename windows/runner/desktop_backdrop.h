#ifndef RUNNER_DESKTOP_BACKDROP_H_
#define RUNNER_DESKTOP_BACKDROP_H_

#include <windows.h>
#include <winrt/Windows.UI.Composition.h>

#include <memory>
#include <string>

// A live, unfiltered DWM backdrop. Only the private helper window has its live
// preview disabled; Orion keeps its normal screenshot and sharing behavior.
// The caller supplies a COM apartment and a dispatcher queue on this thread.
class DesktopBackdrop {
 public:
  explicit DesktopBackdrop(HWND main_window);
  ~DesktopBackdrop() noexcept;

  bool Initialize(HWND material_window, std::string* error);
  void Resize(RECT screen_physical);
  void Refresh();
  winrt::Windows::UI::Composition::Compositor compositor() const;
  winrt::Windows::UI::Composition::Visual visual() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DESKTOP_BACKDROP_H_
