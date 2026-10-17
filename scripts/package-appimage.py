#!/usr/bin/env python3
"""Bundle a built Linux release, including GTK/WebKit, as an x86_64 AppImage.

Build on Ubuntu 24.04 for the published glibc 2.39 baseline. Graphics drivers
and glibc deliberately come from the host; application libraries do not.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
TOOL_URL = "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
TOOL_SHA256 = "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
HOST_LIBRARIES = re.compile(
    r"^(?:ld-linux.*|lib(?:c|m|dl|pthread|rt|resolv|nss_[^.]+)\.so.*|"
    r"lib(?:EGL|GL|GLX|GLdispatch|OpenGL|vulkan|drm[^.]*|gbm)\.so.*)$"
)


def run(*args: str, **kwargs) -> str:
    return subprocess.check_output(args, text=True, **kwargs).strip()


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy_tree(source: Path, destination: Path) -> None:
    if source.exists():
        shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=False)


def relocate_webkit_library(path: Path, original: Path) -> list[dict]:
    """Relocate production WebKit's compiled helper paths without host writes.

    Release WebKit ignores WEBKIT_EXEC_PATH. The kernel's /proc/self/cwd gives
    these helpers a stable absolute path after AppRun enters its own usr tree.
    Each full NUL-terminated string keeps exactly the same byte length, so no
    ELF offsets, code, symbols, or library metadata change.
    """
    source = path.read_bytes()
    old = str(original).encode()
    new = b"/proc/self/cwd/lib/webkit2gtk-4.1"
    patches = []
    pattern = re.compile(re.escape(old) + rb"[^\x00]*\x00")

    def replace(match):
        previous = match.group()[:-1]
        updated = new + previous[len(old):]
        if len(updated) > len(previous):
            raise RuntimeError("WebKit helper relocation exceeds ELF string space")
        patches.append({"from": previous.decode(), "to": updated.decode()})
        return updated + b"\0" * (len(previous) + 1 - len(updated))

    updated = pattern.sub(replace, source)
    if not patches:
        raise RuntimeError("Cannot locate compiled WebKit helper paths; review this WebKit version before packaging")
    path.write_bytes(updated)
    return patches


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=ROOT / "build/linux/x64/release/bundle")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/Orion-x86_64.AppImage")
    parser.add_argument("--appdir-only", action="store_true")
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    for filename in ["orion", "lib/libapp.so", "lib/libflutter_linux_gtk.so", "data/monaco/index.html"]:
        if not (bundle / filename).is_file():
            raise RuntimeError(f"Missing release bundle file: {filename}. Run scripts/build-linux.sh first.")
    for command in ["patchelf", "desktop-file-validate"]:
        if not shutil.which(command):
            raise RuntimeError(f"Install the packaging dependency: {command}")
    appdir = ROOT / "build/appimage/Orion.AppDir"
    if appdir.exists():
        shutil.rmtree(appdir)
    usr = appdir / "usr"
    copy_tree(bundle, usr)
    libraries = usr / "lib"
    library_dir = Path(run("pkg-config", "--variable=libdir", "webkit2gtk-4.1"))
    webkit = library_dir / "webkit2gtk-4.1"
    if not (webkit / "WebKitWebProcess").exists():
        raise RuntimeError(f"WebKit helper executables not found in {webkit}")
    copy_tree(webkit, libraries / "webkit2gtk-4.1")

    # Dynamic modules are not reported by ldd. Include both the modules and
    # their recursively resolved shared libraries.
    for name in ["gio/modules", "gdk-pixbuf-2.0/2.10.0/loaders", "gtk-3.0/3.0.0/immodules"]:
        copy_tree(library_dir / name, libraries / name)
    schema = Path("/usr/share/glib-2.0/schemas/gschemas.compiled")
    if schema.exists():
        (usr / "share/glib-2.0/schemas").mkdir(parents=True)
        shutil.copy2(schema, usr / "share/glib-2.0/schemas/gschemas.compiled")

    queue = [p for p in usr.rglob("*") if p.is_file() and p.open("rb").read(4) == b"\x7fELF"]
    visited = set()
    origins: dict[str, str] = {}
    while queue:
        elf = queue.pop()
        if elf in visited:
            continue
        visited.add(elf)
        result = subprocess.run(["ldd", str(elf)], text=True, capture_output=True)
        if "not found" in result.stdout:
            raise RuntimeError(f"Missing shared library in {elf}:\n{result.stdout}")
        for name, location in re.findall(r"^\s*(\S+)\s+=>\s+(/\S+)", result.stdout, re.MULTILINE):
            if HOST_LIBRARIES.match(name):
                continue
            source = Path(location)
            destination = libraries / name
            if destination.exists():
                continue
            shutil.copy2(source.resolve(), destination)
            origins[name] = str(source.resolve())
            queue.append(destination)

    libwebkit = libraries / "libwebkit2gtk-4.1.so.0"
    patches = relocate_webkit_library(libwebkit, webkit)
    for elf in visited:
        if elf.exists():
            relative = os.path.relpath(libraries, elf.parent)
            subprocess.run(["patchelf", "--set-rpath", "$ORIGIN" if relative == "." else f"$ORIGIN/{relative}", str(elf)], check=True)

    # Keep distribution copyright notices beside the bundled libraries.
    notices = usr / "share/doc/orion-bundled-libraries"
    notices.mkdir(parents=True)
    for source in sorted(set(origins.values())):
        result = subprocess.run(["dpkg-query", "-S", source], text=True, capture_output=True)
        if result.returncode == 0 and ": " in result.stdout:
            package = result.stdout.split(": ", 1)[0].split(":", 1)[0]
            copyright_file = Path("/usr/share/doc") / package / "copyright"
            if copyright_file.exists():
                shutil.copy2(copyright_file, notices / f"{package}.copyright")
    (notices / "bundle-manifest.json").write_text(json.dumps({
        "minimumGlibc": "2.39", "libraries": origins, "webkitRelocations": patches,
        "relocationSource": "scripts/package-appimage.py",
        "librarySources": "Corresponding distribution sources are available through apt source <package>; package names are the copyright filenames.",
    }, indent=2) + "\n")

    shutil.copy2(ROOT / "scripts/appimage-AppRun", appdir / "AppRun")
    (appdir / "AppRun").chmod(0o755)
    desktop = """[Desktop Entry]
