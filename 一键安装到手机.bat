@echo off
chcp 65001 >nul
setlocal EnableExtensions
title NEXUS Agent - 一键安装到手机
cd /d "%~dp0"

rem ============================================================
rem  NEXUS Agent 构建并安装到 USB 手机
rem
rem  用法：
rem    一键安装到手机.bat                release 构建 → 安装 → 启动
rem    一键安装到手机.bat debug          构建 debug 包（独立包名 .debug）→ 安装 → 启动
rem    一键安装到手机.bat dryrun         只构建与预检设备，不实际安装
rem    一键安装到手机.bat nopause        结束不暂停
rem    一键安装到手机.bat <设备序列号>   指定设备（多设备时必须）
rem    也可用环境变量：set NEXUS_DEVICE=<序列号>
rem
rem  相比旧脚本的改动：
rem    · 不再硬编码设备序列号（旧脚本写死 d29380b2，换手机即失效）；
rem      现在自动识别唯一设备，多设备时列出候选并要求显式指定；
rem    · 明确区分 unauthorized / offline / 无设备，并给出对应处理办法；
rem    · release 模式复用签名预检：缺 key.properties 时直接拦下（否则会静默
rem      装上 debug 签名的"正式包"，覆盖安装已发布版本必然失败）；
rem    · 文件编码统一为 UTF-8（旧脚本是 GBK，跨机器/locale 会乱码）。
rem ============================================================

set "MODE=release"
set "DRYRUN=0"
set "PAUSE=1"
set "SERIAL=%NEXUS_DEVICE%"
for %%A in (%*) do call :classify "%%~A"

set "APK_REL=build\app\outputs\flutter-apk\app-release.apk"
set "PACKAGE=com.nexusagent.app"
set "BUILD_ARGS=build apk --release --split-debug-info=build\symbols --obfuscate"
if /i "%MODE%"=="debug" (
    set "APK_REL=build\app\outputs\flutter-apk\app-debug.apk"
    set "PACKAGE=com.nexusagent.app.debug"
    set "BUILD_ARGS=build apk --debug"
)
set "APK=%CD%\%APK_REL%"
set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

echo ========================================================
echo       NEXUS Agent 一键安装到手机（%MODE%）
echo ========================================================

echo.
echo [1/5] 检查工具链
call :find_flutter
if not defined FLUTTER_EXE (
    echo        [错误] 未找到 flutter，请把 Flutter bin 加入 PATH
    goto :fail
)
call :find_adb
if not defined ADB_EXE (
    echo        [错误] 未找到 adb：请安装 Android 平台工具并加入 PATH，
    echo              或放到 %%LOCALAPPDATA%%\Android\Sdk\platform-tools\
    goto :fail
)
echo        flutter : %FLUTTER_EXE%
echo        adb     : %ADB_EXE%

