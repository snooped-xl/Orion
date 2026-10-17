[CmdletBinding()]
param([string]$Target = 'lib/main.dart', [string]$LogName = 'windows-build')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force 'build/package-smoke' | Out-Null
$log = "build/package-smoke/$LogName.log"
& flutter build windows --release --no-tree-shake-icons --target $Target -v *>&1 | Tee-Object $log
$result = $LASTEXITCODE
if ($result -ne 0) {
  # Flutter filters some CMake install errors. Run that stage directly so the
  # original path/asset failure is retained in CI diagnostics.
  if (Test-Path 'build/windows/x64/cmake_install.cmake') {
    & cmake --install build/windows/x64 --config Release --verbose *>&1 | Tee-Object "build/package-smoke/$LogName-install.log"
  }
  throw "Windows build failed with exit code $result. See $log and the native install log."
}
