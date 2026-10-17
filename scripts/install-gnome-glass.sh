#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
for directory in "$script_dir/../linux/gnome" "$script_dir/data/gnome" "$script_dir/../data/gnome"; do
  if [ -f "$directory/install-desktop-glass.py" ]; then
    exec /usr/bin/python3 "$directory/install-desktop-glass.py" "$@"
  fi
done
printf '%s\n' 'Orion Desktop Glass installer data is missing.' >&2
exit 2
