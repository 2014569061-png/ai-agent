@echo off
chcp 936 >nul
title mobile_agent 一键安装到手机
setlocal
cd /d "%~dp0"

rem 可选参数: 一键安装到手机.bat [debug]
rem   debug  跳过 Release 混淆打包，编译更快，适合快速验证 UI 改动
set "PACKAGE=com.nexusagent.app"
set "BUILD_MODE=release"
set "BUILD_ARGS=build apk --release --split-debug-info=build\symbols --obfuscate"
set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
if /i "%~1"=="debug" (
    set "BUILD_MODE=debug"
    set "BUILD_ARGS=build apk --debug"
    set "APK_PATH=build\app\outputs\flutter-apk\app-debug.apk"
)

echo =========================================
echo  mobile_agent 一键安装到手机 (%BUILD_MODE%)
echo =========================================
echo.

rem ---- 1. 环境预检 ----
where adb >nul 2>nul || (echo [×] 未找到 adb，请确认 Android 平台工具已安装并加入 PATH。 & goto :fail)
where flutter >nul 2>nul || (echo [×] 未找到 flutter，请确认 Flutter SDK 已加入 PATH。 & goto :fail)

adb start-server >nul 2>nul

rem ---- 2. 设备预检（没连手机就直接退出，避免白等几分钟编译）----
set /a DEVICE_COUNT=0, UNAUTHORIZED=0, OFFLINE=0
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
    if /i "%%B"=="device" set /a DEVICE_COUNT+=1
    if /i "%%B"=="unauthorized" set /a UNAUTHORIZED+=1
    if /i "%%B"=="offline" set /a OFFLINE+=1
)
if %UNAUTHORIZED% gtr 0 (
    echo [×] 手机已连接但未授权 USB 调试。
    echo     请解锁手机，在弹窗中点「允许 USB 调试」后重试。
    goto :fail
)
if %OFFLINE% gtr 0 (
    echo [×] 手机处于 offline 状态，请重新插拔数据线或关闭再打开 USB 调试。
    goto :fail
)
if %DEVICE_COUNT%==0 (
    echo [×] 未检测到已连接的手机。
    echo     请插上 USB 数据线，并确认手机已开启「开发者选项 - USB 调试」。
    goto :fail
)
set "ADB_TARGET=adb"
if %DEVICE_COUNT% gtr 1 (
    echo [!] 检测到 %DEVICE_COUNT% 台设备，将安装到 USB 连接的手机（模拟器会被忽略）。
    set "ADB_TARGET=adb -d"
)
adb devices
echo.

rem ---- 3. 编译 ----
set "START_TIME=%time%"
echo [%time%] 开始编译 %BUILD_MODE% APK（首次编译较慢，属正常现象）...
echo.
if not exist "build\symbols" mkdir "build\symbols"

call flutter %BUILD_ARGS%
if errorlevel 1 (
    echo.
    echo [×] 打包失败，请检查上面的错误信息。
    goto :fail
)
call :elapsed "%START_TIME%" "%time%"

rem ---- 4. 安装（-r 覆盖安装，-d 允许版本回退）----
echo.
echo 正在安装到手机...
%ADB_TARGET% install -r -d "%APK_PATH%"
if errorlevel 1 (
    echo.
    echo [×] 安装失败：请解锁手机屏幕，若手机弹出安装确认请点「允许」，然后重试。
    goto :fail
)

rem ---- 5. 自动拉起 App ----
adb shell monkey -p %PACKAGE% -c android.intent.category.LAUNCHER 1 >nul 2>nul
if errorlevel 1 (
    echo [√] 安装完成！请到手机上打开 App。
) else (
    echo [√] 安装完成，App 已在手机上启动！
)
goto :done

:fail
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0

rem ---- 耗时计算: :elapsed "起始时间" "结束时间" ----
:elapsed
setlocal
set "T1=%~1"
set "T2=%~2"
set "T1=%T1: =0%"
set "T2=%T2: =0%"
for /f "tokens=1-4 delims=:.," %%a in ("%T1%") do set /a S1=((1%%a-100)*3600+(1%%b-100)*60+(1%%c-100))*100+(1%%d-10)
for /f "tokens=1-4 delims=:.," %%a in ("%T2%") do set /a S2=((1%%a-100)*3600+(1%%b-100)*60+(1%%c-100))*100+(1%%d-10)
if %S2% lss %S1% set /a S2+=8640000
set /a D=S2-S1, M=D/6000, S=D/100%%60
echo     本阶段耗时 %M% 分 %S% 秒
endlocal
goto :eof
