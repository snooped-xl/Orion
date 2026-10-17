[CmdletBinding()]
param([string]$Bundle = 'build/windows/x64/runner/Release', [string]$Output = 'dist/Orion.exe')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)
$Bundle = (Resolve-Path $Bundle).Path
foreach ($file in @('orion.exe', 'flutter_windows.dll', 'vcruntime140.dll', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'data/monaco/index.html', 'data/webview2/msedgewebview2.exe')) {
  if (-not (Test-Path (Join-Path $Bundle $file))) { throw "Incomplete Windows bundle: $file" }
}
New-Item -ItemType Directory -Force (Split-Path $Output -Parent) | Out-Null
$Output = [System.IO.Path]::GetFullPath($Output)
$nsis = Join-Path ${env:ProgramFiles(x86)} 'NSIS/makensis.exe'
if (-not (Test-Path $nsis)) {
  $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
  if (-not $command) { throw 'Install NSIS 3: winget install NSIS.NSIS' }
  $nsis = $command.Source
}
$hashes = @(Get-ChildItem $Bundle -File -Recurse | Sort-Object FullName | ForEach-Object {
  "$($_.FullName.Substring($Bundle.Length)) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
})
$hashes += "portable-launcher $((Get-FileHash 'scripts/windows-portable.nsi' -Algorithm SHA256).Hash)"
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $id = [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($hashes -join "`n")))).ToLowerInvariant().Substring(0,24) }
finally { $sha.Dispose() }
& $nsis /V2 "/DBUNDLE_DIR=$Bundle" "/DOUTPUT_FILE=$Output" "/DBUNDLE_ID=$id" 'scripts/windows-portable.nsi'
if ($LASTEXITCODE -ne 0) { throw "NSIS failed with exit code $LASTEXITCODE" }
$digest = (Get-FileHash $Output -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  $([IO.Path]::GetFileName($Output))" | Set-Content "$Output.sha256" -Encoding ascii
Write-Host "Portable executable: $Output"
