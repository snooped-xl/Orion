[CmdletBinding()]
param(
  [string]$Executable = 'dist/Orion.exe',
  [string[]]$Themes = @('expressive', 'liquid-glass', 'blue-glass', 'material-rain'),
  [int]$MaxCloseVisibilityMilliseconds = 1000
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not ('OrionPackageSmokeNative' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class OrionPackageSmokeNative {
  private delegate bool EnumWindowsProc(IntPtr window, IntPtr argument);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr argument);
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder value, int count);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder value, int count);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
  public static IntPtr FindMainWindow(uint processId) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((window, argument) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != processId || !IsWindowVisible(window)) return true;
      var klass = new StringBuilder(256);
      var title = new StringBuilder(256);
      GetClassName(window, klass, klass.Capacity);
      GetWindowText(window, title, title.Capacity);
      if (klass.ToString() != "FLUTTER_RUNNER_WIN32_WINDOW" || title.ToString() != "Orion") return true;
      found = window;
      return false;
    }, IntPtr.Zero);
    return found;
  }
}
'@
}
Set-Location (Split-Path $PSScriptRoot -Parent)
$directory = [IO.Path]::GetFullPath('build/package-smoke/portable')
New-Item -ItemType Directory -Force $directory | Out-Null
$executablePath = [IO.Path]::GetFullPath($Executable)
$originalWorkspace = $env:ORION_WORKSPACE
$results = [Collections.Generic.List[object]]::new()
$failure = $null
try {
  foreach ($theme in $Themes) {
    if ($theme -notin @('expressive', 'liquid-glass', 'blue-glass', 'material-rain')) {
      throw "Unknown package smoke theme: $theme"
    }
    $caseDirectory = Join-Path $directory $theme
    $env:ORION_WORKSPACE = Join-Path $caseDirectory 'workspace'
    New-Item -ItemType Directory -Force $env:ORION_WORKSPACE | Out-Null
    $glass = $theme -in @('liquid-glass', 'blue-glass')
    $rain = $theme -eq 'material-rain'
    # Cold starts exercise saved translucent themes before the first native
    # frame. All data stays in a fixture workspace, never the user's documents.
    @{
      version = 1
      appearanceVersion = 1
      selectedInterface = 'orion'
      introCompleted = $true
      orionTheme = @{
        version = 2
        presetId = $theme
        basePalette = $(if ($glass) { 'liquid-glass' } else { $theme })
        themeMode = 'dark'
        liquidGlassEnabled = $glass
        rainEnabled = $rain
        windowOpacity = $(if ($glass) { 0.63 } elseif ($rain) { 0.9 } else { 1.0 })
        gradientEnabled = $theme -eq 'blue-glass'
        gradientColors = @(0xFF0057ADL, 0xFF49525EL)
        gradientAngle = 41.48
        surfaceTint = $(if ($theme -eq 'blue-glass') { 0.155 } else { 0.0 })
        outlineStrength = $(if ($glass) { 0.65 } else { 1.0 })
      }
    } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $env:ORION_WORKSPACE 'orion-workspace.json') -Encoding UTF8
    $launcher = $null
    $app = $null
    $appWindow = [IntPtr]::Zero
    try {
      Write-Host "Portable smoke: opening $theme"
      $launcher = Start-Process $executablePath -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $caseDirectory 'stdout.log') `
        -RedirectStandardError (Join-Path $caseDirectory 'stderr.log')
      $deadline = (Get-Date).AddSeconds(120)
      while ((Get-Date) -lt $deadline) {
        if ($launcher.HasExited) { throw "Portable launcher exited early: $($launcher.ExitCode)" }
        $child = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($launcher.Id)" | Where-Object Name -eq 'orion.exe' | Select-Object -First 1
        if ($child) {
          $app = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
          if ($app) {
            # Retain a process handle so ExitCode remains available after exit.
            $null = $app.Handle
            # Process.MainWindowHandle can select DWM's cloaked STATIC helper.
            # Identify Orion's actual Flutter root before sending WM_CLOSE.
            $appWindow = [OrionPackageSmokeNative]::FindMainWindow($app.Id)
            if ($appWindow -ne [IntPtr]::Zero) { break }
          }
        }
        Start-Sleep -Milliseconds 250
      }
      if (-not $app -or $appWindow -eq [IntPtr]::Zero) { throw 'Portable Orion did not create its main native window' }
      Start-Sleep -Seconds 8
      $app.Refresh()
      if ($app.HasExited) { throw "Portable Orion crashed shortly after opening: $($app.ExitCode)" }
      foreach ($required in @('.orion-workspace.json', 'scripts/Special/Orion Bridge.lua', 'themes', 'autoexec', 'cache', 'backups')) {
        if (-not (Test-Path (Join-Path $env:ORION_WORKSPACE $required))) { throw "Portable first launch did not provision $required" }
      }
      $inner = (Get-CimInstance Win32_Process -Filter "ProcessId = $($app.Id)").ExecutablePath
      $runtime = Split-Path $inner -Parent
      if (-not (Test-Path "$runtime/data/webview2/msedgewebview2.exe")) { throw 'Portable package did not extract its offline browser' }

      $close = [Diagnostics.Stopwatch]::StartNew()
      if (-not [OrionPackageSmokeNative]::PostMessage($appWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) {
        throw 'Portable window rejected WM_CLOSE'
      }
      while (-not $app.HasExited -and $close.ElapsedMilliseconds -lt 10000 -and
          [OrionPackageSmokeNative]::IsWindow($appWindow) -and [OrionPackageSmokeNative]::IsWindowVisible($appWindow)) {
        Start-Sleep -Milliseconds 25
      }
      $visibleCloseMilliseconds = $close.ElapsedMilliseconds
      $appExited = $app.WaitForExit(15000)
      $launcherExited = $launcher.WaitForExit(5000)
      $results.Add(@{
        theme = $theme
        nativeWindowOpened = $true
        nativeWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW'
        nativeWindowTitle = 'Orion'
        nativeWindowHandle = $appWindow.ToInt64()
        offlineWebView2Bundled = $true
        workspaceProvisioned = $true
        visibleCloseMilliseconds = $visibleCloseMilliseconds
        processCloseMilliseconds = $close.ElapsedMilliseconds
        exitCode = $(if ($appExited) { $app.ExitCode } else { $null })
        launcherExitCode = $(if ($launcherExited) { $launcher.ExitCode } else { $null })
      })
      if (-not $appExited) { throw 'Portable Orion did not exit after closing its window' }
      if ($app.ExitCode -ne 0) { throw "Portable Orion crashed during close: $($app.ExitCode); visible for ${visibleCloseMilliseconds}ms" }
      if ($visibleCloseMilliseconds -gt $MaxCloseVisibilityMilliseconds) {
        throw "Window stayed visible for ${visibleCloseMilliseconds}ms after close (limit ${MaxCloseVisibilityMilliseconds}ms)"
      }
      if (-not $launcherExited) { throw 'Portable launcher remained alive after Orion exited' }
      if ($launcher.ExitCode -ne 0) { throw "Portable launcher returned $($launcher.ExitCode)" }
      $saved = Get-Content (Join-Path $env:ORION_WORKSPACE 'orion-workspace.json') -Raw | ConvertFrom-Json
      if ($saved.orionTheme.presetId -ne $theme) { throw "Saved theme was not restored/persisted: $theme" }
      Write-Host "Portable smoke: $theme passed; window hidden in ${visibleCloseMilliseconds}ms, process exited cleanly."
    } finally {
      if ($app -and -not $app.HasExited) { & taskkill.exe /PID $app.Id /T /F | Out-Null }
      if ($launcher -and -not $launcher.HasExited) { & taskkill.exe /PID $launcher.Id /T /F | Out-Null }
    }
  }
} catch {
  $failure = $_.ToString()
  throw
} finally {
  @{
    success = $null -eq $failure
    portableExecutable = [IO.Path]::GetFileName($Executable)
    cases = $results.ToArray()
    failure = $failure
  } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $directory 'report.json')
  if ($null -eq $originalWorkspace) {
    Remove-Item Env:ORION_WORKSPACE -ErrorAction SilentlyContinue
  } else {
    $env:ORION_WORKSPACE = $originalWorkspace
  }
}
