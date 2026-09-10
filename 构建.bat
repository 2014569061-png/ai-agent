@echo off
chcp 65001 >nul
setlocal EnableExtensions
title NEXUS Agent - Build Latest APK
cd /d "%~dp0"

rem 使用用户级 Gradle 缓存，避免在项目根目录重新生成 gradle-cache。
set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

echo ========================================================
echo             NEXUS Agent Build Latest APK
echo ========================================================
echo.

set "FLUTTER_EXE="
if exist "C:\src\flutter\bin\flutter.bat" set "FLUTTER_EXE=C:\src\flutter\bin\flutter.bat"
if not defined FLUTTER_EXE (
    for /f "delims=" %%F in ('where flutter 2^>nul') do if not defined FLUTTER_EXE set "FLUTTER_EXE=%%F"
)
if not defined FLUTTER_EXE (
    echo [ERROR] Flutter was not found. Add Flutter bin to PATH.
    goto :fail
)

set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
set "SYMBOL_PATH=build\symbols"

echo [1/3] Checking Flutter...
call "%FLUTTER_EXE%" --version
if errorlevel 1 goto :fail

echo.
echo [2/3] Getting dependencies...
call "%FLUTTER_EXE%" pub get
if errorlevel 1 (
    echo [ERROR] Failed to get dependencies.
    goto :fail
)

if not exist "%SYMBOL_PATH%" mkdir "%SYMBOL_PATH%"
echo.
echo [3/3] Building release APK...
call "%FLUTTER_EXE%" build apk --release --split-debug-info="%SYMBOL_PATH%" --obfuscate
if errorlevel 1 (
    echo [ERROR] APK build failed.
    goto :fail
)

if not exist "%APK_PATH%" (
    echo [ERROR] Build finished but APK was not found: %APK_PATH%
    goto :fail
)

echo.
echo [OK] Latest APK:
echo      %CD%\%APK_PATH%
explorer /select,"%CD%\%APK_PATH%"
pause
exit /b 0

:fail
echo.
echo Build did not complete.
pause
exit /b 1
