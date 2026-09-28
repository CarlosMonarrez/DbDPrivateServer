@echo off
echo This legacy launcher has been disabled for safety.
echo Starting the sandbox manager instead. The official DBD install will not be modified.
echo.
call "%~dp0SandboxLauncher.bat"
exit /b %ERRORLEVEL%
