#include "windows_glass.h"
#include "glass_optics.h"
#include "desktop_backdrop.h"
#include "glass_rim.h"

#include <DispatcherQueue.h>
#include <d2d1effects.h>
#include <dwmapi.h>
#include <windows.graphics.effects.interop.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.Effects.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <winrt/Windows.UI.Composition.Scenes.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <exception>
#include <vector>
#include <unordered_map>

namespace {
using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Foundation::Numerics;
using namespace Windows::Graphics::DirectX;
using namespace Windows::Graphics::Effects;
using namespace Windows::UI::Composition;
using namespace Windows::UI::Composition::Scenes;
namespace effects_abi = ABI::Windows::Graphics::Effects;

struct Frost : implements<Frost, IGraphicsEffect,
    IGraphicsEffectSource, effects_abi::IGraphicsEffectD2D1Interop> {
  IGraphicsEffectSource source_=CompositionEffectSourceParameter(L"Desktop");
  hstring Name() const { return L"LinuxFrost"; }
  void Name(const hstring&) {}
  HRESULT __stdcall GetEffectId(GUID* value) noexcept override {
    *value=CLSID_D2D1GaussianBlur;return S_OK;
  }
  HRESULT __stdcall GetNamedPropertyMapping(LPCWSTR,UINT*,
      effects_abi::GRAPHICS_EFFECT_PROPERTY_MAPPING*) noexcept override { return E_INVALIDARG; }
  HRESULT __stdcall GetPropertyCount(UINT* count) noexcept override { *count=3;return S_OK; }
  HRESULT __stdcall GetProperty(UINT index,ABI::Windows::Foundation::IPropertyValue** value) noexcept override {
    try {
      IInspectable property{nullptr};
      if (index==0) property=PropertyValue::CreateSingle(2.25f);
      else if(index<3) property=PropertyValue::CreateUInt32(1);
      else return E_INVALIDARG;
      *value=static_cast<ABI::Windows::Foundation::IPropertyValue*>(detach_abi(property));return S_OK;
    } catch (...) {return to_hresult();}
  }
  HRESULT __stdcall GetSource(UINT index,effects_abi::IGraphicsEffectSource** value) noexcept override {
    if(index)return E_INVALIDARG;
    try {
      auto source=source_;
      *value=static_cast<effects_abi::IGraphicsEffectSource*>(detach_abi(source));return S_OK;
    } catch (...) {return to_hresult();}
  }
  HRESULT __stdcall GetSourceCount(UINT* count) noexcept override { *count=1;return S_OK; }
};

// SceneVisual's emissive material consumes linear RGB and writes sRGB. Decode
// the backdrop before handing it to the mesh; otherwise the glass is washed out.
struct LinearBackdrop : implements<LinearBackdrop, IGraphicsEffect,
    IGraphicsEffectSource, effects_abi::IGraphicsEffectD2D1Interop> {
  LinearBackdrop() : source_(make<Frost>().as<IGraphicsEffectSource>()) {}
  IGraphicsEffectSource source_;
  hstring Name() const { return L"LinearBackdrop"; }
  void Name(const hstring&) {}
  HRESULT __stdcall GetEffectId(GUID* value) noexcept override {
    *value = CLSID_D2D1GammaTransfer; return S_OK;
  }
  HRESULT __stdcall GetNamedPropertyMapping(LPCWSTR, UINT*,
      effects_abi::GRAPHICS_EFFECT_PROPERTY_MAPPING*) noexcept override {
    return E_INVALIDARG;
  }
  HRESULT __stdcall GetPropertyCount(UINT* count) noexcept override {
    *count = 17; return S_OK;
  }
  HRESULT __stdcall GetProperty(UINT index,
      ABI::Windows::Foundation::IPropertyValue** value) noexcept override {
    try {
      if (index >= 17) return E_INVALIDARG;
      IInspectable property{nullptr};
      if (index == 16 || index % 4 == 3) {
        property = PropertyValue::CreateBoolean(index == 15);
      } else {
        const float number = index % 4 == 0 ? 1.f :
            index % 4 == 1 ? 2.2f : 0.f;
        property = PropertyValue::CreateSingle(number);
      }
      *value = static_cast<ABI::Windows::Foundation::IPropertyValue*>(detach_abi(property));
      return S_OK;
    } catch (...) { return to_hresult(); }
  }
  HRESULT __stdcall GetSource(UINT index,
      effects_abi::IGraphicsEffectSource** value) noexcept override {
    if (index) return E_INVALIDARG;
    try {
      auto source=source_;
      *value = static_cast<effects_abi::IGraphicsEffectSource*>(detach_abi(source));
      return S_OK;
    } catch (...) { return to_hresult(); }
  }
  HRESULT __stdcall GetSourceCount(UINT* count) noexcept override {
    *count = 1; return S_OK;
  }
};

struct __declspec(uuid("5b0d3235-4dba-4d44-865e-8f1d0e4fd04d")) BufferBytes : ::IUnknown {
  virtual HRESULT __stdcall GetBuffer(BYTE** data, UINT* capacity) = 0;
};
template <class T> MemoryBuffer Buffer(const std::vector<T>& data) {
  const size_t byte_count=data.size()*sizeof(T);
  if (byte_count>MAXUINT) throw hresult_error(E_OUTOFMEMORY);
  MemoryBuffer buffer(static_cast<UINT>(byte_count));
  auto reference = buffer.CreateReference();
  BYTE* bytes = nullptr; UINT capacity = 0;
  check_hresult(reference.as<BufferBytes>()->GetBuffer(&bytes, &capacity));
  if (capacity<byte_count) throw hresult_error(E_BOUNDS);
  std::memcpy(bytes, data.data(), byte_count);
  return buffer;
}

// Dense in the curved bevel, coarser in the smooth interior. Shared vertices
// avoid cracks, overlapping tile edges and seams at the bevel/body boundary.
std::vector<float> Axis(float size) {
  std::vector<float> values{0};
  for (float p = 0; p < size;) {
    const float depth = std::min(p, size - p);
    p = std::min(size, p + (depth < 56 || size-p < 80 ? 1.f : 12.f));
    values.push_back(p);
  }
  return values;
}

Windows::System::DispatcherQueueController EnsureQueue() {
  if (Windows::System::DispatcherQueue::GetForCurrentThread()) return nullptr;
  Windows::System::DispatcherQueueController controller{nullptr};
  DispatcherQueueOptions options{sizeof(options), DQTYPE_THREAD_CURRENT, DQTAT_COM_STA};
  check_hresult(CreateDispatcherQueueController(options,
      reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(controller))));
  return controller;
}
}  // namespace

