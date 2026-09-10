@echo off
chcp 65001 >nul
setlocal EnableExtensions
title NEXUS Agent - Build Release APK
cd /d "%~dp0"

rem ============================================================
rem  NEXUS Agent 本机构建正式 APK
rem
rem  用法：
rem    构建.bat              预检 → 构建 → 校验产物 → 打开产物目录
rem    构建.bat check        只做预检（工具链 / 签名配置 / 版本），不构建
rem    构建.bat tests        构建前额外跑一遍全量测试（需 Git Bash）
rem    构建.bat nopause      结束不暂停、不开资源管理器（供脚本调用）
rem    构建.bat debugsign    缺正式签名时也继续（产物仅供本机测试）
rem    可组合：构建.bat tests nopause
rem
rem  本脚本主动拦住三类"看起来成功、实际不能用"的情况：
rem    1) 缺 android\key.properties 或 keystore —— Gradle 会静默回退 debug 签名，
rem       旧脚本照样打印 [OK]，你可能拿着 debug 签名包去上架（必被拒）或
rem       覆盖安装已发布的正式版（签名不一致，必失败）；
rem    2) 产物签名异常（例如仍是 Android Debug 证书）—— 构建后用 apksigner 验签；
rem    3) flutter analyze 有告警 —— 构建前先卡住，避免带告警的代码进正式包。
rem
rem  依赖：Flutter SDK。apksigner/aapt 从 Android SDK build-tools 自动定位，
rem        找不到时跳过对应校验并明确提示（不静默放过）。
rem ============================================================

set "MODE=build"
set "PAUSE=1"
set "RUN_TESTS=0"
set "ALLOW_DEBUG_SIGN=0"
set "SIGN_PROBLEM="
set "APK_SHA="
set "PKG_LINE="
set "ABI_LINE="
for %%A in (%*) do (
    if /i "%%~A"=="check"     set "MODE=check"
    if /i "%%~A"=="nopause"   set "PAUSE=0"
    if /i "%%~A"=="tests"     set "RUN_TESTS=1"
    if /i "%%~A"=="debugsign" set "ALLOW_DEBUG_SIGN=1"
)

set "APK_REL=build\app\outputs\flutter-apk\app-release.apk"
set "APK=%CD%\%APK_REL%"
set "SYMBOL_DIR=build\symbols"
set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

echo ========================================================
echo             NEXUS Agent 构建正式 APK
echo             模式：%MODE%
echo ========================================================

echo.
echo [1/6] 检查工具链
call :find_flutter
if not defined FLUTTER_EXE (
    echo        [错误] 未找到 flutter，请把 Flutter bin 加入 PATH 或装到 C:\src\flutter
    goto :build_fail
)
echo        Flutter   : %FLUTTER_EXE%
set "FLUTTER_LINE="
for /f "tokens=1,*" %%A in ('call "%FLUTTER_EXE%" --version 2^>nul') do (
    if not defined FLUTTER_LINE set "FLUTTER_LINE=%%A %%B"
)
if defined FLUTTER_LINE echo        %FLUTTER_LINE%
call :find_sdk_tool apksigner APKSIGNER
call :find_sdk_tool aapt AAPT
if defined APKSIGNER (echo        apksigner : %APKSIGNER%) else (echo        apksigner : 未找到，将跳过签名校验)
if defined AAPT      (echo        aapt      : %AAPT%)      else (echo        aapt      : 未找到，将跳过分包信息校验)

echo.
echo [2/6] 读取版本号
set "APP_VERSION=未知"
for /f "tokens=2" %%V in ('findstr /b /c:"version:" pubspec.yaml 2^>nul') do set "APP_VERSION=%%V"
echo        pubspec.yaml version : %APP_VERSION%

echo.
echo [3/6] 校验正式签名配置
call :check_signing
if not defined SIGN_PROBLEM goto :signing_ok
echo        [致命] %SIGN_PROBLEM%
echo.
echo        后果：Gradle 会静默改用 debug 签名，产物能装但
echo              · 不能发布到应用商店（商店拒绝 debug 证书）
echo              · 不能覆盖安装你已发布的正式版（签名不一致）
echo.
echo        修复：让 android\key.properties 含以下四行（值不要加引号）：
echo              storePassword=你的keystore密码
echo              keyPassword=你的key密码
echo              keyAlias=你的别名
echo              storeFile=upload-keystore.jks
echo              并把 keystore 放到 android\app\ 下（Gradle 以该目录为基准解析）
echo.
if "%ALLOW_DEBUG_SIGN%"=="1" goto :signing_warn
echo        若确实只想本机测试，请显式加参数：构建.bat debugsign
goto :build_fail

:signing_warn
echo        [!] 已指定 debugsign：继续构建，但产物不可用于发布。
goto :signing_done

:signing_ok
echo        正式签名配置完整：storeFile=%K_STORE%，keystore 已就位

:signing_done
if not "%MODE%"=="check" goto :do_build
echo.
echo [check] 预检通过，未执行构建。
goto :done

:do_build
echo.
echo [4/6] 依赖与质量门
call "%FLUTTER_EXE%" pub get
if errorlevel 1 (
    echo        [错误] flutter pub get 失败
    goto :build_fail
)
call "%FLUTTER_EXE%" analyze --no-pub
if errorlevel 1 (
    echo        [错误] flutter analyze 有告警，已中止构建（正式包必须出自零告警代码）
    goto :build_fail
)
echo        flutter analyze 零告警
if not "%RUN_TESTS%"=="1" goto :skip_tests
where bash >nul 2>nul
if errorlevel 1 (
    echo        [!] 未找到 bash，跳过测试（本机测试必须经 tool\test.sh 修正环境）
    goto :skip_tests
)
call bash tool/test.sh --concurrency=1
if errorlevel 1 (
    echo        [错误] 测试未全绿，已中止构建
    goto :build_fail
)
:skip_tests

