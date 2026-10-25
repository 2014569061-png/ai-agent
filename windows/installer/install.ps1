param([string]$InstallRoot, [switch]$NoShortcut, [switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
if (-not $InstallRoot) { $InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs/NEXUS Agent' }
$setupRoot = [IO.Path]::GetFullPath($InstallRoot)
$setupVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()
if ($setupVersion -notmatch '^[0-9A-Za-z._-]+$') { throw 'Invalid version manifest.' }
$setupDestination = [IO.Path]::GetFullPath((Join-Path $setupRoot "versions/$setupVersion"))
if (-not $setupDestination.StartsWith($setupRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid installation directory.' }
if (Test-Path -LiteralPath $setupDestination) { throw 'This build is already installed. Existing versions have been preserved.' }
$setupArchive = Join-Path $PSScriptRoot 'payload.zip'
$setupExpected = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload.sha256') -Raw).Trim()
if ((Get-FileHash -LiteralPath $setupArchive -Algorithm SHA256).Hash -ine $setupExpected) { throw 'Package checksum mismatch.' }
New-Item -ItemType Directory -Force -Path $setupDestination | Out-Null
Expand-Archive -LiteralPath $setupArchive -DestinationPath $setupDestination
$setupExecutable = Join-Path $setupDestination 'mobile_agent.exe'
if (-not (Test-Path -LiteralPath $setupExecutable)) { throw 'Application executable is missing.' }
$setupStateFile = Join-Path $setupRoot 'installation.json'
$setupPrevious = $null
if (Test-Path -LiteralPath $setupStateFile) { $setupPrevious = (Get-Content -LiteralPath $setupStateFile -Raw | ConvertFrom-Json).current }
@{ current = $setupDestination; previous = $setupPrevious; installedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $setupStateFile -Encoding utf8
if (-not $NoShortcut) {
    $setupShell = New-Object -ComObject WScript.Shell
    $setupLink = $setupShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'NEXUS Agent.lnk'))
    $setupLink.TargetPath = $setupExecutable
    $setupLink.WorkingDirectory = $setupDestination
    $setupLink.Save()
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'rollback.ps1') -Destination (Join-Path $setupRoot 'rollback.ps1') -Force
if (-not $NoLaunch) { Start-Process -FilePath $setupExecutable -WorkingDirectory $setupDestination -WindowStyle Hidden }
Write-Output "Installed: $setupExecutable"
Write-Output 'Previous versions and application data have been retained.'
