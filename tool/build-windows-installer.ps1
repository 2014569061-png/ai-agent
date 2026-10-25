param([string]$ReleaseDirectory)
$ErrorActionPreference = 'Stop'
$installerRepo = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $installerRepo 'build/windows/x64/runner/Release' }
$installerRelease = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $installerRelease 'mobile_agent.exe'))) { throw 'Build Windows release first.' }
$installerVersion = (Select-String -LiteralPath (Join-Path $installerRepo 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value.Replace('+','-')
$installerBuild = $installerVersion + '-' + (Get-Date -Format yyyyMMddHHmmss)
$installerStage = Join-Path $installerRepo "artifacts/installer/$installerBuild"
$installerOutput = Join-Path $installerRepo 'dist/windows'
New-Item -ItemType Directory -Force -Path $installerStage,$installerOutput | Out-Null
Compress-Archive -Path (Join-Path $installerRelease '*') -DestinationPath (Join-Path $installerStage 'payload.zip')
(Get-FileHash -LiteralPath (Join-Path $installerStage 'payload.zip') -Algorithm SHA256).Hash | Set-Content -LiteralPath (Join-Path $installerStage 'payload.sha256') -Encoding ascii
$installerBuild | Set-Content -LiteralPath (Join-Path $installerStage 'version.txt') -Encoding ascii
Copy-Item -LiteralPath (Join-Path $installerRepo 'windows/installer/install.ps1') -Destination $installerStage
Copy-Item -LiteralPath (Join-Path $installerRepo 'windows/installer/rollback.ps1') -Destination $installerStage
'@powershell.exe -NoLogo -NoProfile -File "%~dp0install.ps1"' | Set-Content -LiteralPath (Join-Path $installerStage 'install.cmd') -Encoding ascii
$installerExe = Join-Path $installerOutput "nexus-agent-$installerVersion-windows-x64-setup.exe"
$installerSed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=Install NEXUS Agent for the current user? Existing versions and user data will be retained.
DisplayLicense=
FinishMessage=NEXUS Agent setup completed. A Start menu shortcut is available.
TargetName=$installerExe
FriendlyName=NEXUS Agent
AppLaunched=cmd.exe /d /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=cmd.exe /d /c install.cmd
UserQuietInstCmd=cmd.exe /d /c install.cmd
SourceFiles=SourceFiles
[Strings]
FILE0="payload.zip"
FILE1="payload.sha256"
FILE2="version.txt"
FILE3="install.ps1"
FILE4="install.cmd"
FILE5="rollback.ps1"
[SourceFiles]
SourceFiles0=$installerStage\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
%FILE5%=
"@
$installerSedPath = Join-Path $installerStage 'package.sed'
$installerSed | Set-Content -LiteralPath $installerSedPath -Encoding ascii
$installerProcess = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/iexpress.exe') -ArgumentList @('/N','/Q',('"' + $installerSedPath + '"')) -WorkingDirectory $installerStage -WindowStyle Hidden -PassThru
if (-not $installerProcess.WaitForExit(120000)) { $installerProcess.Kill(); throw 'Installer packaging timed out.' }
if ($installerProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $installerExe)) { throw 'IExpress packaging failed.' }
$installerHash = (Get-FileHash -LiteralPath $installerExe -Algorithm SHA256).Hash.ToLowerInvariant()
($installerHash + '  ' + (Split-Path -Leaf $installerExe)) | Set-Content -LiteralPath ($installerExe + '.sha256') -Encoding ascii
Write-Output "Installer: $installerExe"
Write-Output "Install/rollback test fixture: $installerStage"
