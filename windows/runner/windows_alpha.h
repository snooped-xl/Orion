#ifndef RUNNER_WINDOWS_ALPHA_H_
#define RUNNER_WINDOWS_ALPHA_H_

#include <windows.h>

// Enable before creating Flutter engines. Flutter's bundled ANGLE otherwise
// presents an HWND swapchain that discards the scene's per-pixel alpha.
bool OrionEnableAlphaComposition();
bool OrionHasAlphaComposition(HWND window);
// Call after destroying every Flutter controller and its child HWND.
void OrionDisableAlphaComposition();

#endif  // RUNNER_WINDOWS_ALPHA_H_
