@echo off
chcp 65001 >nul
setlocal EnableExtensions
title NEXUS Agent - 一键热重载调试
cd /d "%~dp0"

rem ============================================================
rem  NEXUS Agent 热重载调试（手机 USB / Chrome Web）
rem
rem  用法：
rem    一键热重载调试.bat               交互选择 [1] USB 手机 [2] Chrome
rem    一键热重载调试.bat usb           直接跑 USB 手机
rem    一键热重载调试.bat chrome        直接跑 Chrome（Web）
rem    一键热重载调试.bat check         只列出设备并退出（不启动 flutter run）
rem    一键热重载调试.bat nopause       退出时不暂停
rem    一键热重载调试.bat <设备序列号>  指定设备
rem    也可用环境变量：set NEXUS_DEVICE=<序列号>
rem
rem  相比旧脚本的改动：
rem    · 不再硬编码设备序列号（旧脚本写死 d29380b2，换手机/重连即失败）；
rem      现在自动识别唯一设备，多设备时列出候选并要求显式指定；
rem    · 明确区分 unauthorized / offline / 无设备，给出对应处理办法；
rem    · 编码统一 UTF-8（旧脚本 GBK + chcp 936，跨机器/locale 乱码）；
rem    · 新增 check 模式，便于脚本化验证环境而不进入长驻的 flutter run。
rem ============================================================

set "TARGET="
set "PAUSE=1"
set "SERIAL=%NEXUS_DEVICE%"
for %%A in (%*) do call :classify "%%~A"

echo ========================================================
echo          NEXUS Agent 热重载调试
echo ========================================================

echo.
echo [1/4] 检查工具链
call :find_flutter
if not defined FLUTTER_EXE (
    echo        [错误] 未找到 flutter，请把 Flutter bin 加入 PATH
    goto :fail
)
call :find_adb
echo        flutter : %FLUTTER_EXE%
if defined ADB_EXE (echo        adb     : %ADB_EXE%) else (echo        adb     : 未找到（USB 手机会不可用，Chrome 不受影响）)

rem check 模式不进入交互选择，只列设备清单后退出（便于脚本化验证环境）
if "%MODE_CHECK%"=="1" goto :check_devices

echo.
echo [2/4] 选择目标
if not defined TARGET (
    echo        [1] USB 手机
    echo        [2] Chrome（Web）
    choice /c 12 /n /m "       请选择目标 [1/2]: "
    if errorlevel 2 ( set "TARGET=chrome" ) else ( set "TARGET=usb" )
)
echo        目标：%TARGET%

if /i "%TARGET%"=="chrome" goto :run_chrome

echo.
echo [3/4] 预检手机
if not defined ADB_EXE (
    echo        [错误] 未找到 adb，无法走 USB。请安装 Android 平台工具，或改用：一键热重载调试.bat chrome
    goto :fail
)
"%ADB_EXE%" start-server >nul 2>nul
"%ADB_EXE%" devices | findstr /i /r /c:"unauthorized$" >nul 2>nul
if not errorlevel 1 (
    echo        [错误] 手机已连接但未授权 USB 调试：请在手机屏幕上点「允许 USB 调试」。
    goto :fail
)
"%ADB_EXE%" devices | findstr /i /r /c:"offline$" >nul 2>nul
if not errorlevel 1 (
    echo        [错误] 设备 offline：请重新插拔数据线，或关闭再打开 USB 调试。
    goto :fail
)
set "DEV_COUNT=0"
set "FOUND_SERIAL="
for /f "tokens=1,2" %%A in ('"%ADB_EXE%" devices ^| findstr /r /c:"device$"') do (
    set /a DEV_COUNT+=1
    if not defined FOUND_SERIAL set "FOUND_SERIAL=%%A"
)
if %DEV_COUNT%==0 (
    echo        [错误] 没有检测到手机。请插好数据线并在手机上选择「文件传输 / USB 调试」，
    echo               或改用：一键热重载调试.bat chrome
    goto :fail
)
if %DEV_COUNT% GTR 1 (
    if not defined SERIAL (
        echo        [错误] 检测到 %DEV_COUNT% 台设备，无法确定用哪台：
        "%ADB_EXE%" devices
        echo        请显式指定：一键热重载调试.bat ^<设备序列号^>
        goto :fail
    )
)
if not defined SERIAL set "SERIAL=%FOUND_SERIAL%"
"%ADB_EXE%" -s %SERIAL% get-state >nul 2>nul
if errorlevel 1 (
    echo        [错误] 指定设备不可用：%SERIAL%
    "%ADB_EXE%" devices
    goto :fail
)
echo        设备：%SERIAL%
set "RUN_TARGET=%SERIAL%"
goto :run

:run_chrome
set "RUN_TARGET=chrome"
goto :run

:check_devices
echo.
echo [check] 环境与设备清单（不启动 flutter run）
if defined ADB_EXE (
    echo        --- adb devices ---
    "%ADB_EXE%" devices
) else (
    echo        adb 未找到：USB 手机会不可用，Chrome 不受影响
)
echo        --- flutter devices ---
call "%FLUTTER_EXE%" devices
goto :done

:run
echo.
echo [4/4] 启动 flutter run -d %RUN_TARGET%
echo        首次编译约 1-3 分钟，之后热重载是秒级。
echo        快捷键：r = 热重载（改 lib 下代码按 r，手机端立刻生效）
echo                R = 热重启（状态清零）    q = 退出
echo        提示：若出现「请按任意键继续」，说明 flutter 已退出（常因设备掉线）。
echo.
call "%FLUTTER_EXE%" run -d %RUN_TARGET%
echo.
echo [!] flutter run 已退出，请检查上方是否有红色错误信息。
goto :done

rem ==================== 子过程 ====================

:classify
if /i "%~1"=="usb"     ( set "TARGET=usb" & goto :eof )
if /i "%~1"=="chrome"  ( set "TARGET=chrome" & goto :eof )
if /i "%~1"=="web"     ( set "TARGET=chrome" & goto :eof )
if /i "%~1"=="check"   ( set "MODE_CHECK=1" & goto :eof )
if /i "%~1"=="nopause" ( set "PAUSE=0" & goto :eof )
set "SERIAL=%~1"
goto :eof

:find_flutter
if exist "C:\src\flutter\bin\flutter.bat" (
    set "FLUTTER_EXE=C:\src\flutter\bin\flutter.bat"
    goto :eof
)
for /f "delims=" %%F in ('where flutter 2^>nul') do if not defined FLUTTER_EXE set "FLUTTER_EXE=%%F"
goto :eof

:find_adb
set "ADB_EXE="
for /f "delims=" %%P in ('where adb 2^>nul') do if not defined ADB_EXE set "ADB_EXE=%%P"
if defined ADB_EXE goto :eof
set "SDK_DIR=%LOCALAPPDATA%\Android\Sdk"
if defined ANDROID_HOME set "SDK_DIR=%ANDROID_HOME%"
if defined ANDROID_SDK_ROOT set "SDK_DIR=%ANDROID_SDK_ROOT%"
if exist "%SDK_DIR%\platform-tools\adb.exe" set "ADB_EXE=%SDK_DIR%\platform-tools\adb.exe"
goto :eof

:fail
echo.
echo 未完成。
if "%PAUSE%"=="1" pause
exit /b 1

:done
echo.
if "%PAUSE%"=="1" pause
exit /b 0
