@echo off
setlocal
title DBD Sandbox Manager

set "SCRIPT_DIR=%~dp0"
set "MANAGER=%SCRIPT_DIR%SandboxManager.ps1"

if not exist "%MANAGER%" (
    echo SandboxManager.ps1 was not found next to this launcher.
    pause
    exit /b 1
)

%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Sandbox Manager exited with code %EXIT_CODE%.
)

pause
exit /b %EXIT_CODE%