struct WindowsGlass::Impl {
  explicit Impl(HWND value) : window(value) {}
  HWND window;
  bool enabled = false;
  bool initialized = false;
  bool frame_transparent = false;
  ULONGLONG next_desktop_update = 0;
  RECT desktop_bounds{};
  UINT_PTR sync_timer = 0;
  static inline UINT_PTR next_timer_id = 0x4A4000;
  static inline std::unordered_map<UINT_PTR, Impl*> timers;
  static void CALLBACK Sync(HWND window, UINT, UINT_PTR id, DWORD) noexcept {
    const auto found = timers.find(id);
    if (found == timers.end() || found->second->window != window) return;
    auto& glass = *found->second;
    if (glass.enabled) try { glass.Resize(); } catch (...) { glass.ResetGraph(); }
  }
  float radius = 24;
  float width = 0, height = 0, scale = 0, applied_radius = -1;
  Windows::System::DispatcherQueueController queue{nullptr};
  Compositor compositor{nullptr};
  Desktop::DesktopWindowTarget target{nullptr};
  LayerVisual root{nullptr};
  SpriteVisual source{nullptr};
  CompositionVisualSurface surface{nullptr};
  SceneVisual scene{nullptr};
  SceneMesh mesh{nullptr};
  std::unique_ptr<DesktopBackdrop> desktop;
  CompositionVisualSurface desktop_surface{nullptr};
  std::unique_ptr<GlassRim> rim;

