<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/branding/orion-light.svg">
    <img src="docs/branding/orion-dark.svg" alt="Orion" width="340">
  </picture>
</p>

<p align="center"><strong>Orion is back.</strong> This time, it is rebuilt from the ground up in Flutter and redesigned with the Material 3 Expressive design language.</p>

<p align="center">
  <a href="https://github.com/snooped-xl/Orion/releases/latest">Download Orion</a> ·
  <a href="docs/BUILDING.md">Build from source</a> ·
  <a href="docs/PRIVACY.md">Privacy</a> ·
  <a href="https://github.com/snooped-xl/Orion/tree/Orion-Legacy">Orion Legacy</a>
</p>

## A workspace that feels like yours

Orion brings a genuine Monaco editor, local script library, online script search,
multiple interfaces, and multi-client management into one desktop app. The main
interface uses Material 3 Expressive shapes, connected controls, responsive
layouts, and restrained motion. Your scripts and workspace follow you when you
switch interfaces.

Orion Bridge connects the app to an executor you already use. Orion does not
bundle an executor, inject into Roblox, or execute Roblox scripts on your PC.
Execution requires a connected client that supports the bridge's Lua script.

## Download and run

Get the files from the **[Latest release](https://github.com/snooped-xl/Orion/releases/latest)**.

| Platform | Download | Start |
| --- | --- | --- |
| Windows 10 / 11, x64 | `Orion.exe` | Double-click the executable. |
| Linux, x86_64 | `Orion-x86_64.flatpak` | Install the bundle with Flatpak. |

### Windows

`Orion.exe` is one self-extracting portable executable. It includes Flutter,
Monaco, the Visual C++ runtime, and an offline Microsoft WebView2 runtime. No
separate Flutter, browser, or Visual Studio installation is needed to run it.

The first launch unpacks its runtime into
`%LOCALAPPDATA%\Orion\Runtime\<content-hash>`. Later launches reuse that cache.
Your scripts and settings live separately in your actual **Documents\orion**
folder, including redirected Documents folders. The current builds are unsigned.

### Linux

Install [Flatpak for your distribution](https://flatpak.org/setup/), then run:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./Orion-x86_64.flatpak
flatpak run dev.snooped.orion
```

Flatpak supplies a shared GNOME runtime, so distributions do not need matching
host GTK, WebKit, or glibc versions. The first installation downloads that runtime
if needed. The same bundle works across Flatpak-supported x86_64 distributions.
Your workspace stays at **~/orion**.

Checksums are included with the release. Flatpak's shared runtime is a separate
first-time download; it is not embedded in the `.flatpak` file.

## Connect Orion Bridge

1. Start Orion and open the editor. The first-launch tutorial can also guide you.
2. Find **scripts/Special/Orion Bridge.lua** inside your Orion workspace.
3. Copy that script into the **autoexecute folder of your executor**. Use that
   executor's own auto attach setting for a smoother experience.
4. Attach your executor to the Roblox client and run the bridge once, or let its
   autoexecute system run it on attach.
5. Open **Clients** in Orion, choose the client or clients to target, and execute
   a script from the editor or script hub.

Putting a file in Orion's own `autoexec` folder does not install it into an
external executor. The executor must actually run `Orion Bridge.lua`.

A connection produces a themed notification titled **Orion Bridge**, with the
subject **Executor Connected! (Executor name)** and the player's display name.
Executor version information is kept out of that notification. Client management
is shared across every interface, including ports that originally had none.

**Executor Quick Launch is coming soon.** It is intended to launch an executor
with Orion; it is not part of this release.

### How the bridge works

Orion starts an HTTP service on **127.0.0.1:31337**. The Lua bridge identifies its
client, reports the player's display name and executor details, and polls for
work. Each connected client has its own session and execution queue. You can
send a script to one client or several; output and errors return to Orion's
console with their client identity.

The bridge supports long polling and compatibility transports, heartbeat expiry,
reconnection, queued execution batches, UTF-8 script transport, and result/log
handling. The bundled Lua script handles executor API differences and avoids
leaving duplicate bridge loops running when it is started again. Teleport
continuation depends on the executor exposing the required queue API.

For development, `/status` reports bridge status and `/bridge.lua` serves the
bundled Lua script. Protocol requests use `orion-bridge-v2`. This is a protocol
marker, not a secret or a remote authentication system. The service listens on
local loopback, validates browser origins, and applies request and queue limits.
It is intended for applications on your own machine.

Disconnecting a client in Orion removes that session; it does not close Roblox.
A bridge that is still running can reconnect. Only one Orion instance can own
port 31337 at a time. If no client is connected, execution has nowhere to go.

### Relapse GTK support on Linux

Start Relapse GTK, then enable **Settings → Relapse support** in Orion. Orion
connects to Relapse's local `/tmp/relapse.sock`, submits editor and script-hub
code to its ready game session, and forwards captured output to Orion's console.
This setting is Linux-only. While enabled, Orion's own HTTP bridge is stopped;
turn it off to return to Orion Bridge. Orion uses Relapse's socket capabilities
without bundling or opening Relapse's GTK interface.

**Multiple profiles.** Relapse publishes one socket per running profile. Orion
watches `/tmp` for `relapse.sock` and `relapse-<profile>.sock` using RelapseGtk's
own rules: the socket must be a Unix socket owned by you and still listening,
and the profile name must be 1–64 letters, digits, dots, underscores or
hyphens. Each profile is listed in **Clients → client manager** separately.
Execute either targets every ready profile or only the ones you tick.

**Session bridge.** Orion follows RelapseGtk's client exactly. For each game
session it runs Relapse's `session.luau`, opens the `relapsegtk.session.v2`
channel, and configures it with `{"op":"configure","version":2,"redirect":…}`.
Only after that acknowledgement does Execute become available, and scripts are
always submitted as
`getgenv().__relapsegtk_session_v2.execute(<script>, <name>)` so they run inside
the live game session. A channel that is still starting is reported instead of
being bypassed: Orion never submits unwrapped code. Relapse sends its numbers as
Lua doubles, so `version` and `dropped` are read as integral integers.

**Output.** **Settings → Execution → Redirect script output** is the same switch
as RelapseGtk's *Redirect script output*: it reconfigures the live channel, and
turns output forwarding on or off without stopping execution. Dropped messages
are reported exactly as RelapseGtk reports them.

**Launching Relapse.** **Settings → Execution** remembers the Relapse
executable, so **Launch Relapse** starts it directly and **Change launcher**
picks a different binary. Like RelapseGtk, Orion runs it headlessly
(`--no-launch-ui`, plus `--profile <name>` for the selected profile) and refuses
to launch a profile that is already listening. Paths are validated as
executable files and never run through a shell.

The Flatpak grants the desktop host's `/tmp` directory so Relapse's sockets
are reachable from inside the sandbox. Relapse names each profile socket after
the profile (`relapse-<profile>.sock`) and only creates it once that client is
running, so the earlier single-path grant on `/tmp/relapse.sock` left profiles
invisible; every discovered profile now connects. The bundled session helper is
attributed and licensed in [`assets/relapsegtk/`](assets/relapsegtk/).

## Editor, scripts, and search

- **Monaco:** bundled offline, with Luau syntax colours, Roblox/Luau completion,
  find, replace, undo, redo, and editor preferences such as minimap visibility.
- **Script tabs:** open, save, clear, scroll through overflowing tabs, and
  right-click a tab to rename or manage it.
- **Local library:** reads the dedicated `scripts` directory rather than listing
  open tabs. Save dialogs start there. Right-click a script to assign a colour
  code; `Special` has its own animated text gradient.
- **Script hub:** search RobloxScripts, ScriptBlox, HaxHell, and Rscripts. Browse
  image previews, copy a script, open it in the workspace, or execute it through
  the selected bridge clients.
- **Recovery:** open documents, their contents, the selected interface, and
  preferences are restored between launches.

Monaco's completion catalog is not a complete Luau language server or type
checker. Formatting currently provides indentation rather than a full Luau
formatter. Remote search depends on each provider's availability, API, and
content; local scripts and the editor work offline.

## Interfaces

| Interface | Notes |
| --- | --- |
| Orion | Main Material 3 Expressive workspace |
| Synapse V3 | Flutter recreation with separate options and hub views |
| Synapse Blue | Includes its animated introduction |
| Synapse X | Classic layout and companion windows |
| Synapse OG | Original-style Synapse layout |
| Zenith V2 | Includes its distinct interface flow |
| AWP.gg | Compact AWP layout |
| Xeno | Xeno-style workspace |
| KRNL | KRNL-style editor and script tabs |
| Calamari | Calamari-style layout |

All interfaces share Orion's editor state and Bridge. The interface you select
is saved. Synapse's **Back to Orion** action is in its settings. RC7 is not
included. Login screens and legacy options in recreated interfaces are local
interface features, not connections to the original vendors' services.

The UI Selection page explains the finish status of each port. Checkmarks mean
ready to use without known bugs; they do not promise complete visual accuracy.
Some other interfaces still need polish.

## Make it yours

**Theme Control** provides simple whole-app colour and gradient editing, logo
replacement with a crop editor, and a reset to Orion Expressive. Built-in themes:

| Theme | Style |
| --- | --- |
| Orion Expressive | Default dark Material 3 palette with blue accents |
| Original Orion | Transparent surfaces, thin outlines, and a background gradient |
| Material Rain | Black and dark blue with animated refracting rain |
| Glassy | Clear, neutral glass surfaces |
| Blue Glass | A blue-tinted glass variation |
| Midnight | A deep, subdued palette |
| Aurora | A colourful gradient palette |
| Ember | A warmer palette |

**Theme Studio** adds advanced editing, saving, import, and export for Orion and
Synapse V3, Blue, X, and OG. Edit individual elements, colours, positions, window
sizes, background and overlay images, logos, and separate options/hub windows.
Orion keeps its simpler Theme Control alongside the studio.

Settings include compact and enlarged window modes, a GUI size slider, topmost,
editor options, reduced motion, and tutorial replay. Normal startup centres the
window on the monitor containing your mouse. Orion's short startup animation is
separate from the first-launch introduction tutorial.

### Desktop effects and platform differences

Linux's optional GNOME companion provides live behind-window glass refraction,
Wayland placement, and topmost integration on supported GNOME sessions. Install
it using the [GNOME integration guide](linux/gnome/README.md). On other desktops,
Orion uses its available fallback materials.

Windows glass ports the Linux lens profile to a native compositor mesh, with
live desktop refraction, light frost, and smooth authored corners. Flutter's
controls and the WebView2 editor stay sharp, and ordinary screenshots and
screen sharing remain available. Windows rain uses a native Direct3D path.

The live desktop source uses private DWM interop on Windows 11. On older Windows
versions or when that interop is unavailable, Orion uses its authored Flutter
glass material. See the [Windows native host
notes](windows/runner/NATIVE_WINDOWS.md) for implementation and validation details.

Flatpak permits network access for the bridge and script search, home and mounted
folders for your files, the session bus for authenticated GNOME integration, and
the host `/tmp` directory for optional Relapse profile sockets. It does not
request host command execution. File dialogs and external opening use desktop
portals. See [build and platform details](docs/BUILDING.md).

## Your workspace

| Location | Purpose |
| --- | --- |
| `scripts/` | Local script library and default save location |
| `scripts/Special/Orion Bridge.lua` | Managed bridge script |
| `autoexec/` | Orion-side autoexecute directory |
| `themes/` | Theme files |
| `cache/` | Workspace cache |
| `backups/` | Backups of replaced managed files |
| `orion-workspace.json` | Saved documents, settings, and recovery state |
| `.orion-workspace.json` | First-run provisioning/version marker |

First launch creates these folders and imports a previous hidden Orion workspace
when available. Existing personal scripts and preferences are preserved. Orion
refreshes its managed bridge on initial provisioning or a bundled update and
backs up a differing previous copy. Normal launches keep user changes to it.
Inside the app the managed bridge script is read-only so it cannot be changed
or removed by accident; enable **Allow modifying the Orion Bridge script** in
Settings if you want to edit or delete it yourself.

For an isolated development profile, set `ORION_WORKSPACE` to an absolute folder.
Automated tests use isolated profiles and do not need your personal workspace.

## Build, contribute, and explore

Read **[Building Orion](docs/BUILDING.md)** for Windows and Linux prerequisites,
source builds, one-file Windows packaging, Flatpak packaging, and native tests.
The project pins Flutter **3.47.7** and Dart **3.13.5**. Keep the lockfile and the
patched packages in `packages/`; they contain platform fixes Orion relies on.

GitHub Actions builds and tests the desktop apps. Downloadable public builds are
published under [Releases](https://github.com/snooped-xl/Orion/releases/latest),
rather than requiring an Actions artifact download.

The previous source is preserved on **[Orion-Legacy](https://github.com/snooped-xl/Orion/tree/Orion-Legacy)**.
Third-party editor, font, effect, and package notices are retained beside their
assets and vendored sources. Recreated interfaces are independent ports and do
not imply affiliation with their original vendors.
