@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Build a signed ARM64 release APK.
rem Default mode keeps incremental Flutter and Gradle outputs. Use --clean
rem only when a reproducible cold build is required.

pushd "%~dp0"
if errorlevel 1 (
  echo.
  echo [ERROR] Cannot open the project directory: %~dp0
  if /i not "%CI%"=="true" pause
  exit /b 1
)

set "PROJECT_ROOT=%CD%"
set "FLUTTER_CMD="
set "FLUTTER_SOURCE="
set "LOCAL_FLUTTER_SDK="
set "SELECTED_JDK17_HOME=%JDK17_HOME%"
set "JAVA_VERSION="
set "JAVA_VERSION_FILE=%TEMP%\mobile_agent_java_version_%RANDOM%_%RANDOM%.txt"
set "BUILD_MARKER=%TEMP%\mobile_agent_build_start_%RANDOM%_%RANDOM%.marker"
set "BUILD_START_TICKS="
set "BUILD_SECONDS=unknown"
set "ANDROID_VERSION="
set "APP_VERSION="
set "APK_HASH="
set "EXIT_CODE=1"
set "BUILD_MODE=incremental"
set "FAST_BUILD=0"
set "DEPENDENCY_MODE=auto"
set "NO_PAUSE=0"
set "INSTALL_AFTER_BUILD=0"
set "ADB_CMD="
set "CHECK_ONLY=0"
set "NO_OPEN=0"
set "KEEP_APKS=3"
set "KEEP_ALL=0"
set "PUBLISHED=0"
set "LOCK_OWNED=0"
set "PUBLISH_RESULT="
set "BUILD_LOG="
set "TOOLS_SCRIPT=%~dp0tool\build-apk-tools.ps1"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--help" (
  call :print_help
  set "EXIT_CODE=0"
  set "NO_PAUSE=1"
  goto :finish
)
if /i "%~1"=="-h" (
  call :print_help
  set "EXIT_CODE=0"
  set "NO_PAUSE=1"
  goto :finish
)
if /i "%~1"=="--no-pause" (
  set "NO_PAUSE=1"
  shift
  goto :parse_args
)
if /i "%~1"=="--no-open" (
  set "NO_OPEN=1"
  shift
  goto :parse_args
)
if /i "%~1"=="--check" (
  set "CHECK_ONLY=1"
  shift
  goto :parse_args
)
if /i "%~1"=="--keep-all" (
  set "KEEP_ALL=1"
  shift
  goto :parse_args
)
if /i "%~1"=="--keep" (
  set "KEEP_APKS=%~2"
  if "%~2"=="" (
    echo [ERROR] --keep requires an integer from 2 to 50.
    goto :fail
  )
  shift
  shift
  goto :parse_args
)
if /i "%~1"=="--clean" (
  set "BUILD_MODE=clean"
  shift
  goto :parse_args
)
if /i "%~1"=="--fast" (
  set "FAST_BUILD=1"
  shift
  goto :parse_args
)
if /i "%~1"=="--offline" (
  if /i "!DEPENDENCY_MODE!"=="online" goto :conflicting_dependency_modes
  set "DEPENDENCY_MODE=offline"
  shift
  goto :parse_args
)
if /i "%~1"=="--online" (
  if /i "!DEPENDENCY_MODE!"=="offline" goto :conflicting_dependency_modes
  set "DEPENDENCY_MODE=online"
  shift
  goto :parse_args
)
if /i "%~1"=="--install" (
  set "INSTALL_AFTER_BUILD=1"
  shift
  goto :parse_args
)
echo.
echo [ERROR] Unknown option: %~1
echo Use build-apk.bat --help for usage.
goto :fail

:conflicting_dependency_modes
echo.
echo [ERROR] --offline and --online cannot be used together.
goto :fail

:args_done
where.exe powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Windows PowerShell is required.
  goto :fail
)
if not exist "!TOOLS_SCRIPT!" (
  echo [ERROR] Missing tool\build-apk-tools.ps1. Restore the helper from this repository.
  goto :fail
)
powershell.exe -NoProfile -Command "$n=0; if ($env:KEEP_APKS -notmatch '^[0-9]+$' -or -not [int]::TryParse($env:KEEP_APKS,[ref]$n) -or $n -lt 2 -or $n -gt 50) { exit 1 }"
if errorlevel 1 (
  echo [ERROR] --keep must be an integer from 2 to 50.
  goto :fail
)
if /i "!BUILD_MODE!"=="clean" if /i not "!DEPENDENCY_MODE!"=="online" (
  echo [ERROR] --clean requires --online: cleaning removes the sqlite3 native cache.
  echo No cache or build output has been removed.
  goto :fail
)
rem Prefer an explicitly configured Flutter SDK, then the project SDK, then PATH.
if defined FLUTTER_BIN if exist "%FLUTTER_BIN%" (
  set "FLUTTER_CMD=%FLUTTER_BIN%"
  set "FLUTTER_SOURCE=FLUTTER_BIN"
)

