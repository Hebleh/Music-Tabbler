[CmdletBinding()]
param(
  [string]$Device = 'windows',
  [switch]$Clean,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exitCode = 0

# PowerShell 7.3+ can turn a native non-zero exit into a terminating error.
# Keep native handling explicit so Flutter's own exit code reaches the caller.
if ($null -ne (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
  $PSNativeCommandUseErrorActionPreference = $false
}

Push-Location $repoRoot
try {
  if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found on PATH. Install/configure Flutter before launching Music Tabbler.'
  }

  if ($Clean) {
    & flutter clean
    if ($LASTEXITCODE -ne 0) {
      throw "flutter clean failed with exit code $LASTEXITCODE."
    }
  }

  $runArguments = @('run', '-d', $Device)
  if ($FlutterArgs) {
    $runArguments += $FlutterArgs
  }

  Write-Host "Launching Music Tabbler on '$Device' in Flutter development mode..."
  & flutter @runArguments
  $exitCode = $LASTEXITCODE
}
finally {
  Pop-Location
}

exit $exitCode
