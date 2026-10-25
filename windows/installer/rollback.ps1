param([switch]$NoLaunch, [switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
$rollbackStateFile = Join-Path $PSScriptRoot 'installation.json'
$rollbackState = Get-Content -LiteralPath $rollbackStateFile -Raw | ConvertFrom-Json
if (-not $rollbackState.previous) { throw 'No previous installed version is available.' }
$rollbackPrevious = [IO.Path]::GetFullPath([string]$rollbackState.previous)
$rollbackRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'versions'))
if (-not $rollbackPrevious.StartsWith($rollbackRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Previous version is outside this installation.' }
$rollbackExecutable = Join-Path $rollbackPrevious 'mobile_agent.exe'
if (-not (Test-Path -LiteralPath $rollbackExecutable)) { throw 'Previous executable is missing.' }
if (-not $NoShortcut) {
    $rollbackShell = New-Object -ComObject WScript.Shell
    $rollbackLink = $rollbackShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'NEXUS Agent.lnk'))
    $rollbackLink.TargetPath = $rollbackExecutable
    $rollbackLink.WorkingDirectory = $rollbackPrevious
    $rollbackLink.Save()
}
$rollbackOld = $rollbackState.current
$rollbackState.current = $rollbackPrevious
$rollbackState.previous = $rollbackOld
$rollbackState | ConvertTo-Json | Set-Content -LiteralPath $rollbackStateFile -Encoding utf8
if (-not $NoLaunch) { Start-Process -FilePath $rollbackExecutable -WorkingDirectory $rollbackPrevious -WindowStyle Hidden }
Write-Output 'Application version rolled back. User data was not changed; use a compatible backup if a data migration needs to be reversed.'
