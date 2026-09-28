@if "%~1"=="" goto :eof

@echo off
@setlocal enableextensions
@pushd %~dp0
set "OUTPUT_DIR=%~dp0..\SandboxOutput"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
@echo "%~1\*.*" "..\..\..\*.*" >filelist.txt
Engine\Binaries\Win64\UnrealPak.exe "%~1.pak" -create=../../../filelist.txt
move "%~1.pak" "%OUTPUT_DIR%"
echo.
echo Created "%OUTPUT_DIR%\%~n1.pak".
echo Import it with SandboxLauncher.bat option 3 if you want it in the sandbox.
@popd
@pause
