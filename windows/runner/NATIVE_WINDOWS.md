# Windows native host

Every Flutter engine (main window and all independently opened settings, script
hubs and Theme Studio windows) registers the generated plugins and the same
Orion native channels. Dart UI, bridge HTTP transport, Luau completion data and
Monaco models are shared with Linux; no GTK, WebKitGTK, X11, GNOME or Linux
compositor library is linked into the Windows build.

## Editor

`orion_native.cpp` hosts the bundled offline Monaco editor in WebView2. It
implements `orion/monaco` creation, disposal, position/GUI scale, real focus,
script messaging, opacity, PNG preview/freeze and visual mirror RPCs. Windows
negotiates PNG preview rather than Linux's raw pixel optimization. Only the
validated editor loopback origin, its assets, data images and its own blob
workers are allowed. Permissions, new browser windows, developer tools and
ordinary browser accelerators are disabled. Session generation guards keep
old controller events from updating a replacement editor.

The build pins Microsoft.Web.WebView2 SDK 1.0.3537.50 and verifies its SHA-256.
Its loader DLL is installed next to `orion.exe`. Portable packaging places an
entire fixed-version x64 WebView2 runtime in `data/webview2`; the host prefers
that runtime and can use installed Evergreen when developing without it. Its
writable browser cache is in `%LOCALAPPDATA%\Orion\WebView2`, outside the
extracted application/runtime and the Documents workspace.

## Window and effects

`orion/window` centers the final window size on the monitor containing the
pointer at launch, follows authored initial loader resizes, and stops tracking
before normal user moves. It accounts for DPI changes when crossing monitors.
Win32 ownership and modal owner-input disabling apply to companion windows.
Deferred destruction bypasses the close-confirmation interception only after
Dart has flushed documents. Rounded regions also clip native input corners.

`windows_alpha.cpp` adapts Flutter's bundled ANGLE presentation to a
premultiplied-alpha DirectComposition swapchain. This process-local DXGI
compatibility layer applies to Flutter child windows, allowing their per-pixel
alpha and smooth corners to reach DWM while keeping the foreground sharp. It
falls back to ordinary Flutter presentation if composition setup fails.

`desktop_backdrop.cpp` obtains live desktop shared visuals through private DWM
and interop-compositor interfaces. `windows_glass.cpp` samples that visual with
`CompositionVisualSurface`, applies mild frost, and refracts it through a GPU
`SceneMesh`. `glass_optics.h` ports the Linux shader's rounded lens, whole-sheet
distortion, and edge-lighting profile. CPU work prepares geometry and static
edge material when size or DPI changes; live desktop frames stay on the GPU.
The Linux compositor implementation remains separate.

The glass material attaches to Orion's main HWND beneath the alpha-composited
Flutter child, so window movement, stacking, minimization, and close apply to
the entire material and foreground together. The shared-visual source excludes
Orion to avoid visual feedback. Only a cloaked helper has live preview exclusion
enabled. The actual Orion window retains `WDA_NONE`, so screenshots, recordings,
and screen sharing can include the application.

Private DWM interfaces can vary between Windows builds. The native desktop
glass path requires Windows 11 and falls back when its shared-visual APIs are
unavailable. Older Windows versions retain the authored Flutter glass and
window-opacity fallback.

`windows_rain.cpp` translates the authored Linux OpenGL water shader to a
Direct3D 11 / DirectComposition alpha overlay. Dart drives the same droplet
simulation; only wet pixels sample bounded Flutter and Monaco PNG textures.
Dry content remains live. The layer is input transparent, hardware rendering
falls back to WARP, and minimized windows do not render rain. Whole-window
opacity is applied even when rain is disabled. At opacity 1 the ordinary DWM
composition path is restored instead of retaining an unnecessary layered
window; click-through window flags remain respected.

`orion/bridge_notification` places the themed Flutter worker in the top-right
work area of Orion's monitor. The worker uses the target monitor's scale,
appears only after its first Flutter frame, stays above other windows and never
activates/focuses itself or adds a taskbar button. If the themed worker cannot
start, the native host falls back to a quiet Windows shell notification and
removes its temporary tray icon after dismissal.

## Validation

The GitHub Windows job compiles with MSVC and runs `tool/desktop_smoke.dart`
against the actual runner, covering Monaco, bridge clients, themes, companion
windows, and production close. It rebuilds the normal app before packaging.

`windows/tests/desktop_glass_test.cpp` provides a controlled checkerboard
underlay. Its Flutter-app mode compares normal and inverted phases to check
live desktop response, filtered transitions, and lens displacement. Two further
captures check that a stationary desktop remains stable. The helper preserves
images for visual review and checks screenshot affinity and glass hide/restore
on minimize.
`tool/glass_visual_smoke.dart` exercises both glass presets in an isolated
workspace. These visual checks must establish actual desktop glass; a native
backend reporting active is insufficient.

`scripts/test-windows-package.ps1` launches the final portable executable with
opaque, glass, and rain themes, measures visible close latency, and checks clean
process exit. The Windows effects remain independent of
`linux/runner/rain_effect.cc` and the GNOME glass extension.
