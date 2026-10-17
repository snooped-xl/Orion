#!/usr/bin/env python3
"""Extract and launch the actual AppImage with an isolated, disposable profile."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
image = ROOT / "dist/Orion-x86_64.AppImage"
with tempfile.TemporaryDirectory(prefix="orion-appimage-smoke-") as temporary:
    directory = Path(temporary)
    subprocess.run([str(image), "--appimage-extract"], cwd=directory, stdout=subprocess.DEVNULL, check=True)
    appdir = directory / "squashfs-root"
    assert (appdir / "usr/lib/webkit2gtk-4.1/WebKitWebProcess").is_file()
    assert (appdir / "usr/data/monaco/index.html").is_file()
    workspace = directory / "workspace"
    workspace.mkdir()
    (workspace / "orion-workspace.json").write_text(json.dumps({
        "version": 2, "introCompleted": True, "reducedMotion": True,
        "documents": [{"id": "package-smoke", "name": "untitled.lua", "content": "print(\"package smoke\")", "savedContent": "", "filePath": None}],
        "activeDocumentId": "package-smoke", "selectedInterface": "orion",
    }))
    env = os.environ | {"ORION_WORKSPACE": str(workspace), "XDG_CONFIG_HOME": str(directory / "config"), "XDG_CACHE_HOME": str(directory / "cache"), "XDG_DATA_HOME": str(directory / "data")}
    with (directory / "app.log").open("w+") as log:
        process = subprocess.Popen([str(appdir / "AppRun")], env=env, stdout=log, stderr=log, start_new_session=True)
        try:
            deadline = time.monotonic() + 30
            bridge = workspace / "scripts/Special/Orion Bridge.lua"
            while time.monotonic() < deadline and process.poll() is None:
                if bridge.is_file() and (workspace / ".orion-workspace.json").is_file():
                    time.sleep(5)
                    break
                time.sleep(0.25)
            if process.poll() is not None:
                log.seek(0)
                raise RuntimeError(f"AppImage exited early ({process.returncode}):\n{log.read()}")
            if not bridge.is_file():
                log.seek(0)
                raise RuntimeError(f"AppImage did not provision its workspace:\n{log.read()}")
            descendants = []
            pending = [process.pid]
            while pending:
                pid = pending.pop()
                try:
                    children = [int(p) for p in Path(f"/proc/{pid}/task/{pid}/children").read_text().split()]
                    pending.extend(children)
                    descendants.extend(children)
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
            helpers = []
            for pid in descendants:
                try:
                    executable = os.readlink(f"/proc/{pid}/exe")
                    if executable.startswith(str(appdir)) and executable.endswith("WebKitWebProcess"):
                        helpers.append(executable)
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
            if not helpers:
                log.seek(0)
                raise RuntimeError(f"AppImage did not launch its bundled WebKit editor process:\n{log.read()}")
            print(json.dumps({"success": True, "appImageLaunched": True, "workspaceProvisioned": True, "bundledWebKitEditorRunning": True}))
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
