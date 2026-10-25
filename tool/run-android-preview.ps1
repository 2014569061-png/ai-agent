param(
    [string]$Avd = 'Nexus_Preview_API_36',
    [string]$SdkRoot,
    [string]$Flutter
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SdkRoot -and (Test-Path -LiteralPath (Join-Path $repoRoot 'local\android-sdk\emulator\emulator.exe'))) {
    $SdkRoot = Join-Path $repoRoot 'local\android-sdk'
}
if (-not $SdkRoot) { $SdkRoot = $env:ANDROID_HOME }
if (-not $SdkRoot) { $SdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $SdkRoot) { $SdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
if (-not $Flutter) { $Flutter = (Get-Command flutter -ErrorAction Stop).Source }
$adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
$emulator = Join-Path $SdkRoot 'emulator\emulator.exe'
$dart = Join-Path (Split-Path $Flutter) 'cache\dart-sdk\bin\dart.exe'
$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$env:ANDROID_AVD_HOME = Join-Path $repoRoot 'local\android-avd'
$env:ANDROID_USER_HOME = Join-Path $repoRoot 'local\android-user'
$env:PUB_CACHE = Join-Path $repoRoot 'local\pub-cache'
$env:TEMP = Join-Path $repoRoot 'local\temp'
$env:TMP = $env:TEMP
foreach ($directory in @($env:ANDROID_AVD_HOME, $env:ANDROID_USER_HOME, $env:PUB_CACHE, $env:TEMP)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
foreach ($path in @($adb, $emulator, $dart)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required tool missing: $path" }
}
$avds = @(& $emulator -list-avds)
if ($Avd -notin $avds) {
    throw "AVD '$Avd' not found under $env:ANDROID_AVD_HOME. See the Android preview setup commands in README.md. Available: $($avds -join ', ')"
}
function Find-PreviewDevice {
    $devices = & $adb devices
    foreach ($line in $devices) {
        if ($line -match '^(emulator-\d+)\s+device$') {
            $serial = $Matches[1]
            $name = @(& $adb -s $serial emu avd name 2>$null)[0]
            if ($name -eq $Avd) { return $serial }
        }
    }
}
& $adb start-server
$device = Find-PreviewDevice
if (-not $device) {
    Write-Host "Starting $Avd..."
    # Show the virtual phone so the user can inspect and interact with the app.
    $logDir = Join-Path $repoRoot 'build\android-preview'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $emulatorProcess = Start-Process -FilePath $emulator -ArgumentList @('-avd', $Avd, '-gpu', 'auto', '-no-boot-anim') -WindowStyle Normal -PassThru -RedirectStandardOutput (Join-Path $logDir 'emulator.log') -RedirectStandardError (Join-Path $logDir 'emulator-error.log')
    $deadline = (Get-Date).AddMinutes(4)
    while (-not $device) {
        if ($emulatorProcess.HasExited) { throw "Emulator exited. See $logDir" }
        if ((Get-Date) -gt $deadline) { throw 'Timed out waiting for emulator.' }
        Start-Sleep -Seconds 2
        $device = Find-PreviewDevice
    }
}
$deadline = (Get-Date).AddMinutes(4)
while ((& $adb -s $device shell getprop sys.boot_completed 2>$null) -ne '1') {
    if ((Get-Date) -gt $deadline) { throw 'Timed out waiting for Android to boot.' }
    Start-Sleep -Seconds 2
}
Write-Host "Android ready: $device. Dart changes reload automatically."
$previousGradleHome = $env:GRADLE_USER_HOME
$env:GRADLE_USER_HOME = Join-Path $repoRoot 'local\gradle-cache'
Push-Location $repoRoot
try {
    & $dart (Join-Path $PSScriptRoot 'android_preview.dart') $Flutter $device
    if ($LASTEXITCODE -ne 0) { throw "Flutter preview exited with code $LASTEXITCODE" }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleHome
    Pop-Location
}
