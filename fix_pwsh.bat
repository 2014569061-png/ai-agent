@echo off
echo [1/2] Checking PowerShell installation...
if exist "C:\Program Files\PowerShell\7\pwsh.exe" (
    echo Found PowerShell 7 at C:\Program Files\PowerShell\7\pwsh.exe
    copy /y "C:\Program Files\PowerShell\7\pwsh.exe" "C:\src\flutter\bin\pwsh.exe"
    echo Successfully copied to C:\src\flutter\bin\pwsh.exe
) else (
    echo PowerShell 7 not found in Program Files, using Windows PowerShell...
    copy /y "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" "C:\src\flutter\bin\pwsh.exe"
    echo Successfully copied Windows PowerShell to C:\src\flutter\bin\pwsh.exe
)
echo.
echo [2/2] Done! You can close this window now.
pause
