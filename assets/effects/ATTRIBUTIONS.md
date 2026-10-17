# RainEffect adaptation

Orion's glass-rain physics and GPU refraction are adapted from **Rain & Water
Effect Experiments**, created by **Lucas Bebber / Codrops (2015)**.

- Original project: https://github.com/codrops/RainEffect
- Pinned source revision: `5270be663903883ae585858216b656120d8d4cd5`
- Physics: https://github.com/codrops/RainEffect/blob/5270be663903883ae585858216b656120d8d4cd5/src/raindrops.js
- Refraction shader: https://github.com/codrops/RainEffect/blob/5270be663903883ae585858216b656120d8d4cd5/src/shaders/water.frag
- Author's article: https://tympanus.net/codrops/2015/11/04/rain-water-effect-experiments/
- Author's license: https://tympanus.net/codrops/licensing/

The repository explicitly permits integrating or building upon the work in
personal or commercial projects and links to Codrops' license page. That page
licenses downloadable code demos under MIT. The complete MIT notice is bundled
as `Codrops-RainEffect-MIT.txt`. Orion integrates adapted physics and optics into
its application; it does not redistribute the original demo as a standalone item.

Adaptation changes (2026-10-16): ported canvas-independent physics to Dart;
introduced a fixed simulation clock, bounded drop/bead counts and no native/mobile
plugin dependencies; corrected frame-dependent movement and the undefined maximum
radius in collision handling; represented spray and trail daughters as bounded
beads; tuned rain speed and density for readable application content; supplied
logical-pixel lens packets to a native GPU compositor that also includes Monaco.
Original demo images, sounds, and fonts are not included.

No code from `flutter_shader_kit`'s Heartfelt-derived shader or the `rainy_day`
RainyDay.js port is included in this implementation.

## Liquid Glass theme

The separate Liquid Glass theme uses **Liquid Glass Easy**, by Ahmed Gamil:
https://github.com/AhmeedGamil/liquid_glass_easy

Pinned version: 5.0.0, revision `8e253fee087ba1d3c0928bea4c877427a36e4889`.
The MIT license is reproduced in `Liquid-Glass-Easy-MIT.txt`. Source, shaders,
the upstream license and Orion's lifecycle/intrinsic-layout integration notes
are included in `packages/liquid_glass_easy/` in the Flutter source package.
Orion uses the alpha-preserving Skia refraction path; it does not bundle Apple's
native materials or claim desktop-backdrop access on unsupported compositors.