if not defined FLUTTER_CMD if defined FLUTTER_HOME if exist "%FLUTTER_HOME%\bin\flutter.bat" (
  set "FLUTTER_CMD=%FLUTTER_HOME%\bin\flutter.bat"
  set "FLUTTER_SOURCE=FLUTTER_HOME"
)

if not defined FLUTTER_CMD if exist "android\local.properties" (
  for /f "usebackq tokens=1,* delims==" %%A in ("android\local.properties") do (
    if /i "%%A"=="flutter.sdk" set "LOCAL_FLUTTER_SDK=%%B"
  )
  set "LOCAL_FLUTTER_SDK=!LOCAL_FLUTTER_SDK:\\=\!"
  if defined LOCAL_FLUTTER_SDK if exist "!LOCAL_FLUTTER_SDK!\bin\flutter.bat" (
    set "FLUTTER_CMD=!LOCAL_FLUTTER_SDK!\bin\flutter.bat"
    set "FLUTTER_SOURCE=android\local.properties"
  )
)

if not defined FLUTTER_CMD (
  rem Prefer Flutter's Windows batch launcher over extensionless PATH shims.
  for /f "delims=" %%F in ('where.exe flutter.bat 2^>nul') do if not defined FLUTTER_CMD (
    set "FLUTTER_CMD=%%F"
    set "FLUTTER_SOURCE=PATH"
  )
)

if not defined FLUTTER_CMD (
  echo.
  echo [ERROR] Flutter could not be found.
  echo Checked: FLUTTER_BIN, FLUTTER_HOME, android\local.properties, and PATH.
  if defined LOCAL_FLUTTER_SDK echo Project Flutter SDK setting: !LOCAL_FLUTTER_SDK!
  echo.
  echo Set FLUTTER_HOME to your Flutter SDK folder, or add its bin folder to PATH.
  goto :fail
)

rem This project requires JDK 17. Keep the selection local to this process.
if defined SELECTED_JDK17_HOME if not exist "%SELECTED_JDK17_HOME%\bin\javac.exe" set "SELECTED_JDK17_HOME="
if not defined SELECTED_JDK17_HOME for /d %%J in ("C:\Program Files\Microsoft\jdk-17*") do if not defined SELECTED_JDK17_HOME (
  if exist "%%~J\bin\javac.exe" set "SELECTED_JDK17_HOME=%%~J"
)
if not defined SELECTED_JDK17_HOME for /d %%J in ("C:\Program Files\Java\jdk-17*") do if not defined SELECTED_JDK17_HOME (
  if exist "%%~J\bin\javac.exe" set "SELECTED_JDK17_HOME=%%~J"
)
if not defined SELECTED_JDK17_HOME for /d %%J in ("C:\Program Files\Eclipse Adoptium\jdk-17*") do if not defined SELECTED_JDK17_HOME (
  if exist "%%~J\bin\javac.exe" set "SELECTED_JDK17_HOME=%%~J"
)
if not defined SELECTED_JDK17_HOME for /d %%J in ("C:\Program Files\BellSoft\LibericaJDK-17*") do if not defined SELECTED_JDK17_HOME (
  if exist "%%~J\bin\javac.exe" set "SELECTED_JDK17_HOME=%%~J"
)
if not defined SELECTED_JDK17_HOME if defined JAVA_HOME if exist "%JAVA_HOME%\bin\javac.exe" (
  set "SELECTED_JDK17_HOME=%JAVA_HOME%"
)

if not defined SELECTED_JDK17_HOME (
  echo.
  echo [ERROR] JDK 17 could not be found.
  echo Install JDK 17 or set JDK17_HOME to its installation folder.
  echo Example: set JDK17_HOME=C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot
  goto :fail
)

set "JAVA_HOME=!SELECTED_JDK17_HOME!"
set "PATH=!JAVA_HOME!\bin;%PATH%"
"!JAVA_HOME!\bin\javac.exe" -version > "!JAVA_VERSION_FILE!" 2>&1
set /p "JAVA_VERSION=" < "!JAVA_VERSION_FILE!"
del "!JAVA_VERSION_FILE!" >nul 2>&1

