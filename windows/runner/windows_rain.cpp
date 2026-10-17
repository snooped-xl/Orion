#include "windows_rain.h"
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <wrl.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
const Value* Get(const Map& map, const char* key) {
  auto found = map.find(Value(key)); return found == map.end() ? nullptr : &found->second;
}
double Number(const Value* value, double fallback = 0) {
  if (!value) return fallback;
  if (auto n = std::get_if<double>(value)) return std::isfinite(*n) ? *n : fallback;
  if (auto n = std::get_if<int32_t>(value)) return *n;
  if (auto n = std::get_if<int64_t>(value)) return static_cast<double>(*n);
  return fallback;
}
bool Boolean(const Value* value) { auto b = value ? std::get_if<bool>(value) : nullptr; return b && *b; }
// The same authored refraction model as linux/runner/rain_effect.cc, rendered
// by Direct3D over the live UI. Dry pixels remain completely untouched.
// Water-normal/thickness model adapted from Lucas Bebber / Codrops RainEffect
// (MIT, 2015); full attribution is shipped in assets/effects.
constexpr char kShader[] = R"HLSL(
cbuffer Scene : register(b0) {
  float2 resolution; float2 packetSize;
  float4 editorBounds;
  float cornerRadius; uint hasEditor; float2 padding;
};
StructuredBuffer<float4> drops : register(t2);
Texture2D frameImage : register(t0);
Texture2D editorImage : register(t1);
SamplerState imageSampler : register(s0);
struct Fragment {
  float4 position : SV_POSITION;
  float2 pixel : TEXCOORD0;
  nointerpolation float4 shape : TEXCOORD1;
  nointerpolation float4 properties : TEXCOORD2;
};
Fragment vertex(uint id : SV_VertexID, uint instance : SV_InstanceID) {
  const float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
  float2 scale = resolution / max(packetSize, float2(1,1));
  Fragment output;
  output.shape = drops[instance * 2] * float4(scale,scale);
  output.properties = drops[instance * 2 + 1]; output.properties.w *= scale.y;
  float tail = output.properties.y > .5 ? output.properties.w : 0;
  float2 from = output.shape.xy - float2(output.shape.z*1.25+3,output.shape.w+tail+3);
  float2 to = output.shape.xy + float2(output.shape.z*1.25+3,output.shape.w+3);
  output.pixel = lerp(from,to,corners[id]);
  output.position = float4(output.pixel.x / resolution.x * 2 - 1,1 - output.pixel.y / resolution.y * 2,0,1);
  return output;
}
float4 scene(float2 p) {
  float4 bg = frameImage.Sample(imageSampler,saturate(p/resolution));
  float3 rgb = bg.rgb * bg.a;
  if (hasEditor && all(p >= editorBounds.xy) && all(p < editorBounds.xy+editorBounds.zw)) {
    float4 ed = editorImage.Sample(imageSampler,saturate((p-editorBounds.xy)/editorBounds.zw));
    rgb = ed.rgb*ed.a+rgb*(1-ed.a); bg.a = ed.a+bg.a*(1-ed.a);
  }
  return float4(bg.a>.0001 ? rgb/bg.a : float3(0,0,0),bg.a);
}
float4 pixel(Fragment input) : SV_TARGET {
  float2 p = input.pixel; float4 shape = input.shape; float4 properties = input.properties;
  float2 corner = max(abs(p-resolution*.5)-(resolution*.5-cornerRadius),float2(0,0));
  float rounded = length(corner)-cornerRadius; if (rounded>.75) discard;
  float2 q = (p-shape.xy)/max(shape.zw,float2(.25,.25));
  q.x /= 1+.10*clamp(q.y,-1,1);
  float radius = length(q); float aa = max(abs(ddx(radius))+abs(ddy(radius)),.018);
  float body = 1-smoothstep(1-aa,1+aa,radius);
  float thickness = sqrt(max(0,1-dot(q,q)));
  float lensRadius = max(shape.z,shape.w); float reach = clamp(lensRadius*.48,.65,3.5);
  float2 normal = -q*float2(.96,.78);
  float2 offset = normal*(reach+thickness*min(lensRadius*.18,1.2));
  float trail = 0; float2 trailOffset = float2(0,0);
  if (properties.y>.5 && properties.w>.5) {
    float behind = shape.y-p.y;
    float along = (behind-shape.w*.42)/max(properties.w,1);
    float width = lerp(max(.65,shape.z*.18),.35,saturate(along));
    float center = shape.x+sin(behind*.075+properties.z)*.24;
    float lateral = (p.x-center)/width;
    float sides = 1-smoothstep(.35,1,abs(lateral));
    float ends = smoothstep(0,.10,along)*(1-smoothstep(.72,1,along));
    trail = sides*ends*.18;
    trailOffset = float2(-lateral*(.65+properties.x*.75),sin(behind*.07+properties.z)*.25);
  }
  float coverage = max(body*(.50+properties.x*.20),trail); if (coverage<.006) discard;
  offset = body<.02 ? trailOffset : lerp(trailOffset,offset,body);
  float4 middle = scene(p+offset);
  float3 refracted = float3(scene(p+offset*1.008).r,middle.g,scene(p+offset*.992).b);
  float rimWidth = max(.065,(abs(ddx(radius))+abs(ddy(radius)))*.65);
  float rim = exp(-pow((radius-.86)/rimWidth,2))*body;
  float2 light = normalize(float2(-.55,-.83));
  float shine = max(0,dot(q,light))*rim*.22;
  float2 glintPoint = (q-float2(-.31,-.48))*float2(5.5,7);
  float glint = exp(-dot(glintPoint,glintPoint))*.09*body;
  float shadow = max(0,dot(q,-light))*rim*.085;
  refracted = saturate(refracted*(1-shadow)+shine+glint);
  float alpha = coverage*middle.a*(1-smoothstep(-.5,.75,rounded));
  return float4(refracted*alpha,alpha);
}
)HLSL";
struct Constants {
  float resolution[2], packet[2], editor[4];
  float radius; uint32_t has_editor; float padding[2];
};
LRESULT CALLBACK OverlayProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_ERASEBKGND) return 1;
  return DefWindowProcW(window,message,wparam,lparam);
}
}

