param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$goCommand = Get-Command go -ErrorAction SilentlyContinue
if ($env:RIFLAY_GO_EXECUTABLE -and (Test-Path -LiteralPath $env:RIFLAY_GO_EXECUTABLE)) {
  $goExecutable = $env:RIFLAY_GO_EXECUTABLE
} elseif ($goCommand) {
  $goExecutable = $goCommand.Source
} else {
  $toolsRoot = Join-Path $projectRoot 'build/tools'
  $goExecutable = Join-Path $toolsRoot 'go/bin/go.exe'
  if (-not (Test-Path -LiteralPath $goExecutable)) {
    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
    $zip = Join-Path $toolsRoot 'go1.27.4.windows-amd64.zip'
    Invoke-WebRequest 'https://go.dev/dl/go1.27.4.windows-amd64.zip' -OutFile $zip
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne '178ab98950ac69ab25069307dc6ade79f3816e414cce95b4da166a115cde1e7e') {
      throw 'Go archive checksum mismatch.'
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $toolsRoot -Force
  }
}
$env:GOTOOLCHAIN = 'local'
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:CGO_ENABLED = '0'
Push-Location (Join-Path $projectRoot 'tool/spotiflac_bridge')
try {
  & $goExecutable build -mod=readonly -trimpath -ldflags '-s -w -H=windowsgui' -o $Output .
  if ($LASTEXITCODE -ne 0) { throw 'SpotiFLAC runtime build failed.' }
} finally { Pop-Location }