Type=Application
Name=Orion
Comment=Orion script workspace
Exec=orion
Icon=dev.snooped.orion
Terminal=false
Categories=Development;IDE;
StartupWMClass=dev.snooped.orion
"""
    (appdir / "dev.snooped.orion.desktop").write_text(desktop)
    subprocess.run(["desktop-file-validate", str(appdir / "dev.snooped.orion.desktop")], check=True)
    shutil.copy2(ROOT / "assets/branding/orion-icon.png", appdir / "dev.snooped.orion.png")
    (appdir / ".DirIcon").symlink_to("dev.snooped.orion.png")
    if args.appdir_only:
        print(appdir)
        return
    cache = Path(os.environ.get("ORION_PACKAGING_CACHE", ROOT / "build/downloads"))
    cache.mkdir(parents=True, exist_ok=True)
    tool = cache / "appimagetool-x86_64.AppImage"
    if not tool.exists():
        urllib.request.urlretrieve(TOOL_URL, tool)
    if digest(tool) != TOOL_SHA256:
        raise RuntimeError(f"AppImage tool checksum mismatch: delete {tool} and retry")
    tool.chmod(0o755)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ | {"APPIMAGE_EXTRACT_AND_RUN": "1", "ARCH": "x86_64", "SOURCE_DATE_EPOCH": os.environ.get("SOURCE_DATE_EPOCH", "0")}
    subprocess.run([str(tool.resolve()), "--no-appstream", str(appdir), str(args.output.resolve())], check=True, env=environment)
    args.output.chmod(0o755)
    args.output.with_suffix(args.output.suffix + ".sha256").write_text(f"{digest(args.output)}  {args.output.name}\n")
    print(f"AppImage: {args.output}")


if __name__ == "__main__":
    main()
