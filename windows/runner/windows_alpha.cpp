#include "windows_alpha.h"

#include <d3d11.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <cstring>
#include <cwchar>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {
using Microsoft::WRL::ComPtr;
using CreateFactory = HRESULT(WINAPI*)(REFIID, void**);
using CreateHwndSwapchain = HRESULT(STDMETHODCALLTYPE*)(IDXGIFactory2*, IUnknown*,
    HWND, const DXGI_SWAP_CHAIN_DESC1*, const DXGI_SWAP_CHAIN_FULLSCREEN_DESC*,
    IDXGIOutput*, IDXGISwapChain1**);

struct CompositionHost {
  ComPtr<IUnknown> graphics_identity;
  ComPtr<IDCompositionDevice> device;
  ComPtr<IDCompositionTarget> target;
  ComPtr<IDCompositionVisual> visual;
};
struct ImportPatch {
  void** address;
  void* original;
};

// Flutter statically links ANGLE, so EGL cannot be wrapped at its DLL imports.
// Its DXGI factory imports are the stable boundary available to the runner.
// Changes are limited to this process and FLUTTERVIEW child swapchains.
std::mutex state_mutex;
std::unordered_map<void**, CreateHwndSwapchain> swapchain_methods;
std::unordered_map<HWND, std::shared_ptr<CompositionHost>> hosts;
std::vector<ImportPatch> import_patches;
CreateFactory create_factory = nullptr;
CreateFactory create_factory1 = nullptr;
HWINEVENTHOOK destroy_hook = nullptr;

bool ReplacePointer(void** address, void* replacement) {
  DWORD protection = 0;
  if (!VirtualProtect(address, sizeof(void*), PAGE_READWRITE, &protection)) {
    return false;
  }
  InterlockedExchangePointer(reinterpret_cast<void* volatile*>(address), replacement);
  DWORD ignored = 0;
  VirtualProtect(address, sizeof(void*), protection, &ignored);
  return true;
}

bool IsFlutterView(HWND window) {
  wchar_t name[64]{};
  return window && GetClassNameW(window, name, 64) &&
      std::wcscmp(name, L"FLUTTERVIEW") == 0;
}

void RetireHost(HWND window) {
  std::shared_ptr<CompositionHost> retired;
  {
    std::lock_guard<std::mutex> lock(state_mutex);
    const auto found = hosts.find(window);
    if (found == hosts.end()) return;
    retired = std::move(found->second);
    hosts.erase(found);
  }
  if (retired) {
    retired->target->SetRoot(nullptr);
    retired->device->Commit();
  }
}

HRESULT STDMETHODCALLTYPE CreateTransparentSwapchain(IDXGIFactory2* factory,
    IUnknown* graphics_device, HWND window, const DXGI_SWAP_CHAIN_DESC1* description,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* fullscreen, IDXGIOutput* restrict_output,
    IDXGISwapChain1** result) {
  CreateHwndSwapchain original = nullptr;
  const auto methods = *reinterpret_cast<void***>(factory);
  {
    std::lock_guard<std::mutex> lock(state_mutex);
    const auto found = swapchain_methods.find(methods + 15);
    if (found != swapchain_methods.end()) original = found->second;
  }
  if (!original) return E_UNEXPECTED;
  if (!description || !result || !IsFlutterView(window)) {
    return original(factory, graphics_device, window, description, fullscreen,
        restrict_output, result);
  }

  try {
  ComPtr<IDXGIDevice> dxgi_device;
  ComPtr<IUnknown> graphics_identity;
  HRESULT status = graphics_device ? graphics_device->QueryInterface(
      IID_PPV_ARGS(&dxgi_device)) : E_INVALIDARG;
  if (SUCCEEDED(status)) status = dxgi_device.As(&graphics_identity);
  if (SUCCEEDED(status)) {
    DXGI_SWAP_CHAIN_DESC1 alpha = *description;
    alpha.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
    alpha.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    alpha.BufferCount = 2;
    alpha.SampleDesc.Count = 1;
    alpha.SampleDesc.Quality = 0;
    alpha.Scaling = DXGI_SCALING_STRETCH;
    ComPtr<IDXGISwapChain1> swapchain;
    status = factory->CreateSwapChainForComposition(graphics_device, &alpha,
        nullptr, &swapchain);
    if (SUCCEEDED(status)) {
      std::lock_guard<std::mutex> lock(state_mutex);
      auto& host = hosts[window];
      // ANGLE can recreate its D3D device after a reset. A composition target
      // tied to the old device cannot accept the replacement swapchain.
      if (host && host->graphics_identity.Get() != graphics_identity.Get()) {
        host->target->SetRoot(nullptr);
        host->device->Commit();
        host.reset();
      }
      if (!host) {
        auto candidate = std::make_shared<CompositionHost>();
        candidate->graphics_identity = graphics_identity;
        status = DCompositionCreateDevice(dxgi_device.Get(),
            IID_PPV_ARGS(&candidate->device));
        // Monaco's WebView2 host is a child of FLUTTERVIEW. The Flutter visual
        // belongs below child HWND content; a topmost composition target draws
        // opaque Flutter editor backgrounds over the otherwise healthy browser.
        if (SUCCEEDED(status)) status = candidate->device->CreateTargetForHwnd(
            window, FALSE, &candidate->target);
        if (SUCCEEDED(status)) status = candidate->device->CreateVisual(
            &candidate->visual);
        if (SUCCEEDED(status)) status = candidate->target->SetRoot(
            candidate->visual.Get());
        if (SUCCEEDED(status)) host = std::move(candidate);
      }
      if (host && SUCCEEDED(status)) {
        status = host->visual->SetContent(swapchain.Get());
        if (SUCCEEDED(status)) status = host->device->Commit();
      }
      if (SUCCEEDED(status) && host) {
        *result = swapchain.Detach();
        return S_OK;
      }
      hosts.erase(window);
    }
  }
  } catch (...) {
    // Allocation failures in optional composition must not cross ANGLE's COM
    // call boundary or prevent the ordinary HWND renderer from starting.
  }

  // Keep ordinary rendering available on systems without composition support.
  RetireHost(window);
  return original(factory, graphics_device, window, description, fullscreen,
      restrict_output, result);
}

