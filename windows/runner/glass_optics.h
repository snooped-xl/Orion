#ifndef RUNNER_GLASS_OPTICS_H_
#define RUNNER_GLASS_OPTICS_H_

#include <winrt/Windows.Foundation.Numerics.h>

#include <algorithm>
#include <cmath>

// CPU evaluation of Orion's Linux compositor shader. Coordinates and optical
// dimensions are in the same pixel space; the caller applies its DPI scale.
// The GPU interpolates these sample positions without filtering the foreground.
namespace orion::glass {
using winrt::Windows::Foundation::Numerics::float2;
using winrt::Windows::Foundation::Numerics::float3;
using winrt::Windows::Foundation::Numerics::dot;
using winrt::Windows::Foundation::Numerics::length;
using winrt::Windows::Foundation::Numerics::normalize;

inline float SmoothStep(float low, float high, float value) {
  const float t = std::clamp((value - low) / (high - low), 0.f, 1.f);
  return t * t * (3.f - 2.f * t);
}

inline float Sign(float value) {
  return value > 0.f ? 1.f : value < 0.f ? -1.f : 0.f;
}

// sdCircleRoundRect from glass.frag. The extension explicitly disables corner
// smoothing so its shape follows the app window's circular rounded corners.
inline float Distance(float2 point, float2 half_size, float radius) {
  const float2 q{std::abs(point.x) - half_size.x + radius,
                 std::abs(point.y) - half_size.y + radius};
  return std::min(std::max(q.x, q.y), 0.f) +
      length(float2{std::max(q.x, 0.f), std::max(q.y, 0.f)}) - radius;
}

inline float2 DistanceDirection(float2 point, float2 half_size, float radius) {
  const float2 q{std::abs(point.x) - half_size.x + radius,
                 std::abs(point.y) - half_size.y + radius};
  // Mesh vertices can lie exactly on a straight/rounded tangent. Its positive
  // part is then zero; treating that as a corner produces a diagonal normal
  // along an entire row/column and draws a spurious inset rectangle.
  if (std::max(q.x, q.y) <= 0.f) {
    return q.x > q.y ? float2{Sign(point.x), 0.f}
                     : float2{0.f, Sign(point.y)};
  }
  const float denominator = std::max(std::max(q.x, q.y), 1.e-6f);
  // The circular superellipse has exponent 2, so its gradient is u^1.
  const float2 direction = normalize(float2{
      std::max(q.x, 0.f) / denominator,
      std::max(q.y, 0.f) / denominator});
  return direction * float2{Sign(point.x), Sign(point.y)};
}

inline float Height(float2 point, float2 half_size, float radius,
                    float band, float lens_scale) {
  const float distance = Distance(point, half_size, radius);
  // edge_smoothing defaults to .5; getHeight uses a minimum fade of 1 pixel.
  if (distance > 1.f) return 0.f;
  const float t = std::clamp(-distance / band, 0.f, 1.f);
  const float inverse_t = 1.f - t;
  // extension.js: max_z=80, profile_shape_n=2.
  return std::sqrt(std::max(1.f - inverse_t * inverse_t, 0.f)) *
      (80.f * lens_scale) * (1.f - SmoothStep(-1.f, 1.f, distance));
}

struct OpticalSample {
  float2 point;       // Backdrop sample in the caller's pixel space.
  float coverage;     // Linux's antialiased circular rounded-rectangle mask.
  float base_gain;    // Inner AO multiplier, before applying rim light.
  float rim_light;    // Screen blend: base + light - base * light.
};

inline OpticalSample Evaluate(float2 pixel, float2 size, float radius) {
  size = {std::max(size.x, 1.f), std::max(size.y, 1.f)};
  const float2 half_size = size * .5f;
  radius = std::clamp(radius, 0.f, std::min(half_size.x, half_size.y));
  const float2 point = pixel - half_size;
  const float distance = Distance(point, half_size, radius);
  constexpr float kBand = 52.f;
  const float band = std::max(std::min(kBand,
      std::min(half_size.x, half_size.y)), 1.f);
  const float lens_scale = band / kBand;
  const float2 direction = DistanceDirection(point, half_size, radius);
  const float step = std::clamp(std::min(size.x, size.y) / 560.f, .45f, 1.2f);
  // Differencing the actual rounded shape along its analytic normal preserves
  // the circular corner field, including the narrow seam at a corner's centre.
  const float h_out = Height(point + direction * step, half_size, radius,
                             band, lens_scale);
  const float h_in = Height(point - direction * step, half_size, radius,
                            band, lens_scale);
  const float2 gradient = direction * ((h_out - h_in) / (2.f * step));
  const float3 normal = normalize(float3{-gradient.x, -gradient.y, 1.f});

  // GLSL refract((0,0,-1), normal, 1/1.65), from air into glass.
  constexpr float kEta = 1.f / 1.65f;
  const float k = 1.f - kEta * kEta * (1.f - normal.z * normal.z);
  const float factor = kEta * normal.z - std::sqrt(std::max(k, 0.f));
  const float3 ray{factor * normal.x, factor * normal.y,
                   -kEta + factor * normal.z};
  float2 displacement{};
  if (distance <= 0.f && length(ray) >= 1.e-4f) {
    displacement = float2{ray.x, ray.y} *
        (43.125f / std::max(-ray.z, .15f));
    const float max_displacement = .30f * std::min(size.x, size.y);
    const float displacement_length = length(displacement);
    if (displacement_length > max_displacement) {
      displacement *= max_displacement / displacement_length;
    }
  }
  const float edge_t = std::clamp(1.f - std::max(-distance, 0.f) / band,
                                0.f, 1.f);
  displacement *= std::pow(edge_t, 1.1f) * lens_scale;
  constexpr float kEdgeLimit = 20.125f;
  displacement *= kEdgeLimit / std::sqrt(kEdgeLimit * kEdgeLimit +
                                        dot(displacement, displacement));

  // The shallow whole-sheet lens is independent of the bevel. Both components
  // vanish at the middle and at the window boundary, without an inner seam.
  const float2 q{std::clamp(point.x / std::max(half_size.x, 1.f), -1.f, 1.f),
                 std::clamp(point.y / std::max(half_size.y, 1.f), -1.f, 1.f)};
  const float envelope = std::max(1.f - q.x * q.x, 0.f) *
                         std::max(1.f - q.y * q.y, 0.f);
  displacement -= q * (envelope * 34.5f);
  displacement *= std::min(1.f, 96.f / std::max(length(displacement), 1.e-4f));

  // stabilizedUV from the Linux shader protects a backdrop without padding.
  const float2 uv = pixel / size;
  const float2 candidate = uv + displacement / size;
  const float edge_distance = std::min(std::min(candidate.x, candidate.y),
      std::min(1.f - candidate.x, 1.f - candidate.y));
  const float keep = SmoothStep(-.04f, .03f, edge_distance);
  const float2 clamped{std::clamp(candidate.x, .001f, .999f),
                       std::clamp(candidate.y, .001f, .999f)};
  const float2 sample = (uv + (clamped - uv) * keep) * size;

  // The compositor's default chromatic dispersion is zero. These are the
  // remaining authored edge terms from _applyOptics (specular/sheen/shadow=0).
  const float coverage = 1.f - SmoothStep(-.75f, .75f, distance);
  const float edge_band = 1.f - SmoothStep(0.f, 2.2f, std::abs(distance));
  const float fresnel = std::pow(std::max(1.f - normal.z, 0.f), 3.f);
  const float3 light = normalize(float3{-.7071067812f, .7071067812f, .38f});
  const float light_mask = std::pow(std::abs(dot(normal, light)), 2.2f);
  const float rim_shape = (.45f * std::pow(edge_band, .85f) + .55f * fresnel) *
                          edge_band;
  const float ao_mask = 1.f - SmoothStep(0.f, 1.f, -distance);
  return {sample, coverage, 1.f - ao_mask * .1f * (1.f - light_mask),
          rim_shape * light_mask * .72f + edge_band * .008f};
}

inline float2 GlassSample(float2 pixel, float2 size, float radius) {
  return Evaluate(pixel, size, radius).point;
}

}  // namespace orion::glass

#endif  // RUNNER_GLASS_OPTICS_H_
