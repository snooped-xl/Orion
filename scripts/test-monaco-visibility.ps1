[CmdletBinding()]
param(
  [string]$Bundle = 'build/windows/x64/runner/Release',
  [string]$Helper = 'build/glass-tests/Release/monaco_visible_test.exe',
  [string]$Output = 'build/monaco-visible-new'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$directory = [IO.Path]::GetFullPath($Output)
$workspacePath = Join-Path $directory 'workspace'
New-Item -ItemType Directory -Force $workspacePath | Out-Null
$reportPath = Join-Path $directory 'report.json'
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
@{
  version = 2
  appearanceVersion = 1
  introCompleted = $true
  selectedInterface = 'orion'
  orionTheme = @{
    version = 2
    presetId = 'expressive'
    basePalette = 'expressive'
    themeMode = 'dark'
    liquidGlassEnabled = $false
    rainEnabled = $false
    windowOpacity = 1.0
  }
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $workspacePath 'orion-workspace.json') -Encoding utf8
$saved = @{}
foreach ($key in @('ORION_WORKSPACE', 'ORION_MONACO_VISIBLE_HELPER', 'ORION_MONACO_VISIBLE_OUTPUT')) {
  $saved[$key] = [Environment]::GetEnvironmentVariable($key)
}
$env:ORION_WORKSPACE = $workspacePath
$env:ORION_MONACO_VISIBLE_HELPER = (Resolve-Path $Helper).Path
$env:ORION_MONACO_VISIBLE_OUTPUT = $directory
$app = $null
try {
  $app = Start-Process (Join-Path (Resolve-Path $Bundle).Path 'orion.exe') -PassThru `
    -RedirectStandardOutput (Join-Path $directory 'stdout.log') `
    -RedirectStandardError (Join-Path $directory 'stderr.log')
  if (-not $app.WaitForExit(150000)) { throw 'Visible Monaco fixture timed out' }
  $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  $expected = @('cold-expressive', 'liquid-glass', 'blue-glass', 'material-rain', 'expressive', 'after-overlay', 'after-restore')
  $actual = @($report.cases | ForEach-Object { $_.name })
  if (($actual -join ',') -ne ($expected -join ',')) { throw 'Incomplete displayed Monaco check' }
  Get-Content (Join-Path $directory 'stdout.log')
  if ($app.ExitCode -ne 0 -or $report.success -ne $true) {
    Get-Content (Join-Path $directory 'stderr.log')
    throw 'Displayed Monaco text check failed'
  }
  Write-Host 'Actual displayed Monaco passed cold start, themes, overlay and restore.'
} finally {
  if ($app -and -not $app.HasExited) { & taskkill.exe /PID $app.Id /T /F | Out-Null }
  foreach ($key in $saved.Keys) {
    [Environment]::SetEnvironmentVariable($key, $saved[$key])
  }
}
