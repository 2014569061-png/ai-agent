@echo off
chcp 65001 >nul
title NEXUS Agent 一键启动
cls

cd /d "%~dp0"

echo ========================================================
echo          🚀 欢迎使用 NEXUS Agent 一键启动脚本
echo ========================================================
echo.

:: 1. 查找 Dart 引擎
set "DART_EXE="
if exist "C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe" set "DART_EXE=C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe"
if not defined DART_EXE (
    where dart >nul 2>nul && set "DART_EXE=dart"
)

:: 2. 查找 Python 引擎
set "PYTHON_EXE="
if exist "D:\Anaconda\python.exe" set "PYTHON_EXE=D:\Anaconda\python.exe"
if not defined PYTHON_EXE if exist "C:\Users\HJIE\AppData\Local\Programs\Python\Python312\python.exe" set "PYTHON_EXE=C:\Users\HJIE\AppData\Local\Programs\Python\Python312\python.exe"
if not defined PYTHON_EXE (
    where python >nul 2>nul && set "PYTHON_EXE=python"
)

:: 3. 编译 Web 产物（每次都重新编译，确保跑的是最新代码）
echo [i] 正在编译 Web 产物...
if exist "mobile_agent\web" (
    cd mobile_agent
) else (
    if not exist "web" (
        echo [!] 未找到 Flutter Web 工程目录（mobile_agent/web 或 ./web），请检查目录结构。
        pause
        exit /b 1
    )
)
call flutter build web
cd /d "%~dp0"

echo [✓] 编译完成，正在启动本地 Web 服务并自动唤起浏览器...
echo.

if defined DART_EXE (
    "%DART_EXE%" run web_server.dart
    goto end
)

if defined PYTHON_EXE (
    "%PYTHON_EXE%" web_server.py
    goto end
)

echo [!] 未检测到 Dart 或 Python 环境，请检查 Flutter 安装。
pause

:end