echo.
echo [2/5] 预检设备
"%ADB_EXE%" start-server >nul 2>nul
"%ADB_EXE%" devices | findstr /i /r /c:"unauthorized$" >nul 2>nul
if not errorlevel 1 (
    echo        [错误] 手机已连接但未授权 USB 调试。
    echo               请在手机屏幕上点「允许 USB 调试」，然后重跑本脚本。
    goto :fail
)
"%ADB_EXE%" devices | findstr /i /r /c:"offline$" >nul 2>nul
if not errorlevel 1 (
    echo        [错误] 设备处于 offline 状态：请重新插拔数据线，或关闭再打开 USB 调试。
    goto :fail
)
set "DEV_COUNT=0"
set "FOUND_SERIAL="
for /f "tokens=1,2" %%A in ('"%ADB_EXE%" devices ^| findstr /r /c:"device$"') do (
    set /a DEV_COUNT+=1
    if not defined FOUND_SERIAL set "FOUND_SERIAL=%%A"
)
if %DEV_COUNT%==0 (
    echo        [错误] 没有检测到已连接的手机。
    echo               请插好 USB 数据线，并在手机上选择「文件传输 / USB 调试」模式。
    goto :fail
)
if %DEV_COUNT% GTR 1 (
    if not defined SERIAL (
        echo        [错误] 检测到 %DEV_COUNT% 台设备，无法确定装到哪台：
        "%ADB_EXE%" devices
        echo.
        echo        请显式指定，例如：一键安装到手机.bat ^<设备序列号^>
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
echo        目标设备：%SERIAL%

if /i "%MODE%"=="debug" goto :skip_sign_check
echo.
echo [3/5] 校验正式签名配置
call :check_signing
if defined SIGN_PROBLEM (
    echo        [致命] %SIGN_PROBLEM%
    echo.
    echo        继续安装会装上 debug 签名的"正式包"：能在本机跑，但无法覆盖安装
    echo        你已发布的正式版（签名不一致，安装会失败）。
    echo        若确实只想本机调试，请改用：一键安装到手机.bat debug
    goto :fail
)
echo        正式签名配置完整
goto :build

:skip_sign_check
echo.
echo [3/5] debug 模式：跳过正式签名校验（使用 debug 签名 + .debug 包名）

:build
echo.
echo [4/5] 构建 APK
call "%FLUTTER_EXE%" pub get
if errorlevel 1 (
    echo        [错误] flutter pub get 失败
    goto :fail
)
call "%FLUTTER_EXE%" analyze --no-pub
if errorlevel 1 (
    echo        [错误] flutter analyze 有告警，已中止（先修告警再装到手机）
    goto :fail
)
echo        flutter analyze 零告警
call "%FLUTTER_EXE%" %BUILD_ARGS%
if errorlevel 1 (
    echo        [错误] 构建失败
    goto :fail
)
if not exist "%APK%" (
    echo        [错误] 找不到产物：%APK_REL%
    goto :fail
)

if not "%DRYRUN%"=="1" goto :install
echo.
echo [5/5] dryrun：跳过安装与启动（构建与设备预检已完成）
echo        将安装   : %APK_REL%
echo        目标设备 : %SERIAL%
goto :done

:install
echo.
echo [5/5] 安装并启动
"%ADB_EXE%" -s %SERIAL% install -r -d "%APK%"
if errorlevel 1 (
    echo.
    echo        [错误] 安装失败。常见原因：
    echo                · 手机上未允许「通过 USB 安装应用」
    echo                · 已安装的是不同签名的同包名应用（先卸载再装）
    echo                · 手机存储空间不足
    goto :fail
)
"%ADB_EXE%" -s %SERIAL% shell monkey -p %PACKAGE% -c android.intent.category.LAUNCHER 1 >nul 2>nul
if errorlevel 1 (
    echo        安装完成，但自动启动失败：请到手机上点开 App
) else (
    echo        安装完成，已在手机上启动（%PACKAGE%）
)
goto :done

rem ==================== 子过程 ====================

rem 解析参数：debug / release / dryrun / nopause / 其它视为设备序列号
:classify
if /i "%~1"=="debug"   ( set "MODE=debug" & goto :eof )
if /i "%~1"=="release" ( set "MODE=release" & goto :eof )
if /i "%~1"=="dryrun"  ( set "DRYRUN=1" & goto :eof )
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

rem 检查 android\key.properties 与 keystore；问题写入 SIGN_PROBLEM
:check_signing
set "SIGN_PROBLEM="
set "K_STORE="
if not exist "android\key.properties" (
    set "SIGN_PROBLEM=找不到 android\key.properties"
    goto :eof
)
findstr /r /b "keyAlias=." "android\key.properties" >nul 2>nul || set "SIGN_PROBLEM=key.properties 里 keyAlias 缺失或为空"
findstr /r /b "storePassword=." "android\key.properties" >nul 2>nul || set "SIGN_PROBLEM=key.properties 里 storePassword 缺失或为空"
findstr /r /b "keyPassword=." "android\key.properties" >nul 2>nul || set "SIGN_PROBLEM=key.properties 里 keyPassword 缺失或为空"
findstr /r /b "storeFile=." "android\key.properties" >nul 2>nul || set "SIGN_PROBLEM=key.properties 里 storeFile 缺失或为空"
for /f "tokens=2 delims==" %%V in ('findstr /b "storeFile=" "android\key.properties"') do set "K_STORE=%%V"
if defined SIGN_PROBLEM goto :eof
if exist "android\app\%K_STORE%" goto :eof
if exist "android\%K_STORE%" goto :eof
set "SIGN_PROBLEM=keystore 文件不存在：%K_STORE%（Gradle 以 android\app\ 为基准解析）"
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