struct WindowsRain::Impl {
  explicit Impl(HWND window) : owner(window) {}
  HWND owner = nullptr, overlay = nullptr;
  bool enabled = false, initialized = false;
  float radius = 16, packet_width = 1, packet_height = 1;
  std::array<float,4> editor_bounds{};
  UINT width = 0, height = 0;
  std::vector<float> drops;
  std::array<std::vector<uint8_t>,2> previous_png;
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<IDXGISwapChain1> swap;
  ComPtr<IDCompositionDevice> composition;
  ComPtr<IDCompositionTarget> target;
  ComPtr<IDCompositionVisual> visual;
  ComPtr<ID3D11RenderTargetView> render_target;
  ComPtr<ID3D11VertexShader> vertex_shader;
  ComPtr<ID3D11PixelShader> pixel_shader;
  ComPtr<ID3D11Buffer> constants, drop_buffer;
  ComPtr<ID3D11ShaderResourceView> drop_view;
  ComPtr<ID3D11SamplerState> sampler;
  ComPtr<ID3D11BlendState> blend;
  ComPtr<ID3D11RasterizerState> rasterizer;
  ComPtr<IWICImagingFactory> wic;
  std::array<ComPtr<ID3D11ShaderResourceView>,2> textures;
  bool Initialize(std::string* error) {
    if (initialized) return true;
    if (device) { *error="The rain compositor could not initialize."; return false; }
    WNDCLASSW wc{}; wc.hInstance=GetModuleHandleW(nullptr); wc.lpfnWndProc=OverlayProcedure; wc.lpszClassName=L"OrionRainOverlay";
    RegisterClassW(&wc);
    overlay = CreateWindowExW(WS_EX_NOREDIRECTIONBITMAP|WS_EX_NOACTIVATE|WS_EX_TRANSPARENT,
      wc.lpszClassName,L"",WS_CHILD|WS_CLIPSIBLINGS,0,0,1,1,owner,nullptr,wc.hInstance,nullptr);
    if (!overlay) { *error="Could not create the rain compositor surface."; return false; }
    const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    D3D_FEATURE_LEVEL feature{};
    HRESULT status = D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,flags,nullptr,0,D3D11_SDK_VERSION,&device,&feature,&context);
    if (FAILED(status)) status = D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,flags,nullptr,0,D3D11_SDK_VERSION,&device,&feature,&context);
    if (FAILED(status)) { *error="Direct3D 11 is unavailable for rain refraction."; return false; }
    ComPtr<IDXGIDevice> dxgi; device.As(&dxgi);
    ComPtr<IDXGIAdapter> adapter; dxgi->GetAdapter(&adapter);
    ComPtr<IDXGIFactory2> factory; adapter->GetParent(IID_PPV_ARGS(&factory));
    DXGI_SWAP_CHAIN_DESC1 description{};
    description.Width=1; description.Height=1; description.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
    description.SampleDesc.Count=1; description.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;
    description.BufferCount=2; description.SwapEffect=DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    description.AlphaMode=DXGI_ALPHA_MODE_PREMULTIPLIED;
    status = factory->CreateSwapChainForComposition(device.Get(),&description,nullptr,&swap);
    if (FAILED(status) || FAILED(DCompositionCreateDevice(dxgi.Get(),IID_PPV_ARGS(&composition))) ||
        FAILED(composition->CreateTargetForHwnd(overlay,TRUE,&target)) || FAILED(composition->CreateVisual(&visual))) {
      *error="DirectComposition is unavailable for the rain surface."; return false;
    }
    visual->SetContent(swap.Get()); target->SetRoot(visual.Get()); composition->Commit();
    ComPtr<ID3DBlob> vertex, pixel, log;
    status = D3DCompile(kShader,sizeof(kShader)-1,nullptr,nullptr,nullptr,"vertex","vs_5_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&vertex,&log);
    if (FAILED(status)) { *error=log?std::string(static_cast<const char*>(log->GetBufferPointer()),log->GetBufferSize()):"Rain vertex shader compilation failed."; return false; }
    status = D3DCompile(kShader,sizeof(kShader)-1,nullptr,nullptr,nullptr,"pixel","ps_5_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&pixel,&log);
    if (FAILED(status)) { *error=log?std::string(static_cast<const char*>(log->GetBufferPointer()),log->GetBufferSize()):"Rain pixel shader compilation failed."; return false; }
    if (FAILED(device->CreateVertexShader(vertex->GetBufferPointer(),vertex->GetBufferSize(),nullptr,&vertex_shader)) ||
        FAILED(device->CreatePixelShader(pixel->GetBufferPointer(),pixel->GetBufferSize(),nullptr,&pixel_shader))) { *error="Could not create rain shaders."; return false; }
    D3D11_BUFFER_DESC buffer{}; buffer.ByteWidth=sizeof(Constants); buffer.Usage=D3D11_USAGE_DYNAMIC; buffer.BindFlags=D3D11_BIND_CONSTANT_BUFFER; buffer.CPUAccessFlags=D3D11_CPU_ACCESS_WRITE;
    if (FAILED(device->CreateBuffer(&buffer,nullptr,&constants))) { *error="Could not allocate rain constants."; return false; }
    buffer.ByteWidth=2048*8*sizeof(float); buffer.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    buffer.MiscFlags=D3D11_RESOURCE_MISC_BUFFER_STRUCTURED; buffer.StructureByteStride=sizeof(float)*4;
    if (FAILED(device->CreateBuffer(&buffer,nullptr,&drop_buffer))) { *error="Could not allocate droplets."; return false; }
    D3D11_SHADER_RESOURCE_VIEW_DESC view{}; view.Format=DXGI_FORMAT_UNKNOWN; view.ViewDimension=D3D11_SRV_DIMENSION_BUFFER; view.Buffer.NumElements=4096;
    device->CreateShaderResourceView(drop_buffer.Get(),&view,&drop_view);
    D3D11_SAMPLER_DESC sampling{}; sampling.Filter=D3D11_FILTER_MIN_MAG_MIP_LINEAR; sampling.AddressU=sampling.AddressV=sampling.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP; sampling.MaxLOD=D3D11_FLOAT32_MAX;
    device->CreateSamplerState(&sampling,&sampler);
    D3D11_BLEND_DESC blending{}; blending.RenderTarget[0].BlendEnable=TRUE;
    blending.RenderTarget[0].SrcBlend=D3D11_BLEND_ONE; blending.RenderTarget[0].DestBlend=D3D11_BLEND_INV_SRC_ALPHA;
    blending.RenderTarget[0].BlendOp=D3D11_BLEND_OP_ADD; blending.RenderTarget[0].SrcBlendAlpha=D3D11_BLEND_ONE;
    blending.RenderTarget[0].DestBlendAlpha=D3D11_BLEND_INV_SRC_ALPHA; blending.RenderTarget[0].BlendOpAlpha=D3D11_BLEND_OP_ADD;
    blending.RenderTarget[0].RenderTargetWriteMask=D3D11_COLOR_WRITE_ENABLE_ALL;
    device->CreateBlendState(&blending,&blend);
    D3D11_RASTERIZER_DESC raster{}; raster.FillMode=D3D11_FILL_SOLID; raster.CullMode=D3D11_CULL_NONE; raster.DepthClipEnable=TRUE;
    device->CreateRasterizerState(&raster,&rasterizer);
    CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&wic));
    width=height=1; initialized=true;
    return true;
  }
  bool Image(int index, const Value* value) {
    const auto* bytes = value ? std::get_if<std::vector<uint8_t>>(value) : nullptr;
    if (!bytes || bytes->size()<24 || bytes->size()>8*1024*1024 || !wic) { textures[index].Reset(); previous_png[index].clear(); return index!=0; }
    if (*bytes==previous_png[index] && textures[index]) return true;
    static const uint8_t signature[]={137,80,78,71,13,10,26,10};
    if (std::memcmp(bytes->data(),signature,8)!=0) return false;
    ComPtr<IWICStream> stream; wic->CreateStream(&stream);
    if (FAILED(stream->InitializeFromMemory(const_cast<BYTE*>(bytes->data()),static_cast<DWORD>(bytes->size())))) return false;
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(wic->CreateDecoderFromStream(stream.Get(),nullptr,WICDecodeMetadataCacheOnLoad,&decoder))) return false;
    ComPtr<IWICBitmapFrameDecode> frame; decoder->GetFrame(0,&frame);
    UINT w=0,h=0; frame->GetSize(&w,&h);
    if (!w || !h || w>4096 || h>4096 || static_cast<uint64_t>(w)*h>8*1024*1024) return false;
    ComPtr<IWICFormatConverter> converter; wic->CreateFormatConverter(&converter);
    if (FAILED(converter->Initialize(frame.Get(),GUID_WICPixelFormat32bppRGBA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom))) return false;
    std::vector<uint8_t> rgba(static_cast<size_t>(w)*h*4);
    if (FAILED(converter->CopyPixels(nullptr,w*4,static_cast<UINT>(rgba.size()),rgba.data()))) return false;
    D3D11_TEXTURE2D_DESC texture{}; texture.Width=w; texture.Height=h; texture.MipLevels=texture.ArraySize=1;
    texture.Format=DXGI_FORMAT_R8G8B8A8_UNORM; texture.SampleDesc.Count=1; texture.Usage=D3D11_USAGE_IMMUTABLE; texture.BindFlags=D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data{}; data.pSysMem=rgba.data(); data.SysMemPitch=w*4;
    ComPtr<ID3D11Texture2D> image;
    if (FAILED(device->CreateTexture2D(&texture,&data,&image))) return false;
    ComPtr<ID3D11ShaderResourceView> resource;
    if (FAILED(device->CreateShaderResourceView(image.Get(),nullptr,&resource))) return false;
    textures[index]=resource; previous_png[index]=*bytes; return true;
  }
  void Resize() {
    if (!overlay || !swap) return;
    RECT area{}; GetClientRect(owner,&area);
    UINT w=static_cast<UINT>(std::max(1L,area.right)),h=static_cast<UINT>(std::max(1L,area.bottom));
    SetWindowPos(overlay,HWND_TOP,0,0,static_cast<int>(w),static_cast<int>(h),SWP_NOACTIVATE);
    if (w==width && h==height && render_target) return;
    context->OMSetRenderTargets(0,nullptr,nullptr); render_target.Reset();
    if (FAILED(swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0))) return;
    ComPtr<ID3D11Texture2D> back; swap->GetBuffer(0,IID_PPV_ARGS(&back));
    if (back && SUCCEEDED(device->CreateRenderTargetView(back.Get(),nullptr,&render_target))) { width=w; height=h; }
  }
  void Render() {
    if (!enabled || !device || !textures[0] || !IsWindowVisible(owner) || IsIconic(owner)) return;
    Resize(); if (!render_target) return;
    const float clear[4]{}; context->ClearRenderTargetView(render_target.Get(),clear);
    if (!drops.empty()) {
      Constants scene{}; scene.resolution[0]=static_cast<float>(width); scene.resolution[1]=static_cast<float>(height);
      scene.packet[0]=packet_width; scene.packet[1]=packet_height;
      const float scale=static_cast<float>(GetDpiForWindow(owner))/96.f;
      for (size_t i=0;i<4;i++) scene.editor[i]=editor_bounds[i]*scale;
      scene.radius=radius*scale; scene.has_editor=textures[1]?1:0;
      D3D11_MAPPED_SUBRESOURCE mapping{};
      if (FAILED(context->Map(constants.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapping))) return;
      std::memcpy(mapping.pData,&scene,sizeof(scene)); context->Unmap(constants.Get(),0);
      if (FAILED(context->Map(drop_buffer.Get(),0,D3D11_MAP_WRITE_DISCARD,0,&mapping))) return;
      std::memcpy(mapping.pData,drops.data(),drops.size()*sizeof(float)); context->Unmap(drop_buffer.Get(),0);
      auto* constant=constants.Get(); context->VSSetConstantBuffers(0,1,&constant); context->PSSetConstantBuffers(0,1,&constant);
      auto* target_view=render_target.Get(); context->OMSetRenderTargets(1,&target_view,nullptr);
      context->OMSetBlendState(blend.Get(),nullptr,0xffffffff); context->RSSetState(rasterizer.Get());
      D3D11_VIEWPORT viewport{0,0,static_cast<float>(width),static_cast<float>(height),0,1}; context->RSSetViewports(1,&viewport);
      context->IASetInputLayout(nullptr); context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
      context->VSSetShader(vertex_shader.Get(),nullptr,0); context->PSSetShader(pixel_shader.Get(),nullptr,0);
      auto* drop_resource=drop_view.Get(); context->VSSetShaderResources(2,1,&drop_resource);
      ID3D11ShaderResourceView* images[2]={textures[0].Get(),textures[1].Get()}; context->PSSetShaderResources(0,2,images);
      auto* image_sampler=sampler.Get(); context->PSSetSamplers(0,1,&image_sampler);
      context->DrawInstanced(6,static_cast<UINT>(drops.size()/8),0,0);
      ID3D11ShaderResourceView* empty[2]{}; context->PSSetShaderResources(0,2,empty);
    }
    swap->Present(0,0); composition->Commit();
  }
  ~Impl() {
    if (target) target->SetRoot(nullptr);
    if (composition) composition->Commit();
    if (overlay) DestroyWindow(overlay);
  }
};
WindowsRain::WindowsRain(HWND owner) : impl_(std::make_unique<Impl>(owner)) {}
WindowsRain::~WindowsRain() = default;
bool WindowsRain::Configure(const Map& args,std::string* error) {
  auto& rain=*impl_; const bool enabled=Boolean(Get(args,"enabled"));
  const double opacity=std::clamp(Number(Get(args,"opacity"),1),0.0,1.0);
  // Window alpha is independent of rain: every transparent theme needs this.
  LONG_PTR style=GetWindowLongPtr(rain.owner,GWL_EXSTYLE);
  const bool layered=opacity<1 || (style&WS_EX_TRANSPARENT)!=0;
  SetWindowLongPtr(rain.owner,GWL_EXSTYLE,layered?style|WS_EX_LAYERED:style&~WS_EX_LAYERED);
  if (layered) SetLayeredWindowAttributes(rain.owner,0,static_cast<BYTE>(std::round(opacity*255)),LWA_ALPHA);
  rain.radius=static_cast<float>(std::clamp(Number(Get(args,"cornerRadius"),16),0.0,64.0));
  if (enabled && !rain.Initialize(error)) { rain.enabled=false; if (rain.overlay) ShowWindow(rain.overlay,SW_HIDE); return false; }
  rain.enabled=enabled;
  if (rain.overlay) ShowWindow(rain.overlay,enabled?SW_SHOWNA:SW_HIDE);
  if (!enabled) { rain.drops.clear(); for (int i=0;i<2;i++) { rain.textures[i].Reset(); rain.previous_png[i].clear(); } }
  return true;
}
bool WindowsRain::Frame(const Map& args) {
  auto& rain=*impl_; if (!rain.enabled) return true;
  if (!rain.Image(0,Get(args,"png"))) return false;
  rain.Image(1,Get(args,"editorPng"));
  const char* keys[]={"editorX","editorY","editorWidth","editorHeight"};
  for (int i=0;i<4;i++) rain.editor_bounds[i]=static_cast<float>(std::clamp(Number(Get(args,keys[i])),i<2?-16384.0:0.0,16384.0));
  rain.Render(); return true;
}
bool WindowsRain::Drops(const Map& args) {
  auto& rain=*impl_; if (!rain.enabled) return true;
  const Value* data=Get(args,"data"); const auto* values=data?std::get_if<std::vector<float>>(data):nullptr;
  if (!values || values->size()%8!=0 || values->size()>2048*8) return false;
  for (float value:*values) if (!std::isfinite(value)) return false;
  rain.drops=*values;
  for (size_t i=0;i<rain.drops.size();i+=8) {
    rain.drops[i]=std::clamp(rain.drops[i],-65536.f,65536.f); rain.drops[i+1]=std::clamp(rain.drops[i+1],-65536.f,65536.f);
    rain.drops[i+2]=std::clamp(rain.drops[i+2],.25f,256.f); rain.drops[i+3]=std::clamp(rain.drops[i+3],.25f,512.f);
    rain.drops[i+4]=std::clamp(rain.drops[i+4],0.f,1.f); rain.drops[i+5]=rain.drops[i+5]>.5f?1.f:0.f;
    rain.drops[i+7]=std::clamp(rain.drops[i+7],0.f,2048.f);
  }
  rain.packet_width=static_cast<float>(std::clamp(Number(Get(args,"width"),1),1.0,16384.0));
  rain.packet_height=static_cast<float>(std::clamp(Number(Get(args,"height"),1),1.0,16384.0));
  rain.Render(); return true;
}
void WindowsRain::Resize() { if (impl_->enabled) impl_->Resize(); }