if /i not "!JAVA_VERSION:~0,8!"=="javac 17" (
  echo.
  echo [ERROR] The selected Java installation is not JDK 17: !JAVA_HOME!
  echo Detected: !JAVA_VERSION!
  goto :fail
)

if not exist "pubspec.yaml" (
  echo [ERROR] pubspec.yaml was not found under !PROJECT_ROOT!
  goto :fail
)
if not exist "pubspec.lock" (
  echo [ERROR] pubspec.lock was not found. Restore the locked dependency file first.
  goto :fail
)
if not exist "android\gradlew.bat" (
  echo [ERROR] android\gradlew.bat was not found under !PROJECT_ROOT!
  goto :fail
)
if not exist "android\key.properties" (
  echo [ERROR] android\key.properties is missing. A signed APK cannot be built.
  goto :fail
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!TOOLS_SCRIPT!" -Action Preflight -ProjectRoot "!PROJECT_ROOT!"
if errorlevel 1 goto :fail

if "!CHECK_ONLY!"=="1" (
  call :package_config_is_current
  if errorlevel 1 (
    echo [ERROR] Dependency configuration is missing or stale. Run --offline or --online to restore it.
    goto :fail
  )
  call :has_sqlite_native_cache
  if errorlevel 1 (
    echo [ERROR] sqlite3 ARM64 cache is missing or invalid. An online build is required.
    goto :fail
  )
  echo [SUCCESS] Read-only preflight passed. No build or device installation was performed.
  set "EXIT_CODE=0"
  goto :finish
)

if not exist "artifacts\build-apk" mkdir "artifacts\build-apk"
if not exist "artifacts\build-apk" goto :fail
set "BUILD_LOCK=!PROJECT_ROOT!\artifacts\build-apk\.lock"
mkdir "!BUILD_LOCK!" 2>nul
if errorlevel 1 (
  echo [ERROR] Another build owns artifacts\build-apk\.lock.
  echo If a previous build crashed, verify no build is running before removing that empty lock directory.
  goto :fail
)
set "LOCK_OWNED=1"
set "BUILD_LOG=!PROJECT_ROOT!\artifacts\build-apk\build-%RANDOM%-%RANDOM%.log"
set "PUBLISH_RESULT=!BUILD_LOG!.publish.env"
echo [info] Build log: !BUILD_LOG!

set "APK_DIR=!PROJECT_ROOT!\build\app\outputs\flutter-apk"
set "APK_PATH=!APK_DIR!\app-release.apk"
set "CHECKSUM_PATH=!APK_PATH!.sha256"

if /i "!BUILD_MODE!"=="clean" (
  echo.
  echo [1/5] Cleaning generated outputs ^(explicit --clean mode^)...
  call "android\gradlew.bat" -p android --stop >nul 2>&1
  call "!FLUTTER_CMD!" clean
  if errorlevel 1 goto :fail
  if exist "!PROJECT_ROOT!\build\app" rmdir /s /q "!PROJECT_ROOT!\build\app" >nul 2>&1
  if exist "!PROJECT_ROOT!\build\app" (
    echo [ERROR] The old build\app directory remains after flutter clean.
    echo Close Android Studio/Gradle tools and run this script again.
    goto :fail
  )
) else (
  echo.
  echo [1/5] Reusing incremental Flutter and Gradle outputs.
)

set "NEEDS_PUB_GET=0"
if /i "!DEPENDENCY_MODE!"=="online" set "NEEDS_PUB_GET=1"
if /i "!DEPENDENCY_MODE!"=="offline" set "NEEDS_PUB_GET=1"
if /i "!DEPENDENCY_MODE!"=="auto" (
  if /i "!BUILD_MODE!"=="clean" (
    set "NEEDS_PUB_GET=1"
  ) else (
    call :package_config_is_current
    if errorlevel 1 set "NEEDS_PUB_GET=1"
  )
)

if "!NEEDS_PUB_GET!"=="1" (
  echo.
  if /i "!DEPENDENCY_MODE!"=="online" (
    echo [2/5] Restoring dependencies online ^(--online^)...
    call "!FLUTTER_CMD!" pub get
  ) else (
    echo [2/5] Restoring dependencies from the local cache ^(--offline^)...
    call "!FLUTTER_CMD!" pub get --offline
  )
  if errorlevel 1 (
    echo.
    if /i "!DEPENDENCY_MODE!"=="online" (
      echo [ERROR] Online dependency restore failed.
    ) else (
      echo [ERROR] Offline dependency restore failed because the local cache is incomplete.
      echo Run build-apk.bat --online once to warm the dependency cache.
    )
    goto :fail
  )
) else (
  echo.
  echo [2/5] Dependency configuration is current; skipping pub get.
)

rem The sqlite3 hook downloads an ARM64 shared library outside the Pub cache.
rem Refuse to enter a long network timeout unless the caller explicitly opted in.
if /i not "!DEPENDENCY_MODE!"=="online" (
  call :has_sqlite_native_cache
  if errorlevel 1 (
    echo.
    echo [ERROR] The cached sqlite3 native asset was not found.
    echo This build would try to reach GitHub from the native-assets hook.
    echo Run build-apk.bat --online once to warm it, then use --offline locally.
    goto :fail
  )
  echo [info] Cached sqlite3 native asset found; its hash will still be verified by the hook.
)

rem Remove only the publish target. Intermediate outputs stay available for incremental builds.
if exist "!APK_PATH!" del /f /q "!APK_PATH!" >nul 2>&1
if exist "!CHECKSUM_PATH!" del /f /q "!CHECKSUM_PATH!" >nul 2>&1
if exist "!APK_PATH!" (
  echo [ERROR] Could not remove the previous release APK:
  echo !APK_PATH!
  goto :fail
)

if not exist "!APK_DIR!" mkdir "!APK_DIR!" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Could not create the APK output directory: !APK_DIR!
  goto :fail
)