  void Initialize() {
    if (initialized) return;
    if (!IsWindow(window)) throw hresult_error(HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE));
    if (!queue) queue = EnsureQueue();
    // The alpha-preserving Flutter child lets the material live in the same
    // top-level window, beneath its sharp foreground.
    desktop=std::make_unique<DesktopBackdrop>(window);
    std::string reason;
    if (!desktop->Initialize(window,&reason)) {
      desktop.reset();
      throw hresult_error(E_FAIL,to_hstring(reason));
    }
    compositor=desktop->compositor();
    check_hresult(compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>()->
        CreateDesktopWindowTarget(window, FALSE,
          reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(put_abi(target))));
    root = compositor.CreateLayerVisual();
    source = compositor.CreateSpriteVisual();
    auto effect = compositor.CreateEffectFactory(make<LinearBackdrop>()).CreateBrush();
    desktop_surface=compositor.CreateVisualSurface();
    desktop_surface.SourceVisual(desktop->visual());
    effect.SetSourceParameter(L"Desktop",compositor.CreateSurfaceBrush(desktop_surface));
    // Keep both sampling visuals detached. Only the lens is visible; a
    // second unrefracted desktop layer would compete with the sampled one.
    source.Brush(effect);
    surface = compositor.CreateVisualSurface(); surface.SourceVisual(source);
    auto input = SceneSurfaceMaterialInput::Create(compositor);
    input.Surface(surface); input.BitmapInterpolationMode(CompositionBitmapInterpolationMode::Linear);
    input.WrappingUMode(SceneWrappingMode::ClampToEdge); input.WrappingVMode(SceneWrappingMode::ClampToEdge);
    auto material = SceneMetallicRoughnessMaterial::Create(compositor);
    material.BaseColorFactor({0, 0, 0, 1}); material.MetallicFactor(0);
    material.EmissiveFactor({1, 1, 1}); material.EmissiveInput(input); material.IsDoubleSided(true);
    mesh = SceneMesh::Create(compositor); mesh.PrimitiveTopology(DirectXPrimitiveTopology::TriangleList);
    auto renderer = SceneMeshRendererComponent::Create(compositor);
    renderer.Mesh(mesh); renderer.Material(material);
    renderer.UVMappings().Insert(L"EmissiveInput", SceneAttributeSemantic::TexCoord0);
    auto node = SceneNode::Create(compositor); node.Components().Append(renderer);
    scene = SceneVisual::Create(compositor); scene.Root(node); scene.Scale({1, -1, 1});
    root.Children().InsertAtTop(scene);
    try {
      rim=std::make_unique<GlassRim>(compositor);
      root.Children().InsertAtTop(rim->visual());
    } catch (const hresult_error&) { rim.reset(); }
    initialized = true;
  }
  void Resize() {
    if (!enabled || !root) return;
    if (!IsWindowVisible(window) || IsIconic(window)) {
      return;
    }
    RECT client{};
    POINT origin{};
    if (!GetClientRect(window, &client) || !ClientToScreen(window,&origin)) throw_last_error();
    if (client.right<1 || client.bottom<1) return;
    if (desktop) {
      const RECT bounds{origin.x,origin.y,origin.x+client.right,origin.y+client.bottom};
      const auto now=GetTickCount64();
      if (!EqualRect(&bounds,&desktop_bounds) || now>=next_desktop_update) {
        desktop->Resize(bounds);desktop_bounds=bounds;next_desktop_update=now+100;
      }
      desktop->Refresh();
      desktop_surface.SourceSize({static_cast<float>(client.right),static_cast<float>(client.bottom)});
    }
    const float w = static_cast<float>(client.right), h = static_cast<float>(client.bottom);
    const UINT dpi_value=GetDpiForWindow(window);
    if (!dpi_value) throw hresult_error(HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE));
    const float dpi = dpi_value / 96.f;
    const float r = IsZoomed(window) ? 0 : radius;
    if (w < 1 || h < 1 || (width == w && height == h && scale == dpi && applied_radius == r)) return;
    const float2 logical{w / dpi, h / dpi};
    const auto xs = Axis(logical.x), ys = Axis(logical.y);
    std::vector<float3> positions, normals;
    std::vector<float2> coordinates;
    std::vector<uint32_t> indices;
    positions.reserve(xs.size()*ys.size()); coordinates.reserve(xs.size()*ys.size());
    for (float y : ys) for (float x : xs) {
      positions.push_back({x * dpi, y * dpi, 0});
      const float2 sample = orion::glass::GlassSample({x, y}, logical, r);
      coordinates.push_back({std::clamp(sample.x/logical.x, 0.f, 1.f),
                             std::clamp(sample.y/logical.y, 0.f, 1.f)});
    }
    normals.resize(positions.size(), {0, 0, 1});
    const auto columns = static_cast<uint32_t>(xs.size());
    for (uint32_t y = 0; y + 1 < ys.size(); ++y) for (uint32_t x = 0; x + 1 < columns; ++x) {
      const uint32_t a = y*columns+x, b = a+1, c = a+columns, d = c+1;
      indices.insert(indices.end(), {a,b,d,a,d,c});
    }
    mesh.FillMeshAttribute(SceneAttributeSemantic::Vertex, DirectXPixelFormat::R32G32B32Float, Buffer(positions));
    mesh.FillMeshAttribute(SceneAttributeSemantic::Normal, DirectXPixelFormat::R32G32B32Float, Buffer(normals));
    mesh.FillMeshAttribute(SceneAttributeSemantic::TexCoord0, DirectXPixelFormat::R32G32Float, Buffer(coordinates));
    mesh.FillMeshAttribute(SceneAttributeSemantic::Index, DirectXPixelFormat::R32UInt, Buffer(indices));
    source.Size({w,h}); surface.SourceSize({w,h}); scene.Size({w,h}); root.Size({w,h});
    const float2 curve{r*dpi, r*dpi};
    root.Clip(compositor.CreateRectangleClip(0, 0, w, h, curve, curve, curve, curve));
    if (rim) rim->Resize(w,h,dpi,r);
    width=w; height=h; scale=dpi; applied_radius=r;
  }
  ~Impl() noexcept { ResetGraph(); }
  void StopTimer() noexcept {
    if (!sync_timer) return;
    // KillTimer leaves already queued WM_TIMER messages in the thread queue.
    // Remove the live entry first so those callbacks cannot touch this object.
    timers.erase(sync_timer);
    KillTimer(window,sync_timer);
    sync_timer=0;
  }
  void Disable() noexcept {
    enabled = false;
    StopTimer();
    try { if (target) target.Root(nullptr); } catch (...) {}
    RemovePropW(window,L"OrionDesktopGlassActive");
    if (frame_transparent && IsWindow(window)) {
      MARGINS margins{};DwmExtendFrameIntoClientArea(window,&margins);
      DWM_BLURBEHIND alpha{};alpha.dwFlags=DWM_BB_ENABLE;
      DwmEnableBlurBehindWindow(window,&alpha);
    }
    frame_transparent=false;
  }
  void ResetGraph() noexcept {
    Disable();
    // Detach every WinRT reference to shared DWM visuals before their helper
    // window is destroyed. Device-loss cleanup must also remain exception safe.
    try { if (surface) surface.SourceVisual(nullptr); } catch (...) {}
    try { if (desktop_surface) desktop_surface.SourceVisual(nullptr); } catch (...) {}
    try { if (source) source.Brush(nullptr); } catch (...) {}
    try { if (root) root.Children().RemoveAll(); } catch (...) {}
    rim.reset();
    mesh=nullptr;scene=nullptr;surface=nullptr;source=nullptr;
    desktop_surface=nullptr;root=nullptr;target=nullptr;
    desktop.reset();
    compositor=nullptr;
    initialized=false;
    next_desktop_update=0;
    desktop_bounds={};
    width=0;height=0;scale=0;applied_radius=-1;
  }
};

