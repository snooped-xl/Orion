#ifndef RUNNER_WINDOWS_RAIN_H_
#define RUNNER_WINDOWS_RAIN_H_
#include <windows.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <string>
class WindowsRain {
 public:
  explicit WindowsRain(HWND owner);
  ~WindowsRain();
  bool Configure(const flutter::EncodableMap& args, std::string* error);
  bool Frame(const flutter::EncodableMap& args);
  bool Drops(const flutter::EncodableMap& args);
  void Resize();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
#endif
