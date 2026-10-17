#!/usr/bin/env python3
"""Test the native rounded input geometry without opening a desktop window."""

from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile


TEST = r"""
#include "window_shape.h"
#include <cmath>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <initializer_list>
#include <limits>
#include <string>
#include <gdk/gdkx.h>
#include <X11/extensions/shape.h>

static void check(bool condition, const char* label) {
  if (!condition) g_error("FAIL: %s", label);
}
static bool contains(cairo_region_t* region, int x, int y) {
  return cairo_region_contains_point(region, x, y);
}
// Preserve the original full-scanline algorithm as the geometry oracle.
static cairo_region_t* reference_region(int width,int height,double radius) {
  auto* region=cairo_region_create();
  if (width<=0 || height<=0) return region;
  radius=std::isfinite(radius)
      ? std::clamp(radius,0.0,std::min(width,height)/2.0) : 0;
  for (int y=0;y<height;++y) {
    const double center_y=y+0.5;
    const double distance=center_y<radius ? radius-center_y
        : center_y>height-radius ? center_y-(height-radius) : 0;
    const double inset=distance>0
        ? radius-std::sqrt(std::max(0.0,radius*radius-distance*distance)) : 0;
    const int left=std::max(0,static_cast<int>(std::ceil(inset-0.5)));
    const cairo_rectangle_int_t row{left,y,width-2*left,1};
    if (row.width>0) cairo_region_union_rectangle(region,&row);
  }
  return region;
}
static void equivalence_test() {
  int cases=0;
  for (int width : {-1,0,1,2,3,4,7,8,17,20,39,40,41,127,740,822,1045}) {
    for (int height : {-1,0,1,2,3,4,5,6,17,19,20,39,40,41,470,523,648}) {
      for (double radius : {-1.0,0.0,0.01,0.49,0.5,0.51,1.0,1.2,2.7,
                            10.0,19.5,20.0,20.1,64.0,1000.0,
                            std::numeric_limits<double>::quiet_NaN(),
                            std::numeric_limits<double>::infinity()}) {
        auto* expected=reference_region(width,height,radius);
        auto* actual=window_shape_rounded_region(width,height,radius);
        check(cairo_region_equal(expected,actual),
              "optimized input geometry exactly matches original scanlines");
        cairo_region_destroy(expected);
        cairo_region_destroy(actual);
        ++cases;
      }
    }
  }
  std::printf("Native window geometry equivalence: PASS (%d cases)\n",cases);
}
static void benchmark() {
  constexpr int count=10000;
  auto measure=[](auto create) {
    const auto start=std::chrono::steady_clock::now();
    for (int i=0;i<count;++i) {
      auto* region=create(822+i%3,523+i%2,20);
      cairo_region_destroy(region);
    }
    return std::chrono::duration<double,std::milli>(
        std::chrono::steady_clock::now()-start).count();
  };
  const double before=measure(reference_region);
  const double after=measure(window_shape_rounded_region);
  std::printf("Native geometry microbenchmark (%d masks): original %.2fms, optimized %.2fms\n",
              count,before,after);
}
static void drain() {
  for (int i=0;i<30;++i) {
    while (g_main_context_iteration(nullptr,FALSE)) {}
    g_usleep(1000);
  }
}
static cairo_region_t* native_region(GtkWidget* widget, int shape_kind=ShapeInput) {
  auto* window=gtk_widget_get_window(widget);
  auto* display=gdk_window_get_display(window);
  gdk_display_sync(display);
  int count=0, ordering=0;
  XRectangle* rectangles=XShapeGetRectangles(
      gdk_x11_display_get_xdisplay(display),gdk_x11_window_get_xid(window),
      shape_kind,&count,&ordering);
  const int scale=gtk_widget_get_scale_factor(widget);
  auto* region=cairo_region_create();
  for (int i=0;i<count;++i) {
    cairo_rectangle_int_t rect{rectangles[i].x/scale,rectangles[i].y/scale,
                              rectangles[i].width/scale,rectangles[i].height/scale};
    cairo_region_union_rectangle(region,&rect);
  }
  XFree(rectangles);
  return region;
}
static void native_test(int* argc,char*** argv) {
  gtk_init(argc,argv);
  GtkWidget* window=gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto* visual=gdk_screen_get_rgba_visual(gtk_widget_get_screen(window));
  check(visual!=nullptr,"ARGB visual is available");
  gtk_widget_set_visual(window,visual);
  gtk_widget_set_app_paintable(window,TRUE);
  gtk_window_set_decorated(GTK_WINDOW(window),FALSE);
  gtk_window_set_default_size(GTK_WINDOW(window),200,120);
  gtk_widget_show(window);
  drain();
  const int scale=gtk_widget_get_scale_factor(window);
  window_shape_set_corner_radius(GTK_WINDOW(window),20);
  check(gdk_visual_get_depth(gdk_window_get_visual(gtk_widget_get_window(window)))==32,
        "rounded window retains per-pixel alpha visual");
  auto* bounds=native_region(window,ShapeBounding);
  check(contains(bounds,0,0) && contains(bounds,199,119),
        "native input mask must never binary-clip visual corner coverage");
  cairo_region_destroy(bounds);
  auto* region=native_region(window);
  check(!contains(region,0,0) && contains(region,10,3),
        "actual GDK input region follows the visible curve");
  cairo_region_destroy(region);
  gtk_window_resize(GTK_WINDOW(window),300,180);
  drain();
  region=native_region(window);
  check(!contains(region,299,179) && contains(region,279,179),
        "actual GDK input region follows window resizing");
  cairo_region_destroy(region);
  bounds=native_region(window,ShapeBounding);
  check(contains(bounds,0,0) && contains(bounds,299,179),
        "visual ARGB bounds stay rectangular after resizing");
  cairo_region_destroy(bounds);
  GdkEventWindowState event{};
  event.type=GDK_WINDOW_STATE;
  event.window=gtk_widget_get_window(window);
  gboolean handled=FALSE;
  for (const auto state : {GDK_WINDOW_STATE_MAXIMIZED,GDK_WINDOW_STATE_FULLSCREEN}) {
    event.changed_mask=state;
    event.new_window_state=state;
    g_signal_emit_by_name(window,"window-state-event",&event,&handled);
    region=native_region(window);
    check(contains(region,0,0) && contains(region,299,179),
          "maximized/fullscreen input region becomes square");
    cairo_region_destroy(region);
    event.new_window_state=static_cast<GdkWindowState>(0);
    g_signal_emit_by_name(window,"window-state-event",&event,&handled);
    region=native_region(window);
    check(!contains(region,0,0), "restoring the window restores its curve");
    cairo_region_destroy(region);
  }
  for (int i=0;i<20;++i) {
    window_shape_set_corner_radius(GTK_WINDOW(window),20);
    gtk_widget_queue_allocate(window);
    drain();
  }
  g_object_notify(G_OBJECT(window),"scale-factor");
  drain();
  region=native_region(window);
  check(!contains(region,0,0) && contains(region,279,179),
        "unchanged native allocations preserve the cached input mask");
  cairo_region_destroy(region);
  gtk_widget_hide(window);
  gtk_widget_unrealize(window);
  gtk_widget_show(window);
  drain();
  region=native_region(window);
  auto* recreated=gtk_widget_get_window(window);
  check(!contains(region,0,0) &&
            contains(region,gdk_window_get_width(recreated)-21,
                     gdk_window_get_height(recreated)-1),
        "a recreated native surface receives its input mask again");
  cairo_region_destroy(region);
  gtk_widget_destroy(window);
  drain();
  std::printf("Native GTK input shape: PASS (ARGB, no visual binary mask, input curve, resize, maximize/fullscreen, restore; scale%d)\n",
              scale);
}
int main(int argc,char** argv) {
  equivalence_test();
  for (const auto size : {GdkRectangle{0,0,1180,760},
                          GdkRectangle{0,0,800,560},
                          GdkRectangle{0,0,1500,900}}) {
    auto* region = window_shape_rounded_region(size.width, size.height, 20);
    check(!contains(region,0,0), "transparent corner must pass through");
    check(contains(region,10,3), "visible curved resize arc must accept input");
    check(contains(region,20,0), "straight top edge must accept input");
    check(contains(region,0,20), "straight left edge must accept input");
    check(contains(region,18,18), "controls inside the arc remain interactive");
    check(contains(region,size.width/2,size.height/2), "interior stays interactive");
    for (int y=0;y<24;++y) for (int x=0;x<24;++x) {
      const bool top_left=contains(region,x,y);
      check(top_left==contains(region,size.width-1-x,y), "top corners symmetric");
      check(top_left==contains(region,x,size.height-1-y), "left corners symmetric");
      check(top_left==contains(region,size.width-1-x,size.height-1-y),
            "opposite corners symmetric");
    }
    cairo_region_destroy(region);
  }
  auto* square=window_shape_rounded_region(1180,760,0);
  check(contains(square,0,0) && contains(square,1179,759),
        "zero radius restores the full maximized input rectangle");
  cairo_region_destroy(square);
  auto* small=window_shape_rounded_region(8,6,20);
  cairo_rectangle_int_t bounds{};
  cairo_region_get_extents(small,&bounds);
  check(bounds.x>=0 && bounds.y>=0 && bounds.width<=8 && bounds.height<=6,
        "tiny allocations clamp the radius inside their bounds");
  cairo_region_destroy(small);
  auto* empty=window_shape_rounded_region(0,0,20);
  check(cairo_region_is_empty(empty), "zero-sized allocations remain empty");
  cairo_region_destroy(empty);
  std::puts("Native window shape: PASS (curve, resize arc, symmetry, resize, square)");
  if (argc>1 && std::string(argv[1])=="--benchmark") benchmark();
  else if (argc>1) native_test(&argc,&argv);
}
"""


def main():
    root = Path(__file__).resolve().parents[1]
    runner = root / "linux/runner"
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "gtk+-3.0", "x11", "xext"],
        text=True))
    with tempfile.TemporaryDirectory(prefix="orion-window-shape-") as directory:
        directory = Path(directory)
        source = directory / "test.cc"
        source.write_text(TEST)
        binary = directory / "test"
        subprocess.run(["c++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(runner), str(source),
                        str(runner / "window_shape.cc"), *flags,
                        "-o", str(binary)], check=True)
        command = [str(binary)]
        if "--native" in sys.argv:
            command = ["xvfb-run", "-a", str(binary), "--native"]
            for scale in ["1", "2"]:
                subprocess.run(command, env=dict(os.environ, GDK_BACKEND="x11", GDK_SCALE=scale),
                               check=True, timeout=10)
        else:
            if "--benchmark" in sys.argv:
                command.append("--benchmark")
            subprocess.run(command, env=dict(os.environ, GDK_BACKEND="x11"),
                           check=True, timeout=10)


if __name__ == "__main__":
    main()
