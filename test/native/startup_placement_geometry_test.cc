#include "../../linux/runner/startup_placement_geometry.h"
#include <cassert>
#include <iostream>

int main() {
  auto check = [](OrionPlacementRect monitor, OrionPlacementRect workarea,
                  int width, int height, int x, int y) {
    const auto result = orion_center_startup_window(monitor, workarea, width, height);
    assert(result.x == x && result.y == y);
    assert(result.width == width && result.height == height);
  };
  check({0, 0, 1920, 1080}, {0, 32, 1920, 1048}, 822, 523, 549, 279);
  check({1920, 0, 2560, 1440}, {1920, 32, 2560, 1408}, 1045, 648, 2678, 396);
  check({-1920, -400, 1920, 1080}, {-1920, -368, 1920, 1048}, 822, 523, -1371, -121);
  // Mixed-DPI monitor geometry is already logical: do not scale it twice.
  check({-1280, 0, 1280, 720}, {-1280, 32, 1280, 688}, 740, 470, -1010, 125);
  // A large reserved panel constrains placement without changing dimensions.
  check({0, 0, 1920, 1080}, {700, 32, 1220, 1048}, 822, 523, 700, 279);
  check({0, 0, 800, 600}, {0, 32, 800, 568}, 1045, 648, 0, 32);
  check({0, 0, 1920, 1080}, {0, 0, 0, 0}, 822, 523, 549, 279);
  std::cout << "Startup logical monitor centering: 7 cases passed\n";
}
