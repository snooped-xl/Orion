#ifndef WINDOW_MANAGER_WINDOW_RESIZE_STATE_H_
#define WINDOW_MANAGER_WINDOW_RESIZE_STATE_H_

// Trivial storage: GObject zero-initializes plugin instance memory.
struct WindowResizeState {
  int width;
  int height;
  int scale;
};

inline bool window_resize_changed(WindowResizeState* state, int width,
                                  int height, int scale) {
  if (width <= 0 || height <= 0 || scale <= 0) return false;
  if (state->width == width && state->height == height &&
      state->scale == scale) return false;
  state->width = width;
  state->height = height;
  state->scale = scale;
  return true;
}

#endif  // WINDOW_MANAGER_WINDOW_RESIZE_STATE_H_
