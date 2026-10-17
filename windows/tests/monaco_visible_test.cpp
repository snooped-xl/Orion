// Verify the displayed editor, not WebView2's healthy offscreen CapturePreview.
// Only an explicitly supplied Orion test process and this helper are captured.
#include <windows.h>
#include <dwmapi.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <fstream>
#include <string>
#include <vector>

namespace {
constexpr wchar_t kPatternClass[] = L"OrionMonacoVisibilityPattern";

void Pump(DWORD milliseconds) {
  const auto deadline = GetTickCount64() + milliseconds;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(5);
  } while (GetTickCount64() < deadline);
}

LRESULT CALLBACK PatternProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint;
    const auto dc = BeginPaint(window, &paint);
    RECT area{};
    GetClientRect(window, &area);
    for (int y = 0; y < area.bottom; y += 48) {
      for (int x = 0; x < area.right; x += 48) {
        RECT cell{x, y, x + 48, y + 48};
        const auto color = ((x / 48 + y / 48) % 2) ?
            RGB(12, 20, 30) : RGB(30, 36, 42);
        const auto brush = CreateSolidBrush(color);
        FillRect(dc, &cell, brush);
        DeleteObject(brush);
      }
    }
    EndPaint(window, &paint);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

struct Windows {
  DWORD pid = 0;
  HWND root = nullptr;
  HWND editor = nullptr;
};

Windows FindWindows(DWORD pid) {
  Windows found{pid};
  EnumWindows([](HWND window, LPARAM argument) -> BOOL {
    auto& result = *reinterpret_cast<Windows*>(argument);
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner != result.pid) return TRUE;
    wchar_t klass[128]{}, title[128]{};
    GetClassNameW(window, klass, 128);
    GetWindowTextW(window, title, 128);
    if (std::wcscmp(klass, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0 ||
        std::wcscmp(title, L"Orion") != 0) return TRUE;
    result.root = window;
    return FALSE;
  }, reinterpret_cast<LPARAM>(&found));
  if (found.root) {
    EnumChildWindows(found.root, [](HWND window, LPARAM argument) -> BOOL {
      auto& result = *reinterpret_cast<Windows*>(argument);
      wchar_t klass[128]{}, title[128]{};
      GetClassNameW(window, klass, 128);
      GetWindowTextW(window, title, 128);
      if (_wcsicmp(klass, L"Static") == 0 &&
          std::wcscmp(title, L"Orion Monaco") == 0) {
        result.editor = window;
        return FALSE;
      }
      return TRUE;
    }, reinterpret_cast<LPARAM>(&found));
  }
  return found;
}

