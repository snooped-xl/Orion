#!/usr/bin/python3
"""Install Orion's optional compositor companion without changing other extensions.

--enable uses GNOME's public API. A fresh local install may be loaded immediately
only when GNOME Shell already permits Eval; this helper never enables unsafe
mode. Otherwise it reports that login again is required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

from gi.repository import Gio, GLib

UUID = 'orion-glass@orion.local'
SOURCE = Path(__file__).resolve().parent / UUID
BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(destination, path, interface, method, arguments=None, signature=None, result=None):
    return BUS.call_sync(destination, path, interface, method,
                         GLib.Variant(signature, arguments) if signature else None,
                         GLib.VariantType.new(result) if result else None,
                         Gio.DBusCallFlags.NONE, 4000, None).unpack()


def digest(directory):
    value = hashlib.sha256()
    for file in sorted(directory.rglob('*')):
        if file.is_file() and file.name != '.orion-build':
            value.update(str(file.relative_to(directory)).encode())
            value.update(file.read_bytes())
    return value.hexdigest()


def emit(**value):
    print(json.dumps(value))
    return 0 if value.get('ok') else 2


def capabilities():
    try:
        return json.loads(call('org.orion.Glass', '/org/orion/Glass',
                               'org.orion.Glass1', 'GetCapabilities', result='(s)')[0])
    except GLib.Error:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enable', action='store_true')
    parser.add_argument('--disable', action='store_true')
    options = parser.parse_args()
    if options.disable:
        disabled = call('org.gnome.Shell.Extensions', '/org/gnome/Shell/Extensions',
                        'org.gnome.Shell.Extensions', 'DisableExtension', (UUID,), '(s)', '(b)')[0]
        return emit(ok=disabled, active=False, reason='disabled' if disabled else 'not-installed')

    # The compositor runs on the host, outside Flatpak's redirected XDG data.
    # The package shares the user's home for scripts and this optional helper.
    data_home = (os.environ.get('HOST_XDG_DATA_HOME', Path.home() / '.local/share')
                 if os.environ.get('FLATPAK_ID') else
                 os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    target = Path(data_home) / 'gnome-shell/extensions' / UUID
    if target.is_symlink():
        return emit(ok=False, active=False, reason='extension-directory-is-symlink')
    fingerprint = digest(SOURCE)
    if target.exists() and digest(target) != fingerprint:
        return emit(ok=False, active=capabilities() is not None,
                    reason='different-version-installed-login-again-required')
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix='.orion-glass-', dir=target.parent))
        try:
            shutil.copytree(SOURCE, temporary, dirs_exist_ok=True)
            (temporary / '.orion-build').write_text(fingerprint)
            temporary.rename(target)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)
    if not options.enable:
        return emit(ok=True, installed=True, active=capabilities() is not None, reason='installed')

    user_enabled = call('org.gnome.Shell.Extensions', '/org/gnome/Shell/Extensions',
                        'org.freedesktop.DBus.Properties', 'Get',
                        ('org.gnome.Shell.Extensions', 'UserExtensionsEnabled'), '(ss)', '(v)')[0]
    if not user_enabled:
        return emit(ok=False, installed=True, active=False, reason='user-extensions-disabled')
    known = call('org.gnome.Shell.Extensions', '/org/gnome/Shell/Extensions',
                 'org.gnome.Shell.Extensions', 'EnableExtension', (UUID,), '(s)', '(b)')[0]
    if not known:
        # GNOME 46 does not expose a public local-extension reload method. This
        # narrowly scoped bootstrap works only if the session already permits
        # Eval; no security flags or other extension state are changed here.
        code = '''(async()=>{
          const Main=await import('resource:///org/gnome/shell/ui/main.js');
          const Gio=(await import('gi://Gio')).default;
          const {ExtensionType}=await import('resource:///org/gnome/shell/misc/extensionUtils.js');
          const uuid=UUID_VALUE;
          let extension=Main.extensionManager.lookup(uuid);
          if(!extension){
            extension=Main.extensionManager.createExtensionObject(uuid,Gio.File.new_for_path(PATH_VALUE),ExtensionType.PER_USER);
            await Main.extensionManager.loadExtension(extension);
          }
          return Main.extensionManager.enableExtension(uuid);
        })()'''.replace('UUID_VALUE', json.dumps(UUID)).replace('PATH_VALUE', json.dumps(str(target)))
        allowed, value = call('org.gnome.Shell', '/org/gnome/Shell', 'org.gnome.Shell',
                              'Eval', (code,), '(s)', '(bs)')
        if not allowed or value != 'true':
            return emit(ok=False, installed=True, active=False, reason='installed-log-out-required')
    for _ in range(20):
        result = capabilities()
        if result:
            return emit(ok=True, installed=True, active=True, reason='enabled', capabilities=result)
        time.sleep(.1)
    return emit(ok=False, installed=True, active=False, reason='extension-not-ready')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (GLib.Error, OSError, ValueError) as error:
        sys.exit(emit(ok=False, active=False, reason=str(error)))