void PatchFactory(IUnknown* instance) noexcept {
  try {
  if (!instance) return;
  ComPtr<IDXGIFactory2> factory;
  if (FAILED(instance->QueryInterface(IID_PPV_ARGS(&factory)))) return;
  const auto methods = *reinterpret_cast<void***>(factory.Get());
  auto address = methods + 15;  // IDXGIFactory2::CreateSwapChainForHwnd.
  std::lock_guard<std::mutex> lock(state_mutex);
  if (swapchain_methods.find(address) != swapchain_methods.end()) return;
  const auto original = reinterpret_cast<CreateHwndSwapchain>(*address);
  swapchain_methods.emplace(address, original);
  if (!ReplacePointer(address, reinterpret_cast<void*>(CreateTransparentSwapchain))) {
    swapchain_methods.erase(address);
  }
  } catch (...) {
    // The original factory remains usable if optional setup cannot allocate.
  }
}

HRESULT WINAPI WrappedCreateFactory(REFIID id, void** result) {
  const HRESULT status = create_factory(id, result);
  if (SUCCEEDED(status) && result && *result) {
    PatchFactory(static_cast<IUnknown*>(*result));
  }
  return status;
}
HRESULT WINAPI WrappedCreateFactory1(REFIID id, void** result) {
  const HRESULT status = create_factory1(id, result);
  if (SUCCEEDED(status) && result && *result) {
    PatchFactory(static_cast<IUnknown*>(*result));
  }
  return status;
}

void CALLBACK WindowDestroyed(HWINEVENTHOOK, DWORD, HWND window, LONG object,
    LONG child, DWORD, DWORD) {
  if (object != OBJID_WINDOW || child != CHILDID_SELF || IsWindow(window)) return;
  try {
    RetireHost(window);
  } catch (...) {
    // No C++ exception may cross a Win32 event callback.
  }
}
}  // namespace

bool OrionEnableAlphaComposition() {
  try {
  if (!import_patches.empty()) return true;
  auto module = reinterpret_cast<BYTE*>(GetModuleHandleW(L"flutter_windows.dll"));
  if (!module) return false;
  const auto dos = reinterpret_cast<IMAGE_DOS_HEADER*>(module);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
  const auto pe = reinterpret_cast<IMAGE_NT_HEADERS*>(module + dos->e_lfanew);
  if (pe->Signature != IMAGE_NT_SIGNATURE) return false;
  const auto directory = pe->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!directory.VirtualAddress) return false;
  auto imports = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(module + directory.VirtualAddress);
  for (; imports->Name; ++imports) {
    if (_stricmp(reinterpret_cast<char*>(module + imports->Name), "dxgi.dll") != 0 ||
        !imports->OriginalFirstThunk) continue;
    auto names = reinterpret_cast<IMAGE_THUNK_DATA*>(module + imports->OriginalFirstThunk);
    auto addresses = reinterpret_cast<IMAGE_THUNK_DATA*>(module + imports->FirstThunk);
    for (; names->u1.AddressOfData; ++names, ++addresses) {
      if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
      const auto name = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(module + names->u1.AddressOfData);
      auto address = reinterpret_cast<void**>(&addresses->u1.Function);
      void* wrapper = nullptr;
      if (std::strcmp(name->Name, "CreateDXGIFactory") == 0) {
        create_factory = reinterpret_cast<CreateFactory>(*address);
        wrapper = reinterpret_cast<void*>(WrappedCreateFactory);
      } else if (std::strcmp(name->Name, "CreateDXGIFactory1") == 0) {
        create_factory1 = reinterpret_cast<CreateFactory>(*address);
        wrapper = reinterpret_cast<void*>(WrappedCreateFactory1);
      }
      if (wrapper) {
        const auto original = *address;
        // Allocate bookkeeping before changing the IAT, so an allocation
        // failure cannot leave an untracked import patched during teardown.
        import_patches.push_back({address, original});
        if (!ReplacePointer(address, wrapper)) import_patches.pop_back();
      }
    }
  }
  if (!import_patches.empty()) {
    destroy_hook = SetWinEventHook(EVENT_OBJECT_DESTROY, EVENT_OBJECT_DESTROY,
        nullptr, WindowDestroyed, GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
  }
  return !import_patches.empty();
  } catch (...) {
    OrionDisableAlphaComposition();
    return false;
  }
}

bool OrionHasAlphaComposition(HWND window) {
  std::lock_guard<std::mutex> lock(state_mutex);
  for (const auto& entry : hosts) {
    if (entry.second && (entry.first == window ||
        GetAncestor(entry.first, GA_ROOT) == window)) return true;
  }
  return false;
}

void OrionDisableAlphaComposition() {
  if (destroy_hook) {
    UnhookWinEvent(destroy_hook);
    destroy_hook = nullptr;
  }
  std::lock_guard<std::mutex> lock(state_mutex);
  hosts.clear();
  for (const auto& method : swapchain_methods) {
    ReplacePointer(method.first, reinterpret_cast<void*>(method.second));
  }
  swapchain_methods.clear();
  for (const auto& patch : import_patches) ReplacePointer(patch.address, patch.original);
  import_patches.clear();
}
