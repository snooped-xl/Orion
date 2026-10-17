# Liquid Glass Easy

Upstream: https://github.com/AhmeedGamil/liquid_glass_easy
Pinned commit: 8e253fee087ba1d3c0928bea4c877427a36e4889
Upstream version: 5.0.0
License: MIT; copyright (c) 2025 Ahmed Gamil. See LICENSE.

Only the package runtime source, shaders, manifest and license are vendored.
Examples, screenshots, generated builds, and upstream development tooling are excluded.

Orion uses the explicit Skia capture path, preserving its existing Linux GPU renderer.
A shared static capture feeds real refractive lens shaders; ImageFilter.shader and
Impeller are not required.

Local patches:
- LiquidGlassView serializes async captures, cancels stale captures on disposal,
  and retires replaced full-frame and per-lens-region image handles after a
  frame instead of retaining them. Current and retired image handles are
  explicitly disposed on teardown, including captures completing after unmount.
- Async shader loading no longer creates per-view shader instances after the
  view has been unmounted. Upstream shader-instance finalizer ownership remains
  unchanged because retained render layers may still reference those instances.
- The additive `LiquidGlassView.shrinkWrap` option sizes layout-driven scenes
  from their foreground child, fills the capture backdrop to that size, and
  skips the unused positioned-lens LayoutBuilder. This supports natural-size
  dialogs and notifications, including intrinsic layout.
- Capture invalidation after an authored background/size change is requested
  explicitly by OrionGlassScene; no perpetual capture loop is enabled. Equivalent
  immutable Orion backdrops do not invalidate captures on foreground updates.
- Explicit static capture requested after paint skips a redundant endOfFrame
  wait, so an idle window refreshes immediately without unrelated later input.
- OrionGlassBackdrop accepts authored gradient colors, stops, directions and
  transforms, or an authored solid background. The optical substrate is opaque;
  desktop transparency is applied once through native window opacity.
  Authored gradient edits participate in capture invalidation.
- Orion's wrapper preserves foreground state with stable keyed subtrees across
  disabled/loading/ready transitions, loads shaders only while enabled, and
  applies material opacity only to the optical layer, leaving foreground
  text and controls unchanged by the shader. Full-strength optical sheets use
  subtle pointer-responsive highlights and refraction without recapturing the
  scene. An inherited material scope keeps nested controls from adding duplicate
  glass sheets, while optics-only opacity transitions preserve foreground state.
- Orion clips the upstream Skia lens to a narrow curved edge band. The center
  stays unchanged with no blanket zoom, blur or artificial lighting blooms;
  directional specular light and actual sample displacement remain at the bevel.
  Pixel regressions verify unchanged interiors and genuinely refracted edges.

The upstream component API is preserved; `shrinkWrap` defaults to false.
