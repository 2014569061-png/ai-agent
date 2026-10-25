param(
    [string]$FlutterExe = 'flutter',
    [string]$NuGetExe,
    [string]$SentryNativeSource,
    [switch]$SkipPub,
    [switch]$SkipPackage
)

$ErrorActionPreference = 'Stop'
$desktopRepo = Split-Path -Parent $PSScriptRoot
$desktopTools = Join-Path $desktopRepo 'local\desktop-tools'
$desktopRelease = Join-Path $desktopRepo 'build\windows\x64\runner\Release'
$desktopOutput = Join-Path $desktopRepo 'dist\windows'
$desktopOriginalPath = $env:PATH
$desktopOriginalSentrySource = $env:NEXUS_SENTRY_NATIVE_SOURCE
$desktopOriginalLocation = Get-Location

try {
    Set-Location -LiteralPath $desktopRepo
    $desktopFlutterCommand = Get-Command $FlutterExe -ErrorAction Stop
    $desktopFlutterPath = $desktopFlutterCommand.Source
    $env:PATH = (Split-Path -Parent $desktopFlutterPath) + ';' + $desktopTools + ';' + $env:PATH
    if ($NuGetExe) {
        $desktopNuGetPath = (Resolve-Path -LiteralPath $NuGetExe).Path
        $env:PATH = (Split-Path -Parent $desktopNuGetPath) + ';' + $env:PATH
    }
    if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
        throw 'NuGet CLI is required. Put nuget.exe on PATH or pass -NuGetExe. See README.md.'
    }
    if ($SentryNativeSource) {
        $desktopSentrySource = (Resolve-Path -LiteralPath $SentryNativeSource).Path
        if (-not (Test-Path -LiteralPath (Join-Path $desktopSentrySource 'CMakeLists.txt'))) {
            throw 'SentryNativeSource must contain the native SDK source and its Windows dependencies.'
        }
        $env:NEXUS_SENTRY_NATIVE_SOURCE = $desktopSentrySource
    }
    if (-not $SkipPub) {
        & $desktopFlutterPath pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency restore failed.' }
    }

    # VS upgrades change the generator and instance path. Preserve old cache
    # rather than asking Flutter to reuse an incompatible CMake configuration.
    $desktopCache = Join-Path $desktopRepo 'build\windows\x64\CMakeCache.txt'
    $desktopVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if ((Test-Path -LiteralPath $desktopCache) -and (Test-Path -LiteralPath $desktopVswhere)) {
        $desktopInstance = (& $desktopVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
        $desktopCachedInstance = Select-String -LiteralPath $desktopCache -Pattern '^CMAKE_GENERATOR_INSTANCE:[^=]+=(.*)$'
        if ($desktopInstance -and $desktopCachedInstance -and
            $desktopCachedInstance.Matches[0].Groups[1].Value.Replace('/', '\').TrimEnd('\') -ine $desktopInstance.TrimEnd('\')) {
            $desktopOldBuild = (Resolve-Path -LiteralPath (Split-Path -Parent $desktopCache)).Path
            $desktopArchive = Join-Path $desktopRepo ('artifacts\desktop\old-windows-build-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
            if (-not $desktopOldBuild.StartsWith($desktopRepo + '\', [StringComparison]::OrdinalIgnoreCase) -or
                -not $desktopArchive.StartsWith($desktopRepo + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Build archive must stay within this workspace.'
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $desktopArchive) | Out-Null
            Move-Item -LiteralPath $desktopOldBuild -Destination $desktopArchive
        }
    }
    & $desktopFlutterPath build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    $desktopApp = Join-Path $desktopRelease 'mobile_agent.exe'
    if (-not (Test-Path -LiteralPath $desktopApp)) { throw 'Release executable is missing.' }
    if (-not $SkipPackage) {
        New-Item -ItemType Directory -Force -Path $desktopOutput | Out-Null
        $desktopVersionLine = Select-String -LiteralPath (Join-Path $desktopRepo 'pubspec.yaml') -Pattern '^version:\s*(\S+)'
        $desktopVersion = $desktopVersionLine.Matches[0].Groups[1].Value.Replace('+', '-')
        $desktopZip = Join-Path $desktopOutput ('nexus-agent-' + $desktopVersion + '-windows-x64.zip')
        # The complete Release folder includes data, DLLs and native assets.
        Compress-Archive -Path (Join-Path $desktopRelease '*') -DestinationPath $desktopZip -Force
        $desktopHash = (Get-FileHash -LiteralPath $desktopZip -Algorithm SHA256).Hash.ToLowerInvariant()
        ($desktopHash + '  ' + (Split-Path -Leaf $desktopZip)) | Set-Content -LiteralPath ($desktopZip + '.sha256') -Encoding ascii
        Write-Output "Windows package: $desktopZip"
    }
    Write-Output "Windows executable: $desktopApp"
} finally {
    $env:PATH = $desktopOriginalPath
    $env:NEXUS_SENTRY_NATIVE_SOURCE = $desktopOriginalSentrySource
    Set-Location -LiteralPath $desktopOriginalLocation.Path
}