struct Fixture {
  HWND root;
  HWND pattern = nullptr;
  bool was_topmost;
  explicit Fixture(HWND window) : root(window),
      was_topmost((GetWindowLongPtrW(root, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0) {}
  ~Fixture() {
    if (pattern) DestroyWindow(pattern);
    if (!was_topmost && IsWindow(root)) {
      SetWindowPos(root, HWND_NOTOPMOST, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
  }
};

bool GeometryMatches(const Windows& app, const RECT& root, const RECT& editor) {
  RECT current_root{}, current_editor{};
  const bool root_rect = GetWindowRect(app.root, &current_root) != FALSE;
  const bool editor_rect = GetWindowRect(app.editor, &current_editor) != FALSE;
  const bool root_visible = IsWindowVisible(app.root) != FALSE;
  const bool editor_visible = IsWindowVisible(app.editor) != FALSE;
  const bool iconic = IsIconic(app.root) != FALSE;
  const bool matches = root_visible && !iconic && editor_visible &&
      root_rect && editor_rect && EqualRect(&root, &current_root) &&
      EqualRect(&editor, &current_editor);
  if (!matches) {
    std::fprintf(stderr,
        "Fixture geometry changed: rootVisible=%d editorVisible=%d iconic=%d "
        "root=(%ld,%ld,%ld,%ld)->(%ld,%ld,%ld,%ld) "
        "editor=(%ld,%ld,%ld,%ld)->(%ld,%ld,%ld,%ld).\n",
        root_visible ? 1 : 0, editor_visible ? 1 : 0, iconic ? 1 : 0,
        root.left, root.top, root.right, root.bottom,
        current_root.left, current_root.top, current_root.right,
        current_root.bottom, editor.left, editor.top, editor.right,
        editor.bottom, current_editor.left, current_editor.top,
        current_editor.right, current_editor.bottom);
  }
  return matches;
}

bool OwnsPixels(const Windows& app, HWND pattern, const RECT& area) {
  const RECT desktop{GetSystemMetrics(SM_XVIRTUALSCREEN),
      GetSystemMetrics(SM_YVIRTUALSCREEN),
      GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
      GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
  if (area.left < desktop.left || area.top < desktop.top ||
      area.right > desktop.right || area.bottom > desktop.bottom) {
    std::fprintf(stderr,
        "Editor outside visible desktop: editor=(%ld,%ld,%ld,%ld), "
        "desktop=(%ld,%ld,%ld,%ld).\n", area.left, area.top, area.right,
        area.bottom, desktop.left, desktop.top, desktop.right, desktop.bottom);
    return false;
  }
  for (LONG y = area.top; y < area.bottom; y += 4) {
    for (LONG x = area.left; x < area.right; x += 4) {
      const auto root = GetAncestor(WindowFromPoint({x, y}), GA_ROOT);
      DWORD owner = 0;
      GetWindowThreadProcessId(root, &owner);
      // Windows may hit-test a fully transparent glass pixel through Orion.
      // The only permitted window beneath it is our controlled dark pattern.
      if ((root == app.root && owner == app.pid) ||
          (root == pattern && owner == GetCurrentProcessId())) continue;
      wchar_t klass[128]{};
      GetClassNameW(root, klass, 128);
      std::fprintf(stderr,
          "Foreign window covers editor at %ld,%ld: hwnd=%p pid=%lu class=%ls.\n",
          x, y, root, owner, klass);
      return false;
    }
  }
  return true;
}

bool Capture(const RECT& area, std::vector<uint32_t>* pixels) {
  const int width = area.right - area.left, height = area.bottom - area.top;
  const auto screen = GetDC(nullptr);
  if (!screen) return false;
  const auto memory = CreateCompatibleDC(screen);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* data = nullptr;
  const auto bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS,
      &data, nullptr, 0);
  const auto previous = bitmap && memory ? SelectObject(memory, bitmap) : nullptr;
  const bool success = previous && data && BitBlt(memory, 0, 0, width, height,
      screen, area.left, area.top, SRCCOPY | CAPTUREBLT);
  if (success) {
    GdiFlush();
    pixels->assign(static_cast<uint32_t*>(data),
        static_cast<uint32_t*>(data) + static_cast<size_t>(width) * height);
  }
  if (previous) SelectObject(memory, previous);
  if (bitmap) DeleteObject(bitmap);
  if (memory) DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return success;
}

bool Save(const std::wstring& path, const RECT& area,
          const std::vector<uint32_t>& pixels) {
  BITMAPINFOHEADER info{};
  info.biSize = sizeof(info);
  info.biWidth = area.right - area.left;
  info.biHeight = area.top - area.bottom;
  info.biPlanes = 1;
  info.biBitCount = 32;
  info.biCompression = BI_RGB;
  BITMAPFILEHEADER file{};
  file.bfType = 0x4d42;
  file.bfOffBits = sizeof(file) + sizeof(info);
  file.bfSize = file.bfOffBits + static_cast<DWORD>(pixels.size() * 4);
  std::ofstream stream(path, std::ios::binary);
  stream.write(reinterpret_cast<const char*>(&file), sizeof(file));
  stream.write(reinterpret_cast<const char*>(&info), sizeof(info));
  stream.write(reinterpret_cast<const char*>(pixels.data()),
      static_cast<std::streamsize>(pixels.size() * 4));
  return stream.good();
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc < 3) {
    std::fprintf(stderr, "Usage: monaco_visible_test <test-app-pid> <output.bmp>\n");
    return 2;
  }
  wchar_t* end = nullptr;
  const auto pid = std::wcstoul(argv[1], &end, 10);
  if (!pid || *end || pid == GetCurrentProcessId()) {
    std::fprintf(stderr, "Refusing an invalid test application PID.\n");
    return 2;
  }
  const auto app = FindWindows(pid);
  if (!app.root || !app.editor) {
    std::fprintf(stderr, "The supplied test process has no Orion editor window.\n");
    return 2;
  }
  RECT root{}, editor{};
  if (!GetWindowRect(app.root, &root) || !GetWindowRect(app.editor, &editor) ||
      editor.right - editor.left < 32 || editor.bottom - editor.top < 32 ||
      editor.right - editor.left > 8192 || editor.bottom - editor.top > 8192 ||
      !GeometryMatches(app, root, editor)) {
    std::fprintf(stderr, "The supplied test editor is hidden or has invalid bounds.\n");
    return 2;
  }
  Fixture fixture(app.root);
  WNDCLASSW klass{};
  klass.lpfnWndProc = PatternProcedure;
  klass.hInstance = GetModuleHandleW(nullptr);
  klass.lpszClassName = kPatternClass;
  if (!RegisterClassW(&klass)) return 2;
  fixture.pattern = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
      kPatternClass, L"Orion controlled editor underlay", WS_POPUP,
      root.left - 8, root.top - 8, root.right - root.left + 16,
      root.bottom - root.top + 16, nullptr, nullptr, klass.hInstance, nullptr);
  if (!fixture.pattern || !SetWindowPos(app.root, HWND_TOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) ||
      !SetWindowPos(fixture.pattern, app.root, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)) return 2;
  InvalidateRect(fixture.pattern, nullptr, FALSE);
  UpdateWindow(fixture.pattern);
  Pump(700);
  if (!GeometryMatches(app, root, editor) ||
      !OwnsPixels(app, fixture.pattern, editor)) {
    std::fprintf(stderr, "Test editor moved or is covered; no pixels captured.\n");
    return 3;
  }
  std::vector<uint32_t> pixels;
  if (!Capture(editor, &pixels) || !GeometryMatches(app, root, editor) ||
      !OwnsPixels(app, fixture.pattern, editor)) {
    std::fprintf(stderr, "Test editor capture was interrupted; image discarded.\n");
    return 3;
  }
  const int width = editor.right - editor.left;
  const int height = editor.bottom - editor.top;
  const int inspected_height = std::min(220, height);
  // A healthy gutter alone cannot establish that document text was displayed.
  const int gutter = std::min(width, static_cast<int>(
      (65ull * GetDpiForWindow(app.root) + 95) / 96));
  size_t glyph_pixels = 0;
  int bands = 0, gap = 3;
  for (int y = 0; y < inspected_height; ++y) {
    size_t row_pixels = 0;
    for (int x = gutter; x < width; ++x) {
      const auto color = pixels[static_cast<size_t>(y) * width + x];
      if (std::min({color & 255, (color >> 8) & 255,
          (color >> 16) & 255}) > 80) ++row_pixels;
    }
    glyph_pixels += row_pixels;
    if (row_pixels >= 3) {
      if (gap >= 3) ++bands;
      gap = 0;
    } else {
      ++gap;
    }
  }
  DWORD key = 0, flags = 0;
  BYTE alpha = 255;
  const bool layered = GetLayeredWindowAttributes(app.editor, &key, &alpha, &flags);
  std::printf("Visible Monaco: pid=%lu root=%p editor=%p bounds=%ld,%ld,%ld,%ld "
      "nativeLayered=%d nativeAlpha=%u glyphPixels=%zu textRows=%d "
      "contentStartX=%d inspected=%dx%d\n",
      pid, app.root, app.editor, editor.left, editor.top, editor.right,
      editor.bottom, layered ? 1 : 0, static_cast<unsigned>(alpha),
      glyph_pixels, bands, gutter, width - gutter, inspected_height);
  if (!Save(argv[2], editor, pixels)) {
    std::fprintf(stderr, "Could not save the controlled editor screenshot.\n");
    return 2;
  }
  if (glyph_pixels <= 100 || bands < 2) {
    std::fprintf(stderr, "Displayed Monaco text is missing or incomplete.\n");
    return 1;
  }
  return 0;
}
