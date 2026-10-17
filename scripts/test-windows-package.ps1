[CmdletBinding()]
param([string]$Executable = 'dist/Orion.exe')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$directory = [IO.Path]::GetFullPath('build/package-smoke/portable')
New-Item -ItemType Directory -Force $directory | Out-Null
$env:ORION_WORKSPACE = Join-Path $directory 'workspace'
$launcher = Start-Process ([IO.Path]::GetFullPath($Executable)) -PassThru
$app = $null
try {
  $deadline = (Get-Date).AddSeconds(120)
  while ((Get-Date) -lt $deadline) {
    if ($launcher.HasExited) { throw "Portable launcher exited early: $($launcher.ExitCode)" }
    $child = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($launcher.Id)" | Where-Object Name -eq 'orion.exe' | Select-Object -First 1
    if ($child) {
      $app = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
      if ($app -and $app.MainWindowHandle -ne 0) { break }
    }
    Start-Sleep -Milliseconds 500
  }
  if (-not $app -or $app.MainWindowHandle -eq 0) { throw 'Portable Orion did not create its main native window' }
  Start-Sleep -Seconds 5
  $app.Refresh()
  if ($app.HasExited) { throw 'Portable Orion crashed shortly after opening' }
  foreach ($required in @('.orion-workspace.json', 'scripts/Special/Orion Bridge.lua', 'themes', 'autoexec', 'cache', 'backups')) {
    if (-not (Test-Path (Join-Path $env:ORION_WORKSPACE $required))) { throw "Portable first launch did not provision $required" }
  }
  $inner = (Get-CimInstance Win32_Process -Filter "ProcessId = $($app.Id)").ExecutablePath
  $runtime = Split-Path $inner -Parent
  if (-not (Test-Path "$runtime/data/webview2/msedgewebview2.exe")) { throw 'Portable package did not extract its offline browser' }
  @{
    success = $true
    portableExecutable = [IO.Path]::GetFileName($Executable)
    nativeWindowOpened = $true
    offlineWebView2Bundled = $true
    workspaceProvisioned = $true
  } | ConvertTo-Json | Set-Content (Join-Path $directory 'report.json')
  Write-Host 'Single EXE extracted and launched successfully, with a native window and a provisioned workspace.'
} finally {
  if ($app -and -not $app.HasExited) { $null = $app.CloseMainWindow(); $null = $app.WaitForExit(10000) }
  if (-not $launcher.HasExited) { & taskkill.exe /PID $launcher.Id /T /F | Out-Null }
  Remove-Item Env:ORION_WORKSPACE -ErrorAction SilentlyContinue
}
