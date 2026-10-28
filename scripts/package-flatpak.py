#!/usr/bin/env python3
"""Package Orion's Linux release against the cross-distribution GNOME runtime.

The source is compiled by Flutter first. Flatpak supplies glibc, GTK, WebKit,
graphics drivers, and portals consistently on supported Linux distributions.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

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
    parser.add_argument("--work-dir", type=Path, default=ROOT / "build/flatpak")
    args = parser.parse_args()
    if not shutil.which("flatpak"):
        raise RuntimeError("Install Flatpak before packaging")
    bundle = args.bundle.resolve()
    for filename in ["orion", "lib/libapp.so", "lib/libflutter_linux_gtk.so", "data/monaco/index.html",
                     "data/gnome/orion-glass@orion.local/dist/rendering/backdropGlass.js"]:
        if not (bundle / filename).is_file():
            raise RuntimeError(f"Missing Linux release file: {filename}. Run scripts/build-linux.sh first.")
    build = args.work_dir.resolve() / "application"
    repository = args.work_dir.resolve() / "repository"
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
    # A Windows checkout may contain CRLF. Linux shebangs require LF even when
    # the package is assembled through WSL from that checkout.
    (files / "bin/orion").write_text(
        (ROOT / "scripts/flatpak-launcher").read_text(), newline="\n")
    (files / "bin/orion").chmod(0o755)
    glass_installer = files / "orion/install-gnome-glass.sh"
    glass_installer.write_text(glass_installer.read_text(), newline="\n")
    applications = files / "share/applications"
    applications.mkdir(parents=True)
    template = (ROOT / "linux/packaging/dev.snooped.orion.desktop.in").read_text()
    (applications / f"{APP_ID}.desktop").write_text(template.replace("@ORION_EXEC@", "orion"))
    icons = files / "share/icons/hicolor/512x512/apps"
    icons.mkdir(parents=True)
    # Flatpak validates exported icons without loading embedded SVG images.
    # Export a normal sized PNG, using the image loader already supplied by GTK.
    run("gdk-pixbuf-thumbnailer", "-s", "512",
        str(ROOT / "assets/branding/orion-icon.png"),
        str(icons / f"{APP_ID}.png"))
    metainfo = files / "share/metainfo"
    metainfo.mkdir(parents=True)
    shutil.copy2(ROOT / "linux/packaging/dev.snooped.orion.metainfo.xml", metainfo)
    run("flatpak", "build-finish", "--command=orion", "--require-version=1.12.0",
        "--share=network", "--share=ipc", "--socket=wayland", "--socket=x11",
        "--socket=pulseaudio", "--socket=session-bus", "--device=dri",
        # Relapse exposes one socket per profile (/tmp/relapse-<Profile>.sock)
        # next to the default /tmp/relapse.sock, so grant the whole directory.
        # A narrower path grant also hides a socket created after the sandbox
        # mounts, which left every profile invisible inside the Flatpak.
        "--filesystem=home", "--filesystem=/tmp",
        "--filesystem=/media", "--filesystem=/mnt",
        "--filesystem=/run/media",
        "--talk-name=org.freedesktop.Flatpak",
        "--env=GTK_USE_PORTAL=1", str(build))
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
