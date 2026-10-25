@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo  NEXUS Desktop UI Verification and Release Build
echo ========================================================

cd /d "d:\AIIIIII\ai-agent\mobile_agent"

set FLUTTER=C:\src\flutter\bin\flutter.bat
set DART=C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe

echo.
echo [Step 1/5] Running Flutter Analyze...
call "%FLUTTER%" analyze --no-pub > artifacts\desktop\zcode-handoff-analyze.log 2>&1
type artifacts\desktop\zcode-handoff-analyze.log
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Flutter analyze failed!
    exit /b %ERRORLEVEL%
)

echo.
echo [Step 2/5] Running Core Desktop Tests...
call "%FLUTTER%" test --no-pub test\desktop_shell_test.dart test\nexus_components_test.dart test\provider_setup_hint_test.dart test\glass_surface_test.dart test\startup_gate_test.dart test\nexus_theme_test.dart test\layering_test.dart > artifacts\desktop\zcode-handoff-tests.log 2>&1
type artifacts\desktop\zcode-handoff-tests.log
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Core desktop tests failed!
    exit /b %ERRORLEVEL%
)

echo.
echo [Step 3/5] Capturing Actual Desktop Screenshots across Themes and Scales...
call "%FLUTTER%" test --no-pub test\render_desktop_test.dart
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Desktop screenshot rendering failed!
    exit /b %ERRORLEVEL%
)

echo.
echo [Step 4/5] Building Windows Release Package...
call powershell.exe -ExecutionPolicy Bypass -File "tool\build-windows.ps1" -FlutterExe "%FLUTTER%" -SkipPub -SentryNativeSource "local\sentry-native-windows"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Windows release build failed!
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo  Verification and Build Complete!
echo ========================================================
echo Output Zip: dist\windows\nexus-agent-0.9.0-95-windows-x64.zip
echo Screenshots generated in: artifacts\desktop\
echo ========================================================
pause
