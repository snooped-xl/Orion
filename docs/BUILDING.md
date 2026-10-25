# Build Orion

Orion is a Flutter desktop application for Windows x64 and Linux x64. The
project uses Flutter **3.47.7**, Dart **3.13.5**, C++ runners, and bundled Monaco
Editor assets. Keep `pubspec.lock` and the patched packages in `packages/`.

## Download Orion

Get the Windows EXE or Linux Flatpak from the
[Latest release](https://github.com/snooped-xl/Orion/releases/latest).

## Build validation with GitHub Actions

Open the repository's **Actions** tab, choose **Desktop test builds**, then
**Run workflow** on the main branch. Pushes to the main branch also build both
platforms. A successful run provides:

| Artifact | File |
| --- | --- |
| `Orion-Windows-x64` | `Orion.exe` |
| `Orion-Flatpak-x86_64` | `Orion-x86_64.flatpak` |

GitHub wraps artifacts in a ZIP. Extract it first. The accompanying `.sha256`
file records the download checksum. These development builds are unsigned.

The Windows download is one portable EXE. It contains the full Flutter app,
assets, plugins, Visual C++ DLLs, and a fixed Microsoft WebView2 runtime. On its
first launch it extracts those files under
`%LOCALAPPDATA%\Orion\Runtime\<content-hash>`, then opens Orion. It does not
require Flutter, Visual Studio, a separate browser installation, or administrator
access on the target machine. New builds use a new cache directory, so they do
not overwrite DLLs used by a running older build. This is a self-extracting app,
not a Flutter runner EXE with its required DLLs omitted.

## User files and first launch

| Platform | Workspace |
| --- | --- |
| Linux | `~/orion` |
| Windows | `Documents\orion` in the user's actual Documents known folder |

Redirected Documents folders, including OneDrive Documents, are supported.
The workspace contains `scripts`, `autoexec`, `themes`, `cache`, and `backups`.
The bundled bridge lives at `scripts/Special/Orion Bridge.lua`.

First launch creates this structure and migrates a previous hidden Orion
workspace when available. Existing user scripts and settings are preserved.
Orion replaces its managed bridge on initial setup or a bundled bridge update;
a differing previous copy is backed up. Normal launches keep user changes.
The `.orion-workspace.json` marker tracks provisioning; the separate
`orion-workspace.json` file stores tabs, settings, and recovery state.

For development and automated tests, set `ORION_WORKSPACE` to an absolute
directory to isolate all workspace data. Do not point smoke tests at your
normal scripts folder.

## Windows: build and run

Use a 64-bit Windows 10 or Windows 11 machine. Flutter Windows builds must run
on Windows; a Linux Flutter SDK cannot produce a supported Windows desktop
release by cross-compiling.

Install:

1. [Flutter 3.47.7](https://docs.flutter.dev/install), available on `PATH`.
2. [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/) with
   **Desktop development with C++**, the Windows SDK, CMake tools, and the
   MSVC x64 build tools and redistributable files. Visual Studio Code alone
   does not supply these native build tools.
3. PowerShell 7 for the packaging scripts.
4. [NSIS 3](https://nsis.sourceforge.io/Download) to create the one-file build.
   `winget install NSIS.NSIS` is one installation option.

In PowerShell, from the repository root:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release --no-tree-shake-icons --target lib/main.dart
./scripts/prepare-windows-runtime.ps1
./build/windows/x64/runner/Release/orion.exe
```

The first runtime preparation downloads Microsoft's pinned WebView2 CAB,
checks its SHA-256, validates the Microsoft signature, and expands it beside
the app. It also copies the redistributable Visual C++ DLLs from Visual Studio.
The browser folder receives Microsoft's required AppContainer read/execute
permissions for Windows 10. The portable launcher applies the same permissions
after extraction; workspace files do not receive these permissions.
Downloads are cached in `build/downloads`; subsequent runs can use that cache.
WebView2 is deliberately pinned. When updating it, change the version, official
CAB URL, and SHA-256 together in `prepare-windows-runtime.ps1`, then rebuild and
rerun the native smoke test. Microsoft retains only recent fixed-runtime
downloads, so keep an archived CAB for reproducible older builds.

Create the portable EXE:

```powershell
./scripts/package-windows.ps1
./dist/Orion.exe
```

If distributing an unpackaged build instead, keep the **entire**
`build/windows/x64/runner/Release` directory together. The internal `orion.exe`
cannot run by itself. Monaco is served from `data/monaco`; WebView2 is in
`data/webview2`. Neither folder should be removed.

Windows uses WebView2 for the genuine Monaco editor, native Windows window
management, and the Windows compositor for supported transparent materials.
Linux WebKitGTK, GNOME extensions, D-Bus, and EGL lifetime patches are confined
to the Linux runner and are not linked into the Windows executable. Theme
appearance can vary with the operating system compositor and graphics driver.

## Linux: install the cross-distribution build

Orion is distributed as a **Flatpak** bundle. Flatpak supplies the GNOME 50
runtime, including glibc, GTK 3, WebKitGTK 4.1, graphics integration, and desktop
portals. This avoids requiring each distribution to provide matching native
library versions. An x86_64 Linux system with Flatpak and a graphical desktop
is required; Ubuntu, Fedora, Arch, Debian, and other Flatpak-supported
Linux distributions can use the same bundle.

Install [Flatpak for your distribution](https://flatpak.org/setup/), then run:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./Orion-x86_64.flatpak
flatpak run dev.snooped.orion
```

The first installation downloads the shared GNOME runtime if it is missing.
The `.flatpak` file includes Orion, its Flutter engine, plugins, fonts, Monaco,
and other application assets. It does not contain the shared runtime. After
the runtime is installed, Orion's editor, local scripts, and Bridge work
offline; remote script search still requires a network connection.

The package allows network access for script sources and Orion Bridge's
host loopback connection, the exact `/tmp/relapse.sock` path for optional
Relapse support, GPU rendering, Wayland and X11 windows, and access
to the user's home and mounted drives for scripts and files. It uses the
session bus directly so Orion's own GNOME compositor companion can verify the
real process that owns each window. It does not request Flatpak host-process
execution. Folder and browser opening and file dialogs use desktop portals.
The workspace remains `~/orion`, including when launched from Flatpak.

On Linux, **Settings → Relapse support** switches execution from Orion Bridge
to running Relapse GTK instances. Orion discovers `relapse.sock` and
`relapse-<profile>.sock` in `/tmp`, opens one channel set per profile it owns,
and prefers Relapse's session-v2 channel so scripts execute in the live game
session with output captured exactly once. Execution targets every ready
profile or only the selected ones. **Settings → Execution** stores the Relapse
executable so Orion can launch it without a shell.

The Flatpak grants access to `/tmp/relapse.sock`, not all of `/tmp`, so only
that profile is reachable from inside the sandbox. This option is hidden on
other platforms, and Orion does not bundle Relapse's GTK UI.

The optional GNOME companion supplies live behind-window refraction,
monitor-based launch placement, and Wayland topmost support on supported
GNOME sessions. Other desktops use the normal fallback. On GNOME, install it
with:

```bash
flatpak run --command=sh dev.snooped.orion -c 'cd /app/orion && ./install-gnome-glass.sh --enable'
```

Its files are installed in the host user's GNOME extensions directory. A new
extension installation may require logging out and back in. Other extensions
and their settings remain unchanged. See
[GNOME integration](../linux/gnome/README.md).

## Linux: build and package

The published native application is built on Ubuntu 24.04, then packaged
against GNOME 50. Flatpak provides the target runtime when installed on older
or different distributions; it does not use the host's glibc or GTK to run
Orion. A raw unpackaged bundle still needs compatible host libraries.

On Ubuntu 24.04 or an equivalent Debian-based development system:

```bash
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  libwebkit2gtk-4.1-dev libepoxy-dev libpng-dev libstdc++-13-dev \
  flatpak desktop-file-utils
flutter doctor -v
flutter config --enable-linux-desktop
./scripts/build-linux.sh
./build/linux/x64/release/bundle/orion
```

Other distributions need equivalent development packages. The compiler helper
in `build-linux.sh` handles an incomplete newer GCC installation when a
complete C++ installation is available.

Install the packaging runtime and produce the bundle:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub org.gnome.Platform//50
python3 scripts/package-flatpak.py
flatpak install --user dist/Orion-x86_64.flatpak
flatpak run dev.snooped.orion
```

`package-flatpak.py` stages the existing release with `flatpak build-init`,
finalizes desktop integration and permissions, exports a local OSTree
repository, and creates `dist/Orion-x86_64.flatpak` plus its SHA-256 file. Since
Flutter has already compiled the application, packaging needs the runtime but
not the much larger GNOME SDK or `flatpak-builder`. The runtime branch is
pinned to 50 and receives its supported bug and security updates separately
from Orion. Network access is needed to install the runtime the first time.

## Validation

```bash
flutter analyze
flutter test
```

CI additionally builds `tool/desktop_smoke.dart` as a real Windows release and
exercises native Monaco editing, snapshots, bridge clients, native windows,
interfaces, and themes. It then rebuilds `lib/main.dart` before packaging, so
the test entry point is never distributed. The final portable EXE is launched
separately and checked for its native window and first-run folders.

For a local Windows native smoke run:

```powershell
flutter build windows --release --no-tree-shake-icons --target tool/desktop_smoke.dart
./scripts/prepare-windows-runtime.ps1
./scripts/test-desktop-smoke.ps1
# Restore the actual app before packaging:
flutter build windows --release --no-tree-shake-icons --target lib/main.dart
./scripts/prepare-windows-runtime.ps1
./scripts/package-windows.ps1
./scripts/test-windows-package.ps1
```

Native browser snapshots cannot prove that text is visible in the final desktop
composition. For that check on Windows, use an interactive desktop and run:

```powershell
cmake -S windows/tests -B build/glass-tests -A x64
cmake --build build/glass-tests --config Release --target monaco_visible_test
flutter build windows --release --no-tree-shake-icons --target tool/monaco_visibility_smoke.dart
./scripts/test-monaco-visibility.ps1
# Restore the actual app before packaging:
flutter build windows --release --no-tree-shake-icons --target lib/main.dart
```

The fixture launches its own workspace, measures displayed text outside the
line-number gutter, and checks cold start, both glass themes, rain, theme return,
overlay return, and minimize/restore. The helper captures only the editor of the
fixture process over a controlled dark background. The equivalent Linux helper,
`tool/monaco_visible_test.py`, requires a privately owned Xvfb session identified
by `ORION_TEST_XVFB_PID`; the shared fixture receives its helper and output paths
through `ORION_MONACO_VISIBLE_HELPER` and `ORION_MONACO_VISIBLE_OUTPUT`.
After packaging the normal Windows entry point, run
`./scripts/test-windows-package.ps1 -VisibleTextHelper build/glass-tests/Release/monaco_visible_test.exe`
to check the actual portable download's displayed text as well.

Linux CI privately installs and launches the actual Flatpak bundle under a
disposable desktop session. It verifies resolved runtime dependencies, first-run
provisioning, and the genuine native WebKit editor process. Both platforms
isolate smoke-test data from the user's workspace. Build output and runtime caches are ignored
by Git; publish the generated distribution files as artifacts or releases.

Flutter's [Windows distribution guide](https://docs.flutter.dev/platform-integration/windows/building),
Microsoft's [WebView2 distribution guidance](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution),
and the [Flatpak distribution guide](https://docs.flatpak.org/en/latest/distributing-applications.html)
describe the platform requirements behind these scripts.