break > "!BUILD_MARKER!"
for /f "delims=" %%A in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).ToFileTimeUtc()"') do set "BUILD_START_TICKS=%%A"

echo.
set "BUILD_ARGS=build apk --release --target-platform android-arm64 --no-pub --android-skip-build-dependency-validation"
if "!FAST_BUILD!"=="1" set "BUILD_ARGS=!BUILD_ARGS! --android-project-arg=fastBuild=true"
echo [3/5] Building signed ARM64 release APK ^(!BUILD_MODE! mode^)...
if "!FAST_BUILD!"=="1" echo [info] --fast enabled: skipping R8/resource shrinking for this local build.
> "!BUILD_LOG!" echo Build started: %DATE% %TIME%
rem Use cmd redirection instead of PowerShell's native stderr pipeline. This keeps
rem Flutter warnings in the log without re-labelling them as NativeCommandError.
call "!FLUTTER_CMD!" !BUILD_ARGS! >> "!BUILD_LOG!" 2>&1
if errorlevel 1 (
  type "!BUILD_LOG!"
  goto :fail
)
type "!BUILD_LOG!"

call :measure_build_seconds

if not exist "!APK_PATH!" (
  echo [ERROR] Build completed but the APK was not found:
  echo !APK_PATH!
  goto :fail
)
for %%F in ("!APK_PATH!") do if %%~zF EQU 0 (
  echo [ERROR] The generated APK is empty.
  goto :fail
)

rem Refuse to publish a pre-existing release file even if a tool returned success.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$marker = Get-Item -LiteralPath $env:BUILD_MARKER -ErrorAction Stop; $apk = Get-Item -LiteralPath $env:APK_PATH -ErrorAction Stop; if ($apk.LastWriteTimeUtc -le $marker.LastWriteTimeUtc) { Write-Error 'APK timestamp is not newer than the build marker'; exit 1 }"
if errorlevel 1 (
  echo [ERROR] The APK was not freshly generated. Refusing to publish it.
  goto :fail
)

rem --fast intentionally skips R8/resource shrinking, so its output must never
rem replace the stable dist\ latest package or enter release retention.
if "!FAST_BUILD!"=="1" (
  echo.
  echo [4/5] Skipping publication: --fast output is a local-only build.
  echo [info] dist\ and the stable latest package were left untouched.
  if "!INSTALL_AFTER_BUILD!"=="1" (
    set "INSTALL_APK=!APK_PATH!"
    call :install_apk
    if errorlevel 1 goto :fail
  )
  echo.
  echo ========================================
  echo [SUCCESS] Fast local ARM64 APK is ready ^(not a release artifact^):
  echo !APK_PATH!
  echo Build time: !BUILD_SECONDS! seconds
  echo Build log: !BUILD_LOG!
  echo ========================================
  set "EXIT_CODE=0"
  goto :finish
)

