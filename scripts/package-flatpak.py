#!/usr/bin/env python3
"""Package Orion's Linux release against the cross-distribution GNOME runtime.

The source is compiled by Flutter first. Flatpak supplies glibc, GTK, WebKit,
graphics drivers, and portals consistently on supported Linux distributions.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
from pathlib import Path
import shutil
import subprocess
import struct

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "dev.snooped.orion"
RUNTIME = "org.gnome.Platform"
RUNTIME_VERSION = "50"
BRANCH = "stable"
RUNTIME_REPO = "https://dl.flathub.org/repo/flathub.flatpakrepo"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=ROOT / "build/linux/x64/release/bundle")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/Orion-x86_64.flatpak")
    args = parser.parse_args()
    if not shutil.which("flatpak"):
        raise RuntimeError("Install Flatpak before packaging")
    bundle = args.bundle.resolve()
    for filename in ["orion", "lib/libapp.so", "lib/libflutter_linux_gtk.so", "data/monaco/index.html"]:
        if not (bundle / filename).is_file():
            raise RuntimeError(f"Missing Linux release file: {filename}. Run scripts/build-linux.sh first.")
    build = ROOT / "build/flatpak/application"
    repository = ROOT / "build/flatpak/repository"
    if build.exists():
        shutil.rmtree(build)
    build.parent.mkdir(parents=True, exist_ok=True)
    # A complete GNOME SDK is unnecessary here: Flutter has already compiled
    # the native application, and packaging only copies its release files.
    run("flatpak", "build-init", "--arch=x86_64", str(build), APP_ID,
        RUNTIME, RUNTIME, RUNTIME_VERSION)
    files = build / "files"
    shutil.copytree(bundle, files / "orion", symlinks=False)
    (files / "bin").mkdir()
    shutil.copy2(ROOT / "scripts/flatpak-launcher", files / "bin/orion")
    (files / "bin/orion").chmod(0o755)
    applications = files / "share/applications"
    applications.mkdir(parents=True)
    template = (ROOT / "linux/packaging/dev.snooped.orion.desktop.in").read_text()
    (applications / f"{APP_ID}.desktop").write_text(template.replace("@ORION_EXEC@", "orion"))
    icons = files / "share/icons/hicolor/scalable/apps"
    icons.mkdir(parents=True)
    # Preserve the supplied pixels. An SVG canvas gives desktop icon renderers
    # a standard size without introducing another raster asset or dependency.
    image = (ROOT / "assets/branding/orion-icon.png").read_bytes()
    width, height = struct.unpack(">II", image[16:24])
    encoded = base64.b64encode(image).decode("ascii")
    (icons / f"{APP_ID}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 {width} {height}">'
        f'<image width="{width}" height="{height}" href="data:image/png;base64,{encoded}"/></svg>\n'
    )
    metainfo = files / "share/metainfo"
    metainfo.mkdir(parents=True)
    shutil.copy2(ROOT / "linux/packaging/dev.snooped.orion.metainfo.xml", metainfo)
    run("flatpak", "build-finish", "--command=orion", "--require-version=1.12.0",
        "--share=network", "--share=ipc", "--socket=wayland", "--socket=fallback-x11",
        "--socket=pulseaudio", "--socket=session-bus", "--device=dri",
        "--filesystem=home", "--filesystem=/media", "--filesystem=/mnt",
        "--filesystem=/run/media", "--env=GTK_USE_PORTAL=1", str(build))
    run("flatpak", "build-export", "--arch=x86_64", "--subject=Orion desktop test build",
        str(repository), str(build), BRANCH)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    run("flatpak", "build-bundle", "--arch=x86_64", f"--runtime-repo={RUNTIME_REPO}",
        str(repository), str(args.output.resolve()), APP_ID, BRANCH)
    with args.output.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    args.output.with_suffix(".flatpak.sha256").write_text(f"{checksum}  {args.output.name}\n")
    print(f"Flatpak bundle: {args.output}")


if __name__ == "__main__":
    main()
