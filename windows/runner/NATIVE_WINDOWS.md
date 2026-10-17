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

Windows uses Orion's authored Flutter glass materials and window opacity. The
DWM transient backdrop is not used because it sits behind Flutter's child
window while suppressing the visible glass scene. The GNOME edge-lens extension
is specific to Linux. Desktop capture exclusion is deliberately not used, so
ordinary screenshots and recordings continue working.

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

The GitHub Windows job compiles with MSVC and runs native integration tests
against the actual runner. Linux-hosted development also syntax-checks the
new C++ sources against Windows x64 headers and the pinned WebView2 SDK; both
HLSL entry points have been compiled to shader-model 5 DXBC. The Direct3D rain
implementation must remain separate from `linux/runner/rain_effect.cc` so
Linux release behavior and dependencies are unchanged.
