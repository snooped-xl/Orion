Based on window_manager 0.5.2 (MIT LICENSE retained).

Linux stores and removes its process-wide mouse emission hook when the per-engine plugin is disposed. Without removal, every later mouse click writes through the destroyed plugin pointer, corrupting the process heap after a companion closes. The hook is also filtered to the originating window, so dragging/resizing uses that window's actual mouse event. title_bar_style_ is cleared safely for repeated GObject disposal. Public APIs and other platforms are unchanged.

Window signal handlers use GObject lifetime-aware connections so GTK cannot deliver late hide/focus/resize callbacks to a disposed engine plugin.

Linux resize notifications follow actual top-level size allocations, with repeated logical size/scale tuples filtered. Child-only layout passes no longer generate redundant resize platform messages. Real size and DPI changes retain their notifications.
