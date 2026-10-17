#!/usr/bin/env python3
"""Verify compositor identity against a real private bus and PID namespace."""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile
import time


def private_bus(binary, folder):
    ready = folder / "ready"
    server = subprocess.Popen([str(binary), "--server", str(ready)])
    try:
        deadline = time.monotonic() + 5
        while not ready.exists():
            if server.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("Private credential verifier did not start")
            time.sleep(0.02)
        subprocess.run([str(binary)], check=True, timeout=10)
        subprocess.run([
            "unshare", "--user", "--map-current-user", "--pid", "--fork",
            str(binary), "--namespace-parent",
        ], check=True, timeout=10)
    finally:
        server.terminate()
        server.wait(timeout=5)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--private-bus":
        private_bus(Path(sys.argv[2]), Path(sys.argv[3]))
        return
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="orion-session-bus-") as directory:
        folder = Path(directory)
        binary = folder / "identity-test"
        flags = shlex.split(subprocess.check_output(
            ["pkg-config", "--cflags", "--libs", "gtk+-3.0"], text=True))
        subprocess.run([
            "c++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
            str(project / "test/native/session_bus_identity_test.cc"),
            "-I" + str(project / "linux/runner"), *flags, "-o", str(binary),
        ], check=True)
        runtime = folder / "runtime"
        runtime.mkdir(mode=0o700)
        subprocess.run([
            "xvfb-run", "-a", "dbus-run-session", "--", sys.executable, __file__,
            "--private-bus", str(binary), str(folder),
        ], env=dict(os.environ, XDG_RUNTIME_DIR=str(runtime), GDK_BACKEND="x11",
                    NO_AT_BRIDGE="1", GIO_USE_VFS="local"), check=True, timeout=30)


if __name__ == "__main__":
    main()
