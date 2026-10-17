[CmdletBinding()]
param([string]$Bundle = 'build/windows/x64/runner/Release')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$directory = [IO.Path]::GetFullPath('build/package-smoke/native')
New-Item -ItemType Directory -Force $directory | Out-Null
$originalWorkspace = $env:ORION_WORKSPACE
$env:ORION_WORKSPACE = Join-Path $directory 'workspace'
$report = Join-Path $directory 'report.json'
if (Test-Path $report) { Remove-Item $report -Force }
# This is the visible GUI under test. SW_HIDE in STARTUPINFO overrides its first
# ShowWindow call and would make the visibility checks test the launcher flag.
$process = Start-Process (Join-Path (Resolve-Path $Bundle).Path 'orion.exe') -ArgumentList @('--report', "`"$report`"") -PassThru `
  -RedirectStandardOutput (Join-Path $directory 'stdout.log') `
  -RedirectStandardError (Join-Path $directory 'stderr.log')
try {
  if (-not $process.WaitForExit(240000)) { throw 'Native desktop smoke timed out after 240 seconds' }
  if ($process.ExitCode -ne 0) { throw "Native desktop smoke failed with exit code $($process.ExitCode)" }
  if (-not (Test-Path $report)) { throw 'Native desktop smoke did not write its result' }
  $result = Get-Content $report -Raw | ConvertFrom-Json
  if ($result.success -ne $true) { throw 'Native desktop smoke report indicates a failure' }
  if ($result.steps -notcontains 'production-close-requested-with-glass-and-companion') {
    throw 'Native desktop smoke did not exercise production window teardown'
  }
  Write-Host 'Native smoke checks passed and the production close path exited cleanly.'
  Get-Content $report
} finally {
  if (-not $process.HasExited) { & taskkill.exe /PID $process.Id /T /F | Out-Null }
  if ($null -eq $originalWorkspace) {
    Remove-Item Env:ORION_WORKSPACE -ErrorAction SilentlyContinue
  } else {
    $env:ORION_WORKSPACE = $originalWorkspace
  }
}
