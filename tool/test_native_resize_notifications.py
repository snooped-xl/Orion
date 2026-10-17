#!/usr/bin/env python3
"""Check real GTK child allocation churn never masquerades as a window resize."""
from pathlib import Path
import os,shlex,subprocess,tempfile
TEST = r"""
#include <gtk/gtk.h>
#include <cstdio>
#include "window_resize_state.h"
struct Counters { int checks=0,allocations=0,changes=0,w=0,h=0,step=0; GtkWidget*window;GtkWidget*child; } c;
WindowResizeState tracker{}; int notified=0;
int main(int argc,char**argv) {
 gtk_init(&argc,&argv);
 c.window=gtk_window_new(GTK_WINDOW_TOPLEVEL);
 gtk_window_set_default_size(GTK_WINDOW(c.window),822,523);
 GtkWidget* overlay=gtk_overlay_new();
 GtkWidget* content=gtk_drawing_area_new();
 gtk_widget_set_hexpand(content,TRUE);gtk_widget_set_vexpand(content,TRUE);
 gtk_container_add(GTK_CONTAINER(overlay),content);
 c.child=gtk_drawing_area_new();
 gtk_widget_set_halign(c.child,GTK_ALIGN_START);gtk_widget_set_valign(c.child,GTK_ALIGN_START);
 gtk_widget_set_size_request(c.child,320,200);
 gtk_overlay_add_overlay(GTK_OVERLAY(overlay),c.child);
 gtk_container_add(GTK_CONTAINER(c.window),overlay);
 g_signal_connect(c.window,"check-resize",G_CALLBACK(+[](GtkWidget*,gpointer){c.checks++;}),nullptr);
 g_signal_connect(c.window,"size-allocate",G_CALLBACK(+[](GtkWidget*,GtkAllocation*a,gpointer){
  c.allocations++;if(window_resize_changed(&tracker,a->width,a->height,gtk_widget_get_scale_factor(c.window))) notified++;if(a->width!=c.w||a->height!=c.h){c.changes++;c.w=a->width;c.h=a->height;}
 }),nullptr);
 gtk_widget_show_all(c.window);
 g_timeout_add(200,+[](gpointer)->gboolean{
  c.checks=0;c.allocations=0;c.changes=0;notified=0;
  g_timeout_add(12,+[](gpointer)->gboolean{
   gtk_widget_set_size_request(c.child,320+c.step%2,200);
   if(c.step%10==0)gtk_window_resize(GTK_WINDOW(c.window),822+c.step,523+c.step/2);
   if(++c.step<120)return G_SOURCE_CONTINUE;
   g_timeout_add(100,+[](gpointer)->gboolean{
    std::printf("{\"child_updates\":120,\"check_resize_events\":%d,\"top_level_allocations\":%d,\"actual_size_changes\":%d}\n",c.checks,c.allocations,c.changes);
    g_assert_cmpint(notified,==,c.changes);
    std::printf("Filtered native resize notifications: %d; all actual size changes delivered\n",notified);
    gtk_widget_destroy(c.window);gtk_main_quit();return G_SOURCE_REMOVE;
   },nullptr);return G_SOURCE_REMOVE;
  },nullptr);return G_SOURCE_REMOVE;
 },nullptr);
 gtk_main();
}
"""

def main():
    project=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="orion-resize-notifications-") as folder:
        folder=Path(folder);source=folder/"test.cc";source.write_text(TEST)
        binary=folder/"test"
        flags=shlex.split(subprocess.check_output(["pkg-config","--cflags","--libs","gtk+-3.0"],text=True))
        subprocess.run(["c++","-std=c++17","-O2","-Wall","-Wextra","-Werror",str(source),"-I"+str(project/"packages/window_manager/linux"),*flags,"-o",str(binary)],check=True)
        runtime=folder/"runtime";runtime.mkdir(mode=0o700)
        env=dict(os.environ,GDK_BACKEND="x11",NO_AT_BRIDGE="1",GIO_USE_VFS="local",GSETTINGS_BACKEND="memory",XDG_RUNTIME_DIR=str(runtime),XDG_CONFIG_HOME=str(folder/"config"),XDG_DATA_HOME=str(folder/"data"),XDG_CACHE_HOME=str(folder/"cache"))
        subprocess.run(["xvfb-run","-a","dbus-run-session","--",str(binary)],env=env,check=True,timeout=15)
if __name__=="__main__":main()
