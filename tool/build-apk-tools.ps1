param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Preflight','Publish')][string]$Action,
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ApkPath,
    [string]$ResultFile,
    [ValidateRange(2,50)][int]$Keep = 3,
    [switch]$KeepAll
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-ProjectVersion {
    $text = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'pubspec.yaml'))
    $m = [regex]::Match($text, '(?m)^version:\s*["'']?(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?\+\d+)["'']?\s*(?:#.*)?$')
    if (-not $m.Success) { throw 'pubspec.yaml must contain a version such as 0.9.0+94.' }
    return $m.Groups[1].Value
}
function Get-Hash([string]$Path) {
    # Use the .NET API instead of Get-FileHash: the latter is not available in
    # some minimal Windows PowerShell images used for the isolated script tests.
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}
function Read-Properties([string]$Path) {
    # This project's ordinary Java property files: decode escaped drive colon/backslash.
    # Reject continuations/unicode rather than silently resolve a different signing key.
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line.TrimStart().StartsWith('#') -or $line.TrimStart().StartsWith('!') -or -not $line.Trim()) { continue }
        if ($line -match '^\s*([^=:\s]+)\s*[=:]\s*(.*)$') {
            $key = $Matches[1]; $value = $Matches[2]
            if ($key -in @('storeFile','sdk.dir')) {
                if ($value -match '\\u[0-9a-fA-F]{4}' -or $value -match '(?<!\\)(?:\\\\)*\\$') { throw "Unsupported escaped/continued path in $key; use forward slashes." }
                $values[$key] = $value.Replace('\:', ':').Replace('\\', '\')
            } else { $values[$key] = $value }
        }
    }
    return $values
}
function Assert-MinimumToolchain {
    # The build passes Flutter's --android-skip-build-dependency-validation to
    # silence its advisory "will soon be dropped" notices. That flag also skips
    # the hard minimum-version errors, so the same floors are enforced here.
    $settings = Join-Path $ProjectRoot 'android/settings.gradle.kts'
    $wrapper = Join-Path $ProjectRoot 'android/gradle/wrapper/gradle-wrapper.properties'
    $agp = $null
    $kgp = $null
    if (Test-Path -LiteralPath $settings) {
        $text = [IO.File]::ReadAllText($settings)
        $m = [regex]::Match($text, 'com\.android\.application"?\)\s*version\s*"([0-9][^"]*)"')
        if ($m.Success) { $agp = $m.Groups[1].Value }
        $m = [regex]::Match($text, 'org\.jetbrains\.kotlin\.android"?\)\s*version\s*"([0-9][^"]*)"')
        if ($m.Success) { $kgp = $m.Groups[1].Value }
    }
    $gradle = $null
    if (Test-Path -LiteralPath $wrapper) {
        $m = [regex]::Match([IO.File]::ReadAllText($wrapper), 'gradle-([0-9]+(?:\.[0-9]+)+)-')
        if ($m.Success) { $gradle = $m.Groups[1].Value }
    }
    # Floors mirror Flutter 3.47.2's error thresholds (DependencyVersionChecker.kt).
    $floors = @(@('Gradle', $gradle, '8.14.0'), @('Android Gradle Plugin', $agp, '8.11.1'), @('Kotlin', $kgp, '2.2.20'))
    foreach ($entry in $floors) {
        $name = $entry[0]
        $value = $entry[1]
        $floor = [version]$entry[2]
        if (-not $value) { throw "Could not detect the $name version. Fix settings.gradle.kts or the Gradle wrapper before building." }
        $parsed = $null
        if (-not [version]::TryParse($value, [ref]$parsed)) { throw "The detected $name version '$value' is not a valid version." }
        if ($parsed -lt $floor) { throw "Your $name version ($value) is below Flutter 3.47.2's minimum supported version $floor." }
    }
    Write-Host "[check] Toolchain meets Flutter minimums: Gradle $gradle, AGP $agp, Kotlin $kgp."
}
function Invoke-Preflight {
    $version = Read-ProjectVersion
    $gradle = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'android/app/build.gradle.kts'))
    $m = [regex]::Match($gradle, 'versionName\s*=\s*"([^"]+)"')
    if (-not $m.Success -or $m.Groups[1].Value -ne ($version -split '\+')[0]) { throw 'Android versionName differs from pubspec.yaml. Align the versions before building.' }
    $props = Read-Properties (Join-Path $ProjectRoot 'android/key.properties')
    foreach ($name in @('storeFile','storePassword','keyPassword','keyAlias')) {
        if (-not $props.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($props[$name])) { throw "Signing configuration is missing $name (values are never printed)." }
    }
    $key = $props['storeFile']
    if (-not [IO.Path]::IsPathRooted($key)) { $key = Join-Path (Join-Path $ProjectRoot 'android/app') $key }
    if (-not (Test-Path -LiteralPath $key -PathType Leaf)) { throw 'The keystore configured by storeFile does not exist.' }
    $sdk = $null
    $local = Join-Path $ProjectRoot 'android/local.properties'
    if (Test-Path -LiteralPath $local) { $localProps = Read-Properties $local; $sdk = $localProps['sdk.dir'] }
    if (-not $sdk) { $sdk = $env:ANDROID_HOME }
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk -or -not (Test-Path -LiteralPath $sdk -PathType Container)) { throw 'Android SDK not found. Configure sdk.dir or ANDROID_HOME.' }
    $compile = [regex]::Match($gradle, 'compileSdk\s*=\s*(\d+)')
    if ($compile.Success) {
        $api = $compile.Groups[1].Value
        # New SDK packages may use a .0 suffix (for example android-37.0).
        $platforms = @((Join-Path $sdk ('platforms/android-' + $api + '/android.jar')), (Join-Path $sdk ('platforms/android-' + $api + '.0/android.jar')))
        if (-not ($platforms | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) { throw 'The configured Android compile SDK platform is not installed.' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sdk 'build-tools'))) { throw 'Android SDK build-tools directory is missing.' }
    Assert-MinimumToolchain
    Write-Host "[check] Version $version, signing configuration and Android SDK checks passed."
    Write-Host '[check] Password validity, SDK licenses and Gradle dependency availability require an actual build.'
}
function Test-Pair([string]$Path) {
    $sidecar = $Path + '.sha256'
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { return $false }
    $expected = ([IO.File]::ReadAllText($sidecar).Trim() -split '\s+')[0]
    return ($expected -match '^[0-9a-fA-F]{64}$' -and (Get-Hash $Path) -eq $expected.ToLowerInvariant())
}
function Invoke-Publish {
    if (-not $ApkPath -or -not $ResultFile) { throw 'Publish requires ApkPath and ResultFile.' }
    if ((Get-Item -LiteralPath $ApkPath).Length -le 0) { throw 'Cannot publish an empty APK.' }
    $version = Read-ProjectVersion
    $dist = Join-Path $ProjectRoot 'dist'
    [IO.Directory]::CreateDirectory($dist) | Out-Null
    if ((Get-Item -LiteralPath $dist).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing publication into a linked dist directory.' }
    $hash = Get-Hash $ApkPath
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $archive = Join-Path $dist ('nexus-agent-' + $version.Replace('+','_') + '-' + $stamp + '.apk')
    $latest = Join-Path $dist 'nexus-agent-latest.apk'
    $stage = Join-Path $dist ('.publish-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    $replaced = @(); $previous = @{}; $preserveStage = $false
    try {
        foreach ($target in @($archive, ($archive+'.sha256'), $latest, ($latest+'.sha256'))) {
            if (Test-Path -LiteralPath $target) {
                if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to replace a linked publication target.' }
            }
        }
        $stagedApk = Join-Path $stage 'new.apk'
        [IO.File]::Copy($ApkPath, $stagedApk, $false)
        [IO.File]::WriteAllText(($stagedApk+'.sha256'), $hash + "`r`n", [Text.Encoding]::ASCII)
        if (-not (Test-Pair $stagedApk)) { throw 'Staged APK failed SHA-256 verification.' }
        foreach ($target in @($latest, ($latest+'.sha256'))) {
            if (Test-Path -LiteralPath $target) {
                $backup = Join-Path $stage ([IO.Path]::GetFileName($target) + '.previous')
                [IO.File]::Copy($target, $backup, $false); $previous[$target] = $backup
            }
        }
        [IO.File]::Copy($stagedApk, $archive, $false)
        [IO.File]::Copy(($stagedApk+'.sha256'), ($archive+'.sha256'), $false)
        if (-not (Test-Pair $archive)) { throw 'Archived APK failed SHA-256 verification.' }
        foreach ($target in @($latest, ($latest+'.sha256'))) {
            $source = if ($target.EndsWith('.sha256')) { $stagedApk+'.sha256' } else { $stagedApk }
            $candidate = Join-Path $stage ([IO.Path]::GetFileName($target) + '.next')
            [IO.File]::Copy($source, $candidate, $false)
            if (Test-Path -LiteralPath $target) { [IO.File]::Replace($candidate, $target, (Join-Path $stage ([IO.Path]::GetFileName($target) + '.replace-backup'))) }
            else { [IO.File]::Move($candidate, $target) }
            $replaced += $target
        }
        if (-not (Test-Pair $latest)) { throw 'Latest APK failed SHA-256 verification.' }
        [IO.File]::WriteAllText(($ApkPath+'.sha256'), $hash + "`r`n", [Text.Encoding]::ASCII)
        [IO.File]::WriteAllLines($ResultFile, @("DIST_APK_PATH=$archive", "LATEST_APK_PATH=$latest", "APK_HASH=$hash", "APP_VERSION=$version"), [Text.Encoding]::Default)
    } catch {
        try {
            foreach ($target in $replaced) {
                if ($previous.ContainsKey($target)) { [IO.File]::Copy($previous[$target], $target, $true) }
                elseif (Test-Path -LiteralPath $target) { [IO.File]::Delete($target) }
            }
        } catch {
            $preserveStage = $true
            Write-Warning ('Automatic rollback failed. Preserve recovery files in: ' + $stage)
            throw
        }
        throw
    } finally {
        # Remove only our uniquely created staging directory, never arbitrary dist contents.
        if (-not $preserveStage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
    # Retention only runs after publication is verified. Unknown files and invalid pairs stay untouched.
    if (-not $KeepAll) {
        try {
            $items = @()
            foreach ($file in Get-ChildItem -LiteralPath $dist -File -Filter 'nexus-agent-*.apk') {
                if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $match = [regex]::Match($file.Name, '^nexus-agent-(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?_\d+)-(\d{8}-\d{6}(?:\d{3}-[a-f0-9]{8})?)\.apk$')
                if (-not $match.Success -or -not (Test-Pair $file.FullName)) { continue }
                if ((Get-Item -LiteralPath ($file.FullName+'.sha256')).Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $items += [pscustomobject]@{ Path=$file.FullName; Version=$match.Groups[1].Value; Stamp=$match.Groups[2].Value }
            }
            $items = @($items | Sort-Object Stamp -Descending)
            $keepers = @($archive)
            $rollback = $items | Where-Object { $_.Version -ne $version.Replace('+','_') } | Select-Object -First 1
            if ($rollback) { $keepers += $rollback.Path }
            foreach ($item in $items) { if ($keepers.Count -lt $Keep -and $item.Path -notin $keepers) { $keepers += $item.Path } }
            $deleted = 0
            foreach ($item in $items) {
                if ($item.Path -notin $keepers) {
                    # Recheck pair immediately before deletion; no broad wildcard removal.
                    if (-not (Test-Pair $item.Path)) { continue }
                    [IO.File]::Delete($item.Path); [IO.File]::Delete(($item.Path+'.sha256')); $deleted++
                }
            }
            Write-Host "[retention] Removed $deleted old verified APK pair(s); keeping up to $Keep timestamped packages plus latest."
        } catch { Write-Warning ('APK published, but retention was skipped/interrupted: ' + $_.Exception.Message) }
    }
    Write-Host "[publish] Verified package: $archive"
}
try {
    $ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
    if ($Action -eq 'Preflight') { Invoke-Preflight } else { Invoke-Publish }
    exit 0
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
    exit 1
}
