#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
flutter_bin="${FLUTTER_BIN:-flutter}"
# Some distros leave a newer GCC directory without the C++ development files.
# Point Clang at the newest complete installation in that case.
if command -v clang++ >/dev/null 2>&1 && [[ -z "${CXXFLAGS:-}" ]]; then
  selected_gcc="$(clang++ -v -x c++ -E /dev/null 2>&1 | sed -n 's/^Selected GCC installation: //p')"
  if [[ -n "$selected_gcc" && ! -e "$selected_gcc/libstdc++.so" ]]; then
    while IFS= read -r gcc_path; do
      if [[ -e "$gcc_path/libstdc++.so" ]]; then
        export CXXFLAGS="--gcc-install-dir=$gcc_path"
        break
      fi
    done < <(find /usr/lib/gcc -mindepth 2 -maxdepth 2 -type d | sort -Vr)
  fi
fi
"$flutter_bin" pub get
"$flutter_bin" build linux --release --no-tree-shake-icons
printf '\nLinux app: build/linux/x64/release/bundle/orion\n'
