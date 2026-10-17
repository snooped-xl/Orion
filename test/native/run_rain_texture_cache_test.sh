#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
rain_test_dir="$(mktemp -d)"
trap 'rm -rf "$rain_test_dir"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror test/native/rain_texture_cache_test.cc \
  -Ilinux/flutter/ephemeral \
  $(pkg-config --cflags --libs gtk+-3.0 epoxy) \
  -Llinux/flutter/ephemeral -lflutter_linux_gtk \
  -Wl,-rpath,"$PWD/linux/flutter/ephemeral" \
  -o "$rain_test_dir/rain_texture_cache_test"
GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  XDG_CONFIG_HOME="$rain_test_dir/config" \
  XDG_CACHE_HOME="$rain_test_dir/cache" \
  XDG_DATA_HOME="$rain_test_dir/data" \
  xvfb-run -a dbus-run-session -- "$rain_test_dir/rain_texture_cache_test"
