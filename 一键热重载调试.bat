@echo off
title NEXUS Agent 热重载调试
cd /d "%~dp0"
echo ========================================================
echo         NEXUS Agent 热重载调试模式
echo ========================================================
echo.
echo  [1] 手机真机调试 (OPPO PKX110, USB, 调试包与正式版并存)
echo  [2] Chrome 浏览器调试
echo.
choice /c 12 /n /m "请选择调试目标 [1/2]: "
if errorlevel 2 goto web
echo.
echo [i] 正在启动手机调试, 首次编译约 1-3 分钟, 请耐心等待...
echo [i] 看到下方出现 "Flutter run key commands" 字样后才能按键:
echo     r = 热重载 (改完 lib 下代码按 r, 手机上秒级生效)
echo     R = 热重启 (状态会重置)    q = 退出
echo [i] 如果看到 "请按任意键继续" 说明 flutter 已经退出, 按任意键只会关窗口!
echo.
call flutter run -d d29380b2
goto end
:web
echo.
echo [i] 正在启动 Chrome 调试...
call flutter run -d chrome
:end
echo.
echo [!] flutter run 已退出。若上方有红色报错信息, 请截图反馈。
echo [i] 手机上会同时存在两个应用: NEXUS Agent(正式版) 和 NEXUS Debug(调试版)
pause
