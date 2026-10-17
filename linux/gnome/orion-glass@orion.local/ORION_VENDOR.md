# Orion Desktop Glass

Compositor engine adapted from [Liquid Glass for GNOME Shell](https://github.com/ryohsuke1231/liquid-glass), commit `05d7697eb94ce1ddf2207431d196d71e99dd5b4c`.
MIT, copyright (c) 2026 Ryosuke Watanabe; see LICENSE.upstream.

Only the 15 runtime modules needed by `BackdropGlass` and its three shaders are bundled. The diagnostics registry is replaced by two no-op registration functions, omitting the upstream global diagnostics, monitor, menus, desktop widgets, preferences, and application manager. The stage-copy, redraw-relay and GNOME compatibility code otherwise remain upstream code. Orion adapts `shaders/glass.frag` with a broader 52px bevel, smoothly bounded edge displacement and a shallow convex whole-sheet refraction field. The latter is applied in both the full shader path and its interior fast path. These sample only the compositor backdrop; the app foreground remains untouched. The profile uses displacement scale 43.125 and body strength 34.5 (at most 13.28px per body component), with a smooth 20.125px bevel cap. The field and its cap scale together, adding another 15% refraction while preserving the lens shape. A restrained two-level Dual Kawase blur retains nominal radius 3, with down/up kernel offsets 0.4725/0.70875, 5% wider than the previous 0.45/0.675 profile. This slightly increases frost while avoiding the abrupt pass-count change below radius 3. The wrapper guards the expected blur method/schedule and assigns fixed offsets idempotently; the existing blur-cache key includes both offsets. No white tint or broad sheen is added. This profile does not set application or window opacity.

`extension.js` and `policy.js` are Orion's narrow integration. They add a caller-PID-authorized, per-window D-Bus control API and lifecycle cleanup. They never change surface opacity, wallpaper, other extension settings, or global GNOME appearance. No image or texture is exported from the compositor. The only image read is a GPU blit of the requested window's background rectangle immediately before that window surface paints; off-screen/overview paint reuses the last safe backdrop. Redraw relays keep live windows behind it current without a perpetual capture timer.

Tested in an isolated GNOME Shell 46 Wayland session against two generated Wayland client windows, including changing background contents and moving the glass window. Other upstream-supported GNOME versions are declared but have not been locally tested.

The optional `SetAlwaysOnTop(pid, exactTitle, enabled)` control is independent of the optical material. The caller’s bus PID must match the requested process. It uses Mutter’s `make_above`/`unmake_above`, reports actual `is_above` state, and keeps separate bounded rules, method-prefixed authorization epochs and lifecycle state. Releasing the request, caller disconnect, title changes and extension shutdown restore each live window’s prior above state. Topmost alone creates no backdrop or optical actor. GTK/X11 uses the ordinary keep-above hint; GTK3’s native Wayland implementation does not implement that hint.

Flatpak uses a PID namespace, so its `getpid()` does not identify the host-side
Mutter window. The native client asks the session bus for the kernel PID belonging
to its own unique connection name, caches that identity only for that connection's
lifetime, and uses it for configuration, startup placement, topmost and teardown.
Failed/closed lookups never fall back to an unauthenticated PID. The Flatpak must
grant `--socket=session-bus`: the filtered proxy supplies its own credentials,
which cannot authorize the application window under this exact-process policy.
The helper's authorization remains unchanged: requested PID equals the caller's
bus credentials, and PID plus exact title equals the target MetaWindow. No
process scanning, broad app-ID rules or host-command spawning is used.

`python3 tool/test_session_bus_identity.py` checks a real private session bus from
ordinary and isolated PID-namespace clients, including cached/reconnected/closed
connections and rejected forged PIDs. This test requires unprivileged user/PID
namespaces, GTK development headers and Xvfb (`xvfb-run`), and never connects to
the desktop's session bus. On X11 the native
client also sets only its own `_NET_WM_PID` property to that authenticated host
PID, both before and after GTK realization; the test verifies that property in
an isolated Xvfb server. This keeps namespace-local notification workers and
ordinary X11 windows compatible with exact compositor PID matching.
