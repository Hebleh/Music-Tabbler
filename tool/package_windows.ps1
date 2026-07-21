[CmdletBinding()]
param(
  [string]$BuildDirectory,
  [string]$OutputDirectory,
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
  $BuildDirectory = Join-Path $repoRoot 'build\windows\x64\runner\Release'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $repoRoot 'build\release'
}
if ([string]::IsNullOrWhiteSpace($Version)) {
  $versionLine = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)'
  if (-not $versionLine) {
    throw 'Could not determine the package version from pubspec.yaml.'
  }
  $Version = $versionLine.Matches[0].Groups[1].Value
}

$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$expectedBuildRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build'))
if (-not $BuildDirectory.StartsWith($expectedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "BuildDirectory must remain under $expectedBuildRoot"
}
if (-not $OutputDirectory.StartsWith($expectedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "OutputDirectory must remain under $expectedBuildRoot"
}

$appExe = Join-Path $BuildDirectory 'music_tabbler.exe'
if (-not (Test-Path -LiteralPath $appExe)) {
  throw "Release executable not found: $appExe"
}

$packageName = "Music-Tabbler-v$Version-Windows-x64"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "music-tabbler-iexpress-$PID"
$payloadPath = Join-Path $stageRoot 'payload.zip'
$installerScriptPath = Join-Path $stageRoot 'install.ps1'
$sedPath = Join-Path $stageRoot 'package.sed'
$iexpressInstallerPath = Join-Path $stageRoot "$packageName.exe"
$installerPath = Join-Path $OutputDirectory "$packageName.exe"
$checksumPath = "$installerPath.sha256"
$portablePath = Join-Path $OutputDirectory "$packageName-portable.zip"
$portableChecksumPath = "$portablePath.sha256"

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (Test-Path -LiteralPath $stageRoot) {
  Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot | Out-Null
if (Test-Path -LiteralPath $installerPath) {
  Remove-Item -LiteralPath $installerPath -Force
}
if (Test-Path -LiteralPath $checksumPath) {
  Remove-Item -LiteralPath $checksumPath -Force
}
if (Test-Path -LiteralPath $portablePath) {
  Remove-Item -LiteralPath $portablePath -Force
}
if (Test-Path -LiteralPath $portableChecksumPath) {
  Remove-Item -LiteralPath $portableChecksumPath -Force
}

Compress-Archive -Path (Join-Path $BuildDirectory '*') -DestinationPath $payloadPath -CompressionLevel Optimal
Compress-Archive -Path (Join-Path $BuildDirectory '*') -DestinationPath $portablePath -CompressionLevel Optimal

$installerScript = @'
$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'Music Tabbler'
$appRoot = Join-Path $installRoot 'app'
$stagingRoot = Join-Path $installRoot ("staging-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
New-Item -ItemType Directory -Path $stagingRoot | Out-Null
try {
  Expand-Archive -LiteralPath (Join-Path $PSScriptRoot 'payload.zip') -DestinationPath $stagingRoot -Force
  if (Test-Path -LiteralPath $appRoot) {
    Remove-Item -LiteralPath $appRoot -Recurse -Force
  }
  Move-Item -LiteralPath $stagingRoot -Destination $appRoot
  $shell = New-Object -ComObject WScript.Shell
  $shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Music Tabbler.lnk'
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = Join-Path $appRoot 'music_tabbler.exe'
  $shortcut.WorkingDirectory = $appRoot
  $shortcut.Description = 'Music Tabbler'
  $shortcut.Save()
  Start-Process -FilePath (Join-Path $appRoot 'music_tabbler.exe') -WorkingDirectory $appRoot
}
finally {
  if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
}
'@
Set-Content -LiteralPath $installerScriptPath -Value $installerScript -Encoding UTF8

$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$iexpressInstallerPath
FriendlyName=Music Tabbler v$Version
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
FILE0="payload.zip"
FILE1="install.ps1"
[SourceFiles]
SourceFiles0=$stageRoot\
[SourceFiles0]
%FILE0%=
%FILE1%=
"@
Set-Content -LiteralPath $sedPath -Value $sed -Encoding ASCII

$iexpress = Start-Process -FilePath "$env:WINDIR\System32\iexpress.exe" -ArgumentList @('/N', '/Q', $sedPath) -Wait -PassThru
if ($iexpress.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $iexpressInstallerPath)) {
  throw "IExpress packaging failed with exit code $($iexpress.ExitCode)."
}
Move-Item -LiteralPath $iexpressInstallerPath -Destination $installerPath

$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksumPath -Value "$hash  $([IO.Path]::GetFileName($installerPath))" -Encoding ASCII
$portableHash = (Get-FileHash -LiteralPath $portablePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $portableChecksumPath -Value "$portableHash  $([IO.Path]::GetFileName($portablePath))" -Encoding ASCII
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Output $installerPath
Write-Output $checksumPath
Write-Output $portablePath
Write-Output $portableChecksumPath
