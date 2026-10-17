[CmdletBinding()]
param(
  [string]$Bundle = 'build/windows/x64/runner/Release',
  [string]$Cache = 'build/downloads'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path "$Bundle/orion.exe")) { throw "Build the Windows release before preparing its runtime: $Bundle" }
$Bundle = (Resolve-Path $Bundle).Path
New-Item -ItemType Directory -Force $Cache | Out-Null
$Cache = (Resolve-Path $Cache).Path

# The Fixed Version package is copied beside Orion, never installed globally.
# Source: https://developer.microsoft.com/microsoft-edge/webview2/#download
$version = '155.0.4283.62'
$url = 'https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/232cf50b-3980-4531-afbb-779f446d7de1/Microsoft.WebView2.FixedVersionRuntime.155.0.4283.62.x64.cab'
$sha256 = 'cf54aa717a0ebd05b40e87620724583cb6eb0a5b8b64764cc11e42822f68bf6c'
$cab = Join-Path $Cache "webview2-$version-x64.cab"
if (-not (Test-Path $cab)) { Invoke-WebRequest $url -OutFile $cab }
if ((Get-FileHash $cab -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) {
  throw "WebView2 CAB checksum mismatch. Delete $cab and retry."
}
$runtime = Join-Path $Bundle 'data/webview2'
$runtimeReady = (Test-Path "$runtime/msedgewebview2.exe") -and (Test-Path "$runtime/msedge.dll") -and (Test-Path "$runtime/icudtl.dat")
if ($runtimeReady) {
  $runtimeReady = (Get-Item "$runtime/msedgewebview2.exe").VersionInfo.ProductVersion.StartsWith($version)
}
if (-not $runtimeReady) {
  $expanded = Join-Path $Cache "webview2-$version-expanded"
  if (Test-Path $expanded) { Remove-Item $expanded -Force -Recurse }
  New-Item -ItemType Directory -Force $expanded | Out-Null
  & expand.exe $cab '-F:*' $expanded | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'WebView2 CAB extraction failed' }
  $browser = Get-ChildItem $expanded -Filter msedgewebview2.exe -Recurse | Select-Object -First 1
  if (-not $browser) { throw 'Microsoft runtime package has no msedgewebview2.exe' }
  $signature = Get-AuthenticodeSignature $browser.FullName
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw 'WebView2 executable does not have a valid Microsoft signature'
  }
  if (Test-Path $runtime) { Remove-Item $runtime -Force -Recurse }
  New-Item -ItemType Directory -Force $runtime | Out-Null
  Copy-Item "$($browser.Directory.FullName)/*" $runtime -Recurse -Force
}
$runtimeSignature = Get-AuthenticodeSignature "$runtime/msedgewebview2.exe"
if ($runtimeSignature.Status -ne 'Valid' -or $runtimeSignature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
  throw 'Bundled WebView2 executable does not have a valid Microsoft signature'
}
# Microsoft requires these read/execute ACLs for Fixed Version 120+ on
# unpackaged Windows 10 apps. Only the browser files receive them.
& icacls.exe $runtime /grant '*S-1-15-2-2:(OI)(CI)(RX)' '*S-1-15-2-1:(OI)(CI)(RX)' /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not grant WebView2 AppContainer read/execute permissions' }

# Flutter's Windows engine uses the Visual C++ runtime. App-local deployment
# avoids requiring an administrator or changing an existing system install.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio vswhere.exe is missing' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Install Visual Studio Desktop development with C++' }
$redists = @(Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory | Sort-Object Name -Descending)
$crt = $null
foreach ($redist in $redists) {
  $candidate = Get-ChildItem (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($candidate) { $crt = $candidate.FullName; break }
}
if (-not $crt) { throw 'No x64 Microsoft Visual C++ redistributable DLLs were found' }
Copy-Item "$crt/*.dll" $Bundle -Force
if (-not (Test-Path "$Bundle/vcruntime140.dll")) { throw 'Visual C++ runtime copy is incomplete' }

$notices = Join-Path $Bundle 'data/licenses'
New-Item -ItemType Directory -Force $notices | Out-Null
@'
Microsoft Edge WebView2 Fixed Version Runtime
This package contains Microsoft's unmodified WebView2 runtime and its notices.
Terms: https://developer.microsoft.com/microsoft-edge/webview2/#download
Distribution: https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution

Microsoft Visual C++ runtime
App-local DLLs redistributed from the Visual Studio REDIST directory.
Terms: https://visualstudio.microsoft.com/license-terms/
'@ | Set-Content (Join-Path $notices 'Microsoft-runtime.txt') -Encoding utf8
Write-Host "Offline WebView2 $version and x64 Visual C++ runtime prepared in $Bundle"
