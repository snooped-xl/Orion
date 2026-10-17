#!/usr/bin/env python3
"""Check lossless native Monaco PNGs and isolated worker/cache generations.

Uses generated image/alpha fixtures only: no display, desktop, profile or network.
Requires the project's generated Flutter Linux headers/runtime and native dev
packages used by its Linux build. Optional arguments are owned PNG captures to
compare/benchmark against the former Cairo encoder, with exact decoded pixels.
"""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile


def main():
    project = Path(__file__).resolve().parents[1]
    ephemeral = project / "linux/flutter/ephemeral"
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "gtk+-3.0", "webkit2gtk-4.1", "libpng"],
        text=True))
    with tempfile.TemporaryDirectory(prefix="orion-monaco-preview-") as directory:
        binary = Path(directory) / "preview_test"
        subprocess.run([
            "c++", "-std=c++14", "-O3", "-Wall", "-Werror",
            str(project / "tool/monaco_preview_test.cc"), "-I" + str(ephemeral),
            "-L" + str(ephemeral), "-Wl,-rpath," + str(ephemeral),
            "-lflutter_linux_gtk", *flags, "-o", str(binary),
        ], check=True)
        environment = dict(os.environ)
        for name in ("DISPLAY", "WAYLAND_DISPLAY", "LD_PRELOAD"):
            environment.pop(name, None)
        subprocess.run([str(binary), *sys.argv[1:]], env=environment,
                       check=True, timeout=30)


if __name__ == "__main__":
    main()
