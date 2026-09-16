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
set "DEPENDENCY_MODE=auto"
set "NO_PAUSE=0"

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
if /i "%~1"=="--clean" (
  set "BUILD_MODE=clean"
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
echo.
echo [ERROR] Unknown option: %~1
echo Use build-apk.bat --help for usage.
goto :fail

:conflicting_dependency_modes
echo.
echo [ERROR] --offline and --online cannot be used together.
goto :fail

:args_done
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
if not defined SELECTED_JDK17_HOME if exist "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot\bin\javac.exe" (
  set "SELECTED_JDK17_HOME=C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"
)
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
if not exist "android\app\upload-keystore.jks" (
  echo [ERROR] android\app\upload-keystore.jks is missing. A signed APK cannot be built.
  goto :fail
)

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

rem Remove only the publish target. Intermediate outputs stay available for incremental builds.
if exist "!APK_PATH!" del /f /q "!APK_PATH!" >nul 2>&1
if exist "!CHECKSUM_PATH!" del /f /q "!CHECKSUM_PATH!" >nul 2>&1
if exist "!APK_PATH!" (
  echo [ERROR] Could not remove the previous release APK:
  echo !APK_PATH!
  goto :fail
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

if not exist "!APK_DIR!" mkdir "!APK_DIR!" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Could not create the APK output directory: !APK_DIR!
  goto :fail
)

break > "!BUILD_MARKER!"
for /f "delims=" %%A in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).ToFileTimeUtc()"') do set "BUILD_START_TICKS=%%A"

echo.
echo [3/5] Building signed ARM64 release APK ^(!BUILD_MODE! mode^)...
call "!FLUTTER_CMD!" build apk --release --target-platform android-arm64 --no-pub
if errorlevel 1 goto :fail

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$marker = Get-Item -LiteralPath '!BUILD_MARKER!' -ErrorAction Stop; $apk = Get-Item -LiteralPath '!APK_PATH!' -ErrorAction Stop; if ($apk.LastWriteTimeUtc -le $marker.LastWriteTimeUtc) { Write-Error 'APK timestamp is not newer than the build marker'; exit 1 }"
if errorlevel 1 (
  echo [ERROR] The APK was not freshly generated. Refusing to publish it.
  goto :fail
)

echo.
echo [4/5] Writing the APK SHA-256 sidecar...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -LiteralPath '!APK_PATH!' -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -LiteralPath '!CHECKSUM_PATH!' -Encoding ascii"
if errorlevel 1 (
  echo [ERROR] Failed to write the SHA-256 file.
  goto :fail
)
set /p "APK_HASH=" < "!CHECKSUM_PATH!"
if not defined APK_HASH (
  echo [ERROR] The SHA-256 file is empty.
  goto :fail
)

for /f "tokens=1,*" %%A in ('findstr /b /c:"version:" pubspec.yaml') do set "APP_VERSION=%%B"
for /f "tokens=2 delims==" %%A in ('findstr /c:"versionName =" android\app\build.gradle.kts') do set "ANDROID_VERSION=%%~A"
set "ANDROID_VERSION=!ANDROID_VERSION:"=!"
set "ANDROID_VERSION=!ANDROID_VERSION: =!"
set "APP_VERSION_FILE=!APP_VERSION:+=_!"
for /f "delims=" %%A in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')"') do set "BUILD_STAMP=%%A"
set "DIST_DIR=!PROJECT_ROOT!\dist"
set "DIST_APK_PATH=!DIST_DIR!\nexus-agent-!APP_VERSION_FILE!-!BUILD_STAMP!.apk"
set "DIST_CHECKSUM_PATH=!DIST_APK_PATH!.sha256"
if not defined APP_VERSION (
  echo [ERROR] Could not read the project version from pubspec.yaml.
  goto :fail
)
if not defined BUILD_STAMP (
  echo [ERROR] Could not create a unique build timestamp.
  goto :fail
)
if not exist "!DIST_DIR!" mkdir "!DIST_DIR!"
if errorlevel 1 (
  echo [ERROR] Could not create the distribution directory: !DIST_DIR!
  goto :fail
)

copy /y "!APK_PATH!" "!DIST_APK_PATH!" >nul
if errorlevel 1 (
  echo [ERROR] Could not create the uniquely named distribution APK.
  goto :fail
)
copy /y "!CHECKSUM_PATH!" "!DIST_CHECKSUM_PATH!" >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy the distribution SHA-256 file.
  goto :fail
)

echo.
echo [5/5] Release artifact checks complete.
echo.
echo ========================================
echo [SUCCESS] Fresh signed ARM64 release APK is ready:
echo !APK_PATH!
echo Shareable APK: !DIST_APK_PATH!
echo Pubspec version: !APP_VERSION!
echo Android version: !ANDROID_VERSION!
echo Build time: !BUILD_SECONDS! seconds
echo SHA-256: !APK_HASH!
echo Checksum: !CHECKSUM_PATH!
echo Shareable checksum: !DIST_CHECKSUM_PATH!
echo ========================================
if /i not "%CI%"=="true" explorer "!DIST_DIR!"
set "EXIT_CODE=0"
goto :finish

:fail
echo.
echo ========================================
echo [FAILED] The APK was not published. Check the error above.
echo ========================================
set "EXIT_CODE=1"

goto :finish

:finish
if exist "!BUILD_MARKER!" del "!BUILD_MARKER!" >nul 2>&1
if exist "!JAVA_VERSION_FILE!" del "!JAVA_VERSION_FILE!" >nul 2>&1
popd
if /i not "%CI%"=="true" if "!NO_PAUSE!"=="0" pause
exit /b !EXIT_CODE!

:print_help
echo.
echo Usage: build-apk.bat [--offline ^| --online] [--clean]
echo.
echo Default:
echo   Reuse incremental Flutter and Gradle outputs. If pubspec files changed,
echo   restore dependencies from the local cache without silently going online.
echo.
echo --offline  Always run flutter pub get --offline and require a cached sqlite3 asset.
echo --online   Explicitly allow network access for dependency and native-asset restore.
echo --clean    Remove Flutter/Gradle outputs before building. Combine with --online
 echo            for a cold build when local caches were removed.
echo --help     Show this message.
echo.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$config=Get-Content -Raw -LiteralPath '.dart_tool\package_config.json' | ConvertFrom-Json; $pkg=@($config.packages | Where-Object { $_.name -eq 'sqlite3' }) | Select-Object -First 1; if ($null -eq $pkg) { exit 1 }; $root=[Uri]::new($pkg.rootUri).LocalPath; $source=Join-Path $root 'lib\src\hook\asset_hashes.dart'; if (-not (Test-Path -LiteralPath $source)) { exit 1 }; $line=Get-Content -LiteralPath $source | Where-Object { $_ -like '*libsqlite3.arm64.android.so*' } | Select-Object -First 1; if (-not $line) { exit 1 }; $hash=(($line -split [char]39)[3]).ToLowerInvariant(); if ($hash.Length -ne 64) { exit 1 }; $cache=Join-Path (Join-Path (Get-Location) '.dart_tool\hooks_runner\shared\sqlite3\build') ('download-' + $hash.Substring(0,8)); $file=Join-Path $cache 'libsqlite3.so'; if (-not (Test-Path -LiteralPath $file)) { exit 1 }; $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant(); if ($actual -ne $hash) { exit 1 }; exit 0"
if errorlevel 1 exit /b 1
exit /b 0