echo.
echo [5/6] 构建 release APK
if not exist "%SYMBOL_DIR%" mkdir "%SYMBOL_DIR%"
echo        flutter build apk --release --split-debug-info="%SYMBOL_DIR%" --obfuscate
call "%FLUTTER_EXE%" build apk --release --split-debug-info="%SYMBOL_DIR%" --obfuscate
if errorlevel 1 (
    echo        [错误] 构建失败
    goto :build_fail
)
if not exist "%APK%" (
    echo        [错误] 构建结束但找不到产物：%APK_REL%
    goto :build_fail
)

echo.
echo [6/6] 校验产物
echo        APK       : %APK_REL%
for %%F in ("%APK%") do echo        体积      : %%~zF 字节
for /f "delims=" %%A in ('certutil -hashfile "%APK%" SHA256 2^>nul ^| findstr /r /v ":"') do (
    if not defined APK_SHA set "APK_SHA=%%A"
)
if defined APK_SHA echo        SHA-256   : %APK_SHA%

if not defined AAPT goto :skip_aapt
rem 先把 aapt 输出落到临时文件再 findstr：for /f 内层带引号的可执行路径会被 cmd 二次解析搞坏
"%AAPT%" dump badging "%APK%" > "%TEMP%\nexus_apk_badge.txt" 2>nul
for /f "delims=" %%L in ('findstr /b "package:" "%TEMP%\nexus_apk_badge.txt"') do set "PKG_LINE=%%L"
for /f "delims=" %%L in ('findstr /c:"native-code" "%TEMP%\nexus_apk_badge.txt"') do set "ABI_LINE=%%L"
:skip_aapt
if defined PKG_LINE echo        %PKG_LINE%
if defined ABI_LINE echo        %ABI_LINE%

if not defined APKSIGNER goto :skip_sign
rem apksigner 本身是 .bat：必须用 call，否则控制权交出去后本脚本不会再继续
call "%APKSIGNER%" verify --print-certs "%APK%" > "%TEMP%\nexus_apk_sign.txt" 2>&1
if errorlevel 1 (
    echo        [错误] apksigner 校验失败（签名损坏或未签名）：
    type "%TEMP%\nexus_apk_sign.txt"
    goto :build_fail
)
for /f "delims=" %%L in ('findstr /c:"certificate DN" "%TEMP%\nexus_apk_sign.txt"') do echo        %%L
findstr /i /c:"CN=Android Debug" "%TEMP%\nexus_apk_sign.txt" >nul 2>nul
if not errorlevel 1 (
    echo.
    echo        [致命] 产物由 Android Debug 证书签名：不能发布、不能覆盖安装正式版。
    echo               请检查 android\key.properties 与 android\app\upload-keystore.jks 是否匹配。
    goto :build_fail
)
echo        签名校验  : 非 debug 证书，通过
goto :sign_done

:skip_sign
echo        [!] 未找到 apksigner，跳过签名校验（Android SDK build-tools 缺失）

:sign_done
echo        符号文件  : %SYMBOL_DIR%\（混淆堆栈反解所需，发布时务必一并归档）

echo.
echo [OK] 正式 APK 构建并校验完成（version %APP_VERSION%）
if "%PAUSE%"=="1" explorer /select,"%APK%"
goto :done

rem ==================== 子过程 ====================

rem 定位 flutter：优先 C:\src\flutter，其次 PATH
:find_flutter
if exist "C:\src\flutter\bin\flutter.bat" (
    set "FLUTTER_EXE=C:\src\flutter\bin\flutter.bat"
    goto :eof
)
for /f "delims=" %%F in ('where flutter 2^>nul') do (
    if not defined FLUTTER_EXE set "FLUTTER_EXE=%%F"
)
goto :eof

rem 在 Android SDK build-tools 里找最新版本的 apksigner.bat / aapt.exe
:find_sdk_tool
set "FOUND="
set "SDK_DIR=%LOCALAPPDATA%\Android\Sdk"
if defined ANDROID_HOME set "SDK_DIR=%ANDROID_HOME%"
if defined ANDROID_SDK_ROOT set "SDK_DIR=%ANDROID_SDK_ROOT%"
if exist "%SDK_DIR%\build-tools" (
    for /f "delims=" %%D in ('dir /b /ad /o-n "%SDK_DIR%\build-tools" 2^>nul') do (
        if not defined FOUND (
            if exist "%SDK_DIR%\build-tools\%%D\%~1.bat" set "FOUND=%SDK_DIR%\build-tools\%%D\%~1.bat"
            if exist "%SDK_DIR%\build-tools\%%D\%~1.exe" set "FOUND=%SDK_DIR%\build-tools\%%D\%~1.exe"
        )
    )
)
if not defined FOUND (
    for /f "delims=" %%P in ('where %~1 2^>nul') do if not defined FOUND set "FOUND=%%P"
)
set "%~2=%FOUND%"
goto :eof

rem 检查 android\key.properties 与 keystore；问题写入 SIGN_PROBLEM
rem 刻意用 findstr 只判断「键存在且值非空」，不解析也不回显密码本身
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

:build_fail
echo.
echo 构建未完成。
if "%PAUSE%"=="1" pause
exit /b 1

:done
if "%PAUSE%"=="1" pause
exit /b 0