echo.
echo [4/5] Publishing verified APK and applying history retention...
set "KEEP_ALL_ARG="
if "!KEEP_ALL!"=="1" set "KEEP_ALL_ARG=-KeepAll"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!TOOLS_SCRIPT!" -Action Publish -ProjectRoot "!PROJECT_ROOT!" -ApkPath "!APK_PATH!" -ResultFile "!PUBLISH_RESULT!" -Keep !KEEP_APKS! !KEEP_ALL_ARG!
if errorlevel 1 goto :fail
for /f "usebackq tokens=1,* delims==" %%A in ("!PUBLISH_RESULT!") do set "%%A=%%B"
set "PUBLISHED=1"
set "DIST_CHECKSUM_PATH=!DIST_APK_PATH!.sha256"
set "LATEST_CHECKSUM_PATH=!LATEST_APK_PATH!.sha256"
if "!INSTALL_AFTER_BUILD!"=="1" (
  call :install_latest_apk
  if errorlevel 1 goto :fail
)

echo.
echo [5/5] Release artifact checks complete.
echo.
echo ========================================
echo [SUCCESS] Fresh signed ARM64 release APK is ready:
echo !APK_PATH!
echo Shareable APK: !DIST_APK_PATH!
echo Stable latest APK: !LATEST_APK_PATH!
echo Pubspec version: !APP_VERSION!
echo Build time: !BUILD_SECONDS! seconds
echo Build log: !BUILD_LOG!
echo SHA-256: !APK_HASH!
echo Checksum: !CHECKSUM_PATH!
echo Shareable checksum: !DIST_CHECKSUM_PATH!
echo Stable checksum: !LATEST_CHECKSUM_PATH!
echo ========================================
if /i not "%CI%"=="true" if "!NO_OPEN!"=="0" explorer.exe /select,"!LATEST_APK_PATH!"
set "EXIT_CODE=0"
goto :finish

:fail
echo.
echo ========================================
if "!PUBLISHED!"=="1" (
  echo [FAILED] APK publication succeeded, but installation or launch failed.
  echo The verified package is still available: !LATEST_APK_PATH!
) else (
  echo [FAILED] Build/preflight/publication did not complete. Check the error above.
)
if defined BUILD_LOG echo Build log, if build started: !BUILD_LOG!
echo ========================================
set "EXIT_CODE=1"

goto :finish

:finish
if defined PUBLISH_RESULT if exist "!PUBLISH_RESULT!" del "!PUBLISH_RESULT!" >nul 2>&1
if "!LOCK_OWNED!"=="1" rmdir "!BUILD_LOCK!" >nul 2>&1
if exist "!BUILD_MARKER!" del "!BUILD_MARKER!" >nul 2>&1
if exist "!JAVA_VERSION_FILE!" del "!JAVA_VERSION_FILE!" >nul 2>&1
popd
if /i not "%CI%"=="true" if "!NO_PAUSE!"=="0" pause
exit /b !EXIT_CODE!

:print_help
echo.
echo Usage: build-apk.bat [--offline ^| --online] [--clean] [--fast] [--install]
echo                      [--check] [--keep N ^| --keep-all] [--no-pause] [--no-open]
echo.
echo Default:
echo   Reuse incremental Flutter and Gradle outputs. If pubspec files changed,
echo   restore dependencies from the local cache without silently going online.
echo.
echo --offline  Always run flutter pub get --offline and require a cached sqlite3 asset.
echo --online   Explicitly allow network access for dependency and native-asset restore.
echo --clean    Remove generated outputs. Requires --online to restore native assets.
echo --fast     Local iteration mode; skips R8/resource shrinking for a faster APK.
echo             The result is not published to dist\ and never replaces latest.
echo --install  Install and launch the stable latest APK on the only connected
echo            Android device. Set ADB_SERIAL when multiple devices are connected.
echo --check    Read-only environment, version, signing-file and cache checks; no build.
echo --keep N   Keep N timestamped packages ^(2..50; default 3^) plus latest.
echo            Preserve one different-version candidate where available.
echo --keep-all Disable automatic APK pruning for this build.
echo --no-pause Do not wait for a key at exit ^(also automatic when CI=true^).
echo --no-open  Do not open Explorer after success.
echo --help     Show this message.
echo Retention only removes recognized APK/checksum pairs after a verified publication.
echo --offline constrains Pub restore; it is not a network firewall for Gradle/hooks.
echo.
exit /b 0

:install_latest_apk
set "INSTALL_APK=!LATEST_APK_PATH!"

