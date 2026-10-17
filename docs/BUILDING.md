# Build Orion

Orion is a Flutter desktop application for Windows x64 and Linux x64. The
project uses Flutter **3.47.7**, Dart **3.13.5**, C++ runners, and bundled Monaco
Editor assets. Keep `pubspec.lock` and the patched packages in `packages/`.

## Download a test build from GitHub Actions

Open the repository's **Actions** tab, choose **Desktop test builds**, then
**Run workflow** on the main branch. Pushes to the main branch also build both
platforms. A successful run provides:

| Artifact | File to run |
| --- | --- |
| `Orion-Windows-x64` | `Orion.exe` |
| `Orion-AppImage-x86_64` | `Orion-x86_64.AppImage` |

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
Downloads are cached in `build/downloads`; subsequent runs can use that cache.

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

## Linux: build and run

Published AppImages are built on Ubuntu 24.04 and require an x86_64 Linux
system with glibc 2.39 or newer and working desktop graphics drivers. They bundle
GTK, WebKitGTK, WebKit subprocesses, application libraries, fonts, and Monaco.
The host supplies glibc, the kernel, display server, and graphics drivers.

On Ubuntu 24.04 or an equivalent Debian-based development system:

```bash
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  libwebkit2gtk-4.1-dev libepoxy-dev libpng-dev libstdc++-13-dev \
  patchelf desktop-file-utils squashfs-tools
flutter doctor -v
flutter config --enable-linux-desktop
./scripts/build-linux.sh
./build/linux/x64/release/bundle/orion
```

Other distributions need equivalent development packages. The compiler helper
in `build-linux.sh` also handles an incomplete newer GCC installation when a
complete C++ installation is present.

Build the AppImage:

```bash
python3 scripts/package-appimage.py
chmod +x dist/Orion-x86_64.AppImage
./dist/Orion-x86_64.AppImage
```

The packager downloads and verifies AppImageTool 1.9.1. It bundles resolved
native dependencies and relocates WebKit's compiled subprocess paths. Its
source and bundled-library copyright notices are retained. Packaging requires
network access on the first run, or a previously populated `build/downloads`.
`ORION_PACKAGING_CACHE` can select another packaging-tool cache.

If the desktop lacks FUSE support, use the AppImage runtime's fallback:

```bash
./dist/Orion-x86_64.AppImage --appimage-extract-and-run
```

The optional GNOME compositor companion supplies live behind-window
refraction on supported GNOME sessions. It remains optional; other desktops
use the app's internal glass fallback. See
[GNOME integration](../linux/gnome/README.md). The AppImage includes its helper
under `usr/data/gnome` after extraction; use `usr/install-gnome-glass.sh --enable`
when installing from an extracted AppImage. Do not install from a temporary
mount that disappears when the app closes.

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

Linux CI extracts and launches the actual AppImage under a disposable desktop
session and checks first-run provisioning. Both platforms isolate smoke-test
data from the user's workspace. Build output and runtime caches are ignored
by Git; publish the generated distribution files as artifacts or releases.

Flutter's [Windows distribution guide](https://docs.flutter.dev/platform-integration/windows/building),
Microsoft's [WebView2 distribution guidance](https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution),
and the [AppImage packaging guide](https://docs.appimage.org/packaging-guide/)
describe the platform requirements behind these scripts.