WindowsGlass::WindowsGlass(HWND window) : impl_(std::make_unique<Impl>(window)) {}
WindowsGlass::~WindowsGlass() = default;
bool WindowsGlass::active() const { return impl_->enabled; }
bool WindowsGlass::Configure(bool enabled, double radius, std::string* error) {
  auto& glass = *impl_;
  try {
    glass.radius = static_cast<float>(std::isfinite(radius)?std::clamp(radius,0.0,256.0):24.0);
    if (!enabled) {
      glass.Disable();
      return true;
    }
    glass.Initialize();
    if (!glass.frame_transparent) {
      DWM_BLURBEHIND alpha{};
      alpha.dwFlags=DWM_BB_ENABLE;alpha.fEnable=TRUE;
      check_hresult(DwmEnableBlurBehindWindow(glass.window,&alpha));
      glass.frame_transparent=true;
      MARGINS transparent_frame{-1,-1,-1,-1};
      check_hresult(DwmExtendFrameIntoClientArea(glass.window,&transparent_frame));
    }
    glass.enabled = true;
    if (!glass.sync_timer) {
      glass.sync_timer=SetTimer(glass.window,++Impl::next_timer_id,16,Impl::Sync);
      if (!glass.sync_timer) throw hresult_error(HRESULT_FROM_WIN32(ERROR_NOT_ENOUGH_MEMORY));
      Impl::timers.emplace(glass.sync_timer,&glass);
    }
    glass.Resize();
    glass.target.Root(glass.root);
    SetPropW(glass.window,L"OrionDesktopGlassActive",reinterpret_cast<HANDLE>(1));
    return true;
  } catch (const hresult_error& failure) {
    try { if(error)*error=to_string(failure.message()); } catch (...) {}
  } catch (const std::exception& failure) {
    try { if(error)*error=failure.what(); } catch (...) {}
  } catch (...) {
    try { if(error)*error="Desktop glass is unavailable."; } catch (...) {}
  }
  glass.ResetGraph();
  return false;
}
void WindowsGlass::Resize() {
  try { impl_->Resize(); } catch (...) {
    // A device reset must not unwind through the Win32 window procedure.
    impl_->ResetGraph();
  }
}
