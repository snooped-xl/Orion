# Orion Desktop Glass for GNOME

This optional compositor companion supplies **live behind-window refraction** on GNOME Wayland. Flutter cannot sample other applications' Wayland buffers. The companion keeps background pixels in GNOME's GPU pipeline: it reads only the requested window's background rectangle immediately before that surface paints, refracts it, and draws Orion's untouched surface above it. It is not a wallpaper approximation and exports no images.

The base and editor backgrounds must be partly transparent, and native whole-window opacity should be 1, so text remains opaque. An opaque editor pane intentionally hides the desktop refraction in that pane.

Install the bundled extension with `./install-desktop-glass.py`. Add `--enable` to enable **only** `orion-glass@orion.local`; use `--disable` to turn it off. Other extensions and their settings are untouched. A fresh install normally requires logging out and back in on GNOME Wayland. If the session already permits Shell Eval, the helper can load this one extension immediately; it never enables unsafe mode. An existing different extension revision is preserved and reported rather than hot-reloaded.

D-Bus session API: name `org.orion.Glass`, path `/org/orion/Glass`, interface `org.orion.Glass1`.

- `GetCapabilities() → s`: JSON capability data, including API version, GNOME version, `mode: compositor-backdrop`, `exportsPixels: false`, and active/configured window counts.
- `Configure(u pid, s exactWindowTitle, b enabled, d cornerRadius) → s`: JSON `{ok, active, windowCount, reason}`. Radius is 0–128. The requesting bus connection's Unix PID must equal `pid`; matching is exact PID and title. Sixteen rules maximum. `waiting-window` means the configured window has not mapped yet.
- `GetStatus(u pid, s exactWindowTitle) → s`: current JSON status, with the same PID authorization.

The client must keep its bus connection alive. When it disconnects, all its rules and effects are removed. Disabling/unloading the extension removes actors, GPU references, signals and name watchers. No per-window opacity or global appearance settings are changed by the companion. With no configured windows, no backdrop copying occurs.

The runtime is adapted from the MIT [Liquid Glass for GNOME Shell](https://github.com/ryohsuke1231/liquid-glass/tree/05d7697eb94ce1ddf2207431d196d71e99dd5b4c). Source and license details are in `orion-glass@orion.local/ORION_VENDOR.md`. GNOME 46 Wayland was tested in a separate private headless session with generated client windows, live backdrop changes, move, minimize/restore, rejection of another caller PID, and cleanup after caller disconnect. Upstream supports GNOME 46–51; later versions have not been tested locally.
