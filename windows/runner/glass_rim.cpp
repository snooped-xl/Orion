#include <d2d1_1.h>
#include <d3d11.h>
#include <windows.ui.composition.interop.h>

#include "glass_rim.h"
#include "glass_optics.h"

#include <winrt/Windows.Graphics.DirectX.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace {
using namespace winrt;
using namespace Windows::Foundation::Numerics;
using namespace Windows::Graphics::DirectX;
using namespace Windows::UI::Composition;
}

struct GlassRim::Impl {
  explicit Impl(Compositor value) : compositor(value) {
    auto status = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
        d3d.put(), nullptr, nullptr);
    if (FAILED(status)) {
      status = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
          d3d.put(), nullptr, nullptr);
    }
    check_hresult(status);
    const auto dxgi = d3d.as<IDXGIDevice>();
    const D2D1_CREATION_PROPERTIES properties{
        D2D1_THREADING_MODE_SINGLE_THREADED, D2D1_DEBUG_LEVEL_NONE,
        D2D1_DEVICE_CONTEXT_OPTIONS_NONE};
    check_hresult(D2D1CreateDevice(dxgi.get(), &properties, d2d.put()));
    check_hresult(compositor.as<ABI::Windows::UI::Composition::ICompositorInterop>()->CreateGraphicsDevice(
        d2d.get(), reinterpret_cast<ABI::Windows::UI::Composition::
        ICompositionGraphicsDevice**>(put_abi(graphics))));
    sprite = compositor.CreateSpriteVisual();
  }
  Compositor compositor{nullptr};
  com_ptr<ID3D11Device> d3d;
  com_ptr<ID2D1Device> d2d;
  CompositionGraphicsDevice graphics{nullptr};
  CompositionDrawingSurface surface{nullptr};
  SpriteVisual sprite{nullptr};
  uint32_t width = 0, height = 0;
  float scale = 0, corner_radius = -1;

  void Resize(float physical_width, float physical_height, float dpi_scale,
              float radius) {
    const auto new_width = static_cast<uint32_t>(std::max(std::ceil(physical_width), 1.f));
    const auto new_height = static_cast<uint32_t>(std::max(std::ceil(physical_height), 1.f));
    dpi_scale = std::max(dpi_scale, .01f);
    const float2 logical_size{new_width / dpi_scale, new_height / dpi_scale};
    radius = std::clamp(radius, 0.f,
        std::min(logical_size.x, logical_size.y) * .5f);
    if (new_width == width && new_height == height && dpi_scale == scale &&
        radius == corner_radius) return;

    std::vector<uint32_t> pixels(static_cast<size_t>(new_width) * new_height, 0);
    const uint32_t band = static_cast<uint32_t>(std::ceil(4.f * dpi_scale));
    const uint32_t corner = static_cast<uint32_t>(std::ceil((radius + 4.f) * dpi_scale));
    const auto paint = [&](uint32_t x, uint32_t y) {
      const float2 point{(x + .5f) / dpi_scale, (y + .5f) / dpi_scale};
      const float distance = orion::glass::Distance(
          point - logical_size * .5f, logical_size * .5f, radius);
      if (distance < -4.f || distance > 1.f) return;
      const auto sample = orion::glass::Evaluate(point, logical_size, radius);
      const float light = std::clamp(sample.rim_light, 0.f, 1.f);
      // Source-over yields gain * (1-light) * backdrop + light, exactly the
      // shader's AO followed by its screen-blended white rim lighting.
      const float alpha = 1.f - sample.base_gain * (1.f - light);
      const auto byte = [](float value) {
        return static_cast<uint32_t>(std::lround(std::clamp(value, 0.f, 1.f) * 255.f));
      };
      const uint32_t color = byte(light);
      pixels[static_cast<size_t>(y) * new_width + x] =
          (byte(alpha) << 24) | color | (color << 8) | (color << 16);
    };
    for (uint32_t y = 0; y < new_height; ++y) {
      const uint32_t depth = std::min(y, new_height - 1 - y);
      const uint32_t strip = std::min(new_width,
          depth < band ? new_width : depth < corner ? corner : band);
      for (uint32_t x = 0; x < strip; ++x) paint(x, y);
      for (uint32_t x = std::max(strip, new_width - strip); x < new_width; ++x) paint(x, y);
    }

    auto next_surface = graphics.CreateDrawingSurface(
        {static_cast<float>(new_width), static_cast<float>(new_height)},
        DirectXPixelFormat::B8G8R8A8UIntNormalized,
        DirectXAlphaMode::Premultiplied);
    const auto interop = next_surface.as<ABI::Windows::UI::Composition::ICompositionDrawingSurfaceInterop>();
    com_ptr<ID2D1DeviceContext> context;
    POINT offset{};
    check_hresult(interop->BeginDraw(nullptr, __uuidof(ID2D1DeviceContext),
                                    context.put_void(), &offset));
    try {
      context->SetDpi(96.f, 96.f);
      context->Clear(D2D1_COLOR_F{0, 0, 0, 0});
      const D2D1_BITMAP_PROPERTIES1 properties = D2D1::BitmapProperties1(
          D2D1_BITMAP_OPTIONS_NONE,
          D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
      com_ptr<ID2D1Bitmap1> bitmap;
      check_hresult(context->CreateBitmap({new_width, new_height}, pixels.data(),
          new_width * sizeof(uint32_t), &properties, bitmap.put()));
      const D2D1_RECT_F destination{
          static_cast<float>(offset.x), static_cast<float>(offset.y),
          static_cast<float>(offset.x + new_width),
          static_cast<float>(offset.y + new_height)};
      context->DrawBitmap(bitmap.get(), destination, 1.f,
                          D2D1_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
    } catch (...) {
      interop->EndDraw();
      throw;
    }
    check_hresult(interop->EndDraw());
    auto brush = compositor.CreateSurfaceBrush(next_surface);
    brush.Stretch(CompositionStretch::None);
    sprite.Brush(brush);
    sprite.Size({static_cast<float>(new_width), static_cast<float>(new_height)});
    surface = next_surface;
    width = new_width;
    height = new_height;
    scale = dpi_scale;
    corner_radius = radius;
  }
};

GlassRim::GlassRim(Compositor compositor) : impl_(std::make_unique<Impl>(compositor)) {}
GlassRim::~GlassRim() = default;
SpriteVisual GlassRim::visual() const { return impl_->sprite; }
void GlassRim::Resize(float width, float height, float dpi_scale, float radius) {
  impl_->Resize(width, height, dpi_scale, radius);
}
