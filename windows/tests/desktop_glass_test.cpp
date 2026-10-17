// A real DWM integration test. Both sampled windows belong to this test; the
// underlay is deterministic, and the test never captures another app's pixels.
#include "../runner/windows_glass.h"
#include <dwmapi.h>
#include <winrt/base.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

namespace {
LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint; const auto dc = BeginPaint(window, &paint);
    RECT area{}; GetClientRect(window, &area);
    const auto phase=GetWindowLongPtr(window, GWLP_USERDATA);
    if (phase) {
      for (int y=0; y<area.bottom; y+=100) for (int x=0; x<area.right; x+=100) {
        RECT cell{x,y,x+100,y+100};
        auto brush=CreateSolidBrush((((x+y)/100)+phase-1)%2 ? RGB(20,70,140) : RGB(230,200,100));
        FillRect(dc,&cell,brush); DeleteObject(brush);
      }
    }
    EndPaint(window,&paint); return 0;
  }
  return DefWindowProc(window,message,wparam,lparam);
}
void PumpMessages() {
  MSG message;
  while(PeekMessage(&message,nullptr,0,0,PM_REMOVE)) {TranslateMessage(&message);DispatchMessage(&message);}
}
void Pump(int milliseconds) {
  const auto deadline=GetTickCount64()+milliseconds;
  while(GetTickCount64()<deadline) {
    PumpMessages();
    Sleep(5);
  }
}
struct Image {
  int width, height;
  std::vector<uint32_t> pixels;
  uint32_t at(int x,int y) const { return pixels[static_cast<size_t>(y)*width+x]&0xffffff; }
};
struct RegionCapture {
  RECT area;
  HDC screen=nullptr,memory=nullptr;
  HBITMAP bitmap=nullptr;
  HGDIOBJ previous=nullptr;
  void* pixels=nullptr;
  explicit RegionCapture(RECT value) : area(value) {
    screen=GetDC(nullptr);memory=CreateCompatibleDC(screen);
    BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth=area.right-area.left;info.bmiHeader.biHeight=area.top-area.bottom;
    info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    bitmap=CreateDIBSection(screen,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
    if(bitmap && memory) previous=SelectObject(memory,bitmap);
  }
  ~RegionCapture() {
    if(previous) SelectObject(memory,previous);
    if(bitmap) DeleteObject(bitmap);
    if(memory) DeleteDC(memory);
    if(screen) ReleaseDC(nullptr,screen);
  }
  Image Read() const {
    Image image{area.right-area.left,area.bottom-area.top,{}};
    if(!pixels || !previous || !BitBlt(memory,0,0,image.width,image.height,screen,area.left,area.top,SRCCOPY|CAPTUREBLT)) return {};
    GdiFlush();
    image.pixels.assign(static_cast<uint32_t*>(pixels),static_cast<uint32_t*>(pixels)+image.width*image.height);
    return image;
  }
};
Image Crop(const Image& image,const RECT& area) {
  if(area.left<0 || area.top<0 || area.right>image.width || area.bottom>image.height ||
      area.right<=area.left || area.bottom<=area.top) return {};
  Image result{area.right-area.left,area.bottom-area.top,{}};
  result.pixels.reserve(static_cast<size_t>(result.width)*result.height);
  for(int y=area.top;y<area.bottom;y++) {
    const auto begin=image.pixels.begin()+static_cast<size_t>(y)*image.width+area.left;
    result.pixels.insert(result.pixels.end(),begin,begin+result.width);
  }
  return result;
}
void SaveImage(const Image& image,const std::wstring& path) {
  BITMAPINFOHEADER info{};info.biSize=sizeof(info);
  info.biWidth=image.width;info.biHeight=-image.height;
  info.biPlanes=1;info.biBitCount=32;info.biCompression=BI_RGB;
  BITMAPFILEHEADER file{};file.bfType=0x4d42;file.bfOffBits=sizeof(file)+sizeof(info);
  file.bfSize=file.bfOffBits+static_cast<DWORD>(image.pixels.size()*4);
  std::ofstream stream(path,std::ios::binary);
  stream.write(reinterpret_cast<const char*>(&file),sizeof(file));
  stream.write(reinterpret_cast<const char*>(&info),sizeof(info));
  stream.write(reinterpret_cast<const char*>(image.pixels.data()),static_cast<std::streamsize>(image.pixels.size()*4));
}
Image Capture(HWND window, const std::wstring& path={}) {
  RECT area; GetWindowRect(window,&area);
  Image image{area.right-area.left,area.bottom-area.top,{}};
  auto screen=GetDC(nullptr), memory=CreateCompatibleDC(screen);
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth=image.width; info.bmiHeader.biHeight=-image.height;
  info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
  void* pixels=nullptr;
  auto bitmap=CreateDIBSection(screen,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
  auto previous=SelectObject(memory,bitmap);
  BitBlt(memory,0,0,image.width,image.height,screen,area.left,area.top,SRCCOPY|CAPTUREBLT);
  GdiFlush();
  image.pixels.assign(static_cast<uint32_t*>(pixels),static_cast<uint32_t*>(pixels)+image.width*image.height);
  SelectObject(memory,previous);DeleteObject(bitmap);DeleteDC(memory);ReleaseDC(nullptr,screen);
  if(!path.empty()) SaveImage(image,path);
  return image;
}
std::wstring WithSuffix(const std::wstring& path,const wchar_t* suffix) {
  const auto extension=path.find_last_of(L'.');
  return path.substr(0,extension)+suffix+L".bmp";
}
struct WindowInputLock {
  HWND window;
  bool restore;
  explicit WindowInputLock(HWND value) : window(value),restore(IsWindowEnabled(value)!=FALSE) {
    if(restore) EnableWindow(window,FALSE);
  }
  void Release() {
    if(restore && IsWindow(window)) EnableWindow(window,TRUE);
    restore=false;
  }
  ~WindowInputLock() {Release();}
};
bool AlignPattern(HWND pattern,HWND app,RECT* app_area,RECT* pattern_area) {
  if(!GetWindowRect(app,app_area) || IsIconic(app) || !IsWindowVisible(app)) return false;
  if(!SetWindowPos(pattern,app,app_area->left-40,app_area->top-40,
      app_area->right-app_area->left+80,app_area->bottom-app_area->top+80,SWP_NOACTIVATE)) return false;
  InvalidateRect(pattern,nullptr,FALSE);UpdateWindow(pattern);
  return GetWindowRect(pattern,pattern_area)!=FALSE;
}
bool FixtureGeometryMatches(HWND app,HWND pattern,const RECT& expected_app,const RECT& expected_pattern) {
  RECT actual_app{},actual_pattern{};
  if(!GetWindowRect(app,&actual_app) || !GetWindowRect(pattern,&actual_pattern) ||
      IsIconic(app) || !IsWindowVisible(app) || !EqualRect(&actual_app,&expected_app) ||
      !EqualRect(&actual_pattern,&expected_pattern)) {
    std::fprintf(stderr,
        "Visual test interrupted by moved/resized fixture: app (%ld,%ld,%ld,%ld) -> (%ld,%ld,%ld,%ld), "
        "pattern (%ld,%ld,%ld,%ld) -> (%ld,%ld,%ld,%ld); metrics not evaluated.\n",
        expected_app.left,expected_app.top,expected_app.right,expected_app.bottom,
        actual_app.left,actual_app.top,actual_app.right,actual_app.bottom,
        expected_pattern.left,expected_pattern.top,expected_pattern.right,expected_pattern.bottom,
        actual_pattern.left,actual_pattern.top,actual_pattern.right,actual_pattern.bottom);
    return false;
  }
  return true;
}
bool CaptureIsOwned(HWND pattern,DWORD app_pid,int step=8) {
  RECT area{};GetWindowRect(pattern,&area);
  const RECT desktop{GetSystemMetrics(SM_XVIRTUALSCREEN),GetSystemMetrics(SM_YVIRTUALSCREEN),
      GetSystemMetrics(SM_XVIRTUALSCREEN)+GetSystemMetrics(SM_CXVIRTUALSCREEN),
      GetSystemMetrics(SM_YVIRTUALSCREEN)+GetSystemMetrics(SM_CYVIRTUALSCREEN)};
  if(area.left<desktop.left || area.top<desktop.top || area.right>desktop.right || area.bottom>desktop.bottom) {
    std::fprintf(stderr,"Controlled visual fixture is outside the visible desktop; no screenshot saved.\n");
    return false;
  }
  // Check again before every capture: the user can switch windows while the
  // helper waits for DWM, including between the two checkerboard phases.
  for(int y=area.top;y<area.bottom;y+=step) for(int x=area.left;x<area.right;x+=step) {
    const auto root=GetAncestor(WindowFromPoint({x,y}),GA_ROOT);
    DWORD owner=0;GetWindowThreadProcessId(root,&owner);
    if(owner!=app_pid && owner!=GetCurrentProcessId()) {
      wchar_t klass[128]{};GetClassName(root,klass,128);
      std::fprintf(stderr,"Visual test interrupted by %ls at %d,%d; no screenshot saved.\n",klass,x,y);
      return false;
    }
  }
  return true;
}
HWND GlassWindow(DWORD app_pid) {
  struct Search { DWORD pid;HWND window=nullptr; } search{app_pid};
  EnumWindows([](HWND candidate,LPARAM argument)->BOOL {
    auto& found=*reinterpret_cast<Search*>(argument);DWORD pid=0;
    GetWindowThreadProcessId(candidate,&pid);wchar_t klass[128]{};GetClassName(candidate,klass,128);
    if(pid==found.pid && std::wstring(klass)==L"OrionDesktopGlass") {
      found.window=candidate;return FALSE;
    }
    return TRUE;
  },reinterpret_cast<LPARAM>(&search));
  return search.window;
}
int Chroma(uint32_t pixel) {
  return static_cast<int>((pixel>>16)&255)-static_cast<int>(pixel&255);
}
RECT EmptyEditorPatch(const RECT& app) {
  return {app.left+static_cast<LONG>((app.right-app.left)*.45),app.top+static_cast<LONG>((app.bottom-app.top)*.54),
      app.right-70,app.top+static_cast<LONG>((app.bottom-app.top)*.72)};
}
struct ColorDifference {
  size_t changed=0,total=0;
  int maximum=0;
};
ColorDifference StationaryDifference(const Image& reference,const Image& sample,const RECT& patch) {
  if(reference.width!=sample.width || reference.height!=sample.height || patch.left<0 || patch.top<0 ||
      patch.right>sample.width || patch.bottom>sample.height || patch.right<=patch.left || patch.bottom<=patch.top) {
    return {};
  }
  ColorDifference result;
  for(int y=patch.top;y<patch.bottom;y++) for(int x=patch.left;x<patch.right;x++) {
    const auto a=reference.at(x,y),b=sample.at(x,y);
    int difference=std::abs(Chroma(a)-Chroma(b));
    for(int shift:{0,8,16}) difference=std::max(difference,
        std::abs(static_cast<int>((a>>shift)&255)-static_cast<int>((b>>shift)&255)));
    result.maximum=std::max(result.maximum,difference);
    if(difference>5) result.changed++;
    result.total++;
  }
  return result;
}
int CheckStationaryBurst(HWND app,HWND pattern,DWORD app_pid,const RECT& screen_app,const RECT& screen_pattern,
    const RECT& local_app,const Image& reference,const std::wstring& output) {
  const auto extension=output.find_last_of(L'.');
  std::ofstream csv(output.substr(0,extension)+L"-frames.csv",std::ios::binary);
  if(!csv) {std::fprintf(stderr,"Could not write stationary glass frame metrics.\n");return 1;}
  csv<<"frame,elapsed_ms,refresh_before,refresh_after,refresh_delta,reference_changed,previous_changed,pixels,max_color_delta\n";
  const auto started=GetTickCount64();
  const auto editor=EmptyEditorPatch(local_app);
  const auto initial_image=Crop(reference,editor);
  const RECT pixels{0,0,initial_image.width,initial_image.height};
  RegionCapture capture({screen_pattern.left+editor.left,screen_pattern.top+editor.top,
      screen_pattern.left+editor.right,screen_pattern.top+editor.bottom});
  Image previous=initial_image,worst;
  ColorDifference maximum_reference,maximum_previous;
  size_t maximum_changed=0;
  int worst_frame=0,frames=0,consecutive=0,even=0,odd=0;
  ULONGLONG previous_refresh=0;
  // Poll the refresh clock instead of pairing DwmFlush with GDI's readback
  // synchronization: those two waits can accidentally sample every other
  // refresh. Reuse a small editor-only DIB and vary the interframe delay.
  while(frames<120 || GetTickCount64()-started<2000) {
    if(GetTickCount64()-started>10000) {
      std::fprintf(stderr,"DWM did not produce enough distinct refreshes for stationary glass verification.\n");return 1;
    }
    PumpMessages();
    DWM_TIMING_INFO timing{};timing.cbSize=sizeof(timing);
    if(FAILED(DwmGetCompositionTimingInfo(nullptr,&timing))) {
      std::fprintf(stderr,"Could not read DWM refresh timing for stationary glass verification.\n");return 1;
    }
    if(frames && timing.cRefresh==previous_refresh) {Sleep(1);continue;}
    if(!FixtureGeometryMatches(app,pattern,screen_app,screen_pattern) ||
        !CaptureIsOwned(pattern,app_pid,frames%8==0?8:64)) return 3;
    auto sample=capture.Read();
    if(!FixtureGeometryMatches(app,pattern,screen_app,screen_pattern)) return 3;
    DWM_TIMING_INFO sampled{};sampled.cbSize=sizeof(sampled);
    if(FAILED(DwmGetCompositionTimingInfo(nullptr,&sampled))) {
      std::fprintf(stderr,"Could not read the captured frame's DWM refresh timing.\n");return 1;
    }
    const auto delta=frames?sampled.cRefresh-previous_refresh:0;
    if(delta==1) consecutive++;
    if(sampled.cRefresh%2) odd++;else even++;
    previous_refresh=sampled.cRefresh;
    const auto initial=StationaryDifference(initial_image,sample,pixels);
    const auto interframe=StationaryDifference(previous,sample,pixels);
    if(!initial.total || !interframe.total) {
      std::fprintf(stderr,"Stationary glass capture bounds are invalid.\n");return 1;
    }
    frames++;
    csv<<frames<<','<<GetTickCount64()-started<<','<<timing.cRefresh<<','<<sampled.cRefresh<<','<<delta<<','<<initial.changed<<','
        <<interframe.changed<<','<<initial.total<<','<<std::max(initial.maximum,interframe.maximum)<<'\n';
    if(initial.changed>maximum_reference.changed) maximum_reference=initial;
    if(interframe.changed>maximum_previous.changed) maximum_previous=interframe;
    const auto changed=std::max(initial.changed,interframe.changed);
    if(changed>maximum_changed) {maximum_changed=changed;worst=sample;worst_frame=frames;}
    previous=std::move(sample);
    Sleep(frames%4);
  }
  const auto total=StationaryDifference(initial_image,previous,pixels).total;
  std::printf("Stationary glass burst: %d frames in %llums, max vs initial=%zu/%zu (%.3f%%), "
      "max adjacent=%zu/%zu (%.3f%%); RGB/chroma tolerance 5, changed-pixel limit 2%%.\n",
      frames,GetTickCount64()-started,maximum_reference.changed,total,static_cast<double>(maximum_reference.changed)*100/total,
      maximum_previous.changed,total,static_cast<double>(maximum_previous.changed)*100/total);
  std::printf("Stationary refresh coverage: consecutive=%d/%d (%.2f%%), even=%d, odd=%d.\n",
      consecutive,frames-1,static_cast<double>(consecutive)*100/(frames-1),even,odd);
  if(maximum_changed*100>total*2) {
    SaveImage(worst,WithSuffix(output,L"-worst-flicker"));
    std::fprintf(stderr,"Desktop glass flickered over a stationary background (worst frame %d).\n",worst_frame);
    return 1;
  }
  if(!even || !odd || consecutive*10<frames-1) {
    std::fprintf(stderr,"Stationary verification insufficient: both refresh parities and at least 10%% consecutive refresh samples are required.\n");
    return 4;
  }
  return 0;
}
bool CheckLiveGlass(const Image& before,const Image& after,const RECT& app,bool require_foreground=true) {
  if(before.width!=after.width || before.height!=after.height || app.left<0 || app.top<0 ||
      app.right>before.width || app.bottom>before.height || app.right-app.left<300 || app.bottom-app.top<250) {
    std::fprintf(stderr,"Glass capture bounds are invalid; metrics not evaluated.\n");return false;
  }
  size_t foreground=0,changed=0,total=0;
  for(int y=app.top+40;y<app.bottom-40;y++) for(int x=app.left+40;x<app.right-40;x++) {
    const auto pixel=before.at(x,y);
    if((pixel&255)>160 && ((pixel>>8)&255)>160 && ((pixel>>16)&255)>160) foreground++;
  }
  // The lower editor body is intentionally empty in the Flutter fixture. The
  // phase difference removes the authored tint and static foreground, leaving
  // the live desktop response. Ordinary alpha transparency changes immediately
  // at a checker edge; real desktop frost produces several intermediate pixels.
  const auto patch=EmptyEditorPatch(app);
  const int x0=patch.left,x1=patch.right,y0=patch.top,y1=patch.bottom;
  int transitions=0,softened=0,blurred=0,maximum_width=0,shifted=0;
  double transition_shift=0,squared_shift=0;
  for(int y=y0;y<y1;y+=7) {
    const auto response=[&](int x) { return Chroma(before.at(x,y))-Chroma(after.at(x,y)); };
    for(int x=x0;x<x1;x+=3) {total++;if(std::abs(response(x))>20) changed++;}
    for(int edge=((x0+99)/100)*100;edge+28<x1;edge+=100) {
      const int left=response(edge-28),right=response(edge+28);
      if(left*right>=0 || std::min(std::abs(left),std::abs(right))<20) continue;
      // Interpolate the actual sign crossing. Choosing the smallest absolute
      // endpoint response gave a spurious -25px shift for an unfiltered step
      // whose two plateaus happened to have the same magnitude. An ordinary
      // checker step instead crosses at edge-.5px and cannot pass the lens test.
      double crossing=0,nearest=10000;
      int previous_x=edge-25,previous=response(previous_x);
      bool found=false;
      for(int x=edge-24;x<=edge+25;x++) {
        const int value=response(x);
        if(value==0) continue;
        if(previous!=0 && previous*value<0 && x-previous_x<=3) {
          const double candidate=previous_x+
              static_cast<double>(previous)*(x-previous_x)/(previous-value);
          if(std::abs(candidate-edge)<nearest) {
            crossing=candidate;nearest=std::abs(candidate-edge);found=true;
          }
        }
        previous=value;previous_x=x;
      }
      if(!found) continue;
      transitions++;
      const double shift=crossing-edge;
      transition_shift+=shift;squared_shift+=shift*shift;
      if(std::abs(shift)>2) shifted++;
      const int limit=std::max(1,static_cast<int>(std::min(std::abs(left),std::abs(right))*.65));
      int run=0,longest=0;
      // A 1.5-2.25px frost kernel can leave only one or two intermediate
      // samples after refraction and pixel alignment; it should not be required
      // to resemble a heavily blurred backdrop.
      for(int x=static_cast<int>(std::floor(crossing))-6;x<=static_cast<int>(std::ceil(crossing))+6;x++) {
        if(std::abs(response(x))<limit) {run++;longest=std::max(longest,run);} else run=0;
      }
      if(longest>=1) softened++;
      if(longest>=2) blurred++;
      maximum_width=std::max(maximum_width,longest);
    }
  }
  const double mean_shift=transitions?transition_shift/transitions:0;
  const double rms_shift=transitions?std::sqrt(squared_shift/transitions):0;
  std::printf("Glass visual metrics: foreground=%zu, live=%zu/%zu, frost=%d softened/%d >=2px/%d transitions, "
      "widest=%dpx, lens=%d shifted, mean=%.2fpx, RMS=%.2fpx.\n",
      foreground,changed,total,softened,blurred,transitions,maximum_width,shifted,mean_shift,rms_shift);
  bool good=true;
  if(require_foreground && foreground<150) {std::fprintf(stderr,"Orion foreground was missing.\n");good=false;}
  if(total==0 || changed*3<total) {std::fprintf(stderr,"Glass did not respond to the live desktop checkerboard.\n");good=false;}
  if(transitions<4 || softened<std::max(4,transitions/4) || blurred<2 || maximum_width<2) {
    std::fprintf(stderr,"Desktop checker edges were not filtered; ordinary transparency is insufficient.\n");good=false;
  }
  if(rms_shift<=2 || shifted*2<transitions) {
    std::fprintf(stderr,"Desktop checker edges did not move through the glass lens.\n");good=false;
  }
  return good;
}
}  // namespace
int wmain(int argc,wchar_t** argv) {
  winrt::init_apartment(winrt::apartment_type::single_threaded);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  WNDCLASS description{}; description.hInstance=GetModuleHandle(nullptr);
  description.lpfnWndProc=Procedure; description.lpszClassName=L"OrionGlassVisualTest";
  RegisterClass(&description);
  if (argc == 4 && std::wstring(argv[1]) == L"--app") {
    struct Search { DWORD pid; HWND window=nullptr; } search{wcstoul(argv[2],nullptr,10)};
    EnumWindows([](HWND candidate,LPARAM argument)->BOOL {
      auto& found=*reinterpret_cast<Search*>(argument); DWORD pid=0;
      GetWindowThreadProcessId(candidate,&pid);
      wchar_t klass[128]{};GetClassName(candidate,klass,128);
      if(pid==found.pid && IsWindowVisible(candidate) &&
          std::wstring(klass)==L"FLUTTER_RUNNER_WIN32_WINDOW") {
        found.window=candidate;return FALSE;
      }
      return TRUE;
    },reinterpret_cast<LPARAM>(&search));
    if(!search.window) return 2;
    WindowInputLock input_lock(search.window);
    wchar_t title[256]{}, klass[256]{};
    GetWindowText(search.window,title,256);GetClassName(search.window,klass,256);
    std::printf("App hwnd %p, class %ls, title %ls, exstyle %llx\n",search.window,klass,title,
        static_cast<unsigned long long>(GetWindowLongPtr(search.window,GWL_EXSTYLE)));
    SetWindowPos(search.window,HWND_TOPMOST,100,100,0,0,SWP_NOSIZE|SWP_NOACTIVATE);
    RECT area;GetWindowRect(search.window,&area);
    auto pattern=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,description.lpszClassName,
        L"Orion glass controlled underlay",WS_POPUP|WS_VISIBLE,area.left-40,area.top-40,
        area.right-area.left+80,area.bottom-area.top+80,nullptr,nullptr,description.hInstance,nullptr);
    SetWindowLongPtr(pattern,GWLP_USERDATA,1);InvalidateRect(pattern,nullptr,FALSE);
    const auto raised=SetWindowPos(search.window,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    SetWindowPos(pattern,search.window,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    Pump(1200);
    RECT pattern_area{};
    if(!AlignPattern(pattern,search.window,&area,&pattern_area)) {DestroyWindow(pattern);return 3;}
    Pump(300);
    std::printf("Controlled fixture: app (%ld,%ld,%ld,%ld), pattern (%ld,%ld,%ld,%ld), raised=%d, input locked=%d.\n",
        area.left,area.top,area.right,area.bottom,pattern_area.left,pattern_area.top,pattern_area.right,pattern_area.bottom,
        raised,!IsWindowEnabled(search.window));
    if(!FixtureGeometryMatches(search.window,pattern,area,pattern_area) || !CaptureIsOwned(pattern,search.pid)) {
      DestroyWindow(pattern);return 3;
    }
    const auto before=Capture(pattern,argv[3]);
    if(!FixtureGeometryMatches(search.window,pattern,area,pattern_area)) {DestroyWindow(pattern);return 3;}
    SetWindowLongPtr(pattern,GWLP_USERDATA,2);InvalidateRect(pattern,nullptr,FALSE);UpdateWindow(pattern);
    Pump(900);
    if(!FixtureGeometryMatches(search.window,pattern,area,pattern_area) || !CaptureIsOwned(pattern,search.pid)) {
      DestroyWindow(pattern);return 3;
    }
    const auto after=Capture(pattern,WithSuffix(argv[3],L"-inverted"));
    if(!FixtureGeometryMatches(search.window,pattern,area,pattern_area)) {DestroyWindow(pattern);return 3;}
    const RECT local_app{area.left-pattern_area.left,area.top-pattern_area.top,
        area.right-pattern_area.left,area.bottom-pattern_area.top};
    bool good=CheckLiveGlass(before,after,local_app);
    const int stability=CheckStationaryBurst(search.window,pattern,search.pid,area,pattern_area,local_app,after,argv[3]);
    if(stability==3 || stability==4) {DestroyWindow(pattern);return stability;}
    good=good && stability==0;
    DWORD affinity=999;
    if(!GetWindowDisplayAffinity(search.window,&affinity) || affinity!=WDA_NONE) {
      std::fprintf(stderr,"Main window changed screenshot capture affinity.\n");good=false;
    }
    const auto glass_window=GlassWindow(search.pid);
    const bool glass_in_main=GetPropW(search.window,L"OrionDesktopGlassActive")!=nullptr;
    if(!glass_in_main && (!glass_window || !IsWindowVisible(glass_window))) {
      std::fprintf(stderr,"Desktop glass material window was not visible.\n");good=false;
    }
    input_lock.Release();
    DWORD_PTR ignored=0;
    if(!SendMessageTimeout(search.window,WM_SYSCOMMAND,SC_MINIMIZE,0,SMTO_ABORTIFHUNG,2000,&ignored)) {
      std::fprintf(stderr,"Main window did not accept minimize.\n");good=false;
    }
    Pump(300);
    if(!IsIconic(search.window) || (!glass_in_main && glass_window && IsWindowVisible(glass_window))) {
      std::fprintf(stderr,"Minimize did not hide the native glass material.\n");good=false;
    }
    if(!SendMessageTimeout(search.window,WM_SYSCOMMAND,SC_RESTORE,0,SMTO_ABORTIFHUNG,2000,&ignored)) {
      std::fprintf(stderr,"Main window did not accept restore.\n");good=false;
    }
    SetWindowPos(search.window,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    SetWindowPos(pattern,search.window,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    Pump(700);
    if(IsIconic(search.window) || (!glass_in_main && glass_window && !IsWindowVisible(glass_window)) ||
        (glass_in_main && !GetPropW(search.window,L"OrionDesktopGlassActive"))) {
      std::fprintf(stderr,"Restore did not show the native glass material.\n");good=false;
    }
    if(!FixtureGeometryMatches(search.window,pattern,area,pattern_area) || !CaptureIsOwned(pattern,search.pid)) {
      DestroyWindow(pattern);return 3;
    }
    Capture(pattern,WithSuffix(argv[3],L"-restored"));
    DestroyWindow(pattern);
    return good?0:1;
  }
  auto background=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW,description.lpszClassName,
      L"Orion glass test background",WS_POPUP|WS_VISIBLE,100,100,880,620,nullptr,nullptr,description.hInstance,nullptr);
  SetWindowLongPtr(background,GWLP_USERDATA,1); InvalidateRect(background,nullptr,FALSE); Pump(150);
  // This fixture has no Flutter alpha child. Suppress the default opaque GDI
  // redirection surface so it cannot cover the composition visual being tested.
  // Keep the checker independent: DWM excludes an owned-window family when
  // removing Orion from its own backdrop, which would exclude this underlay.
  auto window=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOREDIRECTIONBITMAP,description.lpszClassName,
      L"Orion glass visual test",WS_POPUP|WS_VISIBLE,140,140,800,540,nullptr,nullptr,description.hInstance,nullptr);
  int result=0;
  {
    WindowsGlass glass(window); std::string error;
    if(!glass.Configure(true,24,&error) || !glass.active()) {
      std::fprintf(stderr,"Native glass initialization failed: %s\n",error.c_str()); result=1;
    } else {
      Pump(1200);
      const std::wstring output=argc>1?argv[1]:L"desktop-glass.bmp";
      const auto image=Capture(background,output);
      // The square's corners must expose the exact unfiltered background;
      // its centre must actually be filtered by DWM, not plain transparency.
      if(image.at(40,40)!=0xe6c864 || image.at(839,40)!=0xe6c864) {
        std::fprintf(stderr,"Outside corner was not transparent: %06x %06x\n",image.at(40,40),image.at(839,40)); result=1;
      }
      SetWindowLongPtr(background,GWLP_USERDATA,2);
      InvalidateRect(background,nullptr,FALSE);UpdateWindow(background);Pump(700);
      const auto inverted=Capture(background,WithSuffix(output,L"-inverted"));
      // Uniform paint, an opaque composition surface, and plain transparency
      // must all fail. Require a live phase response, frost, and displaced edges.
      if(!CheckLiveGlass(image,inverted,{40,40,840,580},false)) result=1;
      DWORD affinity=999; GetWindowDisplayAffinity(window,&affinity);
      if(affinity!=WDA_NONE) {std::fprintf(stderr,"Glass changed screenshot capture affinity\n");result=1;}
      for(int i=0;i<12;i++) {
        glass.Configure(false,24,&error); glass.Configure(true,24,&error);
        SetWindowPos(window,nullptr,0,0,800+(i%2)*40,540,SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE);
        glass.Resize(); Pump(15);
      }
      if(!result) std::printf("Native desktop glass passed live desktop, frost, lens and 12 toggle/resize checks.\n");
    }
  }
  DestroyWindow(window);DestroyWindow(background);
  return result;
}
