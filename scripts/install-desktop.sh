#!/usr/bin/env bash
# Registers this portable Orion installation for the current desktop user.
# Re-run after moving the bundle. The original icon is copied without resizing.
set -euo pipefail

orion_app_id=dev.snooped.orion
orion_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  printf 'Usage: %s [BUNDLE_DIRECTORY]\n' "${0##*/}"
  printf 'Install Orion in the current user\047s application menu. No root access needed.\n'
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  usage
  exit 0
fi
if (( $# > 1 )); then
  usage >&2
  exit 2
fi

orion_bundle_dir=''
if (( $# == 1 )); then
  orion_bundle_dir="$(cd -- "$1" && pwd -P)"
else
  # The same installer works beside a portable binary or from source/scripts.
  for orion_candidate in \
    "$orion_script_dir" \
    "$orion_script_dir/../../Orion-Linux" \
    "$orion_script_dir/../build/linux/"*/release/bundle; do
    if [[ -x "$orion_candidate/orion" ]]; then
      orion_bundle_dir="$(cd -- "$orion_candidate" && pwd -P)"
      break
    fi
  done
fi
if [[ -z "$orion_bundle_dir" || ! -x "$orion_bundle_dir/orion" ]]; then
  printf 'No built Orion bundle found. Pass the directory containing the orion executable.\n' >&2
  exit 1
fi

orion_launcher="$orion_bundle_dir/launch.sh"
if [[ ! -x "$orion_launcher" ]]; then
  # Flutter's raw build bundle has no launch.sh; the binary finds assets itself.
  orion_launcher="$orion_bundle_dir/orion"
fi
orion_icon_source="$orion_bundle_dir/data/flutter_assets/assets/branding/orion-icon.png"
if [[ ! -f "$orion_icon_source" ]]; then
  printf 'The bundle is missing assets/branding/orion-icon.png.\n' >&2
  exit 1
fi

orion_template=''
for orion_candidate in \
  "$orion_script_dir/dev.snooped.orion.desktop.in" \
  "$orion_script_dir/../linux/packaging/dev.snooped.orion.desktop.in"; do
  if [[ -f "$orion_candidate" ]]; then
    orion_template="$orion_candidate"
    break
  fi
done
if [[ -z "$orion_template" ]]; then
  printf 'The desktop entry template is missing beside the installer.\n' >&2
  exit 1
fi

orion_data_home="${XDG_DATA_HOME:-${HOME:?HOME is required}/.local/share}"
if [[ "$orion_data_home" != /* ]]; then
  printf 'XDG_DATA_HOME must be an absolute directory path.\n' >&2
  exit 1
fi
if [[ "$orion_launcher" =~ [[:cntrl:]] ]]; then
  printf 'Desktop launchers cannot use a bundle path containing control characters.\n' >&2
  exit 1
fi

# Exec has two escaping passes: desktop string decoding, then argument parsing.
# A literal percent must also survive field-code expansion. Keep env as the
# executable so GLib's executable discovery handles percent signs in paths too.
orion_quoted_launcher='"'
for (( orion_i=0; orion_i<${#orion_launcher}; orion_i++ )); do
  orion_character="${orion_launcher:orion_i:1}"
  case "$orion_character" in
    '\') orion_quoted_launcher+='\\\\' ;;
    '"'|'$'|'`') orion_quoted_launcher+='\\'; orion_quoted_launcher+="$orion_character" ;;
    '%') orion_quoted_launcher+='%%' ;;
    *) orion_quoted_launcher+="$orion_character" ;;
  esac
done
orion_quoted_launcher+='"'

orion_applications="$orion_data_home/applications"
orion_icon_theme="$orion_data_home/icons/hicolor"
# scalable/apps is declared by the system hicolor index; arbitrary 859x859
# directories are not. GTK scales this original PNG when requesting dock sizes.
orion_icon_directory="$orion_icon_theme/scalable/apps"
mkdir -p -- "$orion_applications" "$orion_icon_directory"
orion_desktop_tmp=''
orion_icon_tmp=''
cleanup() {
  if [[ -n "$orion_desktop_tmp" && -f "$orion_desktop_tmp" ]]; then
    rm -- "$orion_desktop_tmp"
  fi
  if [[ -n "$orion_icon_tmp" && -f "$orion_icon_tmp" ]]; then
    rm -- "$orion_icon_tmp"
  fi
}
trap cleanup EXIT
orion_desktop_tmp="$(mktemp --suffix=.desktop "$orion_applications/.$orion_app_id.XXXXXX")"
while IFS= read -r orion_line || [[ -n "$orion_line" ]]; do
  if [[ "$orion_line" == 'Exec=@ORION_EXEC@' ]]; then
    printf 'Exec=/usr/bin/env %s\n' "$orion_quoted_launcher"
  else
    printf '%s\n' "$orion_line"
  fi
done < "$orion_template" > "$orion_desktop_tmp"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$orion_desktop_tmp"
fi

orion_icon_tmp="$(mktemp "$orion_icon_directory/.$orion_app_id.XXXXXX")"
cat -- "$orion_icon_source" > "$orion_icon_tmp"
chmod 644 -- "$orion_icon_tmp" "$orion_desktop_tmp"
mv -- "$orion_icon_tmp" "$orion_icon_directory/$orion_app_id.png"
mv -- "$orion_desktop_tmp" "$orion_applications/$orion_app_id.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  if ! update-desktop-database "$orion_applications"; then
    printf 'Launcher installed; desktop database refresh was unavailable.\n' >&2
  fi
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  if ! gtk-update-icon-cache --force --ignore-theme-index "$orion_icon_theme"; then
    printf 'Icon installed; icon cache refresh was unavailable.\n' >&2
  fi
fi
printf 'Installed %s\nIcon: %s\nLauncher: %s\n' \
  "$orion_applications/$orion_app_id.desktop" \
  "$orion_icon_directory/$orion_app_id.png" \
  "$orion_launcher"
