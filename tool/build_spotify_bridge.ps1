# Builds tool/spotify_bridge (librespot) to -Output, for the Windows app. Without Rust installed it builds nothing
# and the app goes without Spotify playback (SpotifyBridge.supported); set RIFLAY_REQUIRE_SPOTIFY_BRIDGE to fail
# instead (release builds).
param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo) {
  if ($env:RIFLAY_REQUIRE_SPOTIFY_BRIDGE) { throw 'cargo was not found: install Rust (https://rustup.rs).' }
  Write-Warning 'cargo was not found: building Riflay without Spotify playback.'
  exit 0
}
$targetDir = Join-Path $projectRoot 'build/spotify_bridge'
Push-Location (Join-Path $projectRoot 'tool/spotify_bridge')
try {
  # --locked: Cargo.lock pins vergen 9.0.6, which librespot-core 0.8.0's build script needs.
  & $cargo.Source build --release --locked --target-dir $targetDir
  if ($LASTEXITCODE -ne 0) { throw 'Spotify bridge build failed.' }
} finally { Pop-Location }
$built = Join-Path $targetDir 'release/spotify_bridge.exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
# Copied only when it changed, so an up-to-date build doesn't touch the app's folder. Plain .NET, not Get-FileHash:
# Windows PowerShell started from PowerShell 7 inherits its module path and can't load that cmdlet. A freshly
# linked exe can be held for a moment (a virus scanner reading it), which fails the copy: try again a few times.
for ($try = 1; ; $try++) {
  try {
    $from = [System.IO.FileInfo]$built
    $to = [System.IO.FileInfo]$Output
    if (-not $to.Exists -or $to.Length -ne $from.Length -or $to.LastWriteTimeUtc -ne $from.LastWriteTimeUtc) {
      [System.IO.File]::Copy($from.FullName, $to.FullName, $true)
    }
    break
  } catch {
    if ($try -ge 5) { throw }
    Start-Sleep -Seconds 1
  }
}
