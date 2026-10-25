#!/usr/bin/env python3
"""Install the actual bundle privately, then launch it with a disposable profile.

Installed runtimes are referenced read-only. The normal user app installation,
workspace, and desktop launcher are never replaced by this packaging check.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import select
import socket
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "dev.snooped.orion"
image = ROOT / "dist/Orion-x86_64.flatpak"
runtime_location = Path(subprocess.check_output(
    ["flatpak", "info", "--show-location", "org.gnome.Platform//50"], text=True).strip())
runtime_tree = next(p for p in [runtime_location, *runtime_location.parents] if p.name == "runtime")

smoke_directory = ROOT / "build/package-smoke/flatpak"
smoke_directory.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="private-", dir=smoke_directory) as temporary:
    directory = Path(temporary)
    installation = directory / "installation"
    installation.mkdir()
    (installation / "runtime").symlink_to(runtime_tree, target_is_directory=True)
    env = os.environ | {"FLATPAK_USER_DIR": str(installation)}
    subprocess.run(["flatpak", "install", "--user", "--noninteractive", "--no-deps", str(image)], env=env, check=True)
    libraries = subprocess.check_output(["flatpak", "run", "--command=sh", APP_ID,
        "-c", "ldd /app/orion/orion"], env=env, text=True, stderr=subprocess.STDOUT)
    if "not found" in libraries:
        raise RuntimeError(f"Unresolved native dependencies in Flatpak runtime:\n{libraries}")
    # Relapse publishes one socket per profile alongside the default one, and
    # the launcher socket only appears once a client is running. Both must be
    # reachable inside the sandbox, so check the default and a profile socket.
    relapse_paths = [Path("/tmp/relapse.sock"), Path("/tmp/relapse-Smoke.sock")]
    for path in relapse_paths:
        if path.exists() or path.is_symlink():
            raise RuntimeError(f"Refusing to replace an existing {path}")
    relapse_sockets = []
    try:
        for path in relapse_paths:
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(str(path))
            listener.listen(1)
            relapse_sockets.append(listener)
        visible = subprocess.run(["flatpak", "run", "--command=sh", APP_ID,
            "-c", " ".join(f"test -S {path} &&" for path in relapse_paths) + " true"],
            env=env, check=False)
        if visible.returncode != 0:
            raise RuntimeError("Flatpak cannot see the Relapse profile Unix sockets")
    finally:
        for listener in relapse_sockets:
            listener.close()
        for path in relapse_paths:
            path.unlink(missing_ok=True)
    workspace = directory / "workspace"
    workspace.mkdir()
    (workspace / "orion-workspace.json").write_text(json.dumps({
        "version": 2, "introCompleted": True, "reducedMotion": True,
        "documents": [{"id": "package-smoke", "name": "untitled.lua", "content": "print(\"package smoke\")", "savedContent": "", "filePath": None}],
        "activeDocumentId": "package-smoke", "selectedInterface": "orion",
    }))
    read_fd, write_fd = os.pipe()
    instance = None
    process = None
    try:
        with (directory / "app.log").open("w+") as log:
            process = subprocess.Popen(["flatpak", "run", f"--instance-id-fd={write_fd}",
                f"--env=ORION_WORKSPACE={workspace}", APP_ID],
                env=env, stdout=log, stderr=log, pass_fds=(write_fd,))
            os.close(write_fd)
            write_fd = -1
            if not select.select([read_fd], [], [], 20)[0]:
                raise RuntimeError("Flatpak did not report its instance ID")
            instance = os.read(read_fd, 256).decode().strip()
            deadline = time.monotonic() + 40
            bridge = workspace / "scripts/Special/Orion Bridge.lua"
            while time.monotonic() < deadline and process.poll() is None:
                if bridge.is_file() and (workspace / ".orion-workspace.json").is_file():
                    time.sleep(5)
                    break
                time.sleep(0.25)
            if process.poll() is not None:
                log.seek(0)
                raise RuntimeError(f"Flatpak exited early ({process.returncode}):\n{log.read()}")
            if not bridge.is_file():
                log.seek(0)
                raise RuntimeError(f"Flatpak did not provision its workspace:\n{log.read()}")
            instances = subprocess.check_output(["flatpak", "ps", "--columns=instance,child-pid"], env=env, text=True)
            match = next((row.split() for row in instances.splitlines() if row.split() and row.split()[0] == instance), None)
            if not match or len(match) < 2:
                raise RuntimeError("The launched Flatpak instance is missing")
            descendants = []
            pending = [int(match[1])]
            while pending:
                pid = pending.pop()
                try:
                    children = [int(p) for p in Path(f"/proc/{pid}/task/{pid}/children").read_text().split()]
                    pending.extend(children)
                    descendants.extend(children)
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
            editors = []
            for pid in descendants:
                try:
                    executable = os.readlink(f"/proc/{pid}/exe")
                    if executable.endswith("WebKitWebProcess"):
                        editors.append(executable)
                except (FileNotFoundError, PermissionError, ProcessLookupError):
                    pass
            if not editors:
                log.seek(0)
                raise RuntimeError(f"Flatpak did not start its genuine WebKit editor process:\n{log.read()}")
            result = {"success": True, "flatpakInstalled": True, "flatpakLaunched": True,
                "workspaceProvisioned": True, "runtimeDependenciesResolved": True,
                "relapseProfileSocketsVisible": True,
                "genuineWebKitEditorRunning": True}
            output = ROOT / "build/package-smoke/flatpak/report.json"
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result))
    finally:
        os.close(read_fd)
        if write_fd >= 0:
            os.close(write_fd)
        if instance:
            subprocess.run(["flatpak", "kill", instance], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if process:
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        # Remove only this private installation's files. The runtime link is
        # detached first so cleanup cannot follow it into installed runtimes.
        (installation / "runtime").unlink(missing_ok=True)
