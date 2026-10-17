#ifndef ORION_WINDOWS_GLASS_H_
#define ORION_WINDOWS_GLASS_H_

#include <windows.h>
#include <memory>
#include <string>

// Live desktop pixels stay inside DWM. A timer refreshes the GPU sampling
// surfaces without screen capture, display-affinity changes, or CPU frame copies.
class WindowsGlass {
 public:
  explicit WindowsGlass(HWND window);
  ~WindowsGlass();
  bool Configure(bool enabled, double radius, std::string* error);
  void Resize();
  bool active() const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
