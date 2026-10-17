#ifndef RUNNER_GLASS_RIM_H_
#define RUNNER_GLASS_RIM_H_

#include <winrt/Windows.UI.Composition.h>

#include <memory>

// Geometry-only Linux rim lighting and inner AO, uploaded once per resize.
// The surface contains no desktop or foreground pixels.
class GlassRim {
 public:
  explicit GlassRim(winrt::Windows::UI::Composition::Compositor compositor);
  ~GlassRim();
  winrt::Windows::UI::Composition::SpriteVisual visual() const;
  void Resize(float physical_width, float physical_height, float dpi_scale,
              float radius);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_GLASS_RIM_H_
