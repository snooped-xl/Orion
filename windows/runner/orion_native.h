#ifndef RUNNER_ORION_NATIVE_H_
#define RUNNER_ORION_NATIVE_H_
#include <flutter/flutter_view_controller.h>
// Attach to every engine, including desktop_multi_window companions.
void RegisterOrionNative(flutter::FlutterViewController* controller);
#endif