:install_apk
set "ADB_CMD="
if defined ADB_BIN if exist "!ADB_BIN!" set "ADB_CMD=!ADB_BIN!"
if not defined ADB_CMD for /f "delims=" %%F in ('where.exe adb.exe 2^>nul') do if not defined ADB_CMD set "ADB_CMD=%%F"
if not defined ADB_CMD (
  echo [ERROR] --install was requested but adb.exe was not found.
  exit /b 1
)

set "ADB_DEVICE_COUNT=0"
for /f "skip=1 tokens=1,2" %%A in ('"!ADB_CMD!" devices 2^>nul') do if /i "%%B"=="device" set /a ADB_DEVICE_COUNT+=1
if "!ADB_DEVICE_COUNT!"=="0" (
  echo [ERROR] --install was requested but no authorized Android device is connected.
  exit /b 1
)
if !ADB_DEVICE_COUNT! GTR 1 if not defined ADB_SERIAL (
  echo [ERROR] Multiple Android devices are connected. Set ADB_SERIAL and retry.
  exit /b 1
)

set "ADB_TARGET_ARGS="
if defined ADB_SERIAL set ADB_TARGET_ARGS=-s "!ADB_SERIAL!"
echo.
echo [install] Installing !INSTALL_APK!
call "!ADB_CMD!" !ADB_TARGET_ARGS! install -r "!INSTALL_APK!"
if errorlevel 1 (
  echo [ERROR] APK installation failed. The existing app may use a different signature or version.
  exit /b 1
)
call "!ADB_CMD!" !ADB_TARGET_ARGS! shell am force-stop com.nexusagent.app >nul 2>&1
call "!ADB_CMD!" !ADB_TARGET_ARGS! shell monkey -p com.nexusagent.app 1 >nul 2>&1
if errorlevel 1 (
  echo [ERROR] APK installed, but launching com.nexusagent.app failed.
  exit /b 1
)
echo [install] Latest APK installed and launched.
exit /b 0

:measure_build_seconds
if not defined BUILD_START_TICKS exit /b 0
set "BUILD_START_TICKS=!BUILD_START_TICKS!"
for /f "delims=" %%A in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$start=[DateTime]::FromFileTimeUtc([int64]$env:BUILD_START_TICKS); [math]::Round(((Get-Date).ToUniversalTime()-$start).TotalSeconds,1)"') do set "BUILD_SECONDS=%%A"
exit /b 0

:package_config_is_current
if not exist ".dart_tool\package_config.json" exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$files=@('pubspec.yaml','pubspec.lock') | ForEach-Object { if (-not (Test-Path -LiteralPath $_)) { exit 1 }; Get-Item -LiteralPath $_ }; $config=Get-Item -LiteralPath '.dart_tool\package_config.json' -ErrorAction Stop; $latest=($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc; if ($config.LastWriteTimeUtc -gt $latest) { exit 0 }; exit 1"
if errorlevel 1 exit /b 1
exit /b 0

:has_sqlite_native_cache
if not exist ".dart_tool\package_config.json" exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$config=Get-Content -Raw -LiteralPath '.dart_tool\package_config.json' | ConvertFrom-Json; $pkg=@($config.packages | Where-Object { $_.name -eq 'sqlite3' }) | Select-Object -First 1; if ($null -eq $pkg) { exit 1 }; $configUri=[Uri]::new((Resolve-Path -LiteralPath '.dart_tool\package_config.json').Path); $root=[Uri]::new($configUri,[string]$pkg.rootUri).LocalPath; $source=Join-Path $root 'lib\src\hook\asset_hashes.dart'; if (-not (Test-Path -LiteralPath $source)) { exit 1 }; $line=Get-Content -LiteralPath $source | Where-Object { $_ -like '*libsqlite3.arm64.android.so*' } | Select-Object -First 1; if (-not $line) { exit 1 }; $hash=(($line -split [char]39)[3]).ToLowerInvariant(); if ($hash.Length -ne 64) { exit 1 }; $cache=Join-Path (Join-Path (Get-Location) '.dart_tool\hooks_runner\shared\sqlite3\build') ('download-' + $hash.Substring(0,8)); $file=Join-Path $cache 'libsqlite3.so'; if (-not (Test-Path -LiteralPath $file)) { exit 1 }; $sha=[Security.Cryptography.SHA256]::Create(); $stream=[IO.File]::OpenRead($file); try { $actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $stream.Dispose(); $sha.Dispose() }; if ($actual -ne $hash) { exit 1 }; exit 0"
if errorlevel 1 exit /b 1
exit /b 0
