[CmdletBinding()]
param([string]$Bundle = 'build/windows/x64/runner/Release')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$directory = [IO.Path]::GetFullPath('build/package-smoke/native')
New-Item -ItemType Directory -Force $directory | Out-Null
$env:ORION_WORKSPACE = Join-Path $directory 'workspace'
$report = Join-Path $directory 'report.json'
if (Test-Path $report) { Remove-Item $report -Force }
$process = Start-Process (Join-Path (Resolve-Path $Bundle).Path 'orion.exe') -ArgumentList @('--report', "`"$report`"") -PassThru
try {
  if (-not $process.WaitForExit(180000)) { throw 'Native desktop smoke timed out after 180 seconds' }
  if ($process.ExitCode -ne 0) { throw "Native desktop smoke failed with exit code $($process.ExitCode)" }
  if (-not (Test-Path $report)) { throw 'Native desktop smoke did not write its result' }
  $result = Get-Content $report -Raw | ConvertFrom-Json
  if ($result.success -ne $true) { throw 'Native desktop smoke report indicates a failure' }
  Get-Content $report
} finally {
  if (-not $process.HasExited) { & taskkill.exe /PID $process.Id /T /F | Out-Null }
  Remove-Item Env:ORION_WORKSPACE -ErrorAction SilentlyContinue
}
